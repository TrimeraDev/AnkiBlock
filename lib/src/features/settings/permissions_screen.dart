import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/di/providers.dart';
import '../../core/services/permission_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/diagnostics_report.dart';
import '../../core/widgets/accessibility_disclosure.dart';

class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen>
    with WidgetsBindingObserver {
  ProtectionStatus? _status;
  String _diagnosticsReport = '';
  bool _loading = true;
  bool _showDiagnostics = false;
  bool _copyFeedback = false;
  bool _notificationsGranted = true;

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
    final notifications = await svc.hasNotificationPermission();
    final inputs = await gatherDiagnosticsInputs(ref);
    if (!mounted) return;
    setState(() {
      _status = status;
      _notificationsGranted = notifications;
      _diagnosticsReport = formatDiagnosticsReport(inputs);
      _loading = false;
    });
    ref.invalidate(protectionStatusProvider);
  }

  Future<void> _copyDiagnostics() async {
    await Clipboard.setData(ClipboardData(text: _diagnosticsReport));
    if (!mounted) return;
    setState(() => _copyFeedback = true);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copyFeedback = false);
    });
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
        actions: [
          IconButton(
            icon: Icon(
              _showDiagnostics ? Icons.bug_report : Icons.bug_report_outlined,
            ),
            tooltip: 'Diagnostics',
            onPressed: () => setState(() => _showDiagnostics = !_showDiagnostics),
          ),
        ],
      ),
      body: _loading || status == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                if (status.hasAnythingToBlock &&
                    status.blockingEnabled &&
                    !status.accessibility)
                  const _StatusBanner(
                    icon: Icons.shield_outlined,
                    color: AppTheme.warning,
                    message:
                        'Accessibility is off. Enable AnkiBlock under '
                        'Settings → Accessibility so blocked apps and sites stay gated.',
                  ),
                if (status.hasAnythingToBlock &&
                    status.blockingEnabled &&
                    status.accessibility &&
                    !status.monitorRunning)
                  const _StatusBanner(
                    icon: Icons.shield_outlined,
                    color: AppTheme.warning,
                    message:
                        'Accessibility is enabled but not connected yet. '
                        'Toggle AnkiBlock off and on in Accessibility settings, '
                        'or reopen the app after reboot.',
                  ),
                const _SectionHeader(label: 'Blocking'),
                _PermissionTile(
                  icon: Icons.accessibility_new_outlined,
                  title: 'Accessibility',
                  subtitle:
                      'Required to detect blocked apps and websites instantly and show the study gate.',
                  granted: status.accessibility,
                  onRequest: () async {
                    final ok = await showAccessibilityDisclosureDialog(context);
                    if (!ok || !context.mounted) return;
                    await svc.openAccessibilitySettings();
                  },
                ),
                _PermissionTile(
                  icon: Icons.visibility_outlined,
                  title: 'Usage Access (optional)',
                  subtitle:
                      'Not required for blocking. Only powers screen-time stats '
                      'when picking apps.',
                  granted: status.usage,
                  onRequest: svc.openUsageAccessSettings,
                ),
                _PermissionTile(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications (optional)',
                  subtitle:
                      'Study progress and unlock timer in the shade, plus a '
                      '1-minute warning before apps and sites lock again.',
                  granted: _notificationsGranted,
                  onRequest: () async {
                    await svc.requestNotificationPermission();
                    await _refresh();
                  },
                ),
                _PermissionTile(
                  icon: Icons.battery_charging_full_outlined,
                  title: 'Unrestricted battery',
                  subtitle:
                      'Helps AnkiBlock survive overnight on aggressive OEMs. '
                      'Accessibility usually stays bound without this, but it is still recommended.',
                  granted: status.batteryUnrestricted,
                  onRequest: svc.requestBatteryOptimizationExemption,
                ),
                if (status.needsOemAutostartHelp) ...[
                  const Divider(height: 32),
                  const _SectionHeader(label: 'Device-specific'),
                  ListTile(
                    leading: const Icon(Icons.phonelink_setup_outlined),
                    title: Text(
                      '${_oemLabel(status.oemManufacturer)} autostart / battery',
                    ),
                    subtitle: const Text(
                      'Open system settings so Accessibility stays enabled '
                      'after reboot on this phone.',
                    ),
                    trailing: ElevatedButton(
                      onPressed: () => svc.openOemAutostartSettings(),
                      child: const Text('Open'),
                    ),
                  ),
                ],
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
                    'AnkiBlock uses Accessibility to enforce blocking. After reboot, '
                    'confirm AnkiBlock is still enabled under Accessibility. On some '
                    'phones (Samsung, Xiaomi, Honor, Huawei, etc.) also enable '
                    'autostart or remove AnkiBlock from sleeping-apps lists.',
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
                if (_showDiagnostics) ...[
                  const Divider(height: 32),
                  const _SectionHeader(label: 'Diagnostics'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'Copy this report when filing a bug. It includes device '
                      'info, permissions, blocking config, Accessibility '
                      'service health, and '
                      'recent errors — no card content or passwords.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed:
                            _diagnosticsReport.isEmpty ? null : _copyDiagnostics,
                        icon: Icon(
                          _copyFeedback ? Icons.check : Icons.copy,
                          size: 18,
                        ),
                        label: Text(
                          _copyFeedback ? 'Copied' : 'Copy diagnostics',
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: SelectableText(
                      _diagnosticsReport,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            height: 1.4,
                          ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  String _oemLabel(String key) {
    switch (key) {
      case 'xiaomi':
        return 'Xiaomi / MIUI';
      case 'huawei':
        return 'Huawei';
      case 'honor':
        return 'Honor';
      case 'samsung':
        return 'Samsung';
      case 'oppo':
        return 'OPPO';
      case 'oneplus':
        return 'OnePlus';
      case 'vivo':
        return 'vivo';
      default:
        return key;
    }
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
