import 'dart:io';

import 'package:flutter/services.dart';

class ProtectionStatus {
  const ProtectionStatus({
    required this.usage,
    required this.overlay,
    required this.batteryUnrestricted,
    required this.monitorRunning,
    required this.hasBlockedApps,
    required this.blockingEnabled,
    required this.protectionActive,
    this.oemManufacturer = 'unknown',
  });

  final bool usage;
  final bool overlay;
  final bool batteryUnrestricted;
  final bool monitorRunning;
  final bool hasBlockedApps;
  final bool blockingEnabled;
  final bool protectionActive;
  final String oemManufacturer;

  bool get permissionsComplete => usage && overlay;

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
      usage: b(map['usage']),
      overlay: b(map['overlay']),
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

  Future<bool> hasOverlayPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('hasOverlayPermission');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openOverlaySettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openOverlaySettings');
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

  Future<bool> isAppMonitorRunning() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('isAppMonitorRunning');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<ProtectionStatus> getProtectionStatus() async {
    if (!Platform.isAndroid) {
      return const ProtectionStatus(
        usage: true,
        overlay: true,
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
          usage: false,
          overlay: false,
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
        usage: false,
        overlay: false,
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

  /// Usage access: required for detecting blocked apps in the foreground.
  Future<bool> hasRequiredPermissions() async {
    return hasUsageAccessPermission();
  }

  /// Usage access + overlay: both required for the app block / study gate flow.
  Future<({bool usage, bool overlay})> getBlockingPermissions() async {
    if (!Platform.isAndroid) return (usage: true, overlay: true);
    final usage = await hasUsageAccessPermission();
    final overlay = await hasOverlayPermission();
    return (usage: usage, overlay: overlay);
  }

  /// Tells the native [AppMonitorService] that the user just earned an unlock
  /// for [packageName] so the gate doesn't fire again until it expires.
  Future<void> grantTempUnlock(String packageName) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel
          .invokeMethod('grantTempUnlock', {'packageName': packageName});
    } catch (_) {}
  }

  /// Launches the app the user just unlocked.
  Future<bool> launchApp(String packageName) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel
          .invokeMethod<bool>('launchApp', {'packageName': packageName});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
