import 'package:intl/intl.dart';

import 'study_day.dart';

String previousStudyDay(String dayKey) {
  final parts = dayKey.split('-');
  final date = DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
  return DateFormat('yyyy-MM-dd')
      .format(date.subtract(const Duration(days: 1)));
}

/// Consecutive study days with the daily goal met (3am day boundary).
///
/// If today is not complete yet, the streak counts backward from yesterday so
/// an in-progress day does not break the streak.
int computeStudyStreak({
  required int dailyGoal,
  required Map<String, int> cardsReviewedByDate,
  String? today,
}) {
  if (dailyGoal <= 0) return 0;

  final todayKey = today ?? studyDayKey();
  final todayReviewed = cardsReviewedByDate[todayKey] ?? 0;
  var day = todayKey;
  if (!isDailyGoalComplete(
    dailyGoal: dailyGoal,
    cardsReviewed: todayReviewed,
  )) {
    day = previousStudyDay(todayKey);
  }

  var streak = 0;
  while (true) {
    final reviewed = cardsReviewedByDate[day] ?? 0;
    if (!isDailyGoalComplete(dailyGoal: dailyGoal, cardsReviewed: reviewed)) {
      break;
    }
    streak++;
    day = previousStudyDay(day);
    if (streak > 366) break;
  }
  return streak;
}
