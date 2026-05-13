import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../services/ankidroid_service.dart';
import '../services/app_blocker_service.dart';
import '../services/apps_service.dart';
import '../services/audio_service.dart';
import '../services/permission_service.dart';
import '../services/study_scope_service.dart';

// Database -------------------------------------------------------------------

final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('Database must be overridden in main.dart');
});

// Services -------------------------------------------------------------------

final appBlockerServiceProvider = Provider<AppBlockerService>((ref) {
  throw UnimplementedError('AppBlockerService must be overridden in main.dart');
});

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

final installedAppsProvider = FutureProvider<List<InstalledApp>>((ref) async {
  return ref.read(appsServiceProvider).listAppsWithUsage();
});

final audioServiceProvider = Provider<AudioService>((ref) {
  final svc = AudioService();
  ref.onDispose(svc.dispose);
  return svc;
});

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

/// True when the user has granted SAF access to the AnkiDroid media folder
/// so card images / audio can resolve. Invalidate after picking the folder
/// or after revoking access.
final ankiDroidMediaAccessProvider = FutureProvider<bool>((ref) async {
  return ref.watch(ankiDroidServiceProvider).hasMediaAccess();
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

final activeSessionsProvider = StreamProvider<List<UnlockSession>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchActiveSessions();
});

/// Live daily stats for a given YYYY-MM-DD date.
final dailyStatsProvider =
    StreamProvider.family<DailyStat?, String>((ref, date) {
  final db = ref.watch(databaseProvider);
  return db.watchDailyStat(date);
});
