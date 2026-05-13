import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'database.g.dart';

/// State of an unlock window earned by a study session.
enum UnlockStatus { active, completed, expired, cancelled }

// ============ TABLES ============
//
// AnkiBlock no longer stores cards, notes, decks, models, media, or review
// logs — AnkiDroid is the source of truth for all of those (we read via the
// `FlashCardsContract` ContentProvider).
//
// What remains is purely AnkiBlock-specific: the app-blocker, the unlock
// rule that governs the study gate, in-flight unlock sessions, and a small
// per-day stats ledger used by the unlock counter / Today screen.

@DataClassName('BlockedApp')
class BlockedApps extends Table {
  TextColumn get packageName => text()();
  TextColumn get displayName => text()();
  BoolColumn get isBlocked => boolean().withDefault(const Constant(true))();
  IntColumn get addedAt =>
      integer().withDefault(Constant(DateTime.now().millisecondsSinceEpoch))();

  @override
  Set<Column> get primaryKey => {packageName};
}

@DataClassName('BlockRule')
class BlockRules extends Table {
  IntColumn get id => integer()();
  IntColumn get cardsRequired => integer().withDefault(const Constant(3))();
  IntColumn get unlockDurationMinutes =>
      integer().withDefault(const Constant(10))();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();
  IntColumn get dailyNewCardsLimit =>
      integer().withDefault(const Constant(20))();
  IntColumn get dailyReviewsLimit =>
      integer().withDefault(const Constant(200))();
  IntColumn get updatedAt =>
      integer().withDefault(Constant(DateTime.now().millisecondsSinceEpoch))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('UnlockSession')
class UnlockSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get packageName => text()();
  IntColumn get startedAt =>
      integer().withDefault(Constant(DateTime.now().millisecondsSinceEpoch))();
  IntColumn get expiresAt => integer()();
  IntColumn get requiredCards => integer()();
  IntColumn get completedCards => integer().withDefault(const Constant(0))();
  IntColumn get status =>
      intEnum<UnlockStatus>().withDefault(const Constant(0))(); // 0 = active
}

@DataClassName('DailyStat')
class DailyStats extends Table {
  TextColumn get date => text()(); // YYYY-MM-DD format
  IntColumn get cardsReviewed => integer().withDefault(const Constant(0))();
  IntColumn get unlocksEarned => integer().withDefault(const Constant(0))();
  IntColumn get blockedAttempts => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {date};
}

// ============ DATABASE ============

