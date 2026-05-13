import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/database/database.dart' as db;
import '../../core/di/providers.dart';
import '../../core/services/ankidroid_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/global_blocking_permission_banner.dart';

/// Home screen. Shows AnkiDroid status, the in-scope study queue, AnkiBlock's
/// daily stats, and the action to start a study session.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeSessionsAsync = ref.watch(activeSessionsProvider);
    final blockedAppsAsync = ref.watch(activeBlockedAppsProvider);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final dailyStatsAsync = ref.watch(dailyStatsProvider(today));
    final countsAsync = ref.watch(studyCountsProvider);
    final ankiStatusAsync = ref.watch(ankiDroidStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AnkiBlock'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          const GlobalBlockingPermissionBanner(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(studyCountsProvider);
                ref.invalidate(ankiDroidStatusProvider);
                ref.invalidate(ankiDroidDecksProvider);
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _AnkiDroidStatusCard(ankiStatusAsync: ankiStatusAsync),
                  const SizedBox(height: 16),
                  _buildStatsSection(
                    context,
                    dailyStatsAsync,
                    blockedAppsAsync,
                    activeSessionsAsync,
                  ),
                  const SizedBox(height: 24),
                  _QueueSection(countsAsync: countsAsync),
                  const SizedBox(height: 24),
                  _QuickActions(countsAsync: countsAsync),
                ],
              ),
            ),
          ),
        ],
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

  Widget _buildStatsSection(
    BuildContext context,
    AsyncValue<db.DailyStat?> statsAsync,
    AsyncValue<List<db.BlockedApp>> blockedAppsAsync,
    AsyncValue<List<db.UnlockSession>> sessionsAsync,
  ) {
    final stats = statsAsync.valueOrNull;
    final blockedCount = blockedAppsAsync.valueOrNull?.length ?? 0;
    final activeUnlocks = sessionsAsync.valueOrNull?.length ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Today', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.check_circle_outline,
                value: '${stats?.cardsReviewed ?? 0}',
                label: 'Cards Reviewed',
                color: AppTheme.success,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.lock_open,
                value: '${stats?.unlocksEarned ?? 0}',
                label: 'Unlocks Earned',
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.block,
                value: '$blockedCount',
                label: 'Apps Blocked',
                color: AppTheme.error,
                onTap: () => context.push('/blocking'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.timer,
                value: '$activeUnlocks',
                label: 'Active Unlocks',
                color: AppTheme.warning,
              ),
            ),
          ],
        ),
      ],
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
    return Material(
      color: AppTheme.warning.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/ankidroid'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppTheme.warning, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  notInstalled
                      ? 'AnkiDroid is not installed. AnkiBlock uses AnkiDroid '
                          'to manage your cards.'
                      : 'AnkiBlock needs access to AnkiDroid. Tap to grant.',
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueueSection extends StatelessWidget {
  final AsyncValue<AnkiDroidCounts> countsAsync;
  const _QueueSection({required this.countsAsync});

  @override
  Widget build(BuildContext context) {
    final counts = countsAsync.valueOrNull ?? AnkiDroidCounts.zero;
    if (counts.studyable == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          const Icon(Icons.school_outlined, size: 28, color: AppTheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('In your queue',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  '${counts.newCount} new • '
                  '${counts.learnCount} learning • '
                  '${counts.reviewCount} review',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final AsyncValue<AnkiDroidCounts> countsAsync;
  const _QuickActions({required this.countsAsync});

  @override
  Widget build(BuildContext context) {
    final counts = countsAsync.valueOrNull ?? AnkiDroidCounts.zero;
    final hasCards = counts.studyable > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: hasCards ? () => context.push('/review') : null,
                icon: const Icon(Icons.school),
                label: Text(
                  hasCards
                      ? 'Study Now (${counts.studyable})'
                      : 'Nothing due',
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.push('/blocking'),
                icon: const Icon(Icons.block),
                label: const Text('Manage Blocking'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.push('/decks'),
                icon: const Icon(Icons.folder_outlined),
                label: const Text('Decks'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(12);
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 12),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
        ),
      ],
    );

    if (onTap != null) {
      return Material(
        color: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: const BorderSide(color: AppTheme.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: column,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: borderRadius,
        border: Border.all(color: AppTheme.divider),
      ),
      child: column,
    );
  }
}
