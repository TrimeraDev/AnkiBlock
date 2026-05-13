import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';

class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen>
    with WidgetsBindingObserver {
  bool _usage = false;
  bool _overlay = false;
  bool _notifications = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check when user returns from system settings
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final svc = ref.read(permissionServiceProvider);
    final usage = await svc.hasUsageAccessPermission();
    final overlay = await svc.hasOverlayPermission();
    final notif = await svc.hasNotificationPermission();
    if (!mounted) return;
    setState(() {
      _usage = usage;
      _overlay = overlay;
      _notifications = notif;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final svc = ref.read(permissionServiceProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Permissions'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _PermissionTile(
                  icon: Icons.visibility_outlined,
                  title: 'Usage Access',
                  subtitle:
                      'Required to detect which app is currently in foreground.',
                  granted: _usage,
                  onRequest: () async {
                    await svc.openUsageAccessSettings();
                  },
                ),
                _PermissionTile(
                  icon: Icons.layers_outlined,
                  title: 'Display over other apps',
                  subtitle: 'Required to show the study gate over blocked apps.',
                  granted: _overlay,
                  onRequest: () async {
                    await svc.openOverlaySettings();
                  },
                ),
                _PermissionTile(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  subtitle: 'Optional. Reminders and unlock status.',
                  granted: _notifications,
                  onRequest: () async {
                    await svc.requestNotificationPermission();
                    await _refresh();
                  },
                ),
              ],
            ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool granted;
  final Future<void> Function() onRequest;

  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.onRequest,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: granted
          ? const Icon(Icons.check_circle, color: Colors.green)
          : ElevatedButton(
              onPressed: onRequest,
              child: const Text('Grant'),
            ),
    );
  }
}
