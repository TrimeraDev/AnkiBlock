import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app.dart';
import 'src/core/database/database.dart';
import 'src/core/di/providers.dart';
import 'src/core/theme/app_theme.dart';
import 'src/core/utils/diagnostics_report.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Local crash capture — no Firebase project configured yet. Errors are
  // persisted for the diagnostics panel and logged in debug builds.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(_persistError(details.exceptionAsString(), details.stack));
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(_persistError(error.toString(), stack));
    return true;
  };

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final db = await _initializeDatabase();

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
      ],
      child: const AnkiBlockApp(),
    ),
  );
}

Future<void> _persistError(String message, StackTrace? stack) async {
  if (kDebugMode) {
    debugPrint('AnkiBlock error: $message\n$stack');
  }
  try {
    final prefs = await SharedPreferences.getInstance();
    final stamp = DateTime.now().toIso8601String();
    final payload = '$stamp\n$message';
    await prefs.setString(
      kLastCrashKey,
      payload.length > 800 ? payload.substring(0, 800) : payload,
    );
  } catch (_) {}
}

Future<AppDatabase> _initializeDatabase() async {
  final documentsDir = await getApplicationDocumentsDirectory();
  final dbPath = p.join(documentsDir.path, 'ankiblock.db');
  return AppDatabase.open(dbPath);
}
