import 'ankidroid_service.dart';
import 'study_scope_service.dart';

/// Picks which AnkiDroid deck to open for study given the user's scope.
int resolveStudyDeckId(
  StudyScope scope,
  List<AnkiDroidDeck> decks,
  List<int> allowedIds,
) {
  final allowed = allowedIds.toSet();
  if (scope.mode == StudyScopeMode.single && scope.activeDeckId != null) {
    return scope.activeDeckId!;
  }
  AnkiDroidDeck? best;
  for (final deck in decks) {
    if (!allowed.contains(deck.id)) continue;
    if (best == null || deck.totalDue > best.totalDue) {
      best = deck;
    }
  }
  return best?.id ?? allowedIds.first;
}

/// Resolves the scoped deck and opens AnkiDroid's native reviewer.
///
/// Returns `false` when no deck is in scope or the launch failed.
Future<bool> openScopedAnkiDroidReviewer({
  required StudyScope scope,
  required List<AnkiDroidDeck> decks,
  required AnkiDroidService anki,
}) async {
  final allowedIds = scope.filterDeckIds(decks.map((d) => d.id));
  if (allowedIds.isEmpty) return false;
  final deckId = resolveStudyDeckId(scope, decks, allowedIds);
  return anki.openAnkiDroidReviewer(deckId);
}
