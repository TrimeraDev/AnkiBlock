import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/di/providers.dart';
import 'core/navigation/router.dart';
import 'core/services/ankidroid_service.dart';
import 'core/services/apps_service.dart';
import 'core/services/settings_protection_service.dart';
import 'core/setup/setup_actions.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/study_day.dart';
import 'core/utils/blocking_goal.dart';
import 'core/widgets/global_blocking_permission_banner.dart';

class AnkiBlockApp extends ConsumerStatefulWidget {
  const AnkiBlockApp({super.key});

  @override
  ConsumerState<AnkiBlockApp> createState() => _AnkiBlockAppState();
}

class _AnkiBlockAppState extends ConsumerState<AnkiBlockApp>
    with WidgetsBindingObserver {
  StreamSubscription<GateRequest>? _gateSub;
  StreamSubscription<void>? _openHomeSub;
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
    await mergeDailyFromNative(ref);
    await syncStudyScopeToNative(ref);
    await syncBlockRuleToNative(ref);
    await ensureAppMonitorRunning(ref);
    await syncDailyGoalToNative(ref);
    await _restoreDelegatedSessionProgress();
    // Refresh live Anki due counts after studying (or any background trip).
    ref.invalidate(studyCountsProvider);
    ref.invalidate(ankiDroidDecksProvider);
    ref.invalidate(ankiDroidStatusProvider);
    ref.invalidate(dailyStatsProvider(studyDayKey()));
  }

  Future<void> _restoreDelegatedSessionProgress() async {
    final state = await ref.read(appsServiceProvider).getDelegatedSessionState();
    if (state == null || state.packageName == kPracticeStudyPackage) {
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
    await ensureAppMonitorRunning(ref);
    await syncDailyGoalToNative(ref);
  }

  Future<void> _bootstrap() async {
    final svc = ref.read(appsServiceProvider);
    _gateSub = svc.gateRequests.listen(_handleGate);
    _openHomeSub = svc.openHomeRequests.listen((_) => _openHome());
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

    // Gate from cold start: route immediately, sync in background.
    final pending = await svc.consumePendingGate();
    if (pending != null) {
      _handleGate(pending);
    }

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
    await mergeDailyFromNative(ref);
    await ensureAppMonitorRunning(ref);
    await syncDailyGoalToNative(ref);

    unawaited(_syncNativeWhenAnkiReady());
    unawaited(ref.read(installedAppsProvider.future));
  }

  void _handleGate(GateRequest req) {
    unawaited(_routeGate(req));
  }

  void _openHome() {
    ref.read(routerProvider).go('/');
  }

  Future<void> _routeGate(GateRequest req) async {
    final router = ref.read(routerProvider);

    // Paint the gate immediately — never wait on AnkiDroid / Drift before
    // navigation. Overnight hangs on ContentProvider used to leave a blank
    // MainActivity while native blocking had already fired.
    router.go('/gate', extra: {
      'packageName': req.packageName,
      'appName': req.appName,
    });
    // StudyGateScreen signals ready after its first frame paints — calling
    // here dismissed the native splash before Flutter rendered (blank screen).
    unawaited(_restoreDelegatedSessionProgress());
    unawaited(_resolveGateShortcuts(req));
  }

  /// After the gate is visible, skip it when the user is already free.
  Future<void> _resolveGateShortcuts(GateRequest req) async {
    final router = ref.read(routerProvider);
    final apps = ref.read(appsServiceProvider);
    try {
      final unlocked = await apps
          .isTemporarilyUnlocked(req.packageName)
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
      if (unlocked) {
        await apps.launchApp(req.packageName);
        router.go('/');
        return;
      }

      final rule = await ref
          .read(blockRuleProvider.future)
          .timeout(const Duration(seconds: 2));
      final unlockGoal = rule?.cardsRequired ?? 10;
      if (await apps
          .tryUnlockFromRecentBout(
            packageName: req.packageName,
            appName: req.appName,
            target: unlockGoal,
          )
          .timeout(const Duration(seconds: 2), onTimeout: () => false)) {
        await apps.launchApp(req.packageName);
        router.go('/');
        return;
      }

      final day = studyDayKey();
      final reviewed = (await ref
                  .read(databaseProvider)
                  .getDailyStat(day)
                  .timeout(const Duration(seconds: 2)))
              ?.cardsReviewed ??
          0;
      final mode = StudyMode.fromStorage(rule?.studyMode);
      // Bound AnkiDroid due-count lookup — hang must not strand the gate.
      int due = 0;
      try {
        final counts = await ref.read(studyCountsProvider.future).timeout(
              const Duration(seconds: 2),
              onTimeout: () => AnkiDroidCounts.zero,
            );
        due = counts.obligationDue;
      } catch (_) {
        due = 0;
      }
      if (isBlockingGoalComplete(
        mode: mode,
        dailyCardsGoal: rule?.dailyCardsGoal ?? 0,
        cardsReviewed: reviewed,
        obligationDue: due,
      )) {
        await apps.launchApp(req.packageName);
        router.go('/');
      }
    } catch (_) {
      // Keep the gate visible on any shortcut-check failure.
    }
  }

  Future<void> _handleDelegatedUnlock(int cardsCompleted) async {
    final protectionSvc = ref.read(settingsProtectionServiceProvider);
    if (await protectionSvc.consumeStrictStudyPending()) {
      await protectionSvc.recordStrictStudyCompleted();
    }
    ref.read(delegatedSessionProgressProvider.notifier).state = null;
    ref.read(delegatedProgressCreditFloorProvider.notifier).state = 0;
    _lastProgressCounted = 0;
    final today = studyDayKey();
    final db = ref.read(databaseProvider);
    // Cards are credited incrementally via the progress listener.
    await db.incrementUnlocksEarned(today);
    await syncDailyGoalToNative(ref);
    ref.invalidate(dailyStatsProvider(today));
    ref.invalidate(studyProgressProvider);
    ref.invalidate(studyCountsProvider);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gateSub?.cancel();
    _openHomeSub?.cancel();
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
