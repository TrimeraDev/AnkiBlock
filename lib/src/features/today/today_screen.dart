import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/utils/study_day.dart';
import '../../core/database/database.dart' as db;
import '../../core/di/providers.dart';
import '../../core/services/ankidroid_service.dart';
import '../../core/services/apps_service.dart';
import '../../core/services/study_launcher.dart';
import '../../core/services/study_scope_service.dart';
import '../../core/setup/setup_actions.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_widgets.dart';
import '../../core/widgets/setup_panels.dart';

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

    final dailyGoal = ruleAsync.valueOrNull?.dailyCardsGoal ?? 30;
    final unlockGoal = ruleAsync.valueOrNull?.cardsRequired ?? 10;
    final reviewed = dailyStatsAsync.valueOrNull?.cardsReviewed ?? 0;
    final dailyRemaining = (dailyGoal - reviewed).clamp(0, dailyGoal);
    final progress =
        dailyGoal > 0 ? (reviewed / dailyGoal).clamp(0.0, 1.0) : 0.0;
    final dailyComplete =
        isDailyGoalComplete(dailyGoal: dailyGoal, cardsReviewed: reviewed);
    final due = countsAsync.valueOrNull?.studyable ?? 0;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppTheme.accent,
          backgroundColor: AppTheme.card,
          onRefresh: () async {
            await mergeDailyFromNative(ref);
            ref.invalidate(dailyStatsProvider(studyDayKey()));
            ref.invalidate(studyStreakProvider);
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
                    'lib/src/assets/logo.png',
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
              _StreakBanner(streakAsync: streakAsync),
              const SizedBox(height: 20),
              _AnkiDroidStatusCard(ankiStatusAsync: ankiStatusAsync),
              _StudyHero(
                progress: progress,
                dailyComplete: dailyComplete,
                reviewed: reviewed,
                dailyGoal: dailyGoal,
                dailyRemaining: dailyRemaining,
                unlockGoal: unlockGoal,
                due: due,
              ),
              const SizedBox(height: 28),
              Text('Your setup', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Tap any section to change your daily or per-unlock goals.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              _DailyGoalSection(goal: dailyGoal),
              const SizedBox(height: 12),
              _UnlockGoalSection(goal: unlockGoal),
              const SizedBox(height: 12),
              _BlockedAppsSection(
                blockedAppsAsync: blockedAppsAsync,
                installedAsync: installedAsync,
              ),
              const SizedBox(height: 12),
              _StudyDecksSection(
                decksAsync: decksAsync,
                scopeAsync: scopeAsync,
                due: due,
              ),
              const SizedBox(height: 28),
              Text('Today', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              _AccomplishmentsRow(stats: dailyStatsAsync.valueOrNull),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        onTap: (index) {
          switch (index) {
            case 0:
              break;
            case 1:
              context.push('/decks');
              break;
            case 2:
              context.push('/blocking');
              break;
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.today), label: 'Today'),
          BottomNavigationBarItem(
              icon: Icon(Icons.folder_outlined), label: 'Decks'),
          BottomNavigationBarItem(icon: Icon(Icons.block), label: 'Block'),
        ],
      ),
    );
  }
}

class _StreakBanner extends StatelessWidget {
  final AsyncValue<int> streakAsync;

  const _StreakBanner({required this.streakAsync});

  @override
  Widget build(BuildContext context) {
    return streakAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (streak) {
        final label = streak == 0
            ? 'Hit your daily goal to start a streak'
            : streak == 1
                ? '1 day streak'
                : '$streak day streak';
        return Row(
          children: [
            Icon(
              Icons.local_fire_department_rounded,
              size: 20,
              color: streak > 0 ? AppTheme.warning : AppTheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: streak > 0
                        ? AppTheme.warning
                        : AppTheme.onSurfaceVariant,
                    fontWeight:
                        streak > 0 ? FontWeight.w600 : FontWeight.w500,
                  ),
            ),
          ],
        );
      },
    );
  }
}

class _StudyHero extends ConsumerStatefulWidget {
  final double progress;
  final bool dailyComplete;
  final int reviewed;
  final int dailyGoal;
  final int dailyRemaining;
  final int unlockGoal;
  final int due;

  const _StudyHero({
    required this.progress,
    required this.dailyComplete,
    required this.reviewed,
    required this.dailyGoal,
    required this.dailyRemaining,
    required this.unlockGoal,
    required this.due,
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
    final sessionGoal = session?.target ?? widget.dailyRemaining.clamp(1, widget.dailyGoal);
    final sessionRemaining =
        (sessionGoal - sessionReviewed).clamp(0, sessionGoal);
    final sessionProgress = sessionGoal > 0
        ? (sessionReviewed / sessionGoal).clamp(0.0, 1.0)
        : 0.0;
    final sessionComplete =
        hasSession && sessionRemaining == 0 && sessionReviewed > 0;

    final displayProgress = hasSession ? sessionProgress : widget.progress;
    final displayComplete =
        hasSession ? sessionComplete : widget.dailyComplete;
    final displayReviewed =
        hasSession ? sessionReviewed : widget.reviewed;
    final displayGoal =
        hasSession ? sessionGoal : widget.dailyGoal;
    final displayRemaining =
        hasSession ? sessionRemaining : widget.dailyRemaining;
    final hasCards = widget.due > 0;

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
                  displayComplete && displayReviewed > displayGoal
                      ? '$displayReviewed'
                      : '$displayReviewed / $displayGoal',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (displayComplete && displayReviewed > displayGoal)
                  Text(
                    'goal $displayGoal',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            hasSession
                ? (displayComplete
                    ? 'Session complete!'
                    : '$displayRemaining cards left in this session')
                : (displayComplete
                    ? 'Unlocked until 3am · $displayReviewed studied'
                    : '$displayRemaining cards until freedom today'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (!hasSession && !displayComplete) ...[
            const SizedBox(height: 6),
            Text(
              'Or ${widget.unlockGoal} cards each time you open a blocked app.',
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
            onPressed: hasCards && !_launching && !hasSession
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
                          : hasCards
                              ? 'Start Studying · ${widget.due} due'
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
      title: 'Daily goal',
      subtitle: '$goal cards · unlocks all apps until 3am',
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
  const _UnlockGoalSection({required this.goal});

  @override
  Widget build(BuildContext context) {
    return _SetupTile(
      icon: Icons.flag_outlined,
      iconColor: AppTheme.accent,
      title: 'Unlock goal',
      subtitle: '$goal cards per blocked app',
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
            ? Image.memory(icon!, fit: BoxFit.cover, gaplessPlayback: true)
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

    return _SetupTile(
      icon: Icons.style_outlined,
      iconColor: AppTheme.success,
      title: 'Study decks',
      subtitle: due > 0 ? '$summary · $due due' : summary,
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
              'Cards from these decks count toward unlocking apps.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            const DeckStudySetupPanel(),
          ],
        ),
      ),
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
    return Row(
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
        const SizedBox(width: 12),
        Expanded(
          child: _MiniStat(
            icon: Icons.shield_outlined,
            value: '${stats?.blockedAttempts ?? 0}',
            label: 'Resisted',
            color: AppTheme.primary,
          ),
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
    final status = ankiStatusAsync.valueOrNull;
    if (status?.isReady ?? false) return const SizedBox.shrink();

    final notInstalled = status != null && !status.installed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: BrandCard(
        color: AppTheme.warning.withValues(alpha: 0.08),
        onTap: () => context.push('/ankidroid'),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppTheme.warning, size: 22),
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
            const Icon(Icons.chevron_right, color: AppTheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
