import 'dart:async';

import 'package:flutter/services.dart';

import '../database/database.dart';

class AppBlockerService {
  static const MethodChannel _channel = MethodChannel('com.ankiblock/app_blocker');
  
  final StreamController<String> _appOpenedController = StreamController<String>.broadcast();
  Stream<String> get onBlockedAppOpened => _appOpenedController.stream;
  
  bool _isInitialized = false;
  bool _isRunning = false;
  Timer? _monitorTimer;
  List<String> _blockedPackages = [];
  AppDatabase? _database;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _channel.setMethodCallHandler(_handleMethodCall);
    _isInitialized = true;
  }

  void setDatabase(AppDatabase database) {
    _database = database;
  }

  Future<void> startMonitoring(List<String> blockedPackages) async {
    _blockedPackages = blockedPackages;
    _isRunning = true;
    
    try {
      await _channel.invokeMethod('startMonitoring', {
        'blockedPackages': blockedPackages,
      });
    } catch (e) {
      // Fallback to timer-based monitoring if platform channel fails
      _startTimerMonitoring();
    }
  }

  void _startTimerMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!_isRunning) return;
      
      try {
        final currentApp = await _channel.invokeMethod<String>('getCurrentApp');
        if (currentApp != null && _blockedPackages.contains(currentApp)) {
          // Check if there's an active unlock session
          if (_database != null) {
            final session = await _database!.getActiveSessionForPackage(currentApp);
            if (session == null) {
              _appOpenedController.add(currentApp);
            }
          }
        }
      } catch (e) {
        // Ignore errors during monitoring
      }
    });
  }

  Future<void> stopMonitoring() async {
    _isRunning = false;
    _monitorTimer?.cancel();
    _monitorTimer = null;
    
    try {
      await _channel.invokeMethod('stopMonitoring');
    } catch (e) {
      // Ignore
    }
  }

  Future<bool> isAppBlocked(String packageName) async {
    return _blockedPackages.contains(packageName);
  }

  Future<void> launchApp(String packageName) async {
    try {
      await _channel.invokeMethod('launchApp', {'packageName': packageName});
    } catch (e) {
      // Could not launch app
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onBlockedAppOpened':
        final packageName = call.arguments['packageName'] as String;
        _appOpenedController.add(packageName);
        break;
    }
  }

  void dispose() {
    stopMonitoring();
    _appOpenedController.close();
  }
}
