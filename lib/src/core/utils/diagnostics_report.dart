import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database.dart';
import '../di/providers.dart';
import '../services/ankidroid_service.dart';
import '../services/permission_service.dart';
import '../services/study_scope_service.dart';
import '../utils/study_day.dart';

/// SharedPreferences key for the last Flutter framework error (see main.dart).
const kLastCrashKey = 'ankiblock_last_crash';

/// Inputs gathered from Flutter + native for the bug-report panel.
class DiagnosticsInputs {
  const DiagnosticsInputs({
    required this.generatedAt,
    required this.native,
    required this.protection,
    required this.rule,
    required this.blockedAppCount,
    required this.activeBlockedCount,
    required this.scope,
    required this.deckCount,
    required this.scopedDeckCount,
    required this.ankiStatus,
    required this.counts,
    required this.todayStats,
    required this.lastCrash,
    required this.dbSchemaVersion,
  });

  final DateTime generatedAt;
  final Map<String, dynamic> native;
  final ProtectionStatus protection;
  final BlockRule? rule;
  final int blockedAppCount;
  final int activeBlockedCount;
  final StudyScope scope;
  final int deckCount;
  final int scopedDeckCount;
  final AnkiDroidStatus ankiStatus;
  final AnkiDroidCounts counts;
  final DailyStat? todayStats;
  final String? lastCrash;
  final int dbSchemaVersion;
}

Future<DiagnosticsInputs> gatherDiagnosticsInputs(WidgetRef ref) async {
  final db = ref.read(databaseProvider);
  final native = await ref.read(appsServiceProvider).getGateDiagnostics();
  final protection = await ref.read(permissionServiceProvider).getProtectionStatus();
  final rule = await db.getBlockRule();
  final blocked = await db.watchAllBlockedApps().first;
  final activeBlocked =
      blocked.where((a) => a.isBlocked).length;
  final scope = await ref.read(studyScopeServiceProvider).load();
  final ankiStatus = await ref.read(ankiDroidServiceProvider).getStatus();
  AnkiDroidCounts counts = AnkiDroidCounts.zero;
  int deckCount = 0;
  int scopedDeckCount = 0;
  if (ankiStatus.isReady) {
    final decks = await ref.read(ankiDroidServiceProvider).listDecks();
    deckCount = decks.length;
    final scopedIds = scope.filterDeckIds(decks.map((d) => d.id));
    scopedDeckCount = scopedIds.length;
    counts = await ref.read(ankiDroidServiceProvider).getCountsForScope(scope);
  }
  final todayStats = await db.getDailyStat(studyDayKey());
  final prefs = await SharedPreferences.getInstance();
  final lastCrash = prefs.getString(kLastCrashKey);

  return DiagnosticsInputs(
    generatedAt: DateTime.now(),
    native: native,
    protection: protection,
    rule: rule,
    blockedAppCount: blocked.length,
    activeBlockedCount: activeBlocked,
    scope: scope,
    deckCount: deckCount,
    scopedDeckCount: scopedDeckCount,
    ankiStatus: ankiStatus,
    counts: counts,
    todayStats: todayStats,
    lastCrash: lastCrash,
    dbSchemaVersion: db.schemaVersion,
  );
}

