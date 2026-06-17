import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'src/app.dart';
import 'src/core/database/database.dart';
import 'src/core/di/providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFFFAF8F5),
      systemNavigationBarIconBrightness: Brightness.dark,
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

Future<AppDatabase> _initializeDatabase() async {
  final documentsDir = await getApplicationDocumentsDirectory();
  final dbPath = p.join(documentsDir.path, 'ankiblock.db');
  return AppDatabase.open(dbPath);
}
