import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/database.dart';
import '../../core/di/providers.dart';
import '../../core/setup/setup_actions.dart';
import '../../core/theme/app_theme.dart';
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
        data: (rule) => _buildList(context, ref, rule),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildList(BuildContext context, WidgetRef ref, BlockRule? rule) {
    final cards = rule?.cardsRequired ?? 10;
    final daily = rule?.dailyCardsGoal ?? 30;
    final minutes = rule?.unlockDurationMinutes ?? 10;
    final enabled = rule?.isEnabled ?? true;

    return ListView(
      children: [
        const _SectionHeader(label: 'Permissions'),
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: const Text('Permissions'),
          subtitle: const Text('Usage Access, Overlay, Notifications'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/permissions'),
        ),
        const Divider(),
        const _SectionHeader(label: 'Source'),
        ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('AnkiDroid sync'),
          subtitle: const Text(
            'AnkiBlock uses your AnkiDroid collection as the source of truth.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/ankidroid'),
        ),
        ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: const Text('Deck scope'),
          subtitle: const Text(
            'Choose which AnkiDroid decks AnkiBlock studies from.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/decks'),
        ),
        const Divider(),
        const _SectionHeader(label: 'Study goals'),
        ListTile(
          leading: const Icon(Icons.calendar_today_outlined),
          title: const Text('Daily goal'),
          subtitle: Text('$daily cards · unlocks all apps until 3am'),
          onTap: () async {
            final result = await _pickInt(
              context,
              title: 'Daily goal',
              initial: daily,
              min: 5,
              max: 200,
              suffix: 'cards',
            );
            if (result != null) {
              _save(ref, dailyCardsGoal: Value(result));
              await syncDailyGoalToNative(ref);
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.tune),
          title: const Text('Unlock goal'),
          subtitle: Text('$cards cards per blocked app'),
          onTap: () async {
            final result = await _pickInt(
              context,
              title: 'Cards per unlock',
              initial: cards,
              min: 1,
              max: 50,
              suffix: 'cards',
            );
            if (result != null) _save(ref, cardsRequired: Value(result));
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.shield_outlined),
          title: const Text('Blocking enabled'),
          subtitle: const Text(
              'When off, blocked apps open without requiring a study session.'),
          value: enabled,
          onChanged: (v) => _save(ref, isEnabled: Value(v)),
        ),
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: const Text('Per-app unlock grace'),
          subtitle: Text('$minutes minutes after a gate unlock'),
          onTap: () async {
            final result = await _pickInt(
              context,
              title: 'Unlock duration',
              initial: minutes,
              min: 1,
              max: 120,
              suffix: 'minutes',
            );
            if (result != null) {
              _save(ref, unlockDurationMinutes: Value(result));
            }
          },
        ),
        const Divider(),
        const _SectionHeader(label: 'About'),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('AnkiBlock'),
          subtitle: Text('1.0.0'),
        ),
      ],
    );
  }

  Future<void> _save(
    WidgetRef ref, {
    Value<int>? cardsRequired,
    Value<int>? dailyCardsGoal,
    Value<int>? unlockDurationMinutes,
    Value<bool>? isEnabled,
  }) async {
    final db = ref.read(databaseProvider);
    await db.updateBlockRule(BlockRulesCompanion(
      id: const Value(1),
      cardsRequired: cardsRequired ?? const Value.absent(),
      dailyCardsGoal: dailyCardsGoal ?? const Value.absent(),
      unlockDurationMinutes: unlockDurationMinutes ?? const Value.absent(),
      isEnabled: isEnabled ?? const Value.absent(),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
    ref.invalidate(blockRuleProvider);
  }

  Future<int?> _pickInt(
    BuildContext context, {
    required String title,
    required int initial,
    required int min,
    required int max,
    required String suffix,
  }) {
    int value = initial;
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$value $suffix',
                style: Theme.of(ctx).textTheme.headlineSmall,
              ),
              Slider(
                value: value.toDouble(),
                min: min.toDouble(),
                max: max.toDouble(),
                divisions: max - min,
                label: '$value',
                onChanged: (v) => setState(() => value = v.round()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, value),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
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
