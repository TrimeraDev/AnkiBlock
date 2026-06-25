import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../services/ankidroid_service.dart';
import '../services/apps_service.dart';
import '../services/study_scope_service.dart';
import '../setup/setup_actions.dart';
import '../theme/app_theme.dart';
import 'brand_widgets.dart';

/// Preset chips + slider for cards required per unlock.
class UnlockGoalPanel extends ConsumerStatefulWidget {
  final int initial;
  final int min;
  final int max;
  final bool showTitle;
  final ValueChanged<int>? onChanged;

  const UnlockGoalPanel({
    super.key,
    required this.initial,
    this.min = 1,
    this.max = 50,
    this.showTitle = true,
    this.onChanged,
  });

  @override
  ConsumerState<UnlockGoalPanel> createState() => _UnlockGoalPanelState();
}

class _UnlockGoalPanelState extends ConsumerState<UnlockGoalPanel> {
  static const _presets = [10, 25, 50];

  late int _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
  }

  @override
  void didUpdateWidget(UnlockGoalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial != widget.initial) {
      _value = widget.initial;
    }
  }

  void _set(int v) {
    setState(() => _value = v);
    widget.onChanged?.call(v);
  }

  Future<void> _persist(int v) async {
    await updateCardsRequired(ref, v);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showTitle) ...[
          Text('Unlock goal', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'How many cards to study each time you open a blocked app.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
        ],
        BrandCard(
          color: AppTheme.cardElevated,
          child: Column(
            children: [
              Text(
                '$_value cards per unlock',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: _presets.map((p) {
                  final selected = _value == p;
                  return ChoiceChip(
                    label: Text('$p'),
                    selected: selected,
                    onSelected: (_) {
                      _set(p);
                      _persist(p);
                    },
                    selectedColor: AppTheme.accent.withValues(alpha: 0.25),
                    labelStyle: TextStyle(
                      color: selected ? AppTheme.accent : AppTheme.onSurface,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                    side: BorderSide(
                      color: selected ? AppTheme.accent : AppTheme.divider,
                    ),
                    backgroundColor: AppTheme.card,
                  );
                }).toList(),
              ),
              Slider(
                value: _value.toDouble(),
                min: widget.min.toDouble(),
                max: widget.max.toDouble(),
                divisions: widget.max - widget.min,
                label: '$_value',
                onChanged: (v) => _set(v.round()),
                onChangeEnd: (v) => _persist(v.round()),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Preset chips + slider for the daily study target (unlocks everything until 3am).
class DailyGoalPanel extends ConsumerStatefulWidget {
  final int initial;
  final int min;
  final int max;
  final bool showTitle;
  final ValueChanged<int>? onChanged;

  const DailyGoalPanel({
    super.key,
    required this.initial,
    this.min = 5,
    this.max = 200,
    this.showTitle = true,
    this.onChanged,
  });

  @override
  ConsumerState<DailyGoalPanel> createState() => _DailyGoalPanelState();
}

class _DailyGoalPanelState extends ConsumerState<DailyGoalPanel> {
  static const _presets = [20, 30, 50];

  late int _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
  }

  @override
  void didUpdateWidget(DailyGoalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial != widget.initial) {
      _value = widget.initial;
    }
  }

  void _set(int v) {
    setState(() => _value = v);
    widget.onChanged?.call(v);
  }

  Future<void> _persist(int v) async {
    await updateDailyCardsGoal(ref, v);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showTitle) ...[
          Text('Daily goal', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Finish this many cards to unlock all blocked apps for the day. '
            'Counts study in AnkiDroid even if you open it directly. '
            'Resets at 3am.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
        ],
        BrandCard(
          color: AppTheme.cardElevated,
          child: Column(
            children: [
              Text(
                '$_value cards per day',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: _presets.map((p) {
                  final selected = _value == p;
                  return ChoiceChip(
                    label: Text('$p'),
                    selected: selected,
                    onSelected: (_) {
                      _set(p);
                      _persist(p);
                    },
                    selectedColor: AppTheme.primary.withValues(alpha: 0.25),
                    labelStyle: TextStyle(
                      color: selected ? AppTheme.primary : AppTheme.onSurface,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                    side: BorderSide(
                      color: selected ? AppTheme.primary : AppTheme.divider,
                    ),
                    backgroundColor: AppTheme.card,
                  );
                }).toList(),
              ),
              Slider(
                value: _value.toDouble(),
                min: widget.min.toDouble(),
                max: widget.max.toDouble(),
                divisions: widget.max - widget.min,
                label: '$_value',
                onChanged: (v) => _set(v.round()),
                onChangeEnd: (v) => _persist(v.round()),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Toggle which installed apps are blocked. Shows suggested apps first.
class AppBlockSetupPanel extends ConsumerWidget {
  final bool suggestedOnly;
  final EdgeInsetsGeometry? padding;

  const AppBlockSetupPanel({
    super.key,
    this.suggestedOnly = false,
    this.padding,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appsAsync = ref.watch(installedAppsProvider);
    final blockedAsync = ref.watch(blockedAppsProvider);

    return appsAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => Padding(
        padding: padding ?? EdgeInsets.zero,
        child: Text(
          'Could not load apps. Grant Usage Access in the previous step, '
          'then try again.\n$e',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      data: (apps) {
        final blockedSet = (blockedAsync.valueOrNull ?? const [])
            .where((b) => b.isBlocked)
            .map((b) => b.packageName)
            .toSet();

        final suggested = apps
            .where((a) => kSuggestedBlockPackages.contains(a.packageName))
            .toList()
          ..sort((a, b) => a.appName.compareTo(b.appName));

        final others = suggestedOnly
            ? <InstalledApp>[]
            : (apps
                  .where((a) =>
                      !kSuggestedBlockPackages.contains(a.packageName) &&
                      !a.isSystem)
                  .toList()
                ..sort((a, b) => a.appName.compareTo(b.appName)));

        final list = [...suggested, ...others];
        if (list.isEmpty) {
          return Padding(
            padding: padding ?? EdgeInsets.zero,
            child: Text(
              'No apps found yet. You can set this up later from the home screen.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }

        final blockedCount =
            list.where((a) => blockedSet.contains(a.packageName)).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (suggested.isNotEmpty && blockedCount == 0) ...[
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => blockSuggestedApps(ref, suggested),
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: Text('Block all suggested (${suggested.length})'),
                ),
              ),
              const SizedBox(height: 4),
            ],
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: padding ?? EdgeInsets.zero,
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final app = list[i];
                final isBlocked = blockedSet.contains(app.packageName);
                final isSuggested =
                    kSuggestedBlockPackages.contains(app.packageName);
                return _AppToggleRow(
                  app: app,
                  isBlocked: isBlocked,
                  isSuggested: isSuggested,
                  onChanged: (v) => toggleAppBlocked(
                    ref,
                    app: app,
                    blocked: v,
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _AppToggleRow extends StatelessWidget {
  final InstalledApp app;
  final bool isBlocked;
  final bool isSuggested;
  final ValueChanged<bool> onChanged;

  const _AppToggleRow({
    required this.app,
    required this.isBlocked,
    required this.isSuggested,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: SizedBox(
        width: 36,
        height: 36,
        child: app.icon != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(app.icon!, gaplessPlayback: true),
              )
            : const Icon(Icons.android, color: AppTheme.onSurfaceVariant),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(app.appName, overflow: TextOverflow.ellipsis),
          ),
          if (isSuggested) ...[
            const SizedBox(width: 6),
            const Icon(Icons.auto_awesome, size: 14, color: AppTheme.accent),
          ],
        ],
      ),
      trailing: Switch(value: isBlocked, onChanged: onChanged),
    );
  }
}

/// Per-deck toggles (multi scope). Simple list for onboarding and home.
class DeckStudySetupPanel extends ConsumerStatefulWidget {
  final EdgeInsetsGeometry? padding;

  const DeckStudySetupPanel({super.key, this.padding});

  @override
  ConsumerState<DeckStudySetupPanel> createState() =>
      _DeckStudySetupPanelState();
}

class _DeckStudySetupPanelState extends ConsumerState<DeckStudySetupPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureMultiMode());
  }

  Future<void> _ensureMultiMode() async {
    final scope = await ref.read(studyScopeProvider.future);
    if (scope.mode != StudyScopeMode.multi) {
      await ref.read(studyScopeServiceProvider).setMode(StudyScopeMode.multi);
      ref.invalidate(studyScopeProvider);
      ref.invalidate(studyCountsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(ankiDroidStatusProvider);
    final decksAsync = ref.watch(ankiDroidDecksProvider);
    final scopeAsync = ref.watch(studyScopeProvider);

    return statusAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Error: $e'),
      data: (status) {
        if (!status.isReady) {
          return Text(
            'Connect AnkiDroid first to choose which decks count toward '
            'your unlock goal.',
            style: Theme.of(context).textTheme.bodySmall,
          );
        }
        return decksAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: $e'),
          data: (decks) {
            if (decks.isEmpty) {
              return Text(
                'No decks found in AnkiDroid.',
                style: Theme.of(context).textTheme.bodySmall,
              );
            }
            return scopeAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
              data: (scope) {
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: widget.padding ?? EdgeInsets.zero,
                  itemCount: decks.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final deck = decks[i];
                    final enabled =
                        !scope.disabledDeckIds.contains(deck.id);
                    final subtitle = '${deck.newCount} new • '
                        '${deck.learnCount} learning • '
                        '${deck.reviewCount} review';
                    return SwitchListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 4),
                      secondary:
                          const Icon(Icons.style_outlined, size: 22),
                      title: Text(deck.name),
                      subtitle: Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      value: enabled,
                      onChanged: (v) async {
                        final svc = ref.read(studyScopeServiceProvider);
                        await svc.setDeckEnabled(deck.id, v);
                        ref.invalidate(studyScopeProvider);
                        ref.invalidate(studyCountsProvider);
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Summary line for enabled decks.
String formatDeckStudySummary(StudyScope scope, List<AnkiDroidDeck> decks) {
  if (decks.isEmpty) return 'No decks in AnkiDroid';
  final enabledIds = scope.filterDeckIds(decks.map((d) => d.id));
  if (enabledIds.isEmpty) return 'No decks selected';
  final enabled =
      decks.where((d) => enabledIds.contains(d.id)).toList();
  if (enabled.length == decks.length && scope.mode == StudyScopeMode.all) {
    return 'All ${decks.length} decks';
  }
  if (enabled.length == 1) return enabled.first.name;
  if (enabled.length <= 3) {
    return enabled.map((d) => d.name).join(', ');
  }
  return '${enabled.length} decks · ${enabled.take(2).map((d) => d.name).join(', ')}…';
}

int countDueInScope(StudyScope scope, List<AnkiDroidDeck> decks) {
  final enabledIds = scope.filterDeckIds(decks.map((d) => d.id)).toSet();
  return decks
      .where((d) => enabledIds.contains(d.id))
      .fold(0, (sum, d) => sum + d.totalDue);
}
