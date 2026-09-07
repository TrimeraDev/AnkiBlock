import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';

import '../database/database.dart';

class InstalledApp {
  final String packageName;
  final String appName;
  final bool isSystem;
  final Uint8List? icon;
  final Duration usage;

  InstalledApp({
    required this.packageName,
    required this.appName,
    required this.isSystem,
    this.icon,
    this.usage = Duration.zero,
  });

  InstalledApp copyWith({Duration? usage}) => InstalledApp(
        packageName: packageName,
        appName: appName,
        isSystem: isSystem,
        icon: icon,
        usage: usage ?? this.usage,
      );
}

class BrowserEntry {
  const BrowserEntry({required this.packageName, required this.appName});

  final String packageName;
  final String appName;

  factory BrowserEntry.fromMap(Map<dynamic, dynamic> map) {
    return BrowserEntry(
      packageName: map['packageName']?.toString() ?? '',
      appName: map['appName']?.toString() ?? '',
    );
  }
}

class BrowserCompatibility {
  const BrowserCompatibility({
    required this.supportedInstalled,
    required this.unsupportedInstalled,
    required this.supportedCatalog,
  });

  final List<BrowserEntry> supportedInstalled;
  final List<BrowserEntry> unsupportedInstalled;
  final List<String> supportedCatalog;

  static const empty = BrowserCompatibility(
    supportedInstalled: [],
    unsupportedInstalled: [],
    supportedCatalog: [],
  );

