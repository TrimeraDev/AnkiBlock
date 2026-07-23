import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/di/providers.dart';
import '../../core/services/permission_service.dart';
import '../../core/theme/app_theme.dart';

class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen>
    with WidgetsBindingObserver {
  ProtectionStatus? _status;
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
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final svc = ref.read(permissionServiceProvider);
    final status = await svc.getProtectionStatus();
    if (!mounted) return;
    setState(() {
      _status = status;
      _loading = false;
    });
    ref.invalidate(protectionStatusProvider);
  }

  @override
  Widget build(BuildContext context) {
    final svc = ref.read(permissionServiceProvider);
    final status = _status;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Permissions & AnkiDroid'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: _loading || status == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                if (status.hasBlockedApps &&
                    status.blockingEnabled &&
                    !status.monitorRunning)
                  const _StatusBanner(
                    icon: Icons.shield_outlined,
                    color: AppTheme.warning,
                    message:
                        'Blocking monitor is not running. It should restart '
                        'automatically after reboot, but you can reopen AnkiBlock '
                        'to force a restart.',
                  ),
                const _SectionHeader(label: 'Blocking'),
                _PermissionTile(
                  icon: Icons.visibility_outlined,
                  title: 'Usage Access',
                  subtitle:
                      'Required to detect which app is currently in foreground.',
                  granted: status.usage,
                  onRequest: svc.openUsageAccessSettings,
                ),
                _PermissionTile(
                  icon: Icons.layers_outlined,
                  title: 'Display over other apps',
                  subtitle: 'Required to show the study gate over blocked apps.',
                  granted: status.overlay,
                  onRequest: svc.openOverlaySettings,
                ),
                _PermissionTile(
                  icon: Icons.battery_charging_full_outlined,
                  title: 'Unrestricted battery',
                  subtitle:
                      'Prevents the system from stopping blocking after reboot '
                      'or when the app is in the background.',
                  granted: status.batteryUnrestricted,
                  onRequest: svc.requestBatteryOptimizationExemption,
                ),
                const Divider(height: 32),
                const _SectionHeader(label: 'AnkiDroid'),
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text('AnkiDroid sync'),
                  subtitle: const Text(
                    'Connection status, database access, and open AnkiDroid.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/ankidroid'),
                ),
                const Divider(height: 32),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'After reboot',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'AnkiBlock restarts its monitor automatically after reboot. '
                    'On some phones (Samsung, Xiaomi, Huawei, etc.) you may also '
                    'need to enable autostart or remove AnkiBlock from sleeping-apps '
                    'lists in system settings.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.onSurface.withValues(alpha: 0.8),
                          height: 1.4,
                        ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                  child: TextButton.icon(
                    onPressed: () => _openDontKillMyApp(),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Device-specific battery tips'),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _openDontKillMyApp() async {
    final uri = Uri.parse('https://dontkillmyapp.com/');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppTheme.onSurfaceVariant,
              letterSpacing: 1,
            ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;

  const _StatusBanner({
    required this.icon,
    required this.color,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.35,
                      ),
                ),
              ),
            ],
          ),
        ),
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
          ? const Icon(Icons.check_circle, color: AppTheme.success)
          : ElevatedButton(
              onPressed: onRequest,
              child: const Text('Grant'),
            ),
    );
  }
}
