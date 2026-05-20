import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/services/ankidroid_service.dart';

/// Shown when the user opens a blocked app. Tells them how many cards they
/// need to answer to unlock, and routes them into a review session.
class StudyGateScreen extends ConsumerWidget {
  final String packageName;
  final String appName;

  const StudyGateScreen({
    super.key,
    required this.packageName,
    required this.appName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ruleAsync = ref.watch(blockRuleProvider);
    final countsAsync = ref.watch(studyCountsProvider);
    final ankiStatusAsync = ref.watch(ankiDroidStatusProvider);

    final cardsRequired = ruleAsync.valueOrNull?.cardsRequired ?? 5;
    final unlockMinutes =
        ruleAsync.valueOrNull?.unlockDurationMinutes ?? 10;
    final counts = countsAsync.valueOrNull ?? AnkiDroidCounts.zero;
    final ankiReady = ankiStatusAsync.valueOrNull?.isReady ?? false;
    final available = counts.studyable;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.lock_outline, size: 80),
              const SizedBox(height: 24),
              Text(
                '$appName is blocked',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Text(
                'Answer $cardsRequired cards to unlock for $unlockMinutes minutes.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              if (!ankiReady)
                const Padding(
                  padding: EdgeInsets.only(bottom: 24),
                  child: _AnkiDroidWarning(),
                )
              else
                _QueueRow(counts: counts),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                icon: const Icon(Icons.school),
                label: Text(
                  !ankiReady
                      ? 'Set up AnkiDroid first'
                      : (available == 0
                          ? 'Nothing due — unlock anyway'
                          : 'Study Now'),
                ),
                onPressed: !ankiReady
                    ? () => context.push('/ankidroid')
                    : () {
                        context.push('/review', extra: {
                          'unlockPackage': packageName,
                          'unlockAppName': appName,
                          'cardLimit': cardsRequired,
                        });
                      },
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  await SystemNavigator.pop();
                },
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnkiDroidWarning extends StatelessWidget {
  const _AnkiDroidWarning();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.amber),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'AnkiDroid is not connected. AnkiBlock needs it to track your '
              'cards.',
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final AnkiDroidCounts counts;
  const _QueueRow({required this.counts});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        _Chip(value: counts.newCount, label: 'New'),
        _Chip(value: counts.learnCount, label: 'Learn'),
        _Chip(value: counts.reviewCount, label: 'Review'),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final int value;
  final String label;
  const _Chip({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
