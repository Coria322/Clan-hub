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
import '../../presentation/household_selection/household_selection_screen.dart';
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

  Widget _buildNavItem(BuildContext context, {
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isActive = navigationShell.currentIndex == index;

    return GestureDetector(
      onTap: () => navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      ),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? (isDark
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                  : theme.colorScheme.primary.withValues(alpha: 0.08)) // Equivalent to bg-indigo-50
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      extendBody: true, // Allows body to scroll behind the transparent nav bar if needed
      body: Column(
        children: [
          const _OfflineBanner(),
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24), // iOS safe area / visual thickness padding
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF151B2B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9), // slate-800 / slate-100
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF5C6BC0).withValues(alpha: 0.08), // shadow-[0_-4px_12px_rgba(92,107,192,0.08)]
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildNavItem(
                context,
                index: 0,
                icon: Icons.check_circle_outline,
                activeIcon: Icons.check_circle,
                label: 'Tareas',
              ),
              _buildNavItem(
                context,
                index: 1,
                icon: Icons.bar_chart_outlined,
                activeIcon: Icons.bar_chart,
                label: 'Dashboard',
              ),
              _buildNavItem(
                context,
                index: 2,
                icon: Icons.settings_outlined,
                activeIcon: Icons.settings,
                label: 'Ajustes',
              ),
            ],
          ),
        ),
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

      // ── Household Selection ──
      GoRoute(
        path: '/household-selection',
        builder: (context, state) => const HouseholdSelectionScreen(),
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
