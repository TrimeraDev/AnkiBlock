import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/services/ankidroid_service.dart';
import '../../core/services/study_scope_service.dart';
import '../../core/theme/app_theme.dart';

/// AnkiDroid decks listing with per-deck inclusion toggles.
///
/// Behavior is driven by the user's [StudyScope]:
/// * **All** — every deck is implicitly included; toggles are disabled.
/// * **Multi** — each deck has a switch; off = excluded.
/// * **Single** — each deck has a radio; tapping picks the one active deck.
class DecksScreen extends ConsumerWidget {
  const DecksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(ankiDroidStatusProvider);
    final decksAsync = ref.watch(ankiDroidDecksProvider);
    final scopeAsync = ref.watch(studyScopeProvider);

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
          return _Body(
            decksAsync: decksAsync,
            scopeAsync: scopeAsync,
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

class _Body extends ConsumerWidget {
  final AsyncValue<List<AnkiDroidDeck>> decksAsync;
  final AsyncValue<StudyScope> scopeAsync;

  const _Body({required this.decksAsync, required this.scopeAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        return scopeAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (scope) => _DeckList(decks: decks, scope: scope),
        );
      },
    );
  }
}

class _DeckList extends ConsumerWidget {
  final List<AnkiDroidDeck> decks;
  final StudyScope scope;
  const _DeckList({required this.decks, required this.scope});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = ListView(
      children: [
        _ScopeHeader(scope: scope),
        const Divider(height: 1),
        for (final d in decks) _DeckRow(deck: d, scope: scope),
      ],
    );

    // Single-deck mode uses radio buttons; wrap in a RadioGroup so the new
    // Material API can manage selection without per-tile `groupValue`s.
    if (scope.mode == StudyScopeMode.single) {
      return RadioGroup<int>(
        groupValue: scope.activeDeckId,
        onChanged: (v) async {
          final svc = ref.read(studyScopeServiceProvider);
          await svc.setActiveDeck(v);
          ref.invalidate(studyScopeProvider);
          ref.invalidate(studyCountsProvider);
        },
        child: body,
      );
    }
    return body;
  }
}

class _ScopeHeader extends ConsumerWidget {
  final StudyScope scope;
  const _ScopeHeader({required this.scope});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Study scope',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppTheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<StudyScopeMode>(
            segments: const [
              ButtonSegment(
                value: StudyScopeMode.all,
                label: Text('All'),
                icon: Icon(Icons.select_all),
              ),
              ButtonSegment(
                value: StudyScopeMode.multi,
                label: Text('Multi'),
                icon: Icon(Icons.checklist),
              ),
              ButtonSegment(
                value: StudyScopeMode.single,
                label: Text('Single'),
                icon: Icon(Icons.radio_button_checked),
              ),
            ],
            selected: {scope.mode},
            onSelectionChanged: (modes) async {
              final svc = ref.read(studyScopeServiceProvider);
              await svc.setMode(modes.first);
              ref.invalidate(studyScopeProvider);
              ref.invalidate(studyCountsProvider);
            },
          ),
          const SizedBox(height: 8),
          Text(
            switch (scope.mode) {
              StudyScopeMode.all =>
                'Studying every AnkiDroid deck. No per-deck filter.',
              StudyScopeMode.multi =>
                'Toggle which decks AnkiBlock should pull cards from.',
              StudyScopeMode.single =>
                'Pick one deck. AnkiBlock will only study cards from there.',
            },
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _DeckRow extends ConsumerWidget {
  final AnkiDroidDeck deck;
  final StudyScope scope;
  const _DeckRow({required this.deck, required this.scope});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = !scope.disabledDeckIds.contains(deck.id);
    final isActive = scope.activeDeckId == deck.id;

    final subtitle = '${deck.newCount} new • '
        '${deck.learnCount} learning • '
        '${deck.reviewCount} review';

    switch (scope.mode) {
      case StudyScopeMode.all:
        return ListTile(
          leading: const Icon(Icons.style_outlined),
          title: Text(deck.name),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.check, color: AppTheme.success),
        );
      case StudyScopeMode.multi:
        return SwitchListTile(
          secondary: const Icon(Icons.style_outlined),
          title: Text(deck.name),
          subtitle: Text(subtitle),
          value: enabled,
          onChanged: (v) async {
            final svc = ref.read(studyScopeServiceProvider);
            await svc.setDeckEnabled(deck.id, v);
            ref.invalidate(studyScopeProvider);
            ref.invalidate(studyCountsProvider);
          },
        );
      case StudyScopeMode.single:
        // [RadioGroup] is provided by the parent _DeckList in this mode,
        // so the tile only needs its own value and the row chrome.
        return RadioListTile<int>(
          secondary: const Icon(Icons.style_outlined),
          value: deck.id,
          title: Text(deck.name),
          subtitle: Text(subtitle),
          selected: isActive,
        );
    }
  }
}
