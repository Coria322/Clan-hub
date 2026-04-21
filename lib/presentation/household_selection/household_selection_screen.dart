import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../application/providers/household_provider.dart';
import '../../infrastructure/auth/auth_repository.dart';

class HouseholdSelectionScreen extends ConsumerWidget {
  const HouseholdSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final householdsAsync = ref.watch(userHouseholdsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tus Hogares'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authRepositoryProvider).signOut();
              ref.read(activeHouseholdProvider.notifier).clear();
              if (context.mounted) context.go('/auth/login');
            },
            tooltip: 'Cerrar sesión',
          )
        ],
      ),
      body: householdsAsync.when(
        data: (households) {
          if (households.isEmpty) {
            return _buildEmptyState(context);
          }
          return _buildList(context, ref, households, theme);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text('Error: $error\nIntenta reiniciar la app.'),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, WidgetRef ref, List<Map<String, String>> households, ThemeData theme) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Text(
            '¿A qué hogar deseas entrar?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: households.length,
            itemBuilder: (context, index) {
              final h = households[index];
              return Card(
                elevation: 1,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    ref.read(activeHouseholdProvider.notifier).setHousehold(h['id']!);
                    context.go('/home/tasks');
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.home, color: theme.colorScheme.onPrimaryContainer),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            h['name'] ?? 'Hogar',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                OutlinedButton.icon(
                  onPressed: () => context.push('/onboarding/join'),
                  icon: const Icon(Icons.add_link),
                  label: const Text('Unirse a un nuevo hogar'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    side: BorderSide(color: theme.colorScheme.primary),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => context.push('/onboarding/create'),
                  icon: const Icon(Icons.add),
                  label: const Text('Crear un nuevo hogar'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
              ],
            ),
          ),
        )
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.home_work_outlined, size: 80, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('No perteneces a ningún hogar.'),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => context.go('/onboarding'),
            child: const Text('Ir al Onboarding'),
          ),
        ],
      ),
    );
  }
}
