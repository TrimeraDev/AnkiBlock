import '../services/ankidroid_service.dart';
import '../services/study_launcher.dart';
import '../services/study_scope_service.dart';

/// Summary line for enabled decks.
String formatDeckStudySummary(StudyScope scope, List<AnkiDroidDeck> decks) {
  if (decks.isEmpty) return 'No decks in AnkiDroid';
  final enabledIds = scope.filterDeckIds(decks.map((d) => d.id));
  if (enabledIds.isEmpty) return 'No decks selected';
  final enabled =
      decks.where((d) => enabledIds.contains(d.id)).toList();
  if (enabled.length == decks.length) {
    return 'All ${decks.length} decks';
  }
  if (enabled.length == 1) return enabled.first.name;
  if (enabled.length <= 3) {
    return enabled.map((d) => d.name).join(', ');
  }
  return '${enabled.length} decks · ${enabled.take(2).map((d) => d.name).join(', ')}…';
}

int countDueInScope(StudyScope scope, List<AnkiDroidDeck> decks) {
  final enabledIds = scope.filterDeckIds(decks.map((d) => d.id)).toSet();
  return decks
      .where((d) => enabledIds.contains(d.id))
      .fold(0, (sum, d) => sum + d.totalDue);
}

/// Hint for which deck AnkiDroid opens when multiple are selected.
String formatLaunchDeckHint(StudyScope scope, List<AnkiDroidDeck> decks) {
  final enabledIds = scope.filterDeckIds(decks.map((d) => d.id));
  if (enabledIds.length <= 1) return '';
  final launchId = resolveLaunchDeckId(scope, decks, enabledIds);
  final launchDeck = decks.where((d) => d.id == launchId).firstOrNull;
  if (launchDeck == null) return '';
  return 'Opens ${launchDeck.name}';
}

int countEnabledDecks(StudyScope scope, List<AnkiDroidDeck> decks) {
  return scope.filterDeckIds(decks.map((d) => d.id)).length;
}

bool hasDecksInScope(StudyScope scope, List<AnkiDroidDeck> decks) {
  return countEnabledDecks(scope, decks) > 0;
}
