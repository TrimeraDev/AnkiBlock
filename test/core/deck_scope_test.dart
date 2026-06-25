import 'package:flutter_test/flutter_test.dart';

import 'package:ankiblock/src/core/services/ankidroid_service.dart';
import 'package:ankiblock/src/core/services/study_launcher.dart';
import 'package:ankiblock/src/core/services/study_scope_service.dart';
import 'package:ankiblock/src/core/utils/deck_scope_format.dart';

AnkiDroidDeck _deck(int id, String name, {int due = 0}) {
  final learn = due ~/ 3;
  final review = due ~/ 3;
  final newC = due - learn - review;
  return AnkiDroidDeck(
    id: id,
    name: name,
    learnCount: learn,
    reviewCount: review,
    newCount: newC,
  );
}

void main() {
  group('StudyScope.filterDeckIds', () {
    test('multi excludes disabled decks', () {
      const scope = StudyScope(
        mode: StudyScopeMode.multi,
        disabledDeckIds: {2},
        activeDeckId: null,
      );
      expect(scope.filterDeckIds([1, 2, 3]), [1, 3]);
    });

    test('single returns only active deck', () {
      const scope = StudyScope(
        mode: StudyScopeMode.single,
        disabledDeckIds: {},
        activeDeckId: 2,
      );
      expect(scope.filterDeckIds([1, 2, 3]), [2]);
    });

    test('single with no active deck returns empty', () {
      const scope = StudyScope(
        mode: StudyScopeMode.single,
        disabledDeckIds: {},
        activeDeckId: null,
      );
      expect(scope.filterDeckIds([1, 2, 3]), isEmpty);
    });

    test('all mode includes every deck', () {
      const scope = StudyScope(
        mode: StudyScopeMode.all,
        disabledDeckIds: {99},
        activeDeckId: null,
      );
      expect(scope.filterDeckIds([1, 2, 3]), [1, 2, 3]);
    });
  });

  group('resolveLaunchDeckId', () {
    final decks = [
      _deck(1, 'Japanese', due: 30),
      _deck(2, 'Spanish', due: 5),
      _deck(3, 'History', due: 12),
    ];

    test('picks highest due in multi mode', () {
      const scope = StudyScope(
        mode: StudyScopeMode.multi,
        disabledDeckIds: {},
        activeDeckId: null,
      );
      expect(
        resolveLaunchDeckId(scope, decks, [1, 2, 3]),
        1,
      );
    });

    test('uses active deck in single mode', () {
      const scope = StudyScope(
        mode: StudyScopeMode.single,
        disabledDeckIds: {},
        activeDeckId: 2,
      );
      expect(
        resolveLaunchDeckId(scope, decks, [2]),
        2,
      );
    });
  });

  group('formatDeckStudySummary', () {
    final decks = [
      _deck(1, 'A'),
      _deck(2, 'B'),
      _deck(3, 'C'),
      _deck(4, 'D'),
    ];

    test('empty selection', () {
      const scope = StudyScope(
        mode: StudyScopeMode.multi,
        disabledDeckIds: {1, 2, 3, 4},
        activeDeckId: null,
      );
      expect(formatDeckStudySummary(scope, decks), 'No decks selected');
    });

    test('single deck shows name', () {
      const scope = StudyScope(
        mode: StudyScopeMode.multi,
        disabledDeckIds: {2, 3, 4},
        activeDeckId: null,
      );
      expect(formatDeckStudySummary(scope, decks), 'A');
    });

    test('many decks shows count summary', () {
      const scope = StudyScope(
        mode: StudyScopeMode.multi,
        disabledDeckIds: {},
        activeDeckId: null,
      );
      expect(formatDeckStudySummary(scope, decks), 'All 4 decks');
    });
  });

  group('formatLaunchDeckHint', () {
    test('empty when one deck selected', () {
      const scope = StudyScope(
        mode: StudyScopeMode.multi,
        disabledDeckIds: {2},
        activeDeckId: null,
      );
      final decks = [_deck(1, 'Japanese', due: 10), _deck(2, 'Spanish')];
      expect(formatLaunchDeckHint(scope, decks), '');
    });

    test('shows launch deck when multiple selected', () {
      const scope = StudyScope(
        mode: StudyScopeMode.multi,
        disabledDeckIds: {},
        activeDeckId: null,
      );
      final decks = [
        _deck(1, 'Japanese', due: 30),
        _deck(2, 'Spanish', due: 5),
      ];
      expect(formatLaunchDeckHint(scope, decks), 'Opens Japanese');
    });
  });

  group('countDueInScope', () {
    test('sums due across enabled decks', () {
      const scope = StudyScope(
        mode: StudyScopeMode.multi,
        disabledDeckIds: {2},
        activeDeckId: null,
      );
      final decks = [
        _deck(1, 'A', due: 10),
        _deck(2, 'B', due: 99),
        _deck(3, 'C', due: 5),
      ];
      expect(countDueInScope(scope, decks), 15);
    });
  });
}
