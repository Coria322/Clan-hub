import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../application/providers/household_provider.dart';
import '../../infrastructure/auth/auth_repository.dart';
import '../../infrastructure/household/household_repository.dart';

class MembersManagementScreen extends ConsumerStatefulWidget {
  const MembersManagementScreen({super.key});

  @override
  ConsumerState<MembersManagementScreen> createState() => _MembersManagementScreenState();
}

class _MembersManagementScreenState extends ConsumerState<MembersManagementScreen> {
  @override
  void initState() {
    super.initState();
    _patchOwnMemberDoc();
  }

  Future<void> _patchOwnMemberDoc() async {
    final householdId = ref.read(activeHouseholdProvider);
    if (householdId == null) return;
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) return;

    String? displayName = user.displayName;
    if (displayName == null || displayName.isEmpty) {
      try {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          displayName = userDoc.data()?['displayName'] as String?;
          if (displayName != null && displayName.isNotEmpty) {
            user.updateDisplayName(displayName);
          }
        }
      } catch (_) {}
    }
    displayName = (displayName?.isNotEmpty == true) ? displayName : user.email;
    if (displayName == null || displayName.isEmpty) return;

    try {
      final memberRef = FirebaseFirestore.instance
          .collection('households').doc(householdId)
          .collection('members').doc(user.uid);
      final doc = await memberRef.get();
      if (doc.exists) {
        final current = (doc.data() ?? {})['displayName'] as String?;
        if (current == null || current.isEmpty) {
          await memberRef.update({'displayName': displayName});
        }
      }
    } catch (_) {}
  }

  Future<String> _resolveName(
    String uid,
    Map<String, dynamic> memberData,
    String? currentUserUid,
    String? currentUserDisplay,
  ) async {
    final fromMember = memberData['displayName'] as String?;
    if (fromMember != null && fromMember.isNotEmpty) return fromMember;

    if (uid == currentUserUid && currentUserDisplay != null && currentUserDisplay.isNotEmpty) {
      return currentUserDisplay;
    }

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (userDoc.exists) {
        final data = userDoc.data() ?? {};
        final name = data['displayName'] as String?;
        if (name != null && name.isNotEmpty) return name;
        final email = data['email'] as String?;
        if (email != null && email.isNotEmpty) return email;
      }
    } catch (_) {}

    return 'Usuario';
  }

  Future<void> _confirmRemoveMember(
    BuildContext context,
    String householdId,
    String targetUid,
    String targetName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar miembro?'),
        content: Text('¿Seguro que quieres eliminar a $targetName del hogar? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(householdRepositoryProvider).removeMember(householdId, targetUid);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$targetName ha sido eliminado del hogar.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final householdId = ref.watch(activeHouseholdProvider);
    if (householdId == null) return const Scaffold();

    final currentUser = ref.read(authRepositoryProvider).currentUser;
    final currentDisplay = currentUser?.displayName ?? currentUser?.email;

    return Scaffold(
      appBar: AppBar(title: const Text('Miembros')),
      body: StreamBuilder<DocumentSnapshot>(
        // Leemos el hogar para saber quién es el admin
        stream: FirebaseFirestore.instance
            .collection('households').doc(householdId).snapshots(),
        builder: (context, householdSnapshot) {
          final householdData = householdSnapshot.data?.data() as Map<String, dynamic>?;
          final adminUid = householdData?['adminUid'] as String?;
          final currentUserIsAdmin = currentUser?.uid == adminUid;

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('households').doc(householdId)
                .collection('members').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final members = snapshot.data!.docs;
              if (members.isEmpty) {
                return const Center(child: Text('No hay miembros en este hogar.'));
              }

              return ListView.builder(
                itemCount: members.length,
                itemBuilder: (context, index) {
                  final memberData = members[index].data() as Map<String, dynamic>;
                  final uid = memberData['uid'] as String? ?? '';
                  final role = memberData['role'] as String? ?? 'member';
                  final isAdminRole = role == 'admin';
                  final isMe = uid == currentUser?.uid;

                  return FutureBuilder<String>(
                    future: _resolveName(uid, memberData, currentUser?.uid, currentDisplay),
                    builder: (context, nameSnapshot) {
                      final name = nameSnapshot.data ?? '...';
                      final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
                      final subtitle = isMe
                          ? 'Tú · ${isAdminRole ? "Administrador" : "Miembro"}'
                          : (isAdminRole ? 'Administrador' : 'Miembro');

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isAdminRole
                              ? Colors.amber.shade200
                              : const Color(0xFF4CAF82).withValues(alpha: 0.2),
                          child: Text(
                            initial,
                            style: TextStyle(
                              color: isAdminRole
                                  ? Colors.amber.shade800
                                  : const Color(0xFF4CAF82),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(name),
                        subtitle: Text(subtitle),
                        trailing: isAdminRole
                            // El admin siempre tiene la estrella, no se puede eliminar
                            ? const Icon(Icons.star, color: Colors.amber)
                            // El admin actual puede eliminar a cualquier miembro que no sea él mismo
                            : currentUserIsAdmin && !isMe
                                ? IconButton(
                                    icon: const Icon(Icons.person_remove, color: Colors.red),
                                    tooltip: 'Eliminar del hogar',
                                    onPressed: () => _confirmRemoveMember(
                                      context, householdId, uid, name,
                                    ),
                                  )
                                : null,
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
