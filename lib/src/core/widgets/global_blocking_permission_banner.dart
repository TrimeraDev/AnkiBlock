import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../navigation/router.dart';
import '../services/permission_service.dart';
import '../theme/app_theme.dart';

/// Shown under the status bar when Android blocking or protection is incomplete.
/// Hidden during onboarding, where those permissions are requested step-by-step.
class GlobalBlockingPermissionBanner extends ConsumerWidget {
  const GlobalBlockingPermissionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return ListenableBuilder(
      listenable: router.routeInformationProvider,
      builder: (context, _) {
        final path = router.routeInformationProvider.value.uri.path;
        if (path == '/onboarding') return const SizedBox.shrink();

        final async = ref.watch(protectionStatusProvider);
        return async.when(
          data: (status) {
            if (!status.needsAttention) return const SizedBox.shrink();
            return _BannerBody(status: status);
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const _BannerBody(verifyFailed: true),
        );
      },
    );
  }
}

class _BannerBody extends ConsumerWidget {
  final ProtectionStatus? status;
  final bool verifyFailed;

  const _BannerBody({
    this.status,
    this.verifyFailed = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final message = verifyFailed
        ? 'Could not verify protection status. Open Permissions to review settings.'
        : _messageFor(status!);

    return Material(
      color: AppTheme.warning.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppTheme.warning, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.onSurface,
                  height: 1.35,
                ),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => ref.read(routerProvider).push('/permissions'),
              child: const Text('Fix'),
            ),
          ],
        ),
      ),
    );
  }

  String _messageFor(ProtectionStatus status) {
    if (!status.usage || !status.overlay) {
      final parts = <String>[
        if (!status.usage) 'Usage access',
        if (!status.overlay) 'Display over other apps',
      ];
      final label = parts.join(' and ');
      return parts.length == 2
          ? '$label are turned off. App blocking will not work until you enable them.'
          : '$label is turned off. App blocking will not work until you enable it.';
    }
    if (status.hasBlockedApps &&
        status.blockingEnabled &&
        !status.monitorRunning) {
      return 'App blocking is not active. Open AnkiBlock or check Permissions '
          'to restart protection after a reboot.';
    }
    if (!status.batteryUnrestricted) {
      return 'Battery optimization is on. Blocking may stop after reboot until '
          'you exempt AnkiBlock from battery restrictions.';
    }
    return 'Protection needs attention. Open Permissions to review settings.';
  }
}
