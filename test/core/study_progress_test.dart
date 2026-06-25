import 'package:flutter_test/flutter_test.dart';

import 'package:ankiblock/src/core/database/database.dart';
import 'package:ankiblock/src/core/utils/study_progress.dart';

DailyStat _stat(String date, int cards) {
  return DailyStat(
    date: date,
    cardsReviewed: cards,
    unlocksEarned: 0,
    blockedAttempts: 0,
    bypassesUsed: 0,
  );
}

void main() {
  group('offsetStudyDay', () {
    test('moves forward and backward', () {
      expect(offsetStudyDay('2026-06-25', 1), '2026-06-26');
      expect(offsetStudyDay('2026-06-25', -1), '2026-06-24');
    });
  });

  group('lastNDayKeys', () {
    test('returns consecutive days ending on anchor', () {
      expect(
        lastNDayKeys('2026-06-25', 3),
        ['2026-06-23', '2026-06-24', '2026-06-25'],
      );
    });
  });

  group('calendarWeekDayKeys', () {
    test('returns Monday through Sunday for mid-week anchor', () {
      expect(
        calendarWeekDayKeys('2026-06-25'),
        [
          '2026-06-22',
          '2026-06-23',
          '2026-06-24',
          '2026-06-25',
          '2026-06-26',
          '2026-06-27',
          '2026-06-28',
        ],
      );
    });
  });

  group('buildStudyProgressOverview', () {
    test('computes streak, recent days, and week totals', () {
      final overview = buildStudyProgressOverview(
        dailyGoal: 30,
        statsByDate: {
          '2026-06-23': _stat('2026-06-23', 35),
          '2026-06-24': _stat('2026-06-24', 30),
          '2026-06-25': _stat('2026-06-25', 10),
        },
        today: '2026-06-25',
      );

      expect(overview.streak, 2);
      expect(overview.recentDays, hasLength(7));
      expect(overview.recentDays.last.date, '2026-06-25');
      expect(overview.recentDays.last.cardsReviewed, 10);
      expect(overview.recentDays.last.isToday, isTrue);
      expect(overview.recentDays.last.goalMet, isFalse);
      expect(overview.thisWeek.totalCards, 75);
      expect(overview.thisWeek.daysGoalMet, 2);
      expect(overview.lastWeek.totalCards, 0);
      expect(overview.weekOverWeekDelta, 75);
    });

    test('does not break streak when today is still in progress', () {
      final overview = buildStudyProgressOverview(
        dailyGoal: 30,
        statsByDate: {
          '2026-06-24': _stat('2026-06-24', 30),
          '2026-06-25': _stat('2026-06-25', 5),
        },
        today: '2026-06-25',
      );

      expect(overview.streak, 1);
    });
  });
}
