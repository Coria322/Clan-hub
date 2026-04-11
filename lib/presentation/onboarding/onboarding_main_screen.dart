import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../infrastructure/auth/auth_repository.dart';

class OnboardingMainScreen extends ConsumerWidget {
  const OnboardingMainScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bienvenido'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authRepositoryProvider).signOut();
              if (context.mounted) {
                context.go('/auth/login');
              }
            },
            tooltip: 'Cerrar Sesión',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.maps_home_work_outlined, size: 80, color: Color(0xFF4CAF82)),
            const SizedBox(height: 32),
            Text(
              '¡Parece que aún no vives en ninguna casa en la app!',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Para empezar a gestionar tus tareas, necesitas unirte a un hogar o crear el tuyo propio.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 64),
            FilledButton.icon(
              onPressed: () => context.push('/onboarding/create'),
              icon: const Icon(Icons.add),
              label: const Text('Crear un Hogar Nuevo'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => context.push('/onboarding/join'),
              icon: const Icon(Icons.group_add),
              label: const Text('Unirme con un Código'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
