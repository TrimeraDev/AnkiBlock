import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';

import '../database/database.dart';

class GateRequest {
  final String packageName;
  final String appName;
  GateRequest(this.packageName, this.appName);
}

/// Today's pickups and screen time for blocked apps (from UsageStats).
class TodayBlockedUsage {
  final int totalPickups;
  final Duration totalScreenTime;
  final int focusPickups;
  final Duration focusScreenTime;

  const TodayBlockedUsage({
    required this.totalPickups,
    required this.totalScreenTime,
    required this.focusPickups,
    required this.focusScreenTime,
  });

  static const zero = TodayBlockedUsage(
    totalPickups: 0,
    totalScreenTime: Duration.zero,
    focusPickups: 0,
    focusScreenTime: Duration.zero,
  );
}

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

/// Common social / distracting apps. Used to auto-select on first scan.
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

  const DelegatedSessionProgress({
    required this.completed,
    required this.target,
  });
}

class NativeDailyGoalState {
  final String studyDayKey;
  final int dailyGoal;
  final int cardsReviewed;

  const NativeDailyGoalState({
    required this.studyDayKey,
    required this.dailyGoal,
    required this.cardsReviewed,
  });
}

class AppsService {
  static const _channel = MethodChannel('com.ankiblock/permissions');

  AppsService() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  final _gateController = StreamController<GateRequest>.broadcast();
  Stream<GateRequest> get gateRequests => _gateController.stream;

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
    if (call.method == 'openGate') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      _gateController.add(GateRequest(
        args['packageName'] as String? ?? '',
        args['appName'] as String? ?? '',
      ));
    } else if (call.method == 'onDelegatedProgress') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final completed = (args['completed'] as num?)?.toInt() ?? 0;
      final target = (args['target'] as num?)?.toInt() ?? 0;
      _delegatedProgressController.add(
        DelegatedSessionProgress(completed: completed, target: target),
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

  Future<void> startAppMonitor() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('startAppMonitor');
  }

  Future<void> stopAppMonitor() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('stopAppMonitor');
  }

  Future<void> grantTempUnlock(String packageName) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('grantTempUnlock', {
      'packageName': packageName,
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
    if (!Platform.isAndroid) {
      return const NativeDailyGoalState(
        studyDayKey: '',
        dailyGoal: 0,
        cardsReviewed: 0,
      );
    }
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getDailyGoalState',
    );
    if (raw == null) {
      return const NativeDailyGoalState(
        studyDayKey: '',
        dailyGoal: 0,
        cardsReviewed: 0,
      );
    }
    return NativeDailyGoalState(
      studyDayKey: raw['studyDayKey'] as String? ?? '',
      dailyGoal: (raw['dailyGoal'] as num?)?.toInt() ?? 0,
      cardsReviewed: (raw['cardsReviewed'] as num?)?.toInt() ?? 0,
    );
  }

  /// Starts a delegated study session tracked by [AppMonitorService] while the
  /// user reviews in AnkiDroid.
  Future<void> startDelegatedSession({
    required String packageName,
    required String appName,
    required int deckId,
    required List<int> deckIds,
    required int target,
    required int baseline,
  }) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('startDelegatedSession', {
      'packageName': packageName,
      'appName': appName,
      'deckId': deckId,
      'deckIds': deckIds,
      'target': target,
      'baseline': baseline,
    });
  }

  Future<void> cancelDelegatedSession() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('cancelDelegatedSession');
  }

  Future<bool> launchApp(String packageName) async {
    if (!Platform.isAndroid) return false;
    final ok = await _channel.invokeMethod<bool>('launchApp', {
      'packageName': packageName,
    });
    return ok ?? false;
  }

  Future<GateRequest?> consumePendingGate() async {
    if (!Platform.isAndroid) return null;
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'consumePendingGate',
    );
    if (raw == null) return null;
    return GateRequest(
      raw['packageName'] as String? ?? '',
      raw['appName'] as String? ?? '',
    );
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

  /// Pickups and screen time today for [packages], with optional [focusPackage].
  Future<TodayBlockedUsage> getTodayBlockedUsage({
    required List<String> packages,
    String? focusPackage,
  }) async {
    if (!Platform.isAndroid || packages.isEmpty) {
      return TodayBlockedUsage.zero;
    }
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getTodayBlockedUsage',
      {
        'packages': packages,
        if (focusPackage != null) 'focusPackage': focusPackage,
      },
    );
    if (raw == null) return TodayBlockedUsage.zero;
    return TodayBlockedUsage(
      totalPickups: (raw['totalPickups'] as num?)?.toInt() ?? 0,
      totalScreenTime: Duration(
        milliseconds: (raw['totalScreenTimeMs'] as num?)?.toInt() ?? 0,
      ),
      focusPickups: (raw['focusPickups'] as num?)?.toInt() ?? 0,
      focusScreenTime: Duration(
        milliseconds: (raw['focusScreenTimeMs'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  Future<List<InstalledApp>> listAppsWithUsage({bool thisWeek = true}) async {
    final apps = await listInstalledApps();
    final usage = await getUsageStats(thisWeek: thisWeek);
    return apps
        .map((a) => a.copyWith(usage: usage[a.packageName] ?? Duration.zero))
        .toList();
  }
}
