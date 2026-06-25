import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/widgets/deck_picker_panel.dart';

/// AnkiDroid decks listing with per-deck inclusion toggles.
class DecksScreen extends ConsumerWidget {
  const DecksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(ankiDroidStatusProvider);
    final decksAsync = ref.watch(ankiDroidDecksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Decks'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh from AnkiDroid',
            onPressed: () {
              ref.invalidate(ankiDroidDecksProvider);
              ref.invalidate(studyCountsProvider);
            },
          ),
        ],
      ),
      body: statusAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ConfigureAnkiDroidCta(message: 'Error: $e'),
        data: (status) {
          if (!status.isReady) {
            return _ConfigureAnkiDroidCta(
              message: status.installed
                  ? 'AnkiBlock does not have access to your AnkiDroid '
                      'collection yet.'
                  : 'AnkiDroid is not installed. AnkiBlock uses AnkiDroid '
                      'to read your cards.',
            );
          }
          return decksAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (decks) {
              if (decks.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No decks found in AnkiDroid.'),
                  ),
                );
              }
              return const DeckPickerPanel(
                showScopeModes: true,
                shrinkWrap: false,
                padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
              );
            },
          );
        },
      ),
    );
  }
}

class _ConfigureAnkiDroidCta extends StatelessWidget {
  final String message;
  const _ConfigureAnkiDroidCta({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sync_disabled, size: 64),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.push('/ankidroid'),
              child: const Text('Set up AnkiDroid'),
            ),
          ],
        ),
      ),
    );
  }
}
