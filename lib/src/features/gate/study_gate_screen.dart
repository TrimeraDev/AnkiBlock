import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/services/ankidroid_service.dart';
import '../../core/services/apps_service.dart';
import '../../core/services/study_launcher.dart';
import '../../core/theme/app_theme.dart';
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

class _StudyGateScreenState extends ConsumerState<StudyGateScreen> {
  bool _delegating = false;
  bool _autoLaunched = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recordBlockedAttempt();
      _maybeAutoLaunch();
    });
  }

  Future<void> _recordBlockedAttempt() async {
    final today = studyDayKey();
    await ref.read(databaseProvider).incrementBlockedAttempts(today);
    ref.invalidate(dailyStatsProvider(today));
    ref.invalidate(studyStreakProvider);
  }

  Future<void> _maybeAutoLaunch() async {
    if (_autoLaunched) return;
    final rule = await ref.read(blockRuleProvider.future);
    final dailyGoal = rule?.dailyCardsGoal ?? 30;
    final today = studyDayKey();
    final reviewed =
        (await ref.read(databaseProvider).getDailyStat(today))?.cardsReviewed ??
            0;
    if (!isDailyGoalComplete(dailyGoal: dailyGoal, cardsReviewed: reviewed)) {
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
      await startScopedStudySession(
        ref: ref,
        scope: scope,
        decks: decks,
        cardsRequired: cardsRequired,
        unlockPackageName: widget.packageName,
        unlockAppName: widget.appName,
        forGate: true,
      );
    } finally {
      if (mounted) setState(() => _delegating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ruleAsync = ref.watch(blockRuleProvider);
    final countsAsync = ref.watch(studyCountsProvider);
    final ankiStatusAsync = ref.watch(ankiDroidStatusProvider);
    final usageAsync = ref.watch(gateTodayUsageProvider(widget.packageName));
    final today = studyDayKey();
    final dailyStatsAsync = ref.watch(dailyStatsProvider(today));

    final unlockGoal = ruleAsync.valueOrNull?.cardsRequired ?? 10;
    final dailyGoal = ruleAsync.valueOrNull?.dailyCardsGoal ?? 30;
    final counts = countsAsync.valueOrNull ?? AnkiDroidCounts.zero;
    final ankiReady = ankiStatusAsync.valueOrNull?.isReady ?? false;
    final available = counts.studyable;
    final usage = usageAsync.valueOrNull ?? TodayBlockedUsage.zero;
    final reviewed = dailyStatsAsync.valueOrNull?.cardsReviewed ?? 0;
    final dailyComplete =
        isDailyGoalComplete(dailyGoal: dailyGoal, cardsReviewed: reviewed);
    final dailyRemaining = (dailyGoal - reviewed).clamp(0, dailyGoal);
    final progress = dailyGoal > 0
        ? (reviewed / dailyGoal).clamp(0.0, 1.0)
        : 0.0;
    final remaining = dailyComplete ? 0 : unlockGoal;

    final canStudy = ankiReady && available > 0;

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
                    progress: progress,
                    complete: dailyComplete,
                    size: 120,
                    strokeWidth: 8,
                    child: Image.asset(
                      'lib/src/assets/logo.png',
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
                  before: dailyComplete ? 'Daily goal done. ' : 'Study first. ',
                  accent: dailyComplete ? 'Enjoy.' : 'Unlock later.',
                ),
                const SizedBox(height: 12),
                if (!usageAsync.isLoading)
                  Text(
                    _formatTodayUsage(usage.focusPickups, usage.focusScreenTime),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
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
                            dailyComplete
                                ? Icons.lock_open_outlined
                                : Icons.lock_outline,
                            size: 18,
                            color: AppTheme.accent,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            dailyComplete
                                ? 'Unlocked until 3am'
                                : remaining > 0
                                    ? '$remaining cards to unlock'
                                    : 'Goal complete!',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        dailyComplete
                            ? 'You finished your daily goal. All blocked apps '
                                'are open for the rest of the study day.'
                            : 'Study $unlockGoal cards in AnkiDroid to open '
                                '${widget.appName}. '
                                '$dailyRemaining more today unlocks everything.',
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
                if (ankiReady && available == 0) ...[
                  const SizedBox(height: 16),
                  Text(
                    'No cards are due right now. Come back when you have '
                    'reviews waiting.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.onSurfaceVariant,
                        ),
                  ),
                ],
                const SizedBox(height: 28),
                if (!dailyComplete)
                  GradientButton(
                    onPressed: !ankiReady
                        ? () => context.push('/ankidroid')
                        : canStudy && !_delegating
                            ? () =>
                                _studyInAnkiDroid(cardsRequired: unlockGoal)
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
                        Text(
                          !ankiReady
                              ? 'Set up AnkiDroid first'
                              : _delegating
                                  ? 'Opening AnkiDroid…'
                                  : (available == 0
                                      ? 'No cards due'
                                      : 'Study in AnkiDroid'),
                        ),
                      ],
                    ),
                  ),
                if (dailyComplete) ...[
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
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.tune),
                  label: const Text('Change Settings'),
                  onPressed: () => context.go('/'),
                ),
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
