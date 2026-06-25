import 'package:intl/intl.dart';

/// AnkiBlock's study day rolls over at 3:00 AM local time (not midnight).
const int studyDayRolloverHour = 3;

/// Returns the YYYY-MM-DD key for the current study day.
String studyDayKey([DateTime? now]) {
  final shifted = (now ?? DateTime.now()).subtract(
    const Duration(hours: studyDayRolloverHour),
  );
  return DateFormat('yyyy-MM-dd').format(shifted);
}

bool isDailyGoalComplete({
  required int dailyGoal,
  required int cardsReviewed,
}) {
  return dailyGoal > 0 && cardsReviewed >= dailyGoal;
}
