import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/blocking_goal.dart';

enum SettingsProtectionDialogResult {
  cancelled,
  allowedSoft,
  allowedStrict,
  studyToUnlock,
}

/// Strict-mode step: study first, then wait, then continue.
enum StrictProtectionPhase {
  needsStudy,
  waiting,
  ready,
}

Future<SettingsProtectionDialogResult> showSettingsProtectionDialog(
  BuildContext context, {
  required SettingsProtection level,
  required int unlockGoal,
  required int unlockMinutes,
  required ProtectedEditKind kind,
  StrictProtectionPhase? strictPhase,
  int strictWaitRemaining = 0,
  bool passwordRequired = false,
  Future<bool> Function(String password)? onVerifyPassword,
}) {
  return showDialog<SettingsProtectionDialogResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _SettingsProtectionDialog(
      level: level,
      unlockGoal: unlockGoal,
      unlockMinutes: unlockMinutes,
      kind: kind,
      strictPhase: strictPhase,
      strictWaitRemaining: strictWaitRemaining,
      passwordRequired: passwordRequired,
      onVerifyPassword: onVerifyPassword,
    ),
  ).then((v) => v ?? SettingsProtectionDialogResult.cancelled);
}

class _SettingsProtectionDialog extends StatefulWidget {
  final SettingsProtection level;
  final int unlockGoal;
  final int unlockMinutes;
  final ProtectedEditKind kind;
  final StrictProtectionPhase? strictPhase;
  final int strictWaitRemaining;
  final bool passwordRequired;
  final Future<bool> Function(String password)? onVerifyPassword;

  const _SettingsProtectionDialog({
    required this.level,
    required this.unlockGoal,
    required this.unlockMinutes,
    required this.kind,
    this.strictPhase,
    this.strictWaitRemaining = 0,
    this.passwordRequired = false,
    this.onVerifyPassword,
  });

  @override
  State<_SettingsProtectionDialog> createState() =>
      _SettingsProtectionDialogState();
}

class _SettingsProtectionDialogState extends State<_SettingsProtectionDialog> {
  static const _softSeconds = kSettingsProtectionSoftWaitSeconds;
  static const _strictSeconds = kSettingsProtectionStrictWaitSeconds;

  Timer? _timer;
  int _remaining = 0;
  late StrictProtectionPhase? _strictPhase;
  final _passwordController = TextEditingController();
  var _verifying = false;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    _strictPhase = widget.strictPhase;
    if (widget.level == SettingsProtection.soft) {
      _remaining = _softSeconds;
      _startCountdown();
    } else if (widget.level == SettingsProtection.strict &&
        _strictPhase == StrictProtectionPhase.waiting) {
      _remaining = widget.strictWaitRemaining.clamp(1, _strictSeconds);
      _startCountdown();
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remaining <= 1) {
        _timer?.cancel();
        setState(() {
          _remaining = 0;
          if (widget.level == SettingsProtection.strict) {
            _strictPhase = StrictProtectionPhase.ready;
          }
        });
      } else {
        setState(() => _remaining -= 1);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _prerequisitesMet {
    return switch (widget.level) {
      SettingsProtection.soft => _remaining == 0,
      SettingsProtection.strict => _strictPhase == StrictProtectionPhase.ready,
      SettingsProtection.off => true,
    };
  }

  bool get _canSubmit =>
      _prerequisitesMet &&
      !_verifying &&
      (!widget.passwordRequired || _passwordController.text.isNotEmpty);

  Future<void> _submit(SettingsProtectionDialogResult result) async {
    if (!_prerequisitesMet || _verifying) return;
    if (widget.passwordRequired) {
      final verify = widget.onVerifyPassword;
      if (verify == null) return;
      setState(() {
        _verifying = true;
        _passwordError = null;
      });
      final ok = await verify(_passwordController.text);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _verifying = false;
          _passwordError = 'Incorrect passphrase';
        });
        return;
      }
    }
    if (!mounted) return;
    Navigator.pop(context, result);
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

  int get _strictStepCount => widget.passwordRequired ? 3 : 2;

  @override
  Widget build(BuildContext context) {
    final isSoft = widget.level == SettingsProtection.soft;
    final isStrict = widget.level == SettingsProtection.strict;

    return AlertDialog(
      title: Text(_title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isSoft
                  ? 'This change makes blocking easier to bypass. '
                      'Wait briefly before confirming while you still have '
                      'reviews left.'
                  : 'Strict mode: study ${widget.unlockGoal} cards in AnkiDroid, '
                      'then wait $_strictSeconds seconds. There is no shortcut.',
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
                  widget.passwordRequired
                      ? 'Enter your passphrase to confirm.'
                      : 'You can confirm now.',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppTheme.success,
                        fontWeight: FontWeight.w600,
                      ),
                ),
            ],
            if (isStrict) ...[
              const SizedBox(height: 16),
              Text(
                switch (_strictPhase) {
                  StrictProtectionPhase.needsStudy =>
                    'Step 1 of $_strictStepCount — study ${widget.unlockGoal} cards.',
                  StrictProtectionPhase.waiting =>
                    'Step 2 of $_strictStepCount — wait $_remaining seconds after studying.',
                  StrictProtectionPhase.ready => widget.passwordRequired
                      ? 'Step $_strictStepCount of $_strictStepCount — enter passphrase.'
                      : 'Done. You can apply this change now.',
                  null => '',
                },
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: _strictPhase == StrictProtectionPhase.ready
                          ? AppTheme.success
                          : AppTheme.accent,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
            if (widget.passwordRequired && _prerequisitesMet) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                autofocus: true,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Passphrase',
                  errorText: _passwordError,
                ),
                onChanged: (_) {
                  setState(() {
                    _passwordError = null;
                  });
                },
                onSubmitted: (_) {
                  if (_canSubmit) {
                    unawaited(_submit(
                      isSoft
                          ? SettingsProtectionDialogResult.allowedSoft
                          : SettingsProtectionDialogResult.allowedStrict,
                    ));
                  }
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _verifying
              ? null
              : () =>
                  Navigator.pop(context, SettingsProtectionDialogResult.cancelled),
          child: const Text('Cancel'),
        ),
        if (isStrict && _strictPhase == StrictProtectionPhase.needsStudy)
          FilledButton(
            onPressed: _verifying
                ? null
                : () => Navigator.pop(
                      context,
                      SettingsProtectionDialogResult.studyToUnlock,
                    ),
            child: Text('Study ${widget.unlockGoal} cards'),
          ),
        if (isStrict && _strictPhase == StrictProtectionPhase.ready)
          FilledButton(
            onPressed: _canSubmit
                ? () => _submit(SettingsProtectionDialogResult.allowedStrict)
                : null,
            child: _verifying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Continue'),
          ),
        if (isSoft)
          FilledButton(
            onPressed: _canSubmit
                ? () => _submit(SettingsProtectionDialogResult.allowedSoft)
                : null,
            child: _verifying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Confirm'),
          ),
      ],
    );
  }
}
