import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/di/providers.dart';
import 'core/navigation/router.dart';
import 'core/services/apps_service.dart';
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
  StreamSubscription<GateRequest>? _gateSub;
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
      unawaited(_onResume());
    }
  }

  Future<void> _recordAppOpen() async {
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
    await ensureAppMonitorRunning(ref);
    await syncDailyGoalToNative(ref);
  }

  Future<void> _syncNativeWhenAnkiReady() async {
    final status = await ref.read(ankiDroidStatusProvider.future);
    if (!status.isReady) return;
    await syncStudyScopeToNative(ref);
    await ensureAppMonitorRunning(ref);
    await syncDailyGoalToNative(ref);
  }

  Future<void> _bootstrap() async {
    final svc = ref.read(appsServiceProvider);
    _gateSub = svc.gateRequests.listen(_handleGate);
    _delegatedUnlockSub = svc.delegatedUnlocks.listen(_handleDelegatedUnlock);
    _delegatedProgressSub = svc.delegatedProgress.listen((progress) async {
      ref.read(delegatedSessionProgressProvider.notifier).state = progress;
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

    // Re-sync blocked list and start monitor on every cold start
    final db = ref.read(databaseProvider);
    final all = await db.watchAllBlockedApps().first;
    final active = all
        .where((b) => b.isBlocked)
        .map((b) => (pkg: b.packageName, name: b.displayName))
        .toList();
    await svc.setBlockedPackages(active);
    await syncStudyScopeToNative(ref);
    await mergeDailyFromNative(ref);
    await ensureAppMonitorRunning(ref);
    await syncDailyGoalToNative(ref);

    unawaited(_syncNativeWhenAnkiReady());

    // If launched from a gate intent, consume and route
    final pending = await svc.consumePendingGate();
    if (pending != null) _handleGate(pending);

    // Warm the installed-apps cache in the background so the blocking screen
    // opens instantly on repeat visits.
    unawaited(ref.read(installedAppsProvider.future));
  }

  void _handleGate(GateRequest req) {
    unawaited(_routeGate(req));
  }

  Future<void> _routeGate(GateRequest req) async {
    final rule = await ref.read(blockRuleProvider.future);
    final day = studyDayKey();
    final reviewed =
        (await ref.read(databaseProvider).getDailyStat(day))?.cardsReviewed ?? 0;
    if (isDailyGoalComplete(
      dailyGoal: rule?.dailyCardsGoal ?? 0,
      cardsReviewed: reviewed,
    )) {
      await ref.read(appsServiceProvider).launchApp(req.packageName);
      return;
    }
    final router = ref.read(routerProvider);
    router.go('/gate', extra: {
      'packageName': req.packageName,
      'appName': req.appName,
    });
  }

  Future<void> _handleDelegatedUnlock(int cardsCompleted) async {
    ref.read(delegatedSessionProgressProvider.notifier).state = null;
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
