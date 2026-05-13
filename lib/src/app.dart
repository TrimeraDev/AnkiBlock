import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/di/providers.dart';
import 'core/navigation/router.dart';
import 'core/services/apps_service.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/global_blocking_permission_banner.dart';

class AnkiBlockApp extends ConsumerStatefulWidget {
  const AnkiBlockApp({super.key});

  @override
  ConsumerState<AnkiBlockApp> createState() => _AnkiBlockAppState();
}

class _AnkiBlockAppState extends ConsumerState<AnkiBlockApp>
    with WidgetsBindingObserver {
  StreamSubscription<GateRequest>? _gateSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(blockingPermissionsProvider);
    }
  }

  Future<void> _bootstrap() async {
    final svc = ref.read(appsServiceProvider);
    _gateSub = svc.gateRequests.listen(_handleGate);

    // Re-sync blocked list and start monitor on every cold start
    final db = ref.read(databaseProvider);
    final all = await db.watchAllBlockedApps().first;
    final active = all
        .where((b) => b.isBlocked)
        .map((b) => (pkg: b.packageName, name: b.displayName))
        .toList();
    await svc.setBlockedPackages(active);
    if (active.isNotEmpty) {
      await svc.startAppMonitor();
    }

    // If launched from a gate intent, consume and route
    final pending = await svc.consumePendingGate();
    if (pending != null) _handleGate(pending);
  }

  void _handleGate(GateRequest req) {
    final router = ref.read(routerProvider);
    router.go('/gate', extra: {
      'packageName': req.packageName,
      'appName': req.appName,
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gateSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'AnkiBlock',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      routerConfig: router,
      builder: (context, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SafeArea(
              bottom: false,
              left: false,
              right: false,
              minimum: EdgeInsets.zero,
              child: GlobalBlockingPermissionBanner(),
            ),
            Expanded(child: child ?? const SizedBox.shrink()),
          ],
        );
      },
    );
  }
}
