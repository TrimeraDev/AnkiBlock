import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

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

  Future<bool> hasNotificationPermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      return status.isGranted;
    }
    return true;
  }

  Future<bool> requestNotificationPermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.notification.request();
      return status.isGranted;
    }
    return true;
  }

  Future<bool> hasRequiredPermissions() async {
    final hasUsage = await hasUsageAccessPermission();
    final hasNotification = await hasNotificationPermission();
    return hasUsage && hasNotification;
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
