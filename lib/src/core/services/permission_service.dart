import 'dart:io';

import 'package:flutter/services.dart';

class ProtectionStatus {
  const ProtectionStatus({
    required this.accessibility,
    required this.usage,
    required this.batteryUnrestricted,
    required this.monitorRunning,
    required this.hasBlockedApps,
    required this.blockingEnabled,
    required this.protectionActive,
    this.oemManufacturer = 'unknown',
  });

  final bool accessibility;
  final bool usage;
  final bool batteryUnrestricted;
  final bool monitorRunning;
  final bool hasBlockedApps;
  final bool blockingEnabled;
  final bool protectionActive;
  final String oemManufacturer;

  /// Accessibility is required for blocking. Usage is optional analytics.
  bool get permissionsComplete => accessibility;

  bool get needsAttention =>
      !permissionsComplete ||
      (hasBlockedApps && blockingEnabled && !protectionActive) ||
      !batteryUnrestricted;

  bool get needsOemAutostartHelp {
    const aggressive = {
      'huawei',
      'honor',
      'xiaomi',
      'samsung',
      'oppo',
      'oneplus',
      'vivo',
    };
    return aggressive.contains(oemManufacturer);
  }

  factory ProtectionStatus.fromMap(Map<dynamic, dynamic> map) {
    bool b(dynamic v) => v == true;
    return ProtectionStatus(
      accessibility: b(map['accessibility']),
      usage: b(map['usage']),
      batteryUnrestricted: b(map['batteryUnrestricted']),
      monitorRunning: b(map['monitorRunning']),
      hasBlockedApps: b(map['hasBlockedApps']),
      blockingEnabled: b(map['blockingEnabled']),
      protectionActive: b(map['protectionActive']),
      oemManufacturer: map['oemManufacturer'] as String? ?? 'unknown',
    );
  }
}

class PermissionService {
  static const _channel = MethodChannel('com.ankiblock/permissions');

  Future<bool> hasAccessibilityPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final result =
          await _channel.invokeMethod<bool>('hasAccessibilityPermission');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openAccessibilitySettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (_) {}
  }

  Future<bool> hasUsageAccessPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('hasUsageAccess');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openUsageAccessSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openUsageAccessSettings');
    } catch (_) {}
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _channel
          .invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestBatteryOptimizationExemption() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('requestBatteryOptimizationExemption');
    } catch (_) {}
  }

  Future<void> openBatterySettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openBatterySettings');
    } catch (_) {}
  }

  Future<ProtectionStatus> getProtectionStatus() async {
    if (!Platform.isAndroid) {
      return const ProtectionStatus(
        accessibility: true,
        usage: true,
        batteryUnrestricted: true,
        monitorRunning: true,
        hasBlockedApps: false,
        blockingEnabled: true,
        protectionActive: true,
      );
    }
    try {
      final result = await _channel.invokeMethod<Map>('getProtectionStatus');
      if (result == null) {
        return const ProtectionStatus(
          accessibility: false,
          usage: false,
          batteryUnrestricted: false,
          monitorRunning: false,
          hasBlockedApps: false,
          blockingEnabled: true,
          protectionActive: false,
        );
      }
      return ProtectionStatus.fromMap(result);
    } catch (_) {
      return const ProtectionStatus(
        accessibility: false,
        usage: false,
        batteryUnrestricted: false,
        monitorRunning: false,
        hasBlockedApps: false,
        blockingEnabled: true,
        protectionActive: false,
      );
    }
  }

  Future<bool> openOemAutostartSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('openOemAutostartSettings');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<String> getOemManufacturer() async {
    if (!Platform.isAndroid) return 'unknown';
    try {
      final m = await _channel.invokeMethod<String>('getOemManufacturer');
      return m ?? 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  /// Accessibility (+ optional usage for analytics).
  Future<({bool accessibility, bool usage})> getBlockingPermissions() async {
    if (!Platform.isAndroid) {
      return (accessibility: true, usage: true);
    }
    final accessibility = await hasAccessibilityPermission();
    final usage = await hasUsageAccessPermission();
    return (accessibility: accessibility, usage: usage);
  }
}
