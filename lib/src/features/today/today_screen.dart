import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/utils/study_day.dart';
import '../../core/utils/blocking_goal.dart';
import '../../core/database/database.dart' as db;
import '../../core/assets/app_assets.dart';
import '../../core/di/providers.dart';
import '../../core/services/ankidroid_service.dart';
import '../../core/services/apps_service.dart';
import '../../core/services/study_launcher.dart';
import '../../core/services/study_scope_service.dart';
import '../../core/setup/setup_actions.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_widgets.dart';
import '../../core/utils/deck_scope_format.dart';
import '../../core/widgets/deck_picker_panel.dart';
import '../../core/widgets/setup_panels.dart';
import '../../core/widgets/support_prompt_banner.dart';
import 'study_progress_sheet.dart';

/// Home screen — study progress, your unlock rule, and today's wins.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blockedAppsAsync = ref.watch(activeBlockedAppsProvider);
    final installedAsync = ref.watch(installedAppsProvider);
    final today = studyDayKey();
    final dailyStatsAsync = ref.watch(dailyStatsProvider(today));
    final streakAsync = ref.watch(studyStreakProvider);
    final countsAsync = ref.watch(studyCountsProvider);
    final ankiStatusAsync = ref.watch(ankiDroidStatusProvider);
    final ruleAsync = ref.watch(blockRuleProvider);
    final decksAsync = ref.watch(ankiDroidDecksProvider);
    final scopeAsync = ref.watch(studyScopeProvider);

    // Derive display values via select-friendly locals (same providers; keep
    // AsyncValue handles for child widgets that need loading/error states).
    final dailyGoal = ruleAsync.valueOrNull?.dailyCardsGoal ?? 30;
    final unlockGoal = ruleAsync.valueOrNull?.cardsRequired ?? 10;
    final mode = StudyMode.fromStorage(ruleAsync.valueOrNull?.studyMode);
    final reviewed = dailyStatsAsync.valueOrNull?.cardsReviewed ?? 0;
    final counts = countsAsync.valueOrNull ?? AnkiDroidCounts.zero;
    final obligation = counts.obligationDue;
    final goalComplete = isBlockingGoalComplete(
      mode: mode,
      dailyCardsGoal: dailyGoal,
      cardsReviewed: reviewed,
      obligationDue: obligation,
    );
    final dailyRemaining = (dailyGoal - reviewed).clamp(0, dailyGoal);
    // Due mode: goal is clearing Anki's learning+reviews — do not mix in the
    // local "cards studied" ledger (different metric; made the ring look wrong).
    final progress = switch (mode) {
      StudyMode.dueCards => obligation <= 0 ? 1.0 : 0.0,
      StudyMode.cardCount =>
        dailyGoal > 0 ? (reviewed / dailyGoal).clamp(0.0, 1.0) : 0.0,
    };
    final decks = decksAsync.valueOrNull ?? const [];
    final scope = scopeAsync.valueOrNull;
    final hasDecksSelected = scope != null &&
        decks.isNotEmpty &&
        hasDecksInScope(scope, decks);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppTheme.accent,
          backgroundColor: AppTheme.card,
          onRefresh: () async {
            await mergeDailyFromNative(ref);
            ref.invalidate(dailyStatsProvider(studyDayKey()));
            ref.invalidate(studyProgressProvider);
            ref.invalidate(studyCountsProvider);
            ref.invalidate(ankiDroidStatusProvider);
            ref.invalidate(ankiDroidDecksProvider);
            ref.invalidate(blockRuleProvider);
            ref.read(installedAppsProvider.notifier).refresh();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Row(
                children: [
                  Image.asset(
                    AppAssets.logo,
                    width: 40,
                    height: 40,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(child: AnkiBlockWordmark(fontSize: 22)),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Settings',
                    onPressed: () => context.push('/settings'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              StreakBanner(
                streakAsync: streakAsync,
                onTap: () => showStudyProgressSheet(context, ref),
              ),
              const SizedBox(height: 20),
              _AnkiDroidStatusCard(ankiStatusAsync: ankiStatusAsync),
              _StudyHero(
                progress: progress,
                goalComplete: goalComplete,
                mode: mode,
                reviewed: reviewed,
                dailyGoal: dailyGoal,
                dailyRemaining: dailyRemaining,
                unlockGoal: unlockGoal,
                obligationDue: obligation,
                learnCount: counts.learnCount,
                reviewCount: counts.reviewCount,
                newCount: counts.newCount,
                hasDecksSelected: hasDecksSelected,
              ),
              const SupportPromptBanner(),
              const SizedBox(height: 28),
              Text('Your setup', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                mode == StudyMode.dueCards
                    ? 'Temporary unlock, or clear your Anki queue for the day.'
                    : 'Daily goal for full unlock · temporary unlock at the gate.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              if (mode == StudyMode.cardCount) ...[
                _DailyGoalSection(goal: dailyGoal),
                const SizedBox(height: 12),
              ],
              _UnlockGoalSection(
                goal: unlockGoal,
                graceMinutes:
                    ruleAsync.valueOrNull?.unlockDurationMinutes ?? 15,
              ),
              const SizedBox(height: 12),
              _BlockedAppsSection(
                blockedAppsAsync: blockedAppsAsync,
                installedAsync: installedAsync,
              ),
              const SizedBox(height: 12),
              _StudyDecksSection(
                decksAsync: decksAsync,
                scopeAsync: scopeAsync,
                due: obligation,
              ),
              const SizedBox(height: 12),
              const _BlockingBehaviourSection(),
              const SizedBox(height: 28),
              Text('Today', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              _AccomplishmentsRow(stats: dailyStatsAsync.valueOrNull),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudyHero extends ConsumerStatefulWidget {
  final double progress;
  final bool goalComplete;
  final StudyMode mode;
  final int reviewed;
  final int dailyGoal;
  final int dailyRemaining;
  final int unlockGoal;
  final int obligationDue;
  final int learnCount;
  final int reviewCount;
  final int newCount;
  final bool hasDecksSelected;

  const _StudyHero({
    required this.progress,
    required this.goalComplete,
    required this.mode,
    required this.reviewed,
    required this.dailyGoal,
    required this.dailyRemaining,
    required this.unlockGoal,
    required this.obligationDue,
    required this.learnCount,
    required this.reviewCount,
    required this.newCount,
    required this.hasDecksSelected,
  });

  @override
  ConsumerState<_StudyHero> createState() => _StudyHeroState();
}

class _StudyHeroState extends ConsumerState<_StudyHero> {
  bool _launching = false;

  Future<void> _openInAnkiDroid() async {
    if (_launching) return;
    setState(() => _launching = true);
    try {
      final scope = await ref.read(studyScopeProvider.future);
      final decks = await ref.read(ankiDroidDecksProvider.future);
      final target = await resolveSessionTarget(ref);
      await startScopedStudySession(
        ref: ref,
        scope: scope,
        decks: decks,
        cardsRequired: target,
      );
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(delegatedSessionProgressProvider);
    final hasSession = session != null;
    final sessionReviewed = session?.completed ?? 0;
    final dueMode = widget.mode == StudyMode.dueCards;
    final sessionGoalFallback = dueMode
        ? (widget.obligationDue > 0
            ? (widget.obligationDue < widget.unlockGoal
                ? widget.obligationDue
                : widget.unlockGoal)
            : widget.unlockGoal)
        : widget.dailyRemaining.clamp(1, widget.dailyGoal);
    final sessionGoal = session?.target ?? sessionGoalFallback;
    final sessionRemaining =
        (sessionGoal - sessionReviewed).clamp(0, sessionGoal);
    final sessionProgress = sessionGoal > 0
        ? (sessionReviewed / sessionGoal).clamp(0.0, 1.0)
        : 0.0;
    final sessionComplete =
        hasSession && sessionRemaining == 0 && sessionReviewed > 0;

    final displayProgress = hasSession ? sessionProgress : widget.progress;
    final displayComplete =
        hasSession ? sessionComplete : widget.goalComplete;
    final displayReviewed =
        hasSession ? sessionReviewed : widget.reviewed;
    final displayGoal =
        hasSession ? sessionGoal : widget.dailyGoal;
    final displayRemaining = hasSession
        ? sessionRemaining
        : (dueMode ? widget.obligationDue : widget.dailyRemaining);
    final hasCards = widget.obligationDue > 0 || widget.newCount > 0;
    final canStartStudy =
        (dueMode ? widget.obligationDue > 0 : hasCards) &&
            widget.hasDecksSelected;

    final subtitle = hasSession
        ? (displayComplete
            ? 'Session complete!'
            : '$displayRemaining cards left in this session')
        : dueMode
            ? (displayComplete
                ? 'Learning & reviews cleared'
                : '${widget.learnCount} learning · ${widget.reviewCount} to review')
            : (displayComplete
                ? 'Unlocked until 3am · $displayReviewed studied'
                : '$displayRemaining cards until freedom today');

    final hint = !hasSession && !displayComplete
        ? (dueMode
            ? (widget.newCount > 0
                ? '${widget.newCount} new available · '
                    '${widget.unlockGoal} cards = temporary unlock.'
                : 'Or ${widget.unlockGoal} cards = temporary unlock.')
            : 'Or ${widget.unlockGoal} cards = temporary unlock.')
        : (!hasSession && displayComplete && dueMode && widget.newCount > 0
            ? '${widget.newCount} new cards still available in AnkiDroid.'
            : null);

    return BrandCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      color: AppTheme.cardElevated,
      child: Column(
        children: [
          GradientProgressRing(
            progress: displayProgress,
            complete: displayComplete,
            size: 132,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayComplete
                      ? '100%'
                      : hasSession
                          ? '${(displayProgress * 100).round()}%'
                          : dueMode
                              ? '$displayRemaining'
                              : '${(displayProgress * 100).round()}%',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: displayComplete
                            ? AppTheme.success
                            : AppTheme.onBackground,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  displayComplete
                      ? (dueMode && !hasSession
                          ? 'all clear'
                          : !dueMode && displayReviewed > displayGoal
                              ? '$displayReviewed'
                              : '$displayReviewed / $displayGoal')
                      : hasSession
                          ? '$displayReviewed / $displayGoal'
                          : dueMode
                              ? 'left to clear'
                              : '$displayReviewed / $displayGoal',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (!dueMode &&
                    displayComplete &&
                    displayReviewed > displayGoal)
                  Text(
                    'goal $displayGoal',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (hasSession) ...[
            const SizedBox(height: 6),
            Text(
              'Studying in AnkiDroid…',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          GradientButton(
            onPressed: canStartStudy && !_launching && !hasSession
                ? _openInAnkiDroid
                : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_launching)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.onPrimary,
                    ),
                  )
                else
                  const Icon(Icons.play_arrow_rounded),
                const SizedBox(width: 8),
                Text(
                  _launching
                      ? 'Opening AnkiDroid…'
                      : hasSession
                          ? 'Studying in AnkiDroid…'
                          : !widget.hasDecksSelected
                              ? 'Select decks to study'
                              : dueMode
                                  ? (widget.obligationDue > 0
                                      ? 'Start Studying · ${widget.obligationDue} left'
                                      : 'Nothing left to clear')
                                  : hasCards
                                      ? 'Start Studying · ${widget.obligationDue + widget.newCount} due'
                                      : 'Nothing due right now',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyGoalSection extends StatelessWidget {
  final int goal;
  const _DailyGoalSection({required this.goal});

  @override
  Widget build(BuildContext context) {
    return _SetupTile(
      icon: Icons.calendar_today_outlined,
      iconColor: AppTheme.primary,
      title: 'Daily card goal',
      subtitle: '$goal cards · all apps open until 3am',
      onTap: () => _showDailyGoalSheet(context, goal),
    );
  }

  void _showDailyGoalSheet(BuildContext context, int goal) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.viewPaddingOf(ctx).bottom,
        ),
        child: DailyGoalPanel(initial: goal),
      ),
    );
  }
}

class _UnlockGoalSection extends StatelessWidget {
  final int goal;
  final int graceMinutes;
  const _UnlockGoalSection({
    required this.goal,
    required this.graceMinutes,
  });

  @override
  Widget build(BuildContext context) {
    return _SetupTile(
      icon: Icons.flag_outlined,
      iconColor: AppTheme.accent,
      title: 'Temporary unlock',
      subtitle: '$goal cards · $graceMinutes min',
      onTap: () => _showUnlockGoalSheet(context, goal),
    );
  }

  void _showUnlockGoalSheet(BuildContext context, int goal) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.viewPaddingOf(ctx).bottom,
        ),
        child: UnlockGoalPanel(initial: goal),
      ),
    );
  }
}

class _BlockedAppsSection extends StatelessWidget {
  final AsyncValue<List<db.BlockedApp>> blockedAppsAsync;
  final AsyncValue<List<InstalledApp>> installedAsync;

  const _BlockedAppsSection({
    required this.blockedAppsAsync,
    required this.installedAsync,
  });

  @override
  Widget build(BuildContext context) {
    final blocked = blockedAppsAsync.valueOrNull ?? const [];
    final installed = installedAsync.valueOrNull ?? const [];
    final iconByPkg = {for (final a in installed) a.packageName: a.icon};
    final names = blocked.map((b) => b.displayName).toList();

    return _SetupTile(
      icon: Icons.lock_outline,
      iconColor: AppTheme.primary,
      title: 'Blocked apps',
      subtitle: blocked.isEmpty
          ? 'None selected — tap to block distractions'
          : blocked.length == 1
              ? names.first
              : '${blocked.length} apps locked',
      onTap: () => context.push('/blocking'),
      trailing: blocked.isEmpty
          ? null
          : _AppIconRow(
              blocked: blocked,
              iconByPkg: iconByPkg,
            ),
    );
  }
}

class _AppIconRow extends StatelessWidget {
  final List<db.BlockedApp> blocked;
  final Map<String, Uint8List?> iconByPkg;

  const _AppIconRow({
    required this.blocked,
    required this.iconByPkg,
  });

  @override
  Widget build(BuildContext context) {
    final shown = blocked.take(4).toList();
    final extra = blocked.length - shown.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final b in shown) ...[
          _MiniAppIcon(
            icon: iconByPkg[b.packageName],
            name: b.displayName,
          ),
          const SizedBox(width: 4),
        ],
        if (extra > 0)
          Text(
            '+$extra',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppTheme.onSurfaceVariant,
                ),
          ),
      ],
    );
  }
}

class _MiniAppIcon extends StatelessWidget {
  final Uint8List? icon;
  final String name;

  const _MiniAppIcon({required this.icon, required this.name});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: name,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: icon != null
            ? Image.memory(
                icon!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: 96,
                cacheHeight: 96,
                filterQuality: FilterQuality.low,
              )
            : const Icon(Icons.android, size: 16),
      ),
    );
  }
}

