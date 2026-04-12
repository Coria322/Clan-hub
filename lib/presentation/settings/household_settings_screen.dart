import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import '../../application/providers/household_provider.dart';
import '../../infrastructure/auth/auth_repository.dart';
import '../../infrastructure/household/household_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HouseholdSettingsScreen extends ConsumerStatefulWidget {
  const HouseholdSettingsScreen({super.key});

  @override
  ConsumerState<HouseholdSettingsScreen> createState() => _HouseholdSettingsScreenState();
}

class _HouseholdSettingsScreenState extends ConsumerState<HouseholdSettingsScreen> {
  @override
  void initState() {
    super.initState();
    _patchOwnMemberDoc();
  }

  /// Parcha el displayName del miembro actual en Firestore si está vacío.
  /// Se dispara al abrir Settings para que otros miembros vean el nombre real.
  Future<void> _patchOwnMemberDoc() async {
    final householdId = ref.read(activeHouseholdProvider);
    if (householdId == null) return;
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) return;

    // Fuente 1: Firebase Auth
    String? displayName = user.displayName;

    // Fuente 2: colección users en Firestore (usuarios registrados antes del fix)
    if (displayName == null || displayName.isEmpty) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          displayName = userDoc.data()?['displayName'] as String?;
          if (displayName != null && displayName.isNotEmpty) {
            user.updateDisplayName(displayName); // sincronizar Firebase Auth
          }
        }
      } catch (_) {}
    }

    // Fuente 3: email como último recurso
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

  Future<void> _confirmDeleteHousehold(BuildContext context, String householdId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar Hogar?'),
        content: const Text(
          'Esta acción es irreversible. Se eliminará el hogar, todos sus miembros y categorías.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
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
      final user = ref.read(authRepositoryProvider).currentUser!;
      await ref.read(householdRepositoryProvider).deleteHousehold(householdId, user.uid);
      ref.read(activeHouseholdProvider.notifier).clear();
      if (mounted) context.go('/onboarding');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _confirmLeaveHousehold(BuildContext context, String householdId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Abandonar Hogar?'),
        content: const Text('Dejarás de tener acceso a las tareas y miembros de este hogar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Abandonar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final user = ref.read(authRepositoryProvider).currentUser!;
      await ref.read(householdRepositoryProvider).leaveHousehold(householdId, user.uid);
      ref.read(activeHouseholdProvider.notifier).clear();
      if (mounted) context.go('/onboarding');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final householdId = ref.watch(activeHouseholdProvider);

    if (householdId == null) {
      return const Scaffold(body: Center(child: Text('Ningún hogar seleccionado.')));
    }

    final householdStream = FirebaseFirestore.instance
        .collection('households').doc(householdId).snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes del Hogar')),
      body: StreamBuilder<DocumentSnapshot>(
        stream: householdStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Error al cargar la información del hogar.'));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final name = data['name'] ?? 'Mi Hogar';
          final inviteCode = data['inviteCode'] ?? '------';
          final adminUid = data['adminUid'];

          final user = ref.read(authRepositoryProvider).currentUser;
          final isAdmin = user?.uid == adminUid;

          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Icon(Icons.home, size: 64, color: Color(0xFF4CAF82)),
                      const SizedBox(height: 16),
                      Text(name, style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Chip(
                        label: Text(isAdmin ? 'Eres Administrador' : 'Eres Miembro'),
                        backgroundColor: isAdmin ? Colors.amber.shade100 : Colors.blue.shade100,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ListTile(
                title: const Text('Código de Invitación'),
                subtitle: Text(
                  inviteCode,
                  style: const TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: inviteCode));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Código copiado al portapapeles')),
                    );
                  },
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.people),
                title: const Text('Administrar Miembros'),
                onTap: () => context.push('/home/settings/members'),
                trailing: const Icon(Icons.chevron_right),
              ),
              ListTile(
                leading: const Icon(Icons.label),
                title: const Text('Categorías de Tareas'),
                onTap: () => context.push('/home/settings/categories'),
                trailing: const Icon(Icons.chevron_right),
              ),
              const Divider(),
              if (isAdmin)
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text('Eliminar Hogar', style: TextStyle(color: Colors.red)),
                  subtitle: const Text('Acción irreversible'),
                  onTap: () => _confirmDeleteHousehold(context, householdId),
                )
              else
                ListTile(
                  leading: const Icon(Icons.exit_to_app, color: Colors.orange),
                  title: const Text('Abandonar Hogar', style: TextStyle(color: Colors.orange)),
                  onTap: () => _confirmLeaveHousehold(context, householdId),
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Cerrar Sesión', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  await ref.read(authRepositoryProvider).signOut();
                  ref.read(activeHouseholdProvider.notifier).clear();
                  if (mounted) context.go('/auth/login');
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
