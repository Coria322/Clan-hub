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
      if (!context.mounted) return;
      context.go('/onboarding');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
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
      if (!context.mounted) return;
      context.go('/onboarding');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _showChangePasswordDialog(BuildContext context) async {
    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ChangePasswordDialog(
        onSave: (newPassword) async {
          await ref.read(authRepositoryProvider).updatePassword(newPassword);
        },
      ),
    );

    if (success == true && context.mounted) {
      final theme = Theme.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('🔑 Contraseña actualizada con éxito.'),
          backgroundColor: theme.colorScheme.tertiary,
        ),
      );
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
      appBar: AppBar(
        title: const Text('Ajustes y Perfil', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Inter')),
        centerTitle: false,
      ),
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
            padding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 120.0),
            physics: const BouncingScrollPhysics(),
            children: [
              // Header Card
              Container(
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.primaryContainer,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.home_rounded, size: 48, color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        isAdmin ? 'Eres Administrador' : 'Eres Miembro',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              _buildSectionHeader('General'),
              _buildSettingsGroup([
                _buildSettingsTile(
                  icon: Icons.tag,
                  iconColor: Colors.deepPurple,
                  title: 'Código de Invitación',
                  subtitle: inviteCode,
                  trailing: IconButton(
                    icon: const Icon(Icons.copy, color: Colors.grey, size: 20),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: inviteCode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Código copiado al portapapeles')),
                      );
                    },
                  ),
                ),
                const Divider(height: 1, indent: 64),
                _buildSettingsTile(
                  icon: Icons.swap_horiz_rounded,
                  iconColor: Colors.blue,
                  title: 'Cambiar de Hogar',
                  onTap: () => context.push('/household-selection'),
                ),
              ]),

              _buildSectionHeader('Miembros y Roles'),
              _buildSettingsGroup([
                _buildSettingsTile(
                  icon: Icons.people_alt_rounded,
                  iconColor: Colors.teal,
                  title: 'Administrar Miembros',
                  onTap: () => context.push('/home/settings/members'),
                ),
                const Divider(height: 1, indent: 64),
                _buildSettingsTile(
                  icon: Icons.category_rounded,
                  iconColor: Colors.orange,
                  title: 'Categorías de Tareas',
                  onTap: () => context.push('/home/settings/categories'),
                ),
              ]),

              _buildSectionHeader('Cuenta y Zona de Peligro'),
              _buildSettingsGroup([
                _buildSettingsTile(
                  icon: Icons.lock_outline_rounded,
                  iconColor: Colors.indigo,
                  title: 'Cambiar Contraseña',
                  onTap: () => _showChangePasswordDialog(context),
                ),
                const Divider(height: 1, indent: 64),
                if (isAdmin)
                  _buildSettingsTile(
                    icon: Icons.delete_forever_rounded,
                    iconColor: Colors.redAccent,
                    title: 'Eliminar Hogar',
                    subtitle: 'Acción irreversible',
                    isDestructive: true,
                    onTap: () => _confirmDeleteHousehold(context, householdId),
                  )
                else
                  _buildSettingsTile(
                    icon: Icons.exit_to_app_rounded,
                    iconColor: Colors.deepOrange,
                    title: 'Abandonar Hogar',
                    isDestructive: true,
                    onTap: () => _confirmLeaveHousehold(context, householdId),
                  ),
                const Divider(height: 1, indent: 64),
                _buildSettingsTile(
                  icon: Icons.logout_rounded,
                  iconColor: Colors.red,
                  title: 'Cerrar Sesión',
                  isDestructive: true,
                  onTap: () async {
                    await ref.read(authRepositoryProvider).signOut();
                    ref.read(activeHouseholdProvider.notifier).clear();
                    if (!context.mounted) return;
                    context.go('/auth/login');
                  },
                ),
              ]),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 12, top: 32),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSettingsGroup(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4352A5).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool isDestructive = false,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: isDestructive ? Colors.redAccent.shade700 : const Color(0xFF1a1a2e),
        ),
      ),
      subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(fontSize: 13, color: Colors.grey)) : null,
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded, size: 22, color: Colors.grey),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  final Future<void> Function(String newPassword) onSave;

  const _ChangePasswordDialog({required this.onSave});

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscureText = true;
  bool _saving = false;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _saving = true);
    try {
      await widget.onSave(_passwordCtrl.text.trim());
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Error de Seguridad'),
            content: Text(e.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar Contraseña'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _passwordCtrl,
              decoration: InputDecoration(
                labelText: 'Nueva Contraseña',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscureText ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscureText = !_obscureText),
                ),
              ),
              obscureText: _obscureText,
              enabled: !_saving,
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Ingresa la contraseña';
                }
                if (val.trim().length < 6) {
                  return 'Mínimo 6 caracteres';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmCtrl,
              decoration: const InputDecoration(
                labelText: 'Confirmar Contraseña',
                border: OutlineInputBorder(),
              ),
              obscureText: _obscureText,
              enabled: !_saving,
              validator: (val) {
                if (val != _passwordCtrl.text) {
                  return 'Las contraseñas no coinciden';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Cambiar'),
        ),
      ],
    );
  }
}
