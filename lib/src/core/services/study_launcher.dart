import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../setup/setup_actions.dart';
import 'ankidroid_service.dart';
import 'apps_service.dart';
import 'study_scope_service.dart';
import '../utils/study_day.dart';

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

/// Cards to study in the next session: remaining daily cards when the daily
/// goal is not met, otherwise the per-unlock amount.
Future<int> resolveSessionTarget(
  WidgetRef ref, {
  bool forGate = false,
}) async {
  final rule = await ref.read(blockRuleProvider.future);
  final unlockGoal = rule?.cardsRequired ?? 10;
  if (forGate) return unlockGoal;

  final dailyGoal = rule?.dailyCardsGoal ?? 30;
  final day = studyDayKey();
  final reviewed =
      (await ref.read(databaseProvider).getDailyStat(day))?.cardsReviewed ?? 0;
  if (isDailyGoalComplete(dailyGoal: dailyGoal, cardsReviewed: reviewed)) {
    return unlockGoal;
  }
  final remaining = (dailyGoal - reviewed).clamp(0, dailyGoal);
  return remaining.clamp(1, dailyGoal);
}

/// Starts a tracked study session in AnkiDroid and opens the reviewer.
/// When [unlockPackageName] is null, cards are tracked for today's stats only
/// (no app unlock at the end). When set (study gate flow), completing the
/// session unlocks that app.
Future<bool> startScopedStudySession({
  required WidgetRef ref,
  required StudyScope scope,
  required List<AnkiDroidDeck> decks,
  required int cardsRequired,
  String? unlockPackageName,
  String? unlockAppName,
  bool forGate = false,
}) async {
  final allowedIds = scope.filterDeckIds(decks.map((d) => d.id));
  if (allowedIds.isEmpty) return false;

  final deckId = resolveStudyDeckId(scope, decks, allowedIds);
  final deck = decks.firstWhere((d) => d.id == deckId);
  final apps = ref.read(appsServiceProvider);
  final anki = ref.read(ankiDroidServiceProvider);

  final target = cardsRequired > 0
      ? cardsRequired
      : await resolveSessionTarget(ref, forGate: forGate);

  ref.read(delegatedSessionProgressProvider.notifier).state =
      DelegatedSessionProgress(completed: 0, target: target);

  await syncStudyScopeToNative(ref);
  await ensureAppMonitorRunning(ref);
  await apps.startAppMonitor();
  await apps.startDelegatedSession(
    packageName: unlockPackageName ?? kPracticeStudyPackage,
    appName: unlockAppName ?? 'Study',
    deckId: deckId,
    deckIds: allowedIds,
    target: target,
    baseline: deck.totalDue,
  );
  return anki.openAnkiDroidReviewer(deckId);
}

/// Opens AnkiDroid without starting a tracked session (legacy).
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
