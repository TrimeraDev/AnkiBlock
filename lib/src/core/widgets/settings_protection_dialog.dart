import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/blocking_goal.dart';

enum SettingsProtectionDialogResult {
  cancelled,
  allowedSoft,
  studyToUnlock,
}

Future<SettingsProtectionDialogResult> showSettingsProtectionDialog(
  BuildContext context, {
  required SettingsProtection level,
  required int unlockGoal,
  required int unlockMinutes,
  required ProtectedEditKind kind,
}) {
  return showDialog<SettingsProtectionDialogResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _SettingsProtectionDialog(
      level: level,
      unlockGoal: unlockGoal,
      unlockMinutes: unlockMinutes,
      kind: kind,
    ),
  ).then((v) => v ?? SettingsProtectionDialogResult.cancelled);
}

class _SettingsProtectionDialog extends StatefulWidget {
  final SettingsProtection level;
  final int unlockGoal;
  final int unlockMinutes;
  final ProtectedEditKind kind;

  const _SettingsProtectionDialog({
    required this.level,
    required this.unlockGoal,
    required this.unlockMinutes,
    required this.kind,
  });

  @override
  State<_SettingsProtectionDialog> createState() =>
      _SettingsProtectionDialogState();
}

class _SettingsProtectionDialogState extends State<_SettingsProtectionDialog> {
  static const _softSeconds = 15;
  Timer? _timer;
  int _remaining = _softSeconds;

  @override
  void initState() {
    super.initState();
    if (widget.level == SettingsProtection.soft ||
        widget.level == SettingsProtection.strict) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_remaining <= 1) {
          _timer?.cancel();
          setState(() => _remaining = 0);
        } else {
          setState(() => _remaining -= 1);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _title {
    return switch (widget.kind) {
      ProtectedEditKind.disableBlocking => 'Disable blocking?',
      ProtectedEditKind.lowerDailyGoal => 'Lower daily goal?',
      ProtectedEditKind.lowerUnlockGoal => 'Lower unlock goal?',
      ProtectedEditKind.unblockApp => 'Unblock this app?',
      ProtectedEditKind.shrinkDeckScope => 'Remove decks from scope?',
      ProtectedEditKind.loosenBypass => 'Loosen emergency bypass?',
      ProtectedEditKind.lowerProtection => 'Lower settings protection?',
      ProtectedEditKind.switchToWeakerStudyMode => 'Switch study mode?',
      ProtectedEditKind.weakenBlockingMode => 'Leave phone lockdown?',
    };
  }

  @override
  Widget build(BuildContext context) {
    final canConfirmSoft = _remaining == 0;
    final isStrict = widget.level == SettingsProtection.strict;

    return AlertDialog(
      title: Text(_title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This change makes blocking easier to bypass. '
            'Stricter changes are always instant — this pause is only for '
            'weakening rules while you still have reviews left.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (!canConfirmSoft)
            Text(
              'Wait $_remaining seconds…',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppTheme.accent,
                    fontWeight: FontWeight.w600,
                  ),
            )
          else
            Text(
              'You can confirm now.',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppTheme.success,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          if (isStrict) ...[
            const SizedBox(height: 12),
            Text(
              'Or study ${widget.unlockGoal} cards to unlock settings for '
              '${widget.unlockMinutes} minutes.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(context, SettingsProtectionDialogResult.cancelled),
          child: const Text('Cancel'),
        ),
        if (isStrict)
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              SettingsProtectionDialogResult.studyToUnlock,
            ),
            child: const Text('Study to unlock'),
          ),
        FilledButton(
          onPressed: canConfirmSoft
              ? () => Navigator.pop(
                    context,
                    SettingsProtectionDialogResult.allowedSoft,
                  )
              : null,
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
