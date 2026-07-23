import 'package:ankiblock/src/core/utils/blocking_goal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isBlockingGoalComplete', () {
    test('dueCards complete when learning+reviews cleared even if new remain',
        () {
      expect(
        isBlockingGoalComplete(
          mode: StudyMode.dueCards,
          dailyCardsGoal: 30,
          cardsReviewed: 0,
          obligationDue: 0,
        ),
        isTrue,
      );
    });

    test('dueCards incomplete when learning or reviews remain', () {
      expect(
        isBlockingGoalComplete(
          mode: StudyMode.dueCards,
          dailyCardsGoal: 30,
          cardsReviewed: 100,
          obligationDue: 5,
        ),
        isFalse,
      );
    });

    test('cardCount uses reviewed vs goal', () {
      expect(
        isBlockingGoalComplete(
          mode: StudyMode.cardCount,
          dailyCardsGoal: 30,
          cardsReviewed: 30,
          obligationDue: 99,
        ),
        isTrue,
      );
      expect(
        isBlockingGoalComplete(
          mode: StudyMode.cardCount,
          dailyCardsGoal: 30,
          cardsReviewed: 29,
          obligationDue: 0,
        ),
        isFalse,
      );
    });
  });

  group('weakening helpers', () {
    test('goals and protection ranks', () {
      expect(isWeakeningUnlockGoal(current: 10, proposed: 5), isTrue);
      expect(isWeakeningUnlockGoal(current: 10, proposed: 15), isFalse);
      expect(isWeakeningDailyGoal(current: 30, proposed: 20), isTrue);
      expect(
        isWeakeningProtection(
          current: SettingsProtection.strict,
          proposed: SettingsProtection.off,
        ),
        isTrue,
      );
      expect(
        isWeakeningProtection(
          current: SettingsProtection.off,
          proposed: SettingsProtection.soft,
        ),
        isFalse,
      );
    });

    test('study mode switch weaker only when obligation remains', () {
      expect(
        isWeakerStudyMode(
          current: StudyMode.dueCards,
          proposed: StudyMode.cardCount,
          obligationDue: 3,
        ),
        isTrue,
      );
      expect(
        isWeakerStudyMode(
          current: StudyMode.dueCards,
          proposed: StudyMode.cardCount,
          obligationDue: 0,
        ),
        isFalse,
      );
      expect(
        isWeakerStudyMode(
          current: StudyMode.cardCount,
          proposed: StudyMode.dueCards,
          obligationDue: 10,
        ),
        isFalse,
      );
    });
  });
}
