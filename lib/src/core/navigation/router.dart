import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/today/today_screen.dart';
import '../../features/decks/decks_screen.dart';
import '../../features/blocking/blocking_screen.dart';
import '../../features/review/review_screen.dart';
import '../../features/gate/study_gate_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/settings/ankidroid_screen.dart';
import '../../features/settings/permissions_screen.dart';
import '../../features/settings/settings_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) async {
      final isOnboardingComplete =
          await ref.read(onboardingCompleteProvider.future);
      if (!isOnboardingComplete && state.matchedLocation != '/onboarding') {
        return '/onboarding';
      }
      if (isOnboardingComplete && state.matchedLocation == '/onboarding') {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const TodayScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/decks',
        builder: (context, state) => const DecksScreen(),
      ),
      GoRoute(
        path: '/blocking',
        builder: (context, state) => const BlockingScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/permissions',
        builder: (context, state) => const PermissionsScreen(),
      ),
      GoRoute(
        path: '/ankidroid',
        builder: (context, state) => const AnkiDroidScreen(),
      ),
      GoRoute(
        path: '/review',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return ReviewScreen(
            unlockPackage: extra?['unlockPackage'] as String?,
            unlockAppName: extra?['unlockAppName'] as String?,
            cardLimit: extra?['cardLimit'] as int? ?? 0,
          );
        },
      ),
      GoRoute(
        path: '/gate',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return StudyGateScreen(
            packageName: extra?['packageName'] as String? ?? '',
            appName: extra?['appName'] as String? ?? 'App',
          );
        },
      ),
    ],
  );
});

const _onboardingKey = 'onboarding_complete';

final onboardingCompleteProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_onboardingKey) ?? false;
});

Future<void> markOnboardingComplete(WidgetRef ref) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_onboardingKey, true);
  ref.invalidate(onboardingCompleteProvider);
}
