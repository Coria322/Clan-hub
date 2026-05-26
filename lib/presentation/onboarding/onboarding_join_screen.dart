import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../infrastructure/auth/auth_repository.dart';
import '../../infrastructure/household/household_repository.dart';
import '../../application/providers/household_provider.dart';

class OnboardingJoinScreen extends ConsumerStatefulWidget {
  const OnboardingJoinScreen({super.key});

  @override
  ConsumerState<OnboardingJoinScreen> createState() => _OnboardingJoinScreenState();
}

class _OnboardingJoinScreenState extends ConsumerState<OnboardingJoinScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length != 6) {
      setState(() => _errorMessage = 'El código debe tener exactamente 6 caracteres.');
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

      final householdId = await ref.read(householdRepositoryProvider).joinHousehold(code, user.uid, displayName);
      
      ref.read(activeHouseholdProvider.notifier).setHousehold(householdId);
      ref.invalidate(userHouseholdsProvider);
      
      if (mounted) {
        context.go('/home');
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
      appBar: AppBar(title: const Text('Unirme a un Hogar')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Pide a un administrador el código de invitación (6 caracteres).'),
            const SizedBox(height: 24),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: 'Código de invitación',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
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
            ElevatedButton(
              onPressed: _isLoading ? null : _join,
              child: _isLoading 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Verificar y Unirse'),
            ),
          ],
        ),
      ),
    );
  }
}
