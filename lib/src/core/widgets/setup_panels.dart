import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../services/apps_service.dart';
import '../services/settings_protection_service.dart';
import '../setup/setup_actions.dart';
import '../theme/app_theme.dart';
import '../utils/app_usage_format.dart';
import '../utils/blocking_goal.dart';
import 'brand_widgets.dart';
import 'stepped_value_picker.dart';

/// Study mode picker: due cards (default) vs fixed card count.
class StudyModePanel extends ConsumerWidget {
  final StudyMode mode;
  final int unlockGoal;
  final int dailyGoal;
  final bool showTitle;

  const StudyModePanel({
    super.key,
    required this.mode,
    required this.unlockGoal,
    required this.dailyGoal,
    this.showTitle = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle) ...[
          Text('Study mode', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Daily freedom for the day. Temporary unlock (below) is separate.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
        ],
        _ModeOption(
          selected: mode == StudyMode.dueCards,
          title: 'Clear learning & reviews',
          subtitle: 'Free when Anki learning + to-review hit zero.',
          badge: 'Recommended',
          onTap: () => updateStudyMode(ref, StudyMode.dueCardsValue),
        ),
        const SizedBox(height: 10),
        _ModeOption(
          selected: mode == StudyMode.cardCount,
          title: 'Fixed daily card count',
          subtitle: 'Free until 3am after today\'s card goal.',
          onTap: () async {
            final due =
                ref.read(studyCountsProvider).valueOrNull?.obligationDue ?? 0;
            if (isWeakerStudyMode(
              current: mode,
              proposed: StudyMode.cardCount,
              obligationDue: due,
            )) {
              final ok = await ref
                  .read(settingsProtectionServiceProvider)
                  .requestProtectedEdit(
                    ref,
                    context,
                    kind: ProtectedEditKind.switchToWeakerStudyMode,
                  );
              if (!ok) return;
            }
            await updateStudyMode(ref, StudyMode.cardCountValue);
          },
        ),
        const SizedBox(height: 20),
        if (mode == StudyMode.cardCount) ...[
          DailyGoalPanel(initial: dailyGoal, showTitle: true),
          const SizedBox(height: 24),
        ],
        UnlockGoalPanel(initial: unlockGoal, showTitle: true),
      ],
    );
  }
}

class _ModeOption extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  const _ModeOption({
    required this.selected,
    required this.title,
    required this.subtitle,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      color: selected ? AppTheme.accent.withValues(alpha: 0.12) : AppTheme.cardElevated,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? AppTheme.accent : AppTheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          badge!,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: AppTheme.accent,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Slider + text field for cards required per unlock.
class UnlockGoalPanel extends ConsumerStatefulWidget {
  final int initial;
  final int min;
  final int sliderMax;
  final bool showTitle;
  final ValueChanged<int>? onChanged;

  const UnlockGoalPanel({
    super.key,
    required this.initial,
    this.min = 5,
    this.sliderMax = 50,
    this.showTitle = true,
    this.onChanged,
  });

  @override
  ConsumerState<UnlockGoalPanel> createState() => _UnlockGoalPanelState();
}

class _UnlockGoalPanelState extends ConsumerState<UnlockGoalPanel> {
  static const _step = 5;

  late int _value;
  late int _committed;

  int _coerce(int raw) => raw < widget.min ? widget.min : raw;

  @override
  void initState() {
    super.initState();
    _value = _coerce(widget.initial);
    _committed = _value;
  }

  @override
  void didUpdateWidget(UnlockGoalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial != widget.initial) {
      _value = _coerce(widget.initial);
      _committed = _value;
    }
  }

  void _set(int v) {
    final next = _coerce(v);
    setState(() => _value = next);
    widget.onChanged?.call(next);
  }

  Future<void> _persist(int v) async {
    final next = _coerce(v);
    if (isWeakeningUnlockGoal(current: _committed, proposed: next)) {
      final ok = await ref
          .read(settingsProtectionServiceProvider)
          .requestProtectedEdit(
            ref,
            context,
            kind: ProtectedEditKind.lowerUnlockGoal,
          );
      if (!ok) {
        setState(() => _value = _committed);
        return;
      }
    }
    await updateCardsRequired(ref, next);
    setState(() => _committed = next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showTitle) ...[
          Text('Temporary unlock', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Short unlock for all blocked apps and sites — not the whole day.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
        ],
        BrandCard(
          color: AppTheme.cardElevated,
          child: SteppedValuePicker(
            value: _value,
            min: widget.min,
            sliderMax: widget.sliderMax,
            step: _step,
            suffix: 'cards',
            onChanged: _set,
            onCommit: _persist,
          ),
        ),
      ],
    );
  }
}

/// Slider + text field for the daily study target (unlocks everything until 3am).
class DailyGoalPanel extends ConsumerStatefulWidget {
  final int initial;
  final int min;
  final int sliderMax;
  final bool showTitle;
  final ValueChanged<int>? onChanged;

  const DailyGoalPanel({
    super.key,
    required this.initial,
    this.min = 5,
    this.sliderMax = 100,
    this.showTitle = true,
    this.onChanged,
  });

  @override
  ConsumerState<DailyGoalPanel> createState() => _DailyGoalPanelState();
}

class _DailyGoalPanelState extends ConsumerState<DailyGoalPanel> {
  late int _value;
  late int _committed;

  int _coerce(int raw) => raw < widget.min ? widget.min : raw;

  @override
  void initState() {
    super.initState();
    _value = _coerce(widget.initial);
    _committed = _value;
  }

  @override
  void didUpdateWidget(DailyGoalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial != widget.initial) {
      _value = _coerce(widget.initial);
      _committed = _value;
    }
  }

  void _set(int v) {
    final next = _coerce(v);
    setState(() => _value = next);
    widget.onChanged?.call(next);
  }

  Future<void> _persist(int v) async {
    final next = _coerce(v);
    if (isWeakeningDailyGoal(current: _committed, proposed: next)) {
      final ok = await ref
          .read(settingsProtectionServiceProvider)
          .requestProtectedEdit(
            ref,
            context,
            kind: ProtectedEditKind.lowerDailyGoal,
          );
      if (!ok) {
        setState(() => _value = _committed);
        return;
      }
    }
    await updateDailyCardsGoal(ref, next);
    setState(() => _committed = next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showTitle) ...[
          Text('Daily card goal', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Full-day freedom until 3am.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
        ],
        BrandCard(
          color: AppTheme.cardElevated,
          child: SteppedValuePicker(
            value: _value,
            min: widget.min,
            sliderMax: widget.sliderMax,
            suffix: 'cards per day',
            onChanged: _set,
            onCommit: _persist,
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
          'Could not load apps. Pull to refresh, or open Permissions '
          'if the list stays empty.\n$e',
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
            .where((a) => kSuggestedBlockPackages.contains(a.packageName))
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
                kSuggestedBlockPackages.contains(app.packageName);
            return _AppToggleRow(
              app: app,
              isBlocked: isBlocked,
              isSuggested: isSuggested,
              showUsage: showUsage,
              onChanged: (v) => toggleAppBlocked(
                ref,
                app: app,
                blocked: v,
                context: context,
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