class _StudyDecksSection extends StatelessWidget {
  final AsyncValue<List<AnkiDroidDeck>> decksAsync;
  final AsyncValue<StudyScope> scopeAsync;
  final int due;

  const _StudyDecksSection({
    required this.decksAsync,
    required this.scopeAsync,
    required this.due,
  });

  @override
  Widget build(BuildContext context) {
    final decks = decksAsync.valueOrNull ?? const [];
    final scope = scopeAsync.valueOrNull;
    final summary = scope == null || decks.isEmpty
        ? 'Connect AnkiDroid to choose decks'
        : formatDeckStudySummary(scope, decks);
    final launchHint = scope == null || decks.isEmpty
        ? ''
        : formatLaunchDeckHint(scope, decks);
    final subtitleParts = <String>[
      summary,
      if (due > 0) '$due due',
      if (launchHint.isNotEmpty) launchHint,
    ];

    return _SetupTile(
      icon: Icons.style_outlined,
      iconColor: AppTheme.success,
      title: 'Study decks',
      subtitle: subtitleParts.join(' · '),
      onTap: () => _showDeckSheet(context),
    );
  }

  void _showDeckSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            20 + MediaQuery.viewPaddingOf(ctx).bottom,
          ),
          children: [
            Text('Study decks', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Reviews from selected decks count — you can switch decks in '
              'AnkiDroid.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            const DeckPickerPanel(),
          ],
        ),
      ),
    );
  }
}