  factory BrowserCompatibility.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return empty;
    return BrowserCompatibility(
      supportedInstalled: _entries(map['supportedInstalled']),
      unsupportedInstalled: _entries(map['unsupportedInstalled']),
      supportedCatalog: (map['supportedCatalog'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  static List<BrowserEntry> _entries(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => BrowserEntry.fromMap(m))
        .where((e) => e.packageName.isNotEmpty)
        .toList();
  }
}

extension InstalledAppCacheX on InstalledApp {
  InstalledAppsCacheCompanion toCacheCompanion() => InstalledAppsCacheCompanion(
        packageName: Value(packageName),
        displayName: Value(appName),
        isSystem: Value(isSystem),
        icon: Value(icon),
        usageMs: Value(usage.inMilliseconds),
        cachedAt: Value(DateTime.now().millisecondsSinceEpoch),
      );
}

extension CachedInstalledAppX on CachedInstalledApp {
  InstalledApp toInstalledApp() => InstalledApp(
        packageName: packageName,
        appName: displayName,
        isSystem: isSystem,
        icon: icon,
        usage: Duration(milliseconds: usageMs),
      );
}

/// Common social / distracting apps suggested for blocking (onboarding + Block).
const Set<String> kSuggestedBlockPackages = {
  // Social
  'com.zhiliaoapp.musically', // TikTok (intl)
  'com.ss.android.ugc.trill', // TikTok (other regions)
  'com.instagram.android',
  'com.facebook.katana',
  'com.facebook.lite',
  'com.snapchat.android',
  'com.twitter.android',
  'com.x.android',
  'com.reddit.frontpage',
  'com.pinterest',
  'com.linkedin.android',
  'com.discord',
  // Video
  'com.google.android.youtube',
  'com.netflix.mediaclient',
  'com.amazon.avod.thirdpartyclient',
  'com.disney.disneyplus',
  // Messaging that often becomes timesink
  'org.telegram.messenger',
  'com.whatsapp',
  // Games (popular timesinks)
  'com.king.candycrushsaga',
  'com.supercell.clashofclans',
};

/// Voluntary study from the home screen — native side tracks cards without unlocking an app.
const String kPracticeStudyPackage = '__ankiblock_practice__';

class DelegatedSessionProgress {
  final int completed;
  final int target;

  /// Blocked app package, or [kPracticeStudyPackage] for home practice.
  final String packageName;

  const DelegatedSessionProgress({
    required this.completed,
    required this.target,
    this.packageName = '',
  });

  bool get isPractice => packageName == kPracticeStudyPackage;

  bool isForPackage(String pkg) =>
      packageName.isNotEmpty && packageName == pkg;
}

/// Result of starting a native delegated (practice) session.
class DelegatedSessionStartResult {
  /// Cards already credited from a recent study bout.
  final int seeded;
  final int target;

  const DelegatedSessionStartResult({
    required this.seeded,
    required this.target,
  });
}

/// Snapshot of an in-progress native unlock session.
class DelegatedSessionState {
  final String packageName;
  final int completed;
  final int target;
  final int seeded;

  const DelegatedSessionState({
    required this.packageName,
    required this.completed,
    required this.target,
    required this.seeded,
  });
}

/// Native mirror of today's study state plus the gate counters native owns.
class NativeDailyGoalState {
  final String studyDayKey;
  final int dailyGoal;
  final int cardsReviewed;
  final int blockedAttempts;
  final int bypassesUsed;
  final int unlocksEarned;

  const NativeDailyGoalState({
    required this.studyDayKey,
    required this.dailyGoal,
    required this.cardsReviewed,
    this.blockedAttempts = 0,
    this.bypassesUsed = 0,
    this.unlocksEarned = 0,
  });

  static const empty = NativeDailyGoalState(
    studyDayKey: '',
    dailyGoal: 0,
    cardsReviewed: 0,
  );
}

class AppsService {
  static const _channel = MethodChannel('com.ankiblock/permissions');

  AppsService() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  final _delegatedUnlockController = StreamController<int>.broadcast();
  Stream<int> get delegatedUnlocks => _delegatedUnlockController.stream;

  final _delegatedProgressController =
      StreamController<DelegatedSessionProgress>.broadcast();
  Stream<DelegatedSessionProgress> get delegatedProgress =>
      _delegatedProgressController.stream;

  final _passiveStudyController = StreamController<int>.broadcast();
  /// Cards credited from organic AnkiDroid study (not via AnkiBlock session).
  Stream<int> get passiveStudyProgress => _passiveStudyController.stream;

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onDelegatedProgress') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final completed = (args['completed'] as num?)?.toInt() ?? 0;
      final target = (args['target'] as num?)?.toInt() ?? 0;
      final packageName = args['packageName'] as String? ?? '';
      _delegatedProgressController.add(
        DelegatedSessionProgress(
          completed: completed,
          target: target,
          packageName: packageName,
        ),
      );
    } else if (call.method == 'onDelegatedUnlock') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final cards = (args['cardsCompleted'] as num?)?.toInt() ?? 0;
      if (cards > 0) _delegatedUnlockController.add(cards);
    } else if (call.method == 'onPassiveStudyProgress') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final delta = (args['delta'] as num?)?.toInt() ?? 0;
      if (delta > 0) _passiveStudyController.add(delta);
    }
    return null;
  }

  Future<void> setBlockedPackages(
      List<({String pkg, String name})> apps) async {
    if (!Platform.isAndroid) return;
    final packages = apps.map((a) => a.pkg).toList();
    final names = {for (final a in apps) a.pkg: a.name};
    await _channel.invokeMethod('setBlockedPackages', {
      'packages': packages,
      'names': names,
    });
  }

  Future<void> setBlockedWebsites({
    required List<({String pattern, bool isRegex, String label})> rules,
    required bool blockUnsupportedBrowsers,
  }) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('setBlockedWebsites', {
      'rules': [
        for (final r in rules)
          {
            'pattern': r.pattern,
            'isRegex': r.isRegex,
            'label': r.label,
          },
      ],
      'blockUnsupportedBrowsers': blockUnsupportedBrowsers,
    });
  }

  Future<BrowserCompatibility> getBrowserCompatibility() async {
    if (!Platform.isAndroid) return BrowserCompatibility.empty;
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getSupportedBrowsers',
    );
    return BrowserCompatibility.fromMap(raw);
  }

  Future<void> syncBlockRuleSettings({
    required int unlockDurationMinutes,
    required int bypassSeconds,
    required bool isEnabled,
    required String studyMode,
    required int unlockGoal,
    required bool bypassEnabled,
    required int bypassDailyCap,
  }) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('syncBlockRuleSettings', {
      'unlockDurationMinutes': unlockDurationMinutes,
      'bypassSeconds': bypassSeconds,
      'isEnabled': isEnabled,
      'studyMode': studyMode,
      'unlockGoal': unlockGoal,
      'bypassEnabled': bypassEnabled,
      'bypassDailyCap': bypassDailyCap,
    });
  }

  /// Syncs today's study progress so native blocking can skip the gate when
  /// the daily goal is complete.
  Future<void> syncDailyGoalState({
    required String studyDayKey,
    required int dailyGoal,
    required int cardsReviewed,
  }) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('syncDailyGoalState', {
      'studyDayKey': studyDayKey,
      'dailyGoal': dailyGoal,
      'cardsReviewed': cardsReviewed,
    });
  }

  Future<void> syncStudyScope({required List<int> deckIds}) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('syncStudyScope', {
      'deckIds': deckIds,
    });
  }

  Future<NativeDailyGoalState> getDailyGoalState() async {
    if (!Platform.isAndroid) return NativeDailyGoalState.empty;
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getDailyGoalState',
    );
    if (raw == null) return NativeDailyGoalState.empty;
    int n(String key) => (raw[key] as num?)?.toInt() ?? 0;
    return NativeDailyGoalState(
      studyDayKey: raw['studyDayKey'] as String? ?? '',
      dailyGoal: n('dailyGoal'),
      cardsReviewed: n('cardsReviewed'),
      blockedAttempts: n('blockedAttempts'),
      bypassesUsed: n('bypassesUsed'),
      unlocksEarned: n('unlocksEarned'),
    );
  }

  /// Starts a practice session tracked natively while the user reviews in
  /// AnkiDroid. Progress is counted from schedule card keys / reps only.
  Future<DelegatedSessionStartResult> startDelegatedSession({
    required String packageName,
    required String appName,
    required int deckId,
    required List<int> deckIds,
    required int target,
  }) async {
    if (!Platform.isAndroid) {
      return DelegatedSessionStartResult(seeded: 0, target: target);
    }
    final raw = await _channel.invokeMethod<dynamic>('startDelegatedSession', {
      'packageName': packageName,
      'appName': appName,
      'deckId': deckId,
      'deckIds': deckIds,
      'target': target,
    });
    if (raw is Map) {
      return DelegatedSessionStartResult(
        seeded: (raw['seeded'] as num?)?.toInt() ?? 0,
        target: (raw['target'] as num?)?.toInt() ?? target,
      );
    }
    return DelegatedSessionStartResult(seeded: 0, target: target);
  }

  /// Restores in-progress unlock session progress after Flutter state loss.
  Future<DelegatedSessionState?> getDelegatedSessionState() async {
    if (!Platform.isAndroid) return null;
    final raw =
        await _channel.invokeMethod<dynamic>('getDelegatedSessionState');
    if (raw is! Map) return null;
    final target = (raw['target'] as num?)?.toInt() ?? 0;
    if (target <= 0) return null;
    final pkg = raw['packageName'] as String? ?? '';
    if (pkg.isEmpty) return null;
    return DelegatedSessionState(
      packageName: pkg,
      completed: (raw['completed'] as num?)?.toInt() ?? 0,
      target: target,
      seeded: (raw['seeded'] as num?)?.toInt() ?? 0,
    );
  }

  /// Health snapshot for the permissions diagnostics panel.
  Future<Map<String, dynamic>> getGateDiagnostics() async {
    if (!Platform.isAndroid) return const {};
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getGateDiagnostics',
      );
      if (raw == null) return const {};
      return Map<String, dynamic>.from(raw);
    } catch (_) {
      return const {};
    }
  }

  Future<List<InstalledApp>> listInstalledApps({bool icons = true}) async {
    if (!Platform.isAndroid) return const [];
    final raw = await _channel.invokeMethod<List<dynamic>>(
      'getInstalledApps',
      {'icons': icons},
    );
    if (raw == null) return const [];
    return raw.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return InstalledApp(
        packageName: m['packageName'] as String,
        appName: m['appName'] as String,
        isSystem: (m['isSystem'] as bool?) ?? false,
        icon: m['icon'] is Uint8List
            ? m['icon'] as Uint8List
            : (m['icon'] is List
                ? Uint8List.fromList(List<int>.from(m['icon']))
                : null),
      );
    }).toList();
  }

  Future<Map<String, Duration>> getUsageStats({
    int days = 7,
    bool thisWeek = false,
  }) async {
    if (!Platform.isAndroid) return const {};
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getUsageStats',
      {
        'days': days,
        'thisWeek': thisWeek,
      },
    );
    if (raw == null) return const {};
    final out = <String, Duration>{};
    raw.forEach((k, v) {
      final ms = (v as num).toInt();
      out[k as String] = Duration(milliseconds: ms);
    });
    return out;
  }

  Future<List<InstalledApp>> listAppsWithUsage({bool thisWeek = true}) async {
    final apps = await listInstalledApps();
    final usage = await getUsageStats(thisWeek: thisWeek);
    return apps
        .map((a) => a.copyWith(usage: usage[a.packageName] ?? Duration.zero))
        .toList();
  }
}
