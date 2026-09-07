import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/database.dart';
import '../../core/constants/support_links.dart';
import '../../core/di/providers.dart';
import '../../core/services/settings_protection_service.dart';
import '../../core/services/settings_password_service.dart';
import '../../core/setup/setup_actions.dart';
import '../../core/support/support_actions.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/blocking_goal.dart';
import '../../core/widgets/settings_password_ui.dart';
import '../../core/widgets/stepped_value_picker.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ruleAsync = ref.watch(blockRuleProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ruleAsync.when(
        data: (rule) => _SettingsBody(rule: rule),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _SettingsBody extends ConsumerWidget {
  final BlockRule? rule;

  const _SettingsBody({required this.rule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = rule?.cardsRequired ?? 10;
    final daily = rule?.dailyCardsGoal ?? 30;
    final minutes = rule?.unlockDurationMinutes ?? 15;
    final bypassEnabled = rule?.bypassEnabled ?? true;
    final bypassCap = rule?.bypassDailyCap ?? 3;
    final enabled = rule?.isEnabled ?? true;
    final mode = StudyMode.fromStorage(rule?.studyMode);
    final protection =
        SettingsProtection.fromStorage(rule?.settingsProtection);
    final passwordEnabled = rule?.settingsPasswordEnabled ?? false;
    final passwordConfigured =
        ref.watch(settingsPasswordConfiguredProvider).valueOrNull ?? false;

    return ListView(
      children: [
        const _SectionHeader(label: 'Protection'),
        ListTile(
          leading: const Icon(Icons.lock_person_outlined),
          title: const Text('Block future-you'),
          subtitle: Text(
            blockFutureYouSubtitle(
              protection: protection,
              passwordEnabled: passwordEnabled,
              passwordConfigured: passwordConfigured,
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await showBlockFutureYouSheet(
              context,
              ref,
              currentProtection: protection,
              passwordEnabled: passwordEnabled,
              passwordConfigured: passwordConfigured,
              unlockGoal: cards,
            );
            ref.invalidate(settingsPasswordConfiguredProvider);
          },
        ),
        const Divider(),
        const _SectionHeader(label: 'Unlocking'),
        ListTile(
          leading: const Icon(Icons.flag_outlined),
          title: const Text('Daily freedom'),
          subtitle: Text(
            mode == StudyMode.dueCards
                ? 'Clear learning & reviews'
                : 'Fixed daily card count',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pickStudyMode(context, ref, mode),
        ),
        if (mode == StudyMode.cardCount)
          ListTile(
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('Daily card goal'),
            subtitle: Text('$daily cards · free until 3am'),
            onTap: () async {
              final result = await showSteppedValuePickerDialog(
                context,
                title: 'Daily card goal',
                initial: daily,
                min: 5,
                sliderMax: 100,
                suffix: 'cards',
              );
              if (result == null) return;
              if (isWeakeningDailyGoal(current: daily, proposed: result)) {
                final ok = await ref
                    .read(settingsProtectionServiceProvider)
                    .requestProtectedEdit(
                      ref,
                      context,
                      kind: ProtectedEditKind.lowerDailyGoal,
                    );
                if (!ok) return;
              }
              await _save(ref, dailyCardsGoal: Value(result));
              await syncDailyGoalToNative(ref);
            },
          ),
        ListTile(
          leading: const Icon(Icons.tune),
          title: const Text('Temporary unlock'),
          subtitle: Text('$cards cards · apps & sites for $minutes min'),
          onTap: () async {
            final result = await showSteppedValuePickerDialog(
              context,
              title: 'Temporary unlock',
              initial: cards,
              min: 5,
              sliderMax: 50,
              step: 5,
              suffix: 'cards',
            );
            if (result == null) return;
            if (isWeakeningUnlockGoal(current: cards, proposed: result)) {
              final ok = await ref
                  .read(settingsProtectionServiceProvider)
                  .requestProtectedEdit(
                    ref,
                    context,
                    kind: ProtectedEditKind.lowerUnlockGoal,
                  );
              if (!ok) return;
            }
            await _save(ref, cardsRequired: Value(result));
          },
        ),
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: const Text('Unlock length'),
          subtitle: Text('$minutes minutes'),
          onTap: () async {
            final result = await showSteppedValuePickerDialog(
              context,
              title: 'Unlock length',
              initial: minutes,
              min: 5,
              sliderMax: 60,
              step: 5,
              suffix: 'minutes',
            );
            if (result != null) {
              await _save(ref, unlockDurationMinutes: Value(result));
              await syncBlockRuleToNative(ref);
            }
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.shield_outlined),
          title: const Text('Blocking enabled'),
          subtitle: const Text('Off = blocked apps and sites open freely'),
          value: enabled,
          onChanged: (v) async {
            if (!v) {
              final ok = await ref
                  .read(settingsProtectionServiceProvider)
                  .requestProtectedEdit(
                    ref,
                    context,
                    kind: ProtectedEditKind.disableBlocking,
                  );
              if (!ok) return;
            }
            await _save(ref, isEnabled: Value(v));
          },
        ),
        const Divider(),
        const _SectionHeader(label: 'Emergency bypass'),
        SwitchListTile(
          secondary: const Icon(Icons.emergency_outlined),
          title: const Text('Emergency bypass'),
          subtitle: Text('${kBypassSeconds}s without studying'),
          value: bypassEnabled,
          onChanged: (v) async {
            if (v) {
              final ok = await ref
                  .read(settingsProtectionServiceProvider)
                  .requestProtectedEdit(
                    ref,
                    context,
                    kind: ProtectedEditKind.loosenBypass,
                  );
              if (!ok) return;
            }
            await _save(ref, bypassEnabled: Value(v));
          },
        ),
        ListTile(
          leading: const Icon(Icons.repeat),
          title: const Text('Bypasses per day'),
          subtitle: Text('$bypassCap per study day'),
          enabled: bypassEnabled,
          onTap: bypassEnabled
              ? () async {
                  final result = await showSteppedValuePickerDialog(
                    context,
                    title: 'Daily bypass limit',
                    initial: bypassCap,
                    min: 1,
                    sliderMax: 10,
                    suffix: 'uses',
                  );
                  if (result == null) return;
                  if (isWeakeningBypassCap(
                      current: bypassCap, proposed: result)) {
                    final ok = await ref
                        .read(settingsProtectionServiceProvider)
                        .requestProtectedEdit(
                          ref,
                          context,
                          kind: ProtectedEditKind.loosenBypass,
                        );
                    if (!ok) return;
                  }
                  await _save(ref, bypassDailyCap: Value(result));
                }
              : null,
        ),
        const Divider(),
        const _SectionHeader(label: 'Permissions'),
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: const Text('Permissions & AnkiDroid'),
          subtitle: const Text('Accessibility, usage, battery, AnkiDroid'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/permissions'),
        ),
        const Divider(),
        const _SectionHeader(label: 'Support'),
        ListTile(
          leading: const Icon(Icons.star_outline),
          title: const Text('Rate AnkiBlock'),
          onTap: () => openSupportLink(
            context,
            ref,
            (a) => a.requestAppReview(),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.local_cafe_outlined),
          title: const Text('Tip on Ko-fi'),
          onTap: () => openSupportLink(context, ref, (a) => a.openKofi()),
        ),
        ListTile(
          leading: const Icon(Icons.volunteer_activism_outlined),
          title: const Text('Tip on PayPal'),
          onTap: () => openSupportLink(context, ref, (a) => a.openPayPal()),
        ),
        ListTile(
          leading: const Icon(Icons.language),
          title: const Text('Privacy & project site'),
          onTap: () => openSupportLink(context, ref, (a) => a.openWebsite()),
        ),
        const Divider(),
        const _SectionHeader(label: 'About'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AnkiBlock · Version 1.0.0',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Free, no ads, open source.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => openSupportLink(
                  context,
                  ref,
                  (a) => a.openEmail(),
                ),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    SupportLinks.contactEmail,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.accent,
                        ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickStudyMode(
    BuildContext context,
    WidgetRef ref,
    StudyMode current,
  ) async {
    final due =
        ref.read(studyCountsProvider).valueOrNull?.obligationDue ?? 0;
    final chosen = await showModalBottomSheet<StudyMode>(
      context: context,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Clear learning & reviews'),
              subtitle: const Text('Recommended · free when queue is done'),
              trailing: current == StudyMode.dueCards
                  ? const Icon(Icons.check, color: AppTheme.accent)
                  : null,
              onTap: () => Navigator.pop(ctx, StudyMode.dueCards),
            ),
            ListTile(
              title: const Text('Fixed daily card count'),
              subtitle: const Text('Free until 3am after today\'s goal'),
              trailing: current == StudyMode.cardCount
                  ? const Icon(Icons.check, color: AppTheme.accent)
                  : null,
              onTap: () => Navigator.pop(ctx, StudyMode.cardCount),
            ),
          ],
        ),
      ),
    );
    if (chosen == null || chosen == current) return;
    if (isWeakerStudyMode(
      current: current,
      proposed: chosen,
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
    await updateStudyMode(ref, chosen.storageValue);
  }

  Future<void> _save(
    WidgetRef ref, {
    Value<int>? cardsRequired,
    Value<int>? dailyCardsGoal,
    Value<int>? unlockDurationMinutes,
    Value<bool>? bypassEnabled,
    Value<int>? bypassDailyCap,
    Value<bool>? isEnabled,
  }) async {
    final db = ref.read(databaseProvider);
    await db.updateBlockRule(BlockRulesCompanion(
      id: const Value(1),
      cardsRequired: cardsRequired ?? const Value.absent(),
      dailyCardsGoal: dailyCardsGoal ?? const Value.absent(),
      unlockDurationMinutes: unlockDurationMinutes ?? const Value.absent(),
      bypassEnabled: bypassEnabled ?? const Value.absent(),
      bypassDailyCap: bypassDailyCap ?? const Value.absent(),
      isEnabled: isEnabled ?? const Value.absent(),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
    ref.invalidate(blockRuleProvider);
    if (unlockDurationMinutes != null || isEnabled != null) {
      await syncBlockRuleToNative(ref);
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppTheme.onSurfaceVariant,
              letterSpacing: 1,
            ),
      ),
    );
  }
}
