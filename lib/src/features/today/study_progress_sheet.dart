import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/di/providers.dart';
import '../../core/utils/study_progress.dart';
import '../../core/widgets/brand_widgets.dart';

/// Opens the weekly study progress bottom sheet.
void showStudyProgressSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final overview = ref.read(studyProgressProvider).valueOrNull;
      if (overview == null) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            32,
            20,
            32 + MediaQuery.viewPaddingOf(ctx).bottom,
          ),
          child: const Center(child: CircularProgressIndicator()),
        );
      }
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.viewPaddingOf(ctx).bottom,
        ),
        child: StudyProgressSheet(overview: overview),
      );
    },
  );
}

/// Bottom sheet showing streak, weekly totals, and a 7-day activity chart.
class StudyProgressSheet extends StatelessWidget {
  final StudyProgressOverview overview;

  const StudyProgressSheet({super.key, required this.overview});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final streak = overview.streak;
    final streakLabel = streak == 0
        ? 'No active streak'
        : streak == 1
            ? '1 day streak'
            : '$streak day streak';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Icon(
              Icons.local_fire_department_rounded,
              size: 28,
              color: streak > 0 ? AppTheme.warning : AppTheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Study progress', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 2),
                  Text(
                    streakLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: streak > 0
                          ? AppTheme.warning
                          : AppTheme.onSurfaceVariant,
                      fontWeight:
                          streak > 0 ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _WeekSummaryCard(overview: overview),
        const SizedBox(height: 16),
        Text('Last 7 days', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Daily goal: ${overview.dailyGoal} cards',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        _RecentDaysChart(overview: overview),
        const SizedBox(height: 16),
        _RecentDaysList(days: overview.recentDays, dailyGoal: overview.dailyGoal),
      ],
    );
  }
}

class _WeekSummaryCard extends StatelessWidget {
  final StudyProgressOverview overview;

  const _WeekSummaryCard({required this.overview});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thisWeek = overview.thisWeek;
    final lastWeek = overview.lastWeek;
    final delta = overview.weekOverWeekDelta;

    String comparison;
    Color comparisonColor;
    if (lastWeek.totalCards == 0 && thisWeek.totalCards == 0) {
      comparison = 'No cards last week either';
      comparisonColor = AppTheme.onSurfaceVariant;
    } else if (delta > 0) {
      comparison = '+$delta vs last week';
      comparisonColor = AppTheme.success;
    } else if (delta < 0) {
      comparison = '$delta vs last week';
      comparisonColor = AppTheme.onSurfaceVariant;
    } else {
      comparison = 'Same as last week';
      comparisonColor = AppTheme.onSurfaceVariant;
    }

    return BrandCard(
      color: AppTheme.cardElevated,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This week', style: theme.textTheme.labelMedium),
          const SizedBox(height: 6),
          Text(
            '${thisWeek.totalCards} cards',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            '${thisWeek.daysGoalMet}/${thisWeek.dayCount} daily goals met',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _WeekStatChip(
                  label: 'Last week',
                  value: '${lastWeek.totalCards}',
                  subtitle: '${lastWeek.daysGoalMet} goals',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _WeekStatChip(
                  label: 'Change',
                  value: delta == 0 ? '—' : (delta > 0 ? '+$delta' : '$delta'),
                  subtitle: 'cards',
                  valueColor: comparisonColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            comparison,
            style: theme.textTheme.bodySmall?.copyWith(color: comparisonColor),
          ),
        ],
      ),
    );
  }
}

class _WeekStatChip extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final Color? valueColor;

  const _WeekStatChip({
    required this.label,
    required this.value,
    required this.subtitle,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(color: valueColor),
          ),
          Text(subtitle, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _RecentDaysChart extends StatelessWidget {
  final StudyProgressOverview overview;

  const _RecentDaysChart({required this.overview});

  @override
  Widget build(BuildContext context) {
    final days = overview.recentDays;
    final dailyGoal = overview.dailyGoal;
    final maxCards = days
        .map((d) => d.cardsReviewed)
        .fold(dailyGoal, (a, b) => a > b ? a : b)
        .clamp(1, 999999);
    const barMaxHeight = 88.0;

    return BrandCard(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in days) ...[
            Expanded(child: _DayBar(day: day, maxCards: maxCards, barMaxHeight: barMaxHeight)),
          ],
        ],
      ),
    );
  }
}

class _DayBar extends StatelessWidget {
  final DayStudyStat day;
  final int maxCards;
  final double barMaxHeight;

  const _DayBar({
    required this.day,
    required this.maxCards,
    required this.barMaxHeight,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = day.cardsReviewed / maxCards;
    final barHeight = (fraction * barMaxHeight).clamp(4.0, barMaxHeight);
    final barColor = day.goalMet
        ? AppTheme.success
        : day.cardsReviewed > 0
            ? AppTheme.accent.withValues(alpha: 0.75)
            : AppTheme.cardElevated;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        children: [
          SizedBox(
            height: barMaxHeight,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                height: barHeight,
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(4),
                  border: day.isToday
                      ? Border.all(color: AppTheme.warning, width: 1.5)
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            day.weekdayLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: day.isToday ? AppTheme.warning : null,
              fontWeight: day.isToday ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${day.cardsReviewed}',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10,
              color: day.goalMet ? AppTheme.success : AppTheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentDaysList extends StatelessWidget {
  final List<DayStudyStat> days;
  final int dailyGoal;

  const _RecentDaysList({required this.days, required this.dailyGoal});

  @override
  Widget build(BuildContext context) {
    final reversed = days.reversed.toList();
    return Column(
      children: [
        for (final day in reversed) _DayListTile(day: day, dailyGoal: dailyGoal),
      ],
    );
  }
}

class _DayListTile extends StatelessWidget {
  final DayStudyStat day;
  final int dailyGoal;

  const _DayListTile({required this.day, required this.dailyGoal});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateLabel = _formatDayLabel(day.date, day.isToday);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            day.goalMet
                ? Icons.check_circle_rounded
                : day.cardsReviewed > 0
                    ? Icons.radio_button_unchecked
                    : Icons.remove_circle_outline,
            size: 18,
            color: day.goalMet
                ? AppTheme.success
                : day.cardsReviewed > 0
                    ? AppTheme.accent
                    : AppTheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              dateLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: day.isToday ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            '${day.cardsReviewed} / $dailyGoal',
            style: theme.textTheme.bodySmall?.copyWith(
              color: day.goalMet ? AppTheme.success : AppTheme.onSurfaceVariant,
              fontWeight: day.goalMet ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDayLabel(String date, bool isToday) {
    if (isToday) return 'Today';
    final parsed = DateTime(
      int.parse(date.split('-')[0]),
      int.parse(date.split('-')[1]),
      int.parse(date.split('-')[2]),
    );
    return DateFormat('EEE, MMM d').format(parsed);
  }
}