class _BlockingBehaviourSection extends StatelessWidget {
  const _BlockingBehaviourSection();

  @override
  Widget build(BuildContext context) {
    return _SetupTile(
      icon: Icons.tune,
      iconColor: AppTheme.accent,
      title: 'Adjust blocking behaviour',
      subtitle: 'Protection, unlocking, bypass',
      onTap: () => context.push('/settings'),
    );
  }
}

class _SetupTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  const _SetupTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: AppTheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _AccomplishmentsRow extends StatelessWidget {
  final db.DailyStat? stats;
  const _AccomplishmentsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MiniStat(
                icon: Icons.check_circle_outline,
                value: '${stats?.cardsReviewed ?? 0}',
                label: 'Studied',
                color: AppTheme.success,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MiniStat(
                icon: Icons.lock_open,
                value: '${stats?.unlocksEarned ?? 0}',
                label: 'Unlocks',
                color: AppTheme.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MiniStat(
                icon: Icons.shield_outlined,
                value: '${stats?.blockedAttempts ?? 0}',
                label: 'Resisted',
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MiniStat(
                icon: Icons.emergency_outlined,
                value: '${stats?.bypassesUsed ?? 0}',
                label: 'Bypasses',
                color: AppTheme.warning,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _MiniStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _AnkiDroidStatusCard extends ConsumerWidget {
  final AsyncValue<AnkiDroidStatus> ankiStatusAsync;
  const _AnkiDroidStatusCard({required this.ankiStatusAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ankiStatusAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (status) {
        if (status.isReady) return const SizedBox.shrink();

        final notInstalled = !status.installed;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: BrandCard(
            color: AppTheme.warning.withValues(alpha: 0.08),
            onTap: () => context.push('/ankidroid'),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    color: AppTheme.warning, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    notInstalled
                        ? 'Requires AnkiDroid — install to start studying.'
                        : 'Grant AnkiDroid access to track your cards.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.onSurface,
                        ),
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: AppTheme.onSurfaceVariant),
              ],
            ),
          ),
        );
      },
    );
  }
}
