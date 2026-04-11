import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/splash/splash_screen.dart';
import '../../presentation/auth/login_screen.dart';
import '../../presentation/auth/register_screen.dart';
import '../../presentation/onboarding/onboarding_main_screen.dart';
import '../../presentation/onboarding/onboarding_create_screen.dart';
import '../../presentation/onboarding/onboarding_join_screen.dart';
import '../../presentation/settings/household_settings_screen.dart';
import '../../presentation/settings/members_management_screen.dart';
import '../../presentation/settings/categories_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/auth/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/auth/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => Scaffold(
          appBar: AppBar(
            title: const Text('Home Dashboard'),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => context.push('/settings'),
              )
            ],
          ),
          body: const Center(child: Text('Home Screen Placeholder (Fase 3)')),
        ),
      ),
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
      GoRoute(
        path: '/settings',
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
  );
});