String formatDiagnosticsReport(DiagnosticsInputs input) {
  final d = input.native;
  final rule = input.rule;
  final today = input.todayStats;

  String agoMs(dynamic ms) {
    final v = (ms as num?)?.toInt() ?? 0;
    if (v <= 0) return 'never';
    final diff = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(v),
    );
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String agoDuration(dynamic ms) {
    final v = (ms as num?)?.toInt() ?? 0;
    if (v <= 0) return 'unknown';
    if (v < 60000) return '${(v / 1000).round()}s';
    return '${(v / 60000).round()} min';
  }

  String yesNo(bool v) => v ? 'yes' : 'no';

  String scopeSummary(StudyScope scope, int deckCount, int scopedCount) {
    switch (scope.mode) {
      case StudyScopeMode.all:
        return 'all decks ($deckCount)';
      case StudyScopeMode.multi:
        if (scope.disabledDeckIds.isEmpty) {
          return 'multi — all enabled ($deckCount decks)';
        }
        return 'multi — $scopedCount of $deckCount decks enabled';
      case StudyScopeMode.single:
        final id = scope.activeDeckId;
        if (id == null) return 'single — no deck selected';
        return 'single — deck $id';
    }
  }

  final lines = <String>[
    '=== AnkiBlock Diagnostics ===',
    'Generated: ${input.generatedAt.toIso8601String()}',
    '',
    '--- App ---',
    'Version: ${d['appVersion'] ?? '?'} (${d['appBuild'] ?? '?'})',
    'DB schema: ${input.dbSchemaVersion}',
    '',
    '--- Device ---',
    'OEM key: ${d['oemManufacturer'] ?? input.protection.oemManufacturer}',
    'Manufacturer: ${d['deviceManufacturer'] ?? '?'}',
    'Model: ${d['deviceModel'] ?? '?'}',
    'Android SDK: ${d['androidSdk'] ?? '?'}',
    '',
    '--- Permissions ---',
    'Accessibility: ${yesNo(d['accessibility'] == true || input.protection.accessibility)}',
    'Usage access: ${yesNo(d['usage'] == true || input.protection.usage)}',
    'Battery unrestricted: ${yesNo(d['batteryUnrestricted'] == true || input.protection.batteryUnrestricted)}',
    'Protection active: ${yesNo(d['protectionActive'] == true || input.protection.protectionActive)}',
    if (!input.protection.protectionActive)
      '  (anythingToBlock=${input.protection.hasAnythingToBlock}, '
          'apps=${input.protection.hasBlockedApps}, '
          'enabled=${input.protection.blockingEnabled}, '
          'a11y=${input.protection.accessibility}, '
          'engine=${input.protection.monitorRunning})',
    '',
    '--- Blocking config (Flutter DB) ---',
    'Rule enabled: ${yesNo(rule?.isEnabled ?? true)}',
    'Study mode: ${rule?.studyMode ?? 'dueCards'}',
    'Cards per unlock: ${rule?.cardsRequired ?? 10}',
    'Unlock duration: ${rule?.unlockDurationMinutes ?? 15} min',
    'Daily goal: ${rule?.dailyCardsGoal ?? 30}',
    'Bypass: ${yesNo(rule?.bypassEnabled ?? true)}, '
        '${rule?.bypassSeconds ?? 60}s, cap ${rule?.bypassDailyCap ?? 3}/day',
    'Settings protection: ${rule?.settingsProtection ?? 'off'}',
    'Settings password: ${yesNo(rule?.settingsPasswordEnabled ?? false)}',
    'Blocked apps (DB): ${input.activeBlockedCount} active / '
        '${input.blockedAppCount} total',
    '',
    '--- Blocking config (native sync) ---',
    'Native enabled: ${yesNo(d['blockingEnabled'] == true)}',
    'Native blocked count: ${d['blockedAppCount'] ?? '?'}',
    'Website rules: ${d['websiteRuleCount'] ?? 0}',
    'Block unsupported browsers: ${yesNo(d['blockUnsupportedBrowsers'] == true)}',
    'Supported browsers installed: ${d['supportedBrowsersInstalled'] ?? '?'}',
    'Last URL host: ${(d['lastUrlHost'] as String?)?.isNotEmpty == true ? d['lastUrlHost'] : '—'}',
    'Last URL check: ${agoMs(d['lastUrlCheckMs'])}',
    'Unlock window: ${((d['unlockRemainingMs'] as num?)?.toInt() ?? 0) > 0 ? '${agoDuration(d['unlockRemainingMs'])} left' : 'locked'}',
    'Study mode: ${d['studyMode'] ?? '?'}',
    'Unlock goal: ${d['unlockGoalCards'] ?? '?'} cards',
    'Unlock duration: ${d['unlockDurationMin'] ?? '?'} min',
    'Bypass: ${yesNo(d['bypassEnabled'] == true)}, ${d['bypassSeconds'] ?? '?'}s, '
        'cap ${d['bypassDailyCap'] ?? '?'}/day',
    'Study day: ${d['studyDayKey'] ?? studyDayKey()}',
    'Daily progress: ${d['dailyReviewed'] ?? 0}/${d['dailyGoal'] ?? rule?.dailyCardsGoal ?? 30}',
    'Study bout cards: ${d['studyBoutCount'] ?? 0}',
    'Native today: attempts ${d['blockedAttempts'] ?? 0}, '
        'bypasses ${d['bypassesUsed'] ?? 0}, unlocks ${d['unlocksEarned'] ?? 0}',
    '',
    '--- Study scope ---',
    scopeSummary(input.scope, input.deckCount, input.scopedDeckCount),
    '',
    '--- AnkiDroid ---',
    'Installed: ${yesNo(input.ankiStatus.installed)}',
    'API permission: ${yesNo(input.ankiStatus.permissionGranted)}',
    if (input.ankiStatus.isReady)
      'Due in scope: L=${input.counts.learnCount} '
          'R=${input.counts.reviewCount} N=${input.counts.newCount}',
    '',
    '--- Accessibility service ---',
    'Should run: ${yesNo(d['shouldStartMonitor'] == true)}',
    'Enabled in Settings: ${yesNo(d['accessibilityEnabled'] == true)}',
    'Service connected: ${yesNo(d['engineConnected'] == true)}',
    'Service healthy: ${yesNo(d['monitorRunning'] == true)}',
    'Last event: ${agoDuration(d['lastEventAgeMs'])} ago',
    'Service (re)connects: ${d['monitorRestarts'] ?? 0}',
    '',
    '--- Study gate (accessibility overlay) ---',
    'Showing now: ${yesNo(d['gateShowing'] == true)}',
    'Last shown: ${agoMs(d['lastGateShownMs'])}',
    'Total shown: ${d['gateShownCount'] ?? 0}',
    if (d['delegatedSessionActive'] == true)
      'Delegated session: ${d['delegatedCompleted']}/${d['delegatedTarget']} '
          'for ${d['delegatedPackage']}'
    else
      'Delegated session: none',
    '',
    '--- Today (${studyDayKey()}) ---',
    'Cards reviewed: ${today?.cardsReviewed ?? 0}',
    'Unlocks earned: ${today?.unlocksEarned ?? 0}',
    'Blocked attempts: ${today?.blockedAttempts ?? 0}',
    'Bypasses used: ${today?.bypassesUsed ?? 0}',
    '',
    '--- Errors ---',
    'Native error count: ${d['errorCount'] ?? 0}',
    if ((d['lastError'] as String?)?.isNotEmpty == true)
      'Last native error: ${d['lastError']}',
    if (input.lastCrash != null && input.lastCrash!.isNotEmpty)
      'Last Flutter error: ${input.lastCrash!.replaceAll('\n', ' | ')}',
  ];

  return lines.join('\n');
}
