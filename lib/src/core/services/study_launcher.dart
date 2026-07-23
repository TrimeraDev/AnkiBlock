import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../setup/setup_actions.dart';
import 'ankidroid_service.dart';
import 'apps_service.dart';
import 'study_scope_service.dart';
import '../utils/study_day.dart';
import '../utils/blocking_goal.dart';

/// Outcome of [startScopedStudySession].
class StudySessionStart {
  /// True when a recent study bout already met the unlock goal.
  final bool alreadyUnlocked;

  /// Whether AnkiDroid reviewer was opened.
  final bool openedAnki;

  final int seeded;
  final int target;

  const StudySessionStart({
    required this.alreadyUnlocked,
    required this.openedAnki,
    required this.seeded,
    required this.target,
  });
}

/// Picks which AnkiDroid deck to open when starting a study session.
///
/// This is the launch deck only — delegated tracking counts reps from all
/// decks in [allowedIds], not just the returned deck.
int resolveLaunchDeckId(
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
    // Prefer decks with learning/reviews (Anki obligation) over new-only.
    if (best == null ||
        deck.obligationDue > best.obligationDue ||
        (deck.obligationDue == best.obligationDue &&
            deck.totalDue > best.totalDue)) {
      best = deck;
    }
  }
  return best?.id ?? allowedIds.first;
}

/// Cards to study in the next session.
///
/// Gate sessions always use the unlock goal. Home sessions use remaining
/// daily cards (card-count mode) or min(obligation, unlock goal) (due mode).
Future<int> resolveSessionTarget(
  WidgetRef ref, {
  bool forGate = false,
}) async {
  final rule = await ref.read(blockRuleProvider.future);
  final unlockGoal = rule?.cardsRequired ?? 10;
  if (forGate) return unlockGoal;

  final mode = StudyMode.fromStorage(rule?.studyMode);
  if (mode == StudyMode.dueCards) {
    final due = (await ref.read(studyCountsProvider.future)).obligationDue;
    if (due <= 0) return unlockGoal;
    return due < unlockGoal ? due : unlockGoal;
  }

  final dailyGoal = rule?.dailyCardsGoal ?? 30;
  final day = studyDayKey();
  final reviewed =
      (await ref.read(databaseProvider).getDailyStat(day))?.cardsReviewed ?? 0;
  if (isBlockingGoalComplete(
    mode: mode,
    dailyCardsGoal: dailyGoal,
    cardsReviewed: reviewed,
    obligationDue: 0,
  )) {
    return unlockGoal;
  }
  final remaining = (dailyGoal - reviewed).clamp(0, dailyGoal);
  return remaining.clamp(1, dailyGoal);
}

/// Starts a tracked study session in AnkiDroid and opens the reviewer.
/// When [unlockPackageName] is null, cards are tracked for today's stats only
/// (no app unlock at the end). When set (study gate flow), completing the
/// session unlocks that app.
///
/// If a recent study bout already meets the unlock goal, returns
/// [StudySessionStart.alreadyUnlocked] without opening Anki.
Future<StudySessionStart> startScopedStudySession({
  required WidgetRef ref,
  required StudyScope scope,
  required List<AnkiDroidDeck> decks,
  required int cardsRequired,
  String? unlockPackageName,
  String? unlockAppName,
  bool forGate = false,
}) async {
  final allowedIds = scope.filterDeckIds(decks.map((d) => d.id));
  if (allowedIds.isEmpty) {
    return const StudySessionStart(
      alreadyUnlocked: false,
      openedAnki: false,
      seeded: 0,
      target: 0,
    );
  }

  final launchDeckId = resolveLaunchDeckId(scope, decks, allowedIds);
  final apps = ref.read(appsServiceProvider);
  final anki = ref.read(ankiDroidServiceProvider);

  final target = cardsRequired > 0
      ? cardsRequired
      : await resolveSessionTarget(ref, forGate: forGate);

  await syncStudyScopeToNative(ref);
  await ensureAppMonitorRunning(ref);
  await apps.startAppMonitor();
  final result = await apps.startDelegatedSession(
    packageName: unlockPackageName ?? kPracticeStudyPackage,
    appName: unlockAppName ?? 'Study',
    deckId: launchDeckId,
    deckIds: allowedIds,
    target: target,
  );

  if (result.unlocked) {
    ref.read(delegatedSessionProgressProvider.notifier).state = null;
    ref.read(delegatedProgressCreditFloorProvider.notifier).state = 0;
    return StudySessionStart(
      alreadyUnlocked: true,
      openedAnki: false,
      seeded: result.seeded,
      target: result.target,
    );
  }

  ref.read(delegatedProgressCreditFloorProvider.notifier).state = result.seeded;
  final pkg = unlockPackageName ?? kPracticeStudyPackage;
  ref.read(delegatedSessionProgressProvider.notifier).state =
      DelegatedSessionProgress(
    completed: result.seeded,
    target: result.target,
    packageName: pkg,
  );

  final opened = await anki.openAnkiDroidReviewer(launchDeckId);
  return StudySessionStart(
    alreadyUnlocked: false,
    openedAnki: opened,
    seeded: result.seeded,
    target: result.target,
  );
}

/// Opens AnkiDroid without starting a tracked session (legacy).
Future<bool> openScopedAnkiDroidReviewer({
  required StudyScope scope,
  required List<AnkiDroidDeck> decks,
  required AnkiDroidService anki,
}) async {
  final allowedIds = scope.filterDeckIds(decks.map((d) => d.id));
  if (allowedIds.isEmpty) return false;
  final launchDeckId = resolveLaunchDeckId(scope, decks, allowedIds);
  return anki.openAnkiDroidReviewer(launchDeckId);
}
