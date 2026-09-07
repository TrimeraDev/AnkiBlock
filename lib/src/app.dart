import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/di/providers.dart';
import 'core/navigation/router.dart';
import 'core/services/apps_service.dart';
import 'core/services/settings_protection_service.dart';
import 'core/setup/setup_actions.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/study_day.dart';
import 'core/widgets/global_blocking_permission_banner.dart';

class AnkiBlockApp extends ConsumerStatefulWidget {
  const AnkiBlockApp({super.key});

  @override
  ConsumerState<AnkiBlockApp> createState() => _AnkiBlockAppState();
}

class _AnkiBlockAppState extends ConsumerState<AnkiBlockApp>
    with WidgetsBindingObserver {
  StreamSubscription<int>? _delegatedUnlockSub;
  StreamSubscription<DelegatedSessionProgress>? _delegatedProgressSub;
  StreamSubscription<int>? _passiveStudySub;
  int _lastProgressCounted = 0;
  bool _countNextResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrap());
      unawaited(_recordAppOpen());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _countNextResume = true;
    }
    if (state == AppLifecycleState.resumed) {
      if (_countNextResume) {
        _countNextResume = false;
        unawaited(_recordAppOpen());
      }
      ref.invalidate(blockingPermissionsProvider);
      ref.invalidate(protectionStatusProvider);
      unawaited(_onResume());
    }
  }

  Future<void> _recordAppOpen() async {
    final onboardingDone = await ref.read(onboardingCompleteProvider.future);
    // Permission settings trips during setup must not count as opens.
    if (!onboardingDone) return;

    final service = ref.read(supportPromptServiceProvider);
    final count = await service.recordLaunch();
    ref.read(appLaunchCountProvider.notifier).state = count;
    if (await service.shouldShowPrompt(count)) {
      ref.read(supportPromptVisibleProvider.notifier).state = true;
    }
  }

  Future<void> _onResume() async {
    await _mergeFromNative();
    await syncStudyScopeToNative(ref);
    await syncBlockRuleToNative(ref);
    await syncDailyGoalToNative(ref);
    await _restoreDelegatedSessionProgress();
    // Refresh live Anki due counts after studying (or any background trip).
    ref.invalidate(studyCountsProvider);
    ref.invalidate(ankiDroidDecksProvider);
    ref.invalidate(ankiDroidStatusProvider);
    ref.invalidate(dailyStatsProvider(studyDayKey()));
  }

  /// Pulls native-owned stats. Unlocks earned through the native gate while
  /// Flutter was not running also settle any strict-protection study debt.
  Future<void> _mergeFromNative() async {
    final newUnlocks = await mergeDailyFromNative(ref);
    if (newUnlocks > 0) {
      await _settleStrictStudy();
    }
  }

  Future<void> _restoreDelegatedSessionProgress() async {
    final state = await ref.read(appsServiceProvider).getDelegatedSessionState();
    if (state == null || state.packageName != kPracticeStudyPackage) {
      return;
    }
    final existing = ref.read(delegatedSessionProgressProvider);
    if (existing != null &&
        existing.isForPackage(state.packageName) &&
        existing.completed >= state.completed) {
      return;
    }
    ref.read(delegatedProgressCreditFloorProvider.notifier).state = state.seeded;
    if (_lastProgressCounted < state.seeded) {
      _lastProgressCounted = state.seeded;
    }
    ref.read(delegatedSessionProgressProvider.notifier).state =
        DelegatedSessionProgress(
      completed: state.completed,
      target: state.target,
      packageName: state.packageName,
    );
  }

  Future<void> _syncNativeWhenAnkiReady() async {
    final status = await ref.read(ankiDroidStatusProvider.future);
    if (!status.isReady) return;
    await syncStudyScopeToNative(ref);
    await syncBlockRuleToNative(ref);
    await syncDailyGoalToNative(ref);
  }

  Future<void> _bootstrap() async {
    final svc = ref.read(appsServiceProvider);
    _delegatedUnlockSub = svc.delegatedUnlocks.listen(_handleDelegatedUnlock);
    _delegatedProgressSub = svc.delegatedProgress.listen((progress) async {
      ref.read(delegatedSessionProgressProvider.notifier).state = progress;
      final floor = ref.read(delegatedProgressCreditFloorProvider);
      if (_lastProgressCounted < floor) {
        _lastProgressCounted = floor;
      }
      if (progress.completed <= _lastProgressCounted) return;
      final delta = progress.completed - _lastProgressCounted;
      _lastProgressCounted = progress.completed;
      final day = studyDayKey();
      final db = ref.read(databaseProvider);
      await db.incrementCardsReviewedBy(day, delta);
      await syncDailyGoalToNative(ref);
      ref.invalidate(dailyStatsProvider(day));
      ref.invalidate(studyProgressProvider);
    });

    _passiveStudySub = svc.passiveStudyProgress.listen((delta) async {
      final day = studyDayKey();
      final db = ref.read(databaseProvider);
      await db.incrementCardsReviewedBy(day, delta);
      ref.invalidate(dailyStatsProvider(day));
      ref.invalidate(studyProgressProvider);
    });

    unawaited(_syncBootstrap());
  }

  Future<void> _syncBootstrap() async {
    final svc = ref.read(appsServiceProvider);
    final db = ref.read(databaseProvider);
    final all = await db.watchAllBlockedApps().first;
    final active = all
        .where((b) => b.isBlocked)
        .map((b) => (pkg: b.packageName, name: b.displayName))
        .toList();
    await svc.setBlockedPackages(active);
    await syncStudyScopeToNative(ref);
    await syncBlockRuleToNative(ref);
    await _mergeFromNative();
    await syncDailyGoalToNative(ref);

    unawaited(_syncNativeWhenAnkiReady());
    unawaited(ref.read(installedAppsProvider.future));
  }

  Future<void> _settleStrictStudy() async {
    final protectionSvc = ref.read(settingsProtectionServiceProvider);
    if (await protectionSvc.consumeStrictStudyPending()) {
      await protectionSvc.recordStrictStudyCompleted();
    }
  }

  /// Live unlock while Flutter is running (practice / strict-study session
  /// completed, or a gate unlock while AnkiBlock sits in the background).
  Future<void> _handleDelegatedUnlock(int cardsCompleted) async {
    await _settleStrictStudy();
    ref.read(delegatedSessionProgressProvider.notifier).state = null;
    ref.read(delegatedProgressCreditFloorProvider.notifier).state = 0;
    _lastProgressCounted = 0;
    // Cards are credited incrementally via the progress listener; the
    // unlocks-earned counter is native-owned and merged on resume.
    await mergeDailyFromNative(ref);
    ref.invalidate(studyCountsProvider);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _delegatedUnlockSub?.cancel();
    _delegatedProgressSub?.cancel();
    _passiveStudySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'AnkiBlock',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: router,
      builder: (context, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SafeArea(
              bottom: false,
              left: false,
              right: false,
              minimum: EdgeInsets.zero,
              child: GlobalBlockingPermissionBanner(),
            ),
            Expanded(child: child ?? const SizedBox.shrink()),
          ],
        );
      },
    );
  }
}
