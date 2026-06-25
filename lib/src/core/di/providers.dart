import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../services/ankidroid_service.dart';
import '../services/apps_service.dart';
import '../services/permission_service.dart';
import '../services/study_scope_service.dart';
import '../services/support_prompt_service.dart';
import '../utils/study_day.dart';
import '../utils/study_progress.dart';

// Database -------------------------------------------------------------------

final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('Database must be overridden in main.dart');
});

// Services -------------------------------------------------------------------

final permissionServiceProvider = Provider<PermissionService>((ref) {
  return PermissionService();
});

/// Usage access + "display over other apps" (Android). Powers the global
/// "missing permissions" banner.
final blockingPermissionsProvider =
    FutureProvider<({bool usage, bool overlay})>((ref) async {
  final perm = ref.watch(permissionServiceProvider);
  return perm.getBlockingPermissions();
});

final appsServiceProvider = Provider<AppsService>((ref) {
  return AppsService();
});

final installedAppsProvider =
    AsyncNotifierProvider<InstalledAppsNotifier, List<InstalledApp>>(
  InstalledAppsNotifier.new,
);

class InstalledAppsNotifier extends AsyncNotifier<List<InstalledApp>> {
  @override
  Future<List<InstalledApp>> build() async {
    ref.keepAlive();
    final cached = await _loadFromCache();
    if (cached.isNotEmpty) {
      unawaited(refresh());
      return cached;
    }
    return _fetchAndSave();
  }

  /// Re-scan installed apps from the OS. Keeps the previous list visible while
  /// loading when we already have data.
  Future<void> refresh() async {
    if (state.hasValue) {
      state = const AsyncValue<List<InstalledApp>>.loading()
          .copyWithPrevious(state);
    }
    try {
      final apps = await _fetchAndSave();
      state = AsyncValue.data(apps);
    } catch (e, st) {
      state = state.hasValue
          ? AsyncValue<List<InstalledApp>>.error(e, st).copyWithPrevious(state)
          : AsyncValue.error(e, st);
    }
  }

  Future<List<InstalledApp>> _loadFromCache() async {
    final db = ref.read(databaseProvider);
    final rows = await db.getCachedInstalledApps();
    return rows.map((r) => r.toInstalledApp()).toList();
  }

  Future<List<InstalledApp>> _fetchAndSave() async {
    final apps = await ref.read(appsServiceProvider).listAppsWithUsage();
    final db = ref.read(databaseProvider);
    await db.replaceInstalledAppsCache(
      apps.map((a) => a.toCacheCompanion()).toList(),
    );
    return apps;
  }
}

// AnkiDroid integration ------------------------------------------------------

final ankiDroidServiceProvider = Provider<AnkiDroidService>((ref) {
  return AnkiDroidService();
});

/// Installed + permission state. Invalidate after the user returns from the
/// permission dialog or app settings to re-check.
final ankiDroidStatusProvider = FutureProvider<AnkiDroidStatus>((ref) async {
  return ref.watch(ankiDroidServiceProvider).getStatus();
});

/// Raw deck listing from AnkiDroid (with live counts).
final ankiDroidDecksProvider =
    FutureProvider<List<AnkiDroidDeck>>((ref) async {
  final status = await ref.watch(ankiDroidStatusProvider.future);
  if (!status.isReady) return const [];
  return ref.watch(ankiDroidServiceProvider).listDecks();
});

// Study scope ----------------------------------------------------------------

final studyScopeServiceProvider = Provider<StudyScopeService>((ref) {
  return StudyScopeService();
});

/// Current scope settings (mode + per-deck toggles). Invalidate after any
/// scope mutation to refresh dependent providers.
final studyScopeProvider = FutureProvider<StudyScope>((ref) async {
  return ref.watch(studyScopeServiceProvider).load();
});

/// Aggregated (learn / review / new) across whichever AnkiDroid decks are
/// currently in scope. This is what Today, the gate, and the unlock-counter
/// all read.
final studyCountsProvider = FutureProvider<AnkiDroidCounts>((ref) async {
  final status = await ref.watch(ankiDroidStatusProvider.future);
  if (!status.isReady) return AnkiDroidCounts.zero;
  final scope = await ref.watch(studyScopeProvider.future);
  return ref.watch(ankiDroidServiceProvider).getCountsForScope(scope);
});

// AnkiBlock-specific (blocker) data -----------------------------------------

final blockedAppsProvider = StreamProvider<List<BlockedApp>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAllBlockedApps();
});

final activeBlockedAppsProvider = StreamProvider<List<BlockedApp>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchActiveBlockedApps();
});

final blockRuleProvider = StreamProvider<BlockRule?>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchBlockRule();
});

/// Live daily stats for a given YYYY-MM-DD date.
final dailyStatsProvider =
    StreamProvider.family<DailyStat?, String>((ref, date) {
  final db = ref.watch(databaseProvider);
  return db.watchDailyStat(date);
});

/// Streak, weekly rollups, and recent daily stats for the progress sheet.
final studyProgressProvider = FutureProvider<StudyProgressOverview>((ref) async {
  ref.watch(dailyStatsProvider(studyDayKey()));
  final rule = await ref.watch(blockRuleProvider.future);
  final dailyGoal = rule?.dailyCardsGoal ?? 30;
  final db = ref.watch(databaseProvider);
  final rows = await db.getAllDailyStats();
  final byDate = {for (final row in rows) row.date: row};
  return buildStudyProgressOverview(
    dailyGoal: dailyGoal,
    statsByDate: byDate,
  );
});

/// Consecutive days the daily goal was met (3am study days).
final studyStreakProvider = FutureProvider<int>((ref) async {
  final overview = await ref.watch(studyProgressProvider.future);
  return overview.streak;
});

/// Today's pickups and screen time across blocked apps (usage access required).
final gateTodayUsageProvider =
    FutureProvider.family<TodayBlockedUsage, String>((ref, focusPackage) async {
  final blocked = await ref.watch(activeBlockedAppsProvider.future);
  if (blocked.isEmpty) return TodayBlockedUsage.zero;
  return ref.read(appsServiceProvider).getTodayBlockedUsage(
        packages: blocked.map((b) => b.packageName).toList(),
        focusPackage: focusPackage,
      );
});

/// Live progress while a delegated AnkiDroid study session is running.
final delegatedSessionProgressProvider =
    StateProvider<DelegatedSessionProgress?>((ref) => null);

// Support prompt --------------------------------------------------------------

final supportPromptServiceProvider = Provider<SupportPromptService>((ref) {
  return SupportPromptService();
});

final appLaunchCountProvider = StateProvider<int>((ref) => 0);

final supportPromptVisibleProvider = StateProvider<bool>((ref) => false);
