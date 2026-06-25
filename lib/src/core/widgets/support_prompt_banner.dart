import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../support/support_actions.dart';
import '../theme/app_theme.dart';
import 'brand_widgets.dart';

/// Shown on the Today screen every 4th app open until dismissed.
class SupportPromptBanner extends ConsumerWidget {
  const SupportPromptBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(supportPromptVisibleProvider);
    if (!visible) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: BrandCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Enjoying AnkiBlock?',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Leave a rating or support the developer with an '
                        'optional tip.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Dismiss',
                  color: AppTheme.onSurfaceVariant,
                  onPressed: () => _dismiss(ref),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => openSupportLink(
                context,
                ref,
                (a) => a.requestAppReview(),
              ),
              icon: const Icon(Icons.star_outline, size: 18),
              label: const Text('Rate AnkiBlock'),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: () => openSupportLink(
                    context,
                    ref,
                    (a) => a.openKofi(),
                  ),
                  child: const Text('Ko-fi'),
                ),
                TextButton(
                  onPressed: () => openSupportLink(
                    context,
                    ref,
                    (a) => a.openPayPal(),
                  ),
                  child: const Text('PayPal'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _dismiss(WidgetRef ref) async {
    final count = ref.read(appLaunchCountProvider);
    await ref.read(supportPromptServiceProvider).dismissPrompt(count);
    ref.read(supportPromptVisibleProvider.notifier).state = false;
  }
}
