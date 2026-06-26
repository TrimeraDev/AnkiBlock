import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../services/apps_service.dart';
import '../setup/setup_actions.dart';
import '../theme/app_theme.dart';
import '../utils/app_usage_format.dart';
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

/// Toggle which installed apps are blocked, sorted by screen time.
class AppBlockSetupPanel extends ConsumerWidget {
  final bool showUsage;
  final bool shrinkWrap;
  final EdgeInsetsGeometry? padding;

  const AppBlockSetupPanel({
    super.key,
    this.showUsage = true,
    this.shrinkWrap = true,
    this.padding,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appsAsync = ref.watch(installedAppsProvider);
    final blockedAsync = ref.watch(blockedAppsProvider);

    return appsAsync.when(
      skipLoadingOnRefresh: true,
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

        int compareApps(InstalledApp a, InstalledApp b) {
          if (showUsage) {
            final cmp = b.usage.compareTo(a.usage);
            if (cmp != 0) return cmp;
          }
          return a.appName.compareTo(b.appName);
        }

        final list = apps.where((a) => !a.isSystem).toList()..sort(compareApps);

        final suggested = list
            .where((a) => kSuggestedSocialPackages.contains(a.packageName))
            .toList();
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

        final listView = ListView.separated(
          shrinkWrap: shrinkWrap,
          physics: shrinkWrap
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          padding: padding ?? EdgeInsets.zero,
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final app = list[i];
            final isBlocked = blockedSet.contains(app.packageName);
            final isSuggested =
                kSuggestedSocialPackages.contains(app.packageName);
            return _AppToggleRow(
              app: app,
              isBlocked: isBlocked,
              isSuggested: isSuggested,
              showUsage: showUsage,
              onChanged: (v) => toggleAppBlocked(
                ref,
                app: app,
                blocked: v,
              ),
            );
          },
        );

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
            if (shrinkWrap) listView else Expanded(child: listView),
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
  final bool showUsage;
  final ValueChanged<bool> onChanged;

  const _AppToggleRow({
    required this.app,
    required this.isBlocked,
    required this.isSuggested,
    this.showUsage = false,
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
                child: Image.memory(
                  app.icon!,
                  gaplessPlayback: true,
                  cacheWidth: 96,
                  cacheHeight: 96,
                ),
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showUsage) ...[
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatAppUsageDuration(app.usage),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  kAppUsagePeriodLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            const SizedBox(width: 8),
          ],
          Switch(value: isBlocked, onChanged: onChanged),
        ],
      ),
    );
  }
}
