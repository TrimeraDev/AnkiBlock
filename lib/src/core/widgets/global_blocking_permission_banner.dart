import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../navigation/router.dart';
import '../services/ankidroid_service.dart';
import '../services/permission_service.dart';
import '../theme/app_theme.dart';

/// Shown under the status bar when setup is incomplete: blocking off, Anki
/// disconnected, or Android permissions missing. Hidden during onboarding.
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

        final protectionAsync = ref.watch(protectionStatusProvider);
        final rule = ref.watch(blockRuleProvider).valueOrNull;
        final anki = ref.watch(ankiDroidStatusProvider).valueOrNull;

        return protectionAsync.when(
          data: (status) {
            final issue = _SetupIssue.detect(
              status: status,
              blockingEnabled: rule?.isEnabled ?? true,
              anki: anki,
            );
            if (issue == null) return const SizedBox.shrink();
            return _BannerBody(issue: issue);
          },
          loading: () {
            final issue = _SetupIssue.detect(
              blockingEnabled: rule?.isEnabled ?? true,
              anki: anki,
            );
            if (issue == null) return const SizedBox.shrink();
            return _BannerBody(issue: issue);
          },
          error: (_, __) => const _BannerBody(verifyFailed: true),
        );
      },
    );
  }
}

class _SetupIssue {
  const _SetupIssue({required this.message, required this.fixRoute});

  final String message;
  final String fixRoute;

  static _SetupIssue? detect({
    ProtectionStatus? status,
    required bool blockingEnabled,
    AnkiDroidStatus? anki,
  }) {
    if (!blockingEnabled) {
      return const _SetupIssue(
        message:
            'Blocking is turned off. Blocked apps open freely until you enable it in Settings.',
        fixRoute: '/settings',
      );
    }
    if (anki != null && !anki.isReady) {
      return _SetupIssue(
        message: !anki.installed
            ? 'AnkiDroid is not installed. Connect it to study and unlock apps.'
            : 'AnkiDroid access not granted. Connect your collection to track cards.',
        fixRoute: '/ankidroid',
      );
    }
    if (status == null) return null;
    if (!status.needsAttention) return null;

    if (!status.accessibility) {
      return const _SetupIssue(
        message:
            'Accessibility is turned off. App blocking will not work until you enable AnkiBlock in Accessibility settings.',
        fixRoute: '/permissions',
      );
    }
    if (status.hasBlockedApps &&
        status.blockingEnabled &&
        !status.monitorRunning) {
      return const _SetupIssue(
        message:
            'App blocking is not active. Open Permissions and re-enable the '
            'AnkiBlock Accessibility service after a reboot.',
        fixRoute: '/permissions',
      );
    }
    if (!status.batteryUnrestricted) {
      return const _SetupIssue(
        message:
            'Battery optimization is on. Blocking may stop after reboot until '
            'you exempt AnkiBlock from battery restrictions.',
        fixRoute: '/permissions',
      );
    }
    return const _SetupIssue(
      message: 'Protection needs attention. Open Permissions to review settings.',
      fixRoute: '/permissions',
    );
  }
}

class _BannerBody extends ConsumerWidget {
  final _SetupIssue? issue;
  final bool verifyFailed;

  const _BannerBody({
    this.issue,
    this.verifyFailed = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final message = verifyFailed
        ? 'Could not verify protection status. Open Permissions to review settings.'
        : issue!.message;
    final fixRoute = verifyFailed ? '/permissions' : issue!.fixRoute;

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
              onPressed: () => ref.read(routerProvider).push(fixRoute),
              child: const Text('Fix'),
            ),
          ],
        ),
      ),
    );
  }
}