@DriftDatabase(tables: [
  BlockedApps,
  BlockRules,
  UnlockSessions,
  DailyStats,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase._internal(super.e);

  static Future<AppDatabase> open(String path) async {
    final file = File(path);
    return AppDatabase._internal(NativeDatabase(file));
  }

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await into(blockRules).insert(
            BlockRulesCompanion.insert(id: const Value(1)),
            mode: InsertMode.insertOrIgnore,
          );
        },
        onUpgrade: (m, from, to) async {
          if (from < 3) {
            // Pre-AnkiDroid schema. Drop every legacy table; AnkiDroid is now
            // the source of truth for cards/notes/decks/etc. The blocker
            // tables below are recreated only if they don't already exist.
            for (final t in const [
              'cards',
              'notes',
              'medias',
              'review_logs',
              'models',
              'decks',
            ]) {
              await m.database
                  .customStatement('DROP TABLE IF EXISTS $t');
            }
            await m.createAll();
            await into(blockRules).insert(
              BlockRulesCompanion.insert(id: const Value(1)),
              mode: InsertMode.insertOrIgnore,
            );
          }
        },
      );

  // ============ BLOCKED APP QUERIES ============

  Stream<List<BlockedApp>> watchAllBlockedApps() => select(blockedApps).watch();
  Stream<List<BlockedApp>> watchActiveBlockedApps() =>
      (select(blockedApps)..where((b) => b.isBlocked.equals(true))).watch();

  Future<BlockedApp?> getBlockedApp(String packageName) =>
      (select(blockedApps)..where((b) => b.packageName.equals(packageName)))
          .getSingleOrNull();

  Future insertBlockedApp(BlockedAppsCompanion app) =>
      into(blockedApps).insertOnConflictUpdate(app);

  Future setBlocked(String packageName, bool blocked) async {
    await (update(blockedApps)..where((b) => b.packageName.equals(packageName)))
        .write(BlockedAppsCompanion(isBlocked: Value(blocked)));
  }

  Future deleteBlockedApp(String packageName) async {
    await (delete(blockedApps)..where((b) => b.packageName.equals(packageName)))
        .go();
  }

  // ============ BLOCK RULE QUERIES ============

  Stream<BlockRule?> watchBlockRule() =>
      (select(blockRules)..where((r) => r.id.equals(1))).watchSingleOrNull();

  Future<BlockRule?> getBlockRule() =>
      (select(blockRules)..where((r) => r.id.equals(1))).getSingleOrNull();

  Future updateBlockRule(BlockRulesCompanion rule) =>
      update(blockRules).write(rule);

  // ============ UNLOCK SESSION QUERIES ============

  Stream<List<UnlockSession>> watchActiveSessions() => (select(unlockSessions)
        ..where((s) => s.status.equals(UnlockStatus.active.index)))
      .watch();

  Future<UnlockSession?> getActiveSessionForPackage(String packageName) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final query = select(unlockSessions)
      ..where((s) => s.packageName.equals(packageName))
      ..where((s) => s.status
          .isIn([UnlockStatus.active.index, UnlockStatus.completed.index]))
      ..where((s) => s.expiresAt.isBiggerThanValue(now))
      ..orderBy([
        (s) => OrderingTerm(expression: s.startedAt, mode: OrderingMode.desc)
      ])
      ..limit(1);
    return query.getSingleOrNull();
  }

  Future<int> insertUnlockSession(UnlockSessionsCompanion session) =>
      into(unlockSessions).insert(session);

  Future updateUnlockSession(UnlockSessionsCompanion session) =>
      update(unlockSessions).write(session);

  Future incrementCompletedCards(int sessionId) async {
    final session = await (select(unlockSessions)
          ..where((s) => s.id.equals(sessionId)))
        .getSingle();
    await (update(unlockSessions)..where((s) => s.id.equals(sessionId))).write(
        UnlockSessionsCompanion(
            completedCards: Value(session.completedCards + 1)));
  }

  Future expireOldSessions(int now) async {
    await (update(unlockSessions)
          ..where((s) => s.status.equals(UnlockStatus.active.index))
          ..where((s) => s.expiresAt.isSmallerOrEqualValue(now)))
        .write(const UnlockSessionsCompanion(
            status: Value(UnlockStatus.expired)));
  }

  // ============ DAILY STATS QUERIES ============

  Future<DailyStat?> getDailyStat(String date) =>
      (select(dailyStats)..where((d) => d.date.equals(date))).getSingleOrNull();

  Stream<DailyStat?> watchDailyStat(String date) =>
      (select(dailyStats)..where((d) => d.date.equals(date)))
          .watchSingleOrNull();

  Future insertOrUpdateDailyStat(DailyStatsCompanion stat) =>
      into(dailyStats).insertOnConflictUpdate(stat);

  Future incrementCardsReviewed(String date) async {
    final stat = await getDailyStat(date);
    if (stat == null) {
      await insertOrUpdateDailyStat(
        DailyStatsCompanion(
          date: Value(date),
          cardsReviewed: const Value(1),
        ),
      );
    } else {
      await (update(dailyStats)..where((d) => d.date.equals(date))).write(
          DailyStatsCompanion(cardsReviewed: Value(stat.cardsReviewed + 1)));
    }
  }

  Future incrementUnlocksEarned(String date) async {
    final stat = await getDailyStat(date);
    if (stat == null) {
      await insertOrUpdateDailyStat(
        DailyStatsCompanion(
          date: Value(date),
          unlocksEarned: const Value(1),
        ),
      );
    } else {
      await (update(dailyStats)..where((d) => d.date.equals(date))).write(
          DailyStatsCompanion(unlocksEarned: Value(stat.unlocksEarned + 1)));
    }
  }

  Future incrementBlockedAttempts(String date) async {
    final stat = await getDailyStat(date);
    if (stat == null) {
      await insertOrUpdateDailyStat(
        DailyStatsCompanion(
          date: Value(date),
          blockedAttempts: const Value(1),
        ),
      );
    } else {
      await (update(dailyStats)..where((d) => d.date.equals(date))).write(
          DailyStatsCompanion(
              blockedAttempts: Value(stat.blockedAttempts + 1)));
    }
  }
}
