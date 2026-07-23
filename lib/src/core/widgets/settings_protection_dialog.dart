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
  static const _softSeconds = 30;
  Timer? _timer;
  int _remaining = 0;

  @override
  void initState() {
    super.initState();
    // Soft: wait before Confirm. Strict: no wait (Confirm + study option).
    if (widget.level == SettingsProtection.soft) {
      _remaining = _softSeconds;
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
    };
  }

  @override
  Widget build(BuildContext context) {
    final isSoft = widget.level == SettingsProtection.soft;
    final isStrict = widget.level == SettingsProtection.strict;
    final canConfirm = !isSoft || _remaining == 0;

    return AlertDialog(
      title: Text(_title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isSoft
                ? 'This change makes blocking easier to bypass. '
                    'Wait briefly before confirming while you still have '
                    'reviews left. Stricter changes are always instant.'
                : 'This change makes blocking easier to bypass. '
                    'Confirm to apply it once, or study to unlock settings '
                    'for a short window. Stricter changes are always instant.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (isSoft) ...[
            const SizedBox(height: 16),
            if (_remaining > 0)
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
          ],
          if (isStrict) ...[
            const SizedBox(height: 12),
            Text(
              'Study ${widget.unlockGoal} cards to unlock settings for '
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
          onPressed: canConfirm
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
