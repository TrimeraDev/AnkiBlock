import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../services/ankidroid_service.dart';
import '../services/study_scope_service.dart';
import '../theme/app_theme.dart';
import '../utils/deck_scope_format.dart';

enum _DeckSort { dueDesc, nameAsc }

/// Shared deck picker: search, filter, bulk actions, and optional scope modes.
class DeckPickerPanel extends ConsumerStatefulWidget {
  final bool showSearch;
  final bool showBulkActions;
  final bool showScopeModes;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;
  final bool shrinkWrap;

  const DeckPickerPanel({
    super.key,
    this.showSearch = true,
    this.showBulkActions = true,
    this.showScopeModes = false,
    this.padding,
    this.physics,
    this.shrinkWrap = true,
  });

  @override
  ConsumerState<DeckPickerPanel> createState() => _DeckPickerPanelState();
}

class _DeckPickerPanelState extends ConsumerState<DeckPickerPanel> {
  String _query = '';
  bool _onlyWithDue = false;
  _DeckSort _sort = _DeckSort.dueDesc;

  List<AnkiDroidDeck> _filterAndSort(List<AnkiDroidDeck> decks) {
    var list = decks.toList();
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((d) => d.name.toLowerCase().contains(q)).toList();
    }
    if (_onlyWithDue) {
      list = list.where((d) => d.totalDue > 0).toList();
    }
    switch (_sort) {
      case _DeckSort.dueDesc:
        list.sort((a, b) {
          final cmp = b.totalDue.compareTo(a.totalDue);
          if (cmp != 0) return cmp;
          return a.name.compareTo(b.name);
        });
      case _DeckSort.nameAsc:
        list.sort((a, b) => a.name.compareTo(b.name));
    }
    return list;
  }

  Future<void> _invalidateScope() async {
    ref.invalidate(studyScopeProvider);
    ref.invalidate(studyCountsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(ankiDroidStatusProvider);
    final decksAsync = ref.watch(ankiDroidDecksProvider);
    final scopeAsync = ref.watch(studyScopeProvider);

    if (!statusAsync.hasValue && statusAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (statusAsync.hasError && !statusAsync.hasValue) {
      return Text('Error: ${statusAsync.error}');
    }

    final status = statusAsync.value;
    if (status == null || !status.isReady) {
      return Text(
        'Connect AnkiDroid first to choose which decks count toward '
        'your unlock goal.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    if (!decksAsync.hasValue && decksAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (decksAsync.hasError && !decksAsync.hasValue) {
      return Text('Error: ${decksAsync.error}');
    }

    final decks = decksAsync.value ?? const <AnkiDroidDeck>[];
    if (decks.isEmpty) {
      return Text(
        'No decks found in AnkiDroid.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    if (!scopeAsync.hasValue && scopeAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (scopeAsync.hasError && !scopeAsync.hasValue) {
      return Text('Error: ${scopeAsync.error}');
    }

    final scope = scopeAsync.value;
    if (scope == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return _DeckPickerBody(
      scope: scope,
      decks: decks,
      filtered: _filterAndSort(decks),
      showScopeModes: widget.showScopeModes,
      showSearch: widget.showSearch,
      showBulkActions: widget.showBulkActions,
      shrinkWrap: widget.shrinkWrap,
      padding: widget.padding,
      physics: widget.physics,
      query: _query,
      onlyWithDue: _onlyWithDue,
      sort: _sort,
      onQueryChanged: (v) => setState(() => _query = v),
      onOnlyWithDueChanged: (v) => setState(() => _onlyWithDue = v),
      onSortChanged: (v) => setState(() => _sort = v),
      onScopeChanged: _invalidateScope,
    );
  }
}

class _DeckPickerBody extends ConsumerWidget {
  final StudyScope scope;
  final List<AnkiDroidDeck> decks;
  final List<AnkiDroidDeck> filtered;
  final bool showScopeModes;
  final bool showSearch;
  final bool showBulkActions;
  final bool shrinkWrap;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;
  final String query;
  final bool onlyWithDue;
  final _DeckSort sort;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<bool> onOnlyWithDueChanged;
  final ValueChanged<_DeckSort> onSortChanged;
  final Future<void> Function() onScopeChanged;

  const _DeckPickerBody({
    required this.scope,
    required this.decks,
    required this.filtered,
    required this.showScopeModes,
    required this.showSearch,
    required this.showBulkActions,
    required this.shrinkWrap,
    required this.padding,
    required this.physics,
    required this.query,
    required this.onlyWithDue,
    required this.sort,
    required this.onQueryChanged,
    required this.onOnlyWithDueChanged,
    required this.onSortChanged,
    required this.onScopeChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabledCount = countEnabledDecks(scope, decks);
    final dueTotal = countDueInScope(scope, decks);

    final scrollPhysics = physics ??
        (shrinkWrap
            ? const NeverScrollableScrollPhysics()
            : const AlwaysScrollableScrollPhysics());

    Widget buildScrollView() {
      final slivers = <Widget>[
          if (showScopeModes) ...[
            SliverToBoxAdapter(
              child: _ScopeModeHeader(scope: scope, onChanged: onScopeChanged),
            ),
            const SliverToBoxAdapter(child: Divider(height: 1)),
          ],
          if (showSearch)
            SliverToBoxAdapter(
              child: _DeckSearchBar(
                query: query,
                onlyWithDue: onlyWithDue,
                sort: sort,
                onQueryChanged: onQueryChanged,
                onOnlyWithDueChanged: onOnlyWithDueChanged,
                onSortChanged: onSortChanged,
              ),
            ),
          if (showBulkActions && scope.mode != StudyScopeMode.single)
            SliverToBoxAdapter(
              child: _BulkActionsHeader(
                enabledCount: enabledCount,
                totalCount: decks.length,
                dueTotal: dueTotal,
                decks: decks,
                onChanged: onScopeChanged,
              ),
            ),
          if (filtered.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No decks match your search.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _DeckPickerRow(
                  deck: filtered[index],
                  scope: scope,
                  onChanged: onScopeChanged,
                ),
                childCount: filtered.length,
              ),
            ),
        ];

      final scrollView = CustomScrollView(
        shrinkWrap: shrinkWrap,
        physics: scrollPhysics,
        slivers: slivers,
      );

      if (padding == null) return scrollView;
      return Padding(padding: padding!, child: scrollView);
    }

    if (scope.mode != StudyScopeMode.single) {
      return buildScrollView();
    }

    return RadioGroup<int>(
      groupValue: scope.activeDeckId,
      onChanged: (v) async {
        await ref.read(studyScopeServiceProvider).setActiveDeck(v);
        await onScopeChanged();
      },
      child: buildScrollView(),
    );
  }
}

class _ScopeModeHeader extends ConsumerWidget {
  final StudyScope scope;
  final Future<void> Function() onChanged;

  const _ScopeModeHeader({required this.scope, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Advanced',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppTheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<StudyScopeMode>(
            segments: const [
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
            selected: {
              scope.mode == StudyScopeMode.single
                  ? StudyScopeMode.single
                  : StudyScopeMode.multi,
            },
            onSelectionChanged: (modes) async {
              await ref.read(studyScopeServiceProvider).setMode(modes.first);
              await onChanged();
            },
          ),
          const SizedBox(height: 8),
          Text(
            scope.mode == StudyScopeMode.single
                ? 'Pick one deck. Only cards from that deck count.'
                : 'Toggle which decks count. Reviews from any selected deck '
                    'count — you can switch decks in AnkiDroid.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _DeckSearchBar extends StatelessWidget {
  final String query;
  final bool onlyWithDue;
  final _DeckSort sort;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<bool> onOnlyWithDueChanged;
  final ValueChanged<_DeckSort> onSortChanged;

  const _DeckSearchBar({
    required this.query,
    required this.onlyWithDue,
    required this.sort,
    required this.onQueryChanged,
    required this.onOnlyWithDueChanged,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            onChanged: onQueryChanged,
            decoration: InputDecoration(
              hintText: 'Search decks',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilterChip(
                label: const Text('Only with due'),
                selected: onlyWithDue,
                onSelected: onOnlyWithDueChanged,
              ),
              const Spacer(),
              PopupMenuButton<_DeckSort>(
                initialValue: sort,
                onSelected: onSortChanged,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _DeckSort.dueDesc,
                    child: Text('Sort by due'),
                  ),
                  PopupMenuItem(
                    value: _DeckSort.nameAsc,
                    child: Text('Sort by name'),
                  ),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      sort == _DeckSort.dueDesc ? 'Due ↓' : 'Name A–Z',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Icon(Icons.arrow_drop_down, size: 20),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BulkActionsHeader extends ConsumerWidget {
  final int enabledCount;
  final int totalCount;
  final int dueTotal;
  final List<AnkiDroidDeck> decks;
  final Future<void> Function() onChanged;

  const _BulkActionsHeader({
    required this.enabledCount,
    required this.totalCount,
    required this.dueTotal,
    required this.decks,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.read(studyScopeServiceProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$enabledCount of $totalCount decks · $dueTotal due',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 0,
            children: [
              TextButton(
                onPressed: () async {
                  await svc.enableAll();
                  await onChanged();
                },
                child: const Text('Select all'),
              ),
              TextButton(
                onPressed: () async {
                  await svc.disableAll(decks.map((d) => d.id));
                  await onChanged();
                },
                child: const Text('Clear all'),
              ),
              TextButton(
                onPressed: () async {
                  final withDue = decks.where((d) => d.totalDue > 0).toList();
                  final disabled = decks
                      .where((d) => d.totalDue == 0)
                      .map((d) => d.id)
                      .toSet();
                  await svc.setDisabledDeckIds(disabled);
                  if (withDue.isEmpty) {
                    await svc.enableAll();
                  }
                  await onChanged();
                },
                child: const Text('Select with due'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeckPickerRow extends ConsumerWidget {
  final AnkiDroidDeck deck;
  final StudyScope scope;
  final Future<void> Function() onChanged;

  const _DeckPickerRow({
    required this.deck,
    required this.scope,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = !scope.disabledDeckIds.contains(deck.id);
    final isActive = scope.activeDeckId == deck.id;
    final subtitle = '${deck.newCount} new • '
        '${deck.learnCount} learning • '
        '${deck.reviewCount} review';

    if (scope.mode == StudyScopeMode.single) {
      return RadioListTile<int>(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        secondary: const Icon(Icons.style_outlined, size: 22),
        value: deck.id,
        title: Text(deck.name),
        subtitle: Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        selected: isActive,
      );
    }

    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      secondary: const Icon(Icons.style_outlined, size: 22),
      title: Text(deck.name),
      subtitle: Text(
        subtitle,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      value: enabled,
      onChanged: (v) async {
        await ref.read(studyScopeServiceProvider).setDeckEnabled(deck.id, v);
        await onChanged();
      },
    );
  }
}

/// Backward-compatible alias used by onboarding and Today sheet.
typedef DeckStudySetupPanel = DeckPickerPanel;
