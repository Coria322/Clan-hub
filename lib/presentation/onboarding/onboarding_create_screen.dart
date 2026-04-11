import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../infrastructure/auth/auth_repository.dart';
import '../../infrastructure/household/household_repository.dart';
import '../../application/providers/household_provider.dart';

class OnboardingCreateScreen extends ConsumerStatefulWidget {
  const OnboardingCreateScreen({super.key});

  @override
  ConsumerState<OnboardingCreateScreen> createState() => _OnboardingCreateScreenState();
}

class _OnboardingCreateScreenState extends ConsumerState<OnboardingCreateScreen> {
  final _nameController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || name.length > 50) {
      setState(() => _errorMessage = 'Introduce un nombre válido (máx 50 caracteres).');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = ref.read(authRepositoryProvider).currentUser;
      if (user == null) throw Exception('Usuario no autenticado');
      final displayName = user.displayName ?? user.email ?? 'Usuario';

      final householdId = await ref.read(householdRepositoryProvider).createHousehold(name, user.uid, displayName);
      
      // Actualizamos el provider activo
      ref.read(activeHouseholdProvider.notifier).setHousehold(householdId);
      
      if (mounted) {
        context.go('/home'); // O a una pantalla de éxito
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear Hogar')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Dale un nombre a tu nuevo hogar.'),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre del hogar (ej. Familia Pérez)',
                border: OutlineInputBorder(),
              ),
              maxLength: 50,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isLoading ? null : _create,
              child: _isLoading 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Crear y Continuar'),
            ),
          ],
        ),
      ),
    );
  }
}
