import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../di/providers.dart';
import '../services/apps_service.dart';
import '../utils/study_day.dart';

Future<void> updateCardsRequired(WidgetRef ref, int cards) async {
  final db = ref.read(databaseProvider);
  await db.updateBlockRule(BlockRulesCompanion(
    id: const Value(1),
    cardsRequired: Value(cards),
    updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
  ));
  ref.invalidate(blockRuleProvider);
}

Future<void> updateDailyCardsGoal(WidgetRef ref, int cards) async {
  final db = ref.read(databaseProvider);
  await db.updateBlockRule(BlockRulesCompanion(
    id: const Value(1),
    dailyCardsGoal: Value(cards),
    updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
  ));
  ref.invalidate(blockRuleProvider);
  await syncDailyGoalToNative(ref);
}

Future<void> syncBlockRuleToNative(WidgetRef ref) async {
  final rule = await ref.read(blockRuleProvider.future);
  await ref.read(appsServiceProvider).syncBlockRuleSettings(
        unlockDurationMinutes: rule?.unlockDurationMinutes ?? 10,
        bypassSeconds: rule?.bypassSeconds ?? 60,
        isEnabled: rule?.isEnabled ?? true,
      );
}

Future<void> syncDailyGoalToNative(WidgetRef ref) async {
  final rule = await ref.read(blockRuleProvider.future);
  final day = studyDayKey();
  final stat = await ref.read(databaseProvider).getDailyStat(day);
  await ref.read(appsServiceProvider).syncDailyGoalState(
        studyDayKey: day,
        dailyGoal: rule?.dailyCardsGoal ?? 0,
        cardsReviewed: stat?.cardsReviewed ?? 0,
      );
}

Future<void> syncStudyScopeToNative(WidgetRef ref) async {
  try {
    final status = await ref.read(ankiDroidStatusProvider.future);
    var ids = <int>[];
    if (status.isReady) {
      final scope = await ref.read(studyScopeProvider.future);
      final decks = await ref.read(ankiDroidDecksProvider.future);
      ids = scope.filterDeckIds(decks.map((d) => d.id));
    }
    await ref.read(appsServiceProvider).syncStudyScope(deckIds: ids);
  } catch (_) {
    await ref.read(appsServiceProvider).syncStudyScope(deckIds: const []);
  }
}

/// Pulls passive study counts from native when the user studied in AnkiDroid
/// without opening AnkiBlock.
Future<void> mergeDailyFromNative(WidgetRef ref) async {
  final native = await ref.read(appsServiceProvider).getDailyGoalState();
  final day = studyDayKey();
  if (native.studyDayKey != day) return;
  final db = ref.read(databaseProvider);
  final stat = await db.getDailyStat(day);
  final dbCount = stat?.cardsReviewed ?? 0;
  if (native.cardsReviewed > dbCount) {
    await db.setCardsReviewedForDay(day, native.cardsReviewed);
    ref.invalidate(dailyStatsProvider(day));
    ref.invalidate(studyProgressProvider);
    await syncDailyGoalToNative(ref);
  }
}

Future<void> ensureAppMonitorRunning(WidgetRef ref) async {
  final blocked =
      await ref.read(databaseProvider).watchActiveBlockedApps().first;
  final svc = ref.read(appsServiceProvider);
  if (blocked.isNotEmpty) {
    await svc.startAppMonitor();
  } else {
    await svc.stopAppMonitor();
  }
}

Future<void> toggleAppBlocked(
  WidgetRef ref, {
  required InstalledApp app,
  required bool blocked,
}) async {
  final db = ref.read(databaseProvider);
  final existing = await db.getBlockedApp(app.packageName);
  if (existing == null) {
    await db.insertBlockedApp(BlockedAppsCompanion.insert(
      packageName: app.packageName,
      displayName: app.appName,
      isBlocked: Value(blocked),
    ));
  } else {
    await db.setBlocked(app.packageName, blocked);
  }
  await syncBlockedPackagesToNative(ref);
}

Future<void> blockSuggestedApps(WidgetRef ref, List<InstalledApp> apps) async {
  final db = ref.read(databaseProvider);
  for (final app in apps) {
    final existing = await db.getBlockedApp(app.packageName);
    if (existing == null) {
      await db.insertBlockedApp(BlockedAppsCompanion.insert(
        packageName: app.packageName,
        displayName: app.appName,
        isBlocked: const Value(true),
      ));
    } else if (!existing.isBlocked) {
      await db.setBlocked(app.packageName, true);
    }
  }
  await syncBlockedPackagesToNative(ref);
}

Future<void> syncBlockedPackagesToNative(WidgetRef ref) async {
  final db = ref.read(databaseProvider);
  final all = await db.watchAllBlockedApps().first;
  final active = all
      .where((b) => b.isBlocked)
      .map((b) => (pkg: b.packageName, name: b.displayName))
      .toList();
  final svc = ref.read(appsServiceProvider);
  await svc.setBlockedPackages(active);
  await syncStudyScopeToNative(ref);
  await syncBlockRuleToNative(ref);
  await ensureAppMonitorRunning(ref);
}
