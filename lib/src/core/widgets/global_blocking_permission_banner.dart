import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../navigation/router.dart';
import '../theme/app_theme.dart';

/// Shown under the status bar when Android blocking permissions are incomplete.
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

        final async = ref.watch(blockingPermissionsProvider);
        return async.when(
          data: (s) {
            if (s.usage && s.overlay) return const SizedBox.shrink();
            return _BannerBody(
              missingUsage: !s.usage,
              missingOverlay: !s.overlay,
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const _BannerBody(
            missingUsage: true,
            missingOverlay: true,
            verifyFailed: true,
          ),
        );
      },
    );
  }
}

class _BannerBody extends ConsumerWidget {
  final bool missingUsage;
  final bool missingOverlay;
  final bool verifyFailed;

  const _BannerBody({
    required this.missingUsage,
    required this.missingOverlay,
    this.verifyFailed = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final parts = <String>[
      if (missingUsage) 'Usage access',
      if (missingOverlay) 'Display over other apps',
    ];
    final label = parts.join(' and ');
    final message = verifyFailed
        ? 'Could not verify blocking permissions. Open Permissions to review settings.'
        : (parts.length == 2
            ? '$label are turned off. App blocking will not work until you enable them.'
            : '$label is turned off. App blocking will not work until you enable it.');

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
}
