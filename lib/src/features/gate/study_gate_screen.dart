import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/di/providers.dart';
import '../../core/services/ankidroid_service.dart';
import '../../core/services/apps_service.dart';
import '../../core/services/study_launcher.dart';
import '../../core/theme/app_theme.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recordBlockedAttempt());
  }

  Future<void> _recordBlockedAttempt() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await ref.read(databaseProvider).incrementBlockedAttempts(today);
    ref.invalidate(dailyStatsProvider(today));
  }

  Future<void> _studyInAnkiDroid({required int cardsRequired}) async {
    if (_delegating) return;
    setState(() => _delegating = true);
    try {
      final scope = await ref.read(studyScopeProvider.future);
      final anki = ref.read(ankiDroidServiceProvider);
      final apps = ref.read(appsServiceProvider);
      final decks = await anki.listDecks();
      final allowedIds = scope.filterDeckIds(decks.map((d) => d.id));
      if (allowedIds.isEmpty) return;

      final deckId = resolveStudyDeckId(scope, decks, allowedIds);
      final deck = decks.firstWhere((d) => d.id == deckId);
      await apps.startAppMonitor();
      await apps.startDelegatedSession(
        packageName: widget.packageName,
        appName: widget.appName,
        deckId: deckId,
        deckIds: [deckId],
        target: cardsRequired,
        baseline: deck.totalDue,
      );
      await anki.openAnkiDroidReviewer(deckId);
    } finally {
      if (mounted) setState(() => _delegating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final ruleAsync = ref.watch(blockRuleProvider);
    final countsAsync = ref.watch(studyCountsProvider);
    final ankiStatusAsync = ref.watch(ankiDroidStatusProvider);
    final dailyStatsAsync = ref.watch(dailyStatsProvider(today));
    final usageAsync = ref.watch(gateTodayUsageProvider(widget.packageName));

    final cardsRequired = ruleAsync.valueOrNull?.cardsRequired ?? 5;
    final unlockMinutes =
        ruleAsync.valueOrNull?.unlockDurationMinutes ?? 10;
    final counts = countsAsync.valueOrNull ?? AnkiDroidCounts.zero;
    final ankiReady = ankiStatusAsync.valueOrNull?.isReady ?? false;
    final available = counts.studyable;
    final cardsToday = dailyStatsAsync.valueOrNull?.cardsReviewed ?? 0;
    final usage = usageAsync.valueOrNull ?? TodayBlockedUsage.zero;

    final canStudy = ankiReady && available > 0;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                const Icon(Icons.lock_outline, size: 72),
                const SizedBox(height: 20),
                Text(
                  '${widget.appName} is blocked',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'Answer $cardsRequired cards to unlock for $unlockMinutes minutes.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                _GateStatsPanel(
                  cardsToday: cardsToday,
                  usage: usage,
                  focusAppName: widget.appName,
                  loadingUsage: usageAsync.isLoading,
                ),
                const SizedBox(height: 24),
                if (!ankiReady)
                  const _AnkiDroidWarning()
                else
                  _QueueRow(counts: counts),
                if (ankiReady && available == 0) ...[
                  const SizedBox(height: 16),
                  Text(
                    'No cards are due right now. Come back when you have '
                    'reviews waiting.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  icon: _delegating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.open_in_new),
                  label: Text(
                    !ankiReady
                        ? 'Set up AnkiDroid first'
                        : _delegating
                            ? 'Opening AnkiDroid…'
                            : (available == 0
                                ? 'No cards due'
                                : 'Study in AnkiDroid'),
                  ),
                  onPressed: !ankiReady
                      ? () => context.push('/ankidroid')
                      : canStudy && !_delegating
                          ? () => _studyInAnkiDroid(cardsRequired: cardsRequired)
                          : null,
                ),
                if (canStudy) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Opens AnkiDroid with your due cards. AnkiBlock tracks '
                    'progress and unlocks $unlockMinutes minutes when done.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('Change Settings'),
                  onPressed: () => context.go('/'),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GateStatsPanel extends StatelessWidget {
  final int cardsToday;
  final TodayBlockedUsage usage;
  final String focusAppName;
  final bool loadingUsage;

  const _GateStatsPanel({
    required this.cardsToday,
    required this.usage,
    required this.focusAppName,
    required this.loadingUsage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatSection(
          title: 'Today\'s wins',
          icon: Icons.emoji_events_outlined,
          accent: AppTheme.success,
          children: [
            _StatLine(
              value: '$cardsToday',
              label: cardsToday == 1 ? 'card studied' : 'cards studied',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _StatSection(
          title: 'The guilty truth',
          icon: Icons.visibility_outlined,
          accent: AppTheme.error,
          children: [
            if (loadingUsage)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else ...[
              _StatLine(
                value: '${usage.totalPickups} '
                    '${usage.totalPickups == 1 ? 'pickup' : 'pickups'}',
                label:
                    '${_formatDuration(usage.totalScreenTime)} in blocked apps',
              ),
              if (usage.focusPickups > 0 ||
                  usage.focusScreenTime > Duration.zero) ...[
                const SizedBox(height: 8),
                Text(
                  '$focusAppName today: ${usage.focusPickups} '
                  '${usage.focusPickups == 1 ? 'open' : 'opens'} · '
                  '${_formatDuration(usage.focusScreenTime)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ],
        ),
      ],
    );
  }

  static String _formatDuration(Duration d) {
    if (d == Duration.zero) return '0m';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

class _StatSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final List<Widget> children;

  const _StatSection({
    required this.title,
    required this.icon,
    required this.accent,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _StatLine extends StatelessWidget {
  final String value;
  final String label;
  final String? trailing;

  const _StatLine({
    required this.value,
    required this.label,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
      ],
    );
  }
}

/// Picks the deck AnkiDroid should open for a delegated session.
class _AnkiDroidWarning extends StatelessWidget {
  const _AnkiDroidWarning();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.amber),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'AnkiDroid is not connected. AnkiBlock needs it to track your '
              'cards.',
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final AnkiDroidCounts counts;
  const _QueueRow({required this.counts});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        _Chip(value: counts.newCount, label: 'New'),
        _Chip(value: counts.learnCount, label: 'Learn'),
        _Chip(value: counts.reviewCount, label: 'Review'),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final int value;
  final String label;
  const _Chip({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
