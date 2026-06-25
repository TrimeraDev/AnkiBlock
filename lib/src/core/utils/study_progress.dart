import 'package:intl/intl.dart';

import '../database/database.dart';
import 'study_day.dart';
import 'study_streak.dart';

/// Cards reviewed and goal status for a single study day.
class DayStudyStat {
  final String date;
  final int cardsReviewed;
  final int unlocksEarned;
  final int blockedAttempts;
  final bool goalMet;
  final bool isToday;

  const DayStudyStat({
    required this.date,
    required this.cardsReviewed,
    required this.unlocksEarned,
    required this.blockedAttempts,
    required this.goalMet,
    required this.isToday,
  });

  String get weekdayLabel =>
      DateFormat('EEEEE').format(_parseDayKey(date)).toUpperCase();
}

/// Aggregated stats for a calendar week (Monday–Sunday).
class WeekStudySummary {
  final List<String> dayKeys;
  final int totalCards;
  final int daysGoalMet;

  const WeekStudySummary({
    required this.dayKeys,
    required this.totalCards,
    required this.daysGoalMet,
  });

  int get dayCount => dayKeys.length;
}

/// Streak plus recent daily and weekly rollups for the progress sheet.
class StudyProgressOverview {
  final int streak;
  final int dailyGoal;
  final List<DayStudyStat> recentDays;
  final WeekStudySummary thisWeek;
  final WeekStudySummary lastWeek;

  const StudyProgressOverview({
    required this.streak,
    required this.dailyGoal,
    required this.recentDays,
    required this.thisWeek,
    required this.lastWeek,
  });

  int get weekOverWeekDelta => thisWeek.totalCards - lastWeek.totalCards;
}

DateTime _parseDayKey(String dayKey) {
  final parts = dayKey.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

String _formatDayKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

String offsetStudyDay(String dayKey, int days) {
  return _formatDayKey(_parseDayKey(dayKey).add(Duration(days: days)));
}

List<String> lastNDayKeys(String endDay, int count) {
  return List.generate(
    count,
    (i) => offsetStudyDay(endDay, i - count + 1),
  );
}

List<String> calendarWeekDayKeys(String anchorDay) {
  final date = _parseDayKey(anchorDay);
  final monday = date.subtract(Duration(days: date.weekday - DateTime.monday));
  return List.generate(7, (i) => _formatDayKey(monday.add(Duration(days: i))));
}

DayStudyStat _dayStat({
  required String date,
  required DailyStat? stat,
  required int dailyGoal,
  required String today,
}) {
  final reviewed = stat?.cardsReviewed ?? 0;
  return DayStudyStat(
    date: date,
    cardsReviewed: reviewed,
    unlocksEarned: stat?.unlocksEarned ?? 0,
    blockedAttempts: stat?.blockedAttempts ?? 0,
    goalMet: isDailyGoalComplete(dailyGoal: dailyGoal, cardsReviewed: reviewed),
    isToday: date == today,
  );
}

WeekStudySummary _weekSummary({
  required List<String> dayKeys,
  required Map<String, DailyStat> statsByDate,
  required int dailyGoal,
}) {
  var totalCards = 0;
  var daysGoalMet = 0;
  for (final day in dayKeys) {
    final stat = statsByDate[day];
    final reviewed = stat?.cardsReviewed ?? 0;
    totalCards += reviewed;
    if (isDailyGoalComplete(dailyGoal: dailyGoal, cardsReviewed: reviewed)) {
      daysGoalMet++;
    }
  }
  return WeekStudySummary(
    dayKeys: dayKeys,
    totalCards: totalCards,
    daysGoalMet: daysGoalMet,
  );
}

StudyProgressOverview buildStudyProgressOverview({
  required int dailyGoal,
  required Map<String, DailyStat> statsByDate,
  String? today,
}) {
  final todayKey = today ?? studyDayKey();
  final cardsByDate = {
    for (final entry in statsByDate.entries) entry.key: entry.value.cardsReviewed,
  };
  final streak = computeStudyStreak(
    dailyGoal: dailyGoal,
    cardsReviewedByDate: cardsByDate,
    today: todayKey,
  );

  final recentDays = lastNDayKeys(todayKey, 7)
      .map(
        (day) => _dayStat(
          date: day,
          stat: statsByDate[day],
          dailyGoal: dailyGoal,
          today: todayKey,
        ),
      )
      .toList();

  final thisWeekKeys = calendarWeekDayKeys(todayKey);
  final lastWeekAnchor = offsetStudyDay(thisWeekKeys.first, -7);
  final lastWeekKeys = calendarWeekDayKeys(lastWeekAnchor);

  return StudyProgressOverview(
    streak: streak,
    dailyGoal: dailyGoal,
    recentDays: recentDays,
    thisWeek: _weekSummary(
      dayKeys: thisWeekKeys,
      statsByDate: statsByDate,
      dailyGoal: dailyGoal,
    ),
    lastWeek: _weekSummary(
      dayKeys: lastWeekKeys,
      statsByDate: statsByDate,
      dailyGoal: dailyGoal,
    ),
  );
}
