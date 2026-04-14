import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../presentation/splash/splash_screen.dart';
import '../../presentation/auth/login_screen.dart';
import '../../presentation/auth/register_screen.dart';
import '../../presentation/onboarding/onboarding_main_screen.dart';
import '../../presentation/onboarding/onboarding_create_screen.dart';
import '../../presentation/onboarding/onboarding_join_screen.dart';
import '../../presentation/settings/household_settings_screen.dart';
import '../../presentation/settings/members_management_screen.dart';
import '../../presentation/settings/categories_screen.dart';
import '../../presentation/task/tasks_list_screen.dart';
import '../../presentation/task/create_task_screen.dart';
import '../../presentation/task/task_detail_screen.dart';
import '../../presentation/dashboard/dashboard_screen.dart';

// ──────────────────────────────────────────────
// Shell de navegación: bottom nav bar del /home
// ──────────────────────────────────────────────
class _HomeShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const _HomeShell({required this.navigationShell});

  static const _tabs = [
    NavigationDestination(
      icon: Icon(Icons.check_circle_outline),
      selectedIcon: Icon(Icons.check_circle),
      label: 'Tareas',
    ),
    NavigationDestination(
      icon: Icon(Icons.bar_chart_outlined),
      selectedIcon: Icon(Icons.bar_chart),
      label: 'Dashboard',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Ajustes',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const _OfflineBanner(),
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: _tabs,
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ConnectivityResult>>(
      stream: Connectivity().onConnectivityChanged,
      builder: (context, snapshot) {
        final results = snapshot.data ?? [ConnectivityResult.wifi];
        final isOffline = results.isEmpty || results.contains(ConnectivityResult.none);
        
        if (!isOffline) return const SizedBox.shrink();

        return SafeArea(
          bottom: false,
          child: Container(
            color: Colors.amber.shade700,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: const Text(
              'Sin conexión — mostrando datos guardados',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────
// Router principal
// ──────────────────────────────────────────────
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    routes: [
      // ── Splash ──
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),

      // ── Auth ──
      GoRoute(
        path: '/auth/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/auth/register',
        builder: (context, state) => const RegisterScreen(),
      ),

      // ── Onboarding ──
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingMainScreen(),
        routes: [
          GoRoute(
            path: 'create',
            builder: (context, state) => const OnboardingCreateScreen(),
          ),
          GoRoute(
            path: 'join',
            builder: (context, state) => const OnboardingJoinScreen(),
          ),
        ],
      ),

      // ── Home shell con bottom nav ──
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            _HomeShell(navigationShell: navigationShell),
        branches: [
          // Tab 0 — Tareas
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/tasks',
                builder: (context, state) => const TasksListScreen(),
                routes: [
                  GoRoute(
                    path: 'create',
                    builder: (context, state) => const CreateTaskScreen(),
                  ),
                  GoRoute(
                    path: ':id',
                    builder: (context, state) =>
                        TaskDetailScreen(taskId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),

          // Tab 1 — Dashboard
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/dashboard',
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),

          // Tab 2 — Ajustes
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/settings',
                builder: (context, state) => const HouseholdSettingsScreen(),
                routes: [
                  GoRoute(
                    path: 'members',
                    builder: (context, state) => const MembersManagementScreen(),
                  ),
                  GoRoute(
                    path: 'categories',
                    builder: (context, state) => const CategoriesScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),

      // Ruta /home legacy → redirige al tab de tareas
      GoRoute(
        path: '/home',
        redirect: (context, state) => '/home/tasks',
      ),
    ],
  );
});
