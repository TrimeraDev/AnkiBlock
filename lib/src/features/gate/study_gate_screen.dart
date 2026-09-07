import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/assets/app_assets.dart';
import '../../core/di/providers.dart';
import '../../core/services/ankidroid_service.dart';
import '../../core/services/study_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/bypass.dart';
import '../../core/utils/blocking_goal.dart';
import '../../core/utils/deck_scope_format.dart';
import '../../core/utils/study_day.dart';
import '../../core/widgets/brand_widgets.dart';

/// Shown when the user opens a blocked app. Tells them how many cards they
/// need to answer to unlock, and routes them into AnkiDroid to study.
class StudyGateScreen extends ConsumerStatefulWidget {
  final String packageName;
  final String appName;

  const StudyGateScreen({
    super.key,
    required this.packageName,
    required this.appName,
  });

  @override
  ConsumerState<StudyGateScreen> createState() => _StudyGateScreenState();
}

class _StudyGateScreenState extends ConsumerState<StudyGateScreen>
    with WidgetsBindingObserver {
  bool _delegating = false;
  bool _bypassing = false;
  bool _autoLaunched = false;
  int _boutPreview = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(appsServiceProvider).signalGateReady());
      _recordBlockedAttempt();
      _maybeAutoLaunch();
      _loadBoutPreview();
      ref.invalidate(gateTodayUsageProvider(widget.packageName));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(gateTodayUsageProvider(widget.packageName));
      ref.invalidate(studyCountsProvider);
      ref.invalidate(dailyStatsProvider(studyDayKey()));
      unawaited(_loadBoutPreview());
    }
  }

  Future<void> _loadBoutPreview() async {
    final bout = await ref.read(appsServiceProvider).getStudyBoutCount();
    if (!mounted) return;
    setState(() => _boutPreview = bout);
  }

  Future<void> _recordBlockedAttempt() async {
    final today = studyDayKey();
    await ref.read(databaseProvider).incrementBlockedAttempts(today);
    ref.invalidate(dailyStatsProvider(today));
    ref.invalidate(studyProgressProvider);
  }

  Future<void> _maybeAutoLaunch() async {
    if (_autoLaunched) return;
    final rule = await ref.read(blockRuleProvider.future);
    final mode = StudyMode.fromStorage(rule?.studyMode);
    final dailyGoal = rule?.dailyCardsGoal ?? 30;
    final today = studyDayKey();
    final reviewed =
        (await ref.read(databaseProvider).getDailyStat(today))?.cardsReviewed ??
            0;
    final due = (await ref.read(studyCountsProvider.future)).obligationDue;
    if (!isBlockingGoalComplete(
      mode: mode,
      dailyCardsGoal: dailyGoal,
      cardsReviewed: reviewed,
      obligationDue: due,
    )) {
      return;
    }
    _autoLaunched = true;
    final launched =
        await ref.read(appsServiceProvider).launchApp(widget.packageName);
    if (mounted) {
      if (launched) {
        context.go('/');
      }
    }
  }

  Future<void> _studyInAnkiDroid({required int cardsRequired}) async {
    if (_delegating) return;
    setState(() => _delegating = true);
    try {
      final scope = await ref.read(studyScopeProvider.future);
      final decks = await ref.read(ankiDroidDecksProvider.future);
      // Always start/ensure a *gate* unlock session for this package.
      // Do not resume home-practice progress — that never grants app unlock.
      final start = await startScopedStudySession(
        ref: ref,
        scope: scope,
        decks: decks,
        cardsRequired: cardsRequired,
        unlockPackageName: widget.packageName,
        unlockAppName: widget.appName,
        forGate: true,
      );
      if (start.alreadyUnlocked) {
        final launched = await ref
            .read(appsServiceProvider)
            .launchApp(widget.packageName);
        if (mounted && launched) {
          context.go('/');
        }
      }
    } finally {
      if (mounted) setState(() => _delegating = false);
    }
  }

  Future<void> _useEmergencyBypass({required int bypassSeconds}) async {
    if (_bypassing) return;
    setState(() => _bypassing = true);
    try {
      final today = studyDayKey();
      final db = ref.read(databaseProvider);
      await db.incrementBypassesUsed(today);
      ref.invalidate(dailyStatsProvider(today));
      ref.invalidate(studyProgressProvider);

      await ref.read(appsServiceProvider).grantBypass(
            widget.packageName,
            durationMs: bypassSeconds * 1000,
          );
      final launched = await ref.read(appsServiceProvider).launchApp(
            widget.packageName,
          );
      if (!launched) return;
      if (mounted) context.go('/');
    } finally {
      if (mounted) setState(() => _bypassing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Narrow watches — avoid rebuilding the whole gate on unrelated provider noise.
    final unlockGoal =
        ref.watch(blockRuleProvider.select((a) => a.valueOrNull?.cardsRequired ?? 10));
    final dailyGoal =
        ref.watch(blockRuleProvider.select((a) => a.valueOrNull?.dailyCardsGoal ?? 30));
    final mode = StudyMode.fromStorage(
      ref.watch(blockRuleProvider.select((a) => a.valueOrNull?.studyMode)),
    );
    final bypassEnabled =
        ref.watch(blockRuleProvider.select((a) => a.valueOrNull?.bypassEnabled ?? true));
    final bypassCap =
        ref.watch(blockRuleProvider.select((a) => a.valueOrNull?.bypassDailyCap ?? 3));
    final counts = ref.watch(
          studyCountsProvider.select((a) => a.valueOrNull),
        ) ??
        AnkiDroidCounts.zero;
    final ankiReady = ref.watch(
          ankiDroidStatusProvider.select((a) => a.valueOrNull?.isReady),
        ) ??
        false;
    final decks = ref.watch(
          ankiDroidDecksProvider.select((a) => a.valueOrNull),
        ) ??
        const <AnkiDroidDeck>[];
    final scope = ref.watch(studyScopeProvider.select((a) => a.valueOrNull));
    final usageAsync = ref.watch(gateTodayUsageProvider(widget.packageName));
    final today = studyDayKey();
    final reviewed = ref.watch(
          dailyStatsProvider(today).select((a) => a.valueOrNull?.cardsReviewed),
        ) ??
        0;
    final bypassesUsed = ref.watch(
          dailyStatsProvider(today).select((a) => a.valueOrNull?.bypassesUsed),
        ) ??
        0;
    final streakAsync = ref.watch(studyStreakProvider);

    final obligation = counts.obligationDue;
    final available = counts.studyable;
    final hasDecksSelected = scope != null &&
        decks.isNotEmpty &&
        hasDecksInScope(scope, decks);
    final goalComplete = isBlockingGoalComplete(
      mode: mode,
      dailyCardsGoal: dailyGoal,
      cardsReviewed: reviewed,
      obligationDue: obligation,
    );
    final dailyRemaining = (dailyGoal - reviewed).clamp(0, dailyGoal);

    // Per-app unlock session only — ignore home practice progress.
    final rawSession = ref.watch(delegatedSessionProgressProvider);
    final session = rawSession != null &&
            rawSession.isForPackage(widget.packageName)
        ? rawSession
        : null;
    final boutCredit = _boutPreview.clamp(0, unlockGoal);
    final unlockDone = session?.completed ?? boutCredit;
    final unlockTarget = session?.target ?? unlockGoal;
    final unlockRemaining =
        goalComplete ? 0 : (unlockTarget - unlockDone).clamp(0, unlockTarget);
    final hasUnlockProgress = !goalComplete && unlockDone > 0;

    final freedomProgress = switch (mode) {
      StudyMode.dueCards => obligation <= 0 ? 1.0 : 0.0,
      StudyMode.cardCount => dailyGoal > 0
          ? (reviewed / dailyGoal).clamp(0.0, 1.0)
          : 0.0,
    };
    final unlockProgress = unlockTarget > 0
        ? (unlockDone / unlockTarget).clamp(0.0, 1.0)
        : 0.0;
    final ringProgress =
        goalComplete ? 1.0 : (session != null ? unlockProgress : freedomProgress);

    final obligationSummary =
        '${counts.learnCount} learning · ${counts.reviewCount} to review';
    final headlineBefore = goalComplete
        ? (mode == StudyMode.dueCards
            ? 'Learning & reviews done. '
            : 'Daily goal done. ')
        : 'Study first. ';
    final headlineAccent = goalComplete ? 'Enjoy.' : 'Unlock later.';

    // Primary: this app's unlock. Secondary: full-day freedom.
    final statusLine = goalComplete
        ? (mode == StudyMode.dueCards
            ? 'Unlocked · queue cleared'
            : 'Unlocked until 3am')
        : hasUnlockProgress
            ? '$unlockDone / $unlockTarget to unlock'
            : '$unlockGoal cards to unlock';
    final statusDetail = goalComplete
        ? (mode == StudyMode.dueCards
            ? 'You finished learning and reviews. All blocked apps are open '
                'until more come due.'
                '${counts.newCount > 0 ? ' ${counts.newCount} new still available.' : ''}'
            : 'You finished your daily goal. All blocked apps '
                'are open for the rest of the study day.')
        : mode == StudyMode.dueCards
            ? (hasUnlockProgress
                ? '$unlockRemaining more for a temporary unlock. '
                    '$obligationSummary left today.'
                : 'Study $unlockGoal cards for a temporary unlock. '
                    '$obligationSummary left today.')
            : (hasUnlockProgress
                ? '$unlockRemaining more for a temporary unlock. '
                    '$dailyRemaining left for freedom until 3am.'
                : 'Study $unlockGoal cards for a temporary unlock. '
                    '$dailyRemaining left for freedom until 3am.');

    final studyButtonLabel = !ankiReady
        ? 'Set up AnkiDroid first'
        : _delegating
            ? 'Opening AnkiDroid…'
            : (available == 0
                ? 'No cards due'
                : !hasDecksSelected
                    ? 'Select decks first'
                    : hasUnlockProgress
                        ? 'Continue studying'
                        : 'Study in AnkiDroid');

    const bypassSeconds = kBypassSeconds;
    final bypassesLeft = bypassesRemaining(
      bypassEnabled: bypassEnabled,
      bypassDailyCap: bypassCap,
      bypassesUsed: bypassesUsed,
    );
    final showBypass = !goalComplete &&
        bypassEnabled &&
        canUseBypass(
          bypassEnabled: bypassEnabled,
          bypassDailyCap: bypassCap,
          bypassesUsed: bypassesUsed,
        );
    final canStudy = ankiReady && available > 0 && hasDecksSelected;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: GradientProgressRing(
                    progress: ringProgress,
                    complete: goalComplete,
                    size: 120,
                    strokeWidth: 8,
                    child: Image.asset(
                      AppAssets.logo,
                      width: 56,
                      height: 56,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  widget.appName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppTheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                AccentHeadline(
                  before: headlineBefore,
                  accent: headlineAccent,
                ),
                const SizedBox(height: 10),
                StreakBanner(streakAsync: streakAsync, center: true),
                const SizedBox(height: 12),
                usageAsync.when(
                  loading: () => Text(
                    'Loading today\'s usage…',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (usage) => Text(
                    _formatTodayUsage(
                      usage.focusPickups,
                      usage.focusScreenTime,
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 16),
                BrandCard(
                  color: AppTheme.cardElevated,
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            goalComplete
                                ? Icons.lock_open_outlined
                                : Icons.lock_outline,
                            size: 18,
                            color: AppTheme.accent,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            statusLine,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        statusDetail,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (!ankiReady) ...[
                  const SizedBox(height: 20),
                  const _AnkiDroidWarning(),
                ],
                if (ankiReady && !hasDecksSelected) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Select at least one deck for study to count.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.go('/decks'),
                    child: const Text('Choose decks'),
                  ),
                ],
                if (ankiReady && hasDecksSelected && available == 0) ...[
                  const SizedBox(height: 16),
                  Text(
                    'No learning or review cards right now. Come back when '
                    'AnkiDroid has cards waiting.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.onSurfaceVariant,
                        ),
                  ),
                ],
                const SizedBox(height: 28),
                if (!goalComplete)
                  GradientButton(
                    onPressed: !ankiReady
                        ? () => context.push('/ankidroid')
                        : canStudy && !_delegating
                            ? () => _studyInAnkiDroid(
                                  cardsRequired: unlockGoal,
                                )
                            : null,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_delegating)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.onPrimary,
                            ),
                          )
                        else
                          const Icon(Icons.open_in_new),
                        const SizedBox(width: 8),
                        Text(studyButtonLabel),
                      ],
                    ),
                  ),
                if (showBypass) ...[
                  const SizedBox(height: 12),
                  _HoldToBypassButton(
                    bypassSeconds: bypassSeconds,
                    remainingBypasses: bypassesLeft,
                    busy: _bypassing,
                    onConfirmed: () =>
                        _useEmergencyBypass(bypassSeconds: bypassSeconds),
                  ),
                ],
                if (!goalComplete && bypassEnabled && bypassesLeft == 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    'No emergency bypasses left today. Study to unlock.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.onSurfaceVariant,
                        ),
                  ),
                ],
                if (goalComplete) ...[
                  GradientButton(
                    onPressed: () async {
                      final ok = await ref
                          .read(appsServiceProvider)
                          .launchApp(widget.packageName);
                      if (mounted && ok) context.go('/');
                    },
                    child: Text('Open ${widget.appName}'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatTodayUsage(int pickups, Duration screenTime) {
    final opens = pickups == 1 ? '1 open' : '$pickups opens';
    final h = screenTime.inHours;
    final m = screenTime.inMinutes.remainder(60);
    final duration = h > 0 ? '${h}h, $m min' : '$m min';
    return '$opens today · $duration on this app';
  }
}

class _HoldToBypassButton extends StatefulWidget {
  final int bypassSeconds;
  final int remainingBypasses;
  final bool busy;
  final VoidCallback onConfirmed;

  const _HoldToBypassButton({
    required this.bypassSeconds,
    required this.remainingBypasses,
    required this.busy,
    required this.onConfirmed,
  });

  @override
  State<_HoldToBypassButton> createState() => _HoldToBypassButtonState();
}

class _HoldToBypassButtonState extends State<_HoldToBypassButton> {
  static const _holdDuration = Duration(seconds: 3);
  static const _tick = Duration(milliseconds: 50);

  Timer? _timer;
  double _progress = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startHold() {
    if (widget.busy) return;
    _timer?.cancel();
    _timer = Timer.periodic(_tick, (_) {
      setState(() {
        _progress += _tick.inMilliseconds / _holdDuration.inMilliseconds;
        if (_progress >= 1) {
          _timer?.cancel();
          _progress = 0;
          widget.onConfirmed();
        }
      });
    });
  }

  void _cancelHold() {
    _timer?.cancel();
    if (_progress > 0) {
      setState(() => _progress = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.busy
        ? 'Opening ${widget.bypassSeconds}s access…'
        : 'Hold for emergency ${widget.bypassSeconds}s access';

    return Listener(
      onPointerDown: (_) => _startHold(),
      onPointerUp: (_) => _cancelHold(),
      onPointerCancel: (_) => _cancelHold(),
      child: OutlinedButton(
        onPressed: widget.busy ? null : () {},
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(
            color: _progress > 0 ? AppTheme.accent : AppTheme.onSurfaceVariant,
          ),
        ),
        child: Column(
          children: [
            if (_progress > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 3,
                  backgroundColor: AppTheme.cardElevated,
                  color: AppTheme.accent,
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  const Icon(Icons.emergency_outlined, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.remainingBypasses} left today · re-blocks when time is up',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _AnkiDroidWarning extends StatelessWidget {
  const _AnkiDroidWarning();

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      color: AppTheme.warning.withValues(alpha: 0.08),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: AppTheme.warning, size: 22),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Requires AnkiDroid. Connect AnkiBlock to use your real '
              'study progress.',
            ),
          ),
        ],
      ),
    );
  }
}
