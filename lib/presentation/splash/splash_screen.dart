import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../infrastructure/auth/auth_repository.dart';
import '../../application/providers/household_provider.dart';
import '../../infrastructure/notifications/notification_service.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final authRepo = ref.read(authRepositoryProvider);
    final user = authRepo.currentUser;

    if (user == null) {
      context.go('/auth/login');
      return;
    }

    try {
      ref.read(notificationServiceProvider).requestPermissions();
    } catch (e) {
      debugPrint('FCM init failed: $e');
    }

    // En lugar de usar collectionGroup que requiere índices globales de la BD,
    // leemos directamente el perfil del usuario para ver sus casas atadas.
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (userDoc.exists) {
        final data = userDoc.data() ?? {};
        final rawHouseholds = List<String>.from(data['households'] ?? []);

        // Filtramos hogares que ya no existen (ej. el admin los eliminó)
        final validHouseholdIds = <String>[];
        final staleIds = <String>[];

        for (final id in rawHouseholds) {
          final hDoc = await FirebaseFirestore.instance
              .collection('households')
              .doc(id)
              .get();
          if (hDoc.exists) {
            // Verificar también que el usuario sigue siendo miembro activo
            // (puede haber sido eliminado por el admin)
            final memberDoc = await FirebaseFirestore.instance
                .collection('households')
                .doc(id)
                .collection('members')
                .doc(user.uid)
                .get();

            if (memberDoc.exists) {
              validHouseholdIds.add(id);
            } else {
              // El hogar existe pero el usuario ya no es miembro
              staleIds.add(id);
            }
          } else {
            staleIds.add(id);
          }
        }

        // Limpiar referencias huérfanas del perfil del usuario
        if (staleIds.isNotEmpty) {
          FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set(
                {'households': FieldValue.arrayRemove(staleIds)},
                SetOptions(merge: true),
              );
        }

        if (!mounted) return;

        if (validHouseholdIds.length == 1) {
          ref.read(activeHouseholdProvider.notifier).setHousehold(validHouseholdIds.first);
          context.go('/home/tasks');
          return;
        } else if (validHouseholdIds.length > 1) {
          context.go('/household-selection');
          return;
        }
      }

      context.go('/onboarding');
    } catch (e) {
      debugPrint('Splash error: $e');
      if (mounted) context.go('/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.home_outlined, size: 80, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            CircularProgressIndicator(color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}

