import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'database.g.dart';

// ============ TABLES ============
//
// AnkiBlock no longer stores cards, notes, decks, models, media, or review
// logs — AnkiDroid is the source of truth for all of those (we read via the
// `FlashCardsContract` ContentProvider).
//
// What remains is purely AnkiBlock-specific: the app-blocker, the unlock
// rule that governs the study gate, and a small per-day stats ledger.

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
  IntColumn get updatedAt =>
      integer().withDefault(Constant(DateTime.now().millisecondsSinceEpoch))();

  @override
  Set<Column> get primaryKey => {id};
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

/// Snapshot of installed apps from the last successful native scan. Used so the
/// blocking screen can render immediately while a fresh scan runs.
@DataClassName('CachedInstalledApp')
class InstalledAppsCache extends Table {
  TextColumn get packageName => text()();
  TextColumn get displayName => text()();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  BlobColumn get icon => blob().nullable()();
  IntColumn get usageMs => integer().withDefault(const Constant(0))();
  IntColumn get cachedAt =>
      integer().withDefault(Constant(DateTime.now().millisecondsSinceEpoch))();

  @override
  Set<Column> get primaryKey => {packageName};
}

// ============ DATABASE ============

@DriftDatabase(tables: [
  BlockedApps,
  BlockRules,
  DailyStats,
  InstalledAppsCache,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase._internal(super.e);

  static Future<AppDatabase> open(String path) async {
    final file = File(path);
    return AppDatabase._internal(NativeDatabase(file));
  }

  @override
  int get schemaVersion => 5;

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
          if (from < 5) {
            await m.database
                .customStatement('DROP TABLE IF EXISTS unlock_sessions');
            await m.database.customStatement('''
              CREATE TABLE IF NOT EXISTS block_rules_new (
                id INTEGER NOT NULL PRIMARY KEY,
                cards_required INTEGER NOT NULL DEFAULT 3,
                unlock_duration_minutes INTEGER NOT NULL DEFAULT 10,
                is_enabled INTEGER NOT NULL DEFAULT 1 CHECK (is_enabled IN (0, 1)),
                updated_at INTEGER NOT NULL DEFAULT 0
              )
            ''');
            await m.database.customStatement('''
              INSERT OR IGNORE INTO block_rules_new
                (id, cards_required, unlock_duration_minutes, is_enabled, updated_at)
              SELECT id, cards_required, unlock_duration_minutes, is_enabled, updated_at
              FROM block_rules
            ''');
            await m.database.customStatement('DROP TABLE block_rules');
            await m.database
                .customStatement('ALTER TABLE block_rules_new RENAME TO block_rules');
          }
          if (from < 4) {
            await m.createTable(installedAppsCache);
          }
          if (from < 3) {
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

  // ============ INSTALLED APPS CACHE ============

  Future<List<CachedInstalledApp>> getCachedInstalledApps() =>
      select(installedAppsCache).get();

  Future<void> replaceInstalledAppsCache(
    List<InstalledAppsCacheCompanion> rows,
  ) async {
    await transaction(() async {
      await delete(installedAppsCache).go();
      if (rows.isNotEmpty) {
        await batch((b) => b.insertAll(installedAppsCache, rows));
      }
    });
  }

  // ============ BLOCK RULE QUERIES ============

  Stream<BlockRule?> watchBlockRule() =>
      (select(blockRules)..where((r) => r.id.equals(1))).watchSingleOrNull();

  Future<BlockRule?> getBlockRule() =>
      (select(blockRules)..where((r) => r.id.equals(1))).getSingleOrNull();

  Future updateBlockRule(BlockRulesCompanion rule) =>
      update(blockRules).write(rule);

  // ============ DAILY STATS QUERIES ============

  Future<DailyStat?> getDailyStat(String date) =>
      (select(dailyStats)..where((d) => d.date.equals(date))).getSingleOrNull();

  Stream<DailyStat?> watchDailyStat(String date) =>
      (select(dailyStats)..where((d) => d.date.equals(date)))
          .watchSingleOrNull();

  Future insertOrUpdateDailyStat(DailyStatsCompanion stat) =>
      into(dailyStats).insertOnConflictUpdate(stat);

  Future incrementCardsReviewed(String date) async {
    await incrementCardsReviewedBy(date, 1);
  }

  Future incrementCardsReviewedBy(String date, int count) async {
    if (count <= 0) return;
    final stat = await getDailyStat(date);
    if (stat == null) {
      await insertOrUpdateDailyStat(
        DailyStatsCompanion(
          date: Value(date),
          cardsReviewed: Value(count),
        ),
      );
    } else {
      await (update(dailyStats)..where((d) => d.date.equals(date))).write(
          DailyStatsCompanion(cardsReviewed: Value(stat.cardsReviewed + count)));
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
