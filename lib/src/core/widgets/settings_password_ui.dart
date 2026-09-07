import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings_password_service.dart';
import '../services/settings_protection_service.dart';
import '../setup/setup_actions.dart';
import '../theme/app_theme.dart';
import '../utils/blocking_goal.dart';

String blockFutureYouSubtitle({
  required SettingsProtection protection,
  required bool passwordEnabled,
  required bool passwordConfigured,
}) {
  final detail = switch (protection) {
    SettingsProtection.off => 'No friction',
    SettingsProtection.soft => passwordEnabled && passwordConfigured
        ? '30s pause, then passphrase'
        : '30s pause, then confirm',
    SettingsProtection.strict => passwordEnabled && passwordConfigured
        ? 'Study, wait, then passphrase'
        : 'Study & wait, then confirm',
  };
  return '${protection.label} · $detail';
}

/// Full-screen bottom sheet for protection level + passphrase management.
Future<void> showBlockFutureYouSheet(
  BuildContext context,
  WidgetRef ref, {
  required SettingsProtection currentProtection,
  required bool passwordEnabled,
  required bool passwordConfigured,
  required int unlockGoal,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _BlockFutureYouSheet(
      currentProtection: currentProtection,
      passwordEnabled: passwordEnabled,
      passwordConfigured: passwordConfigured,
      unlockGoal: unlockGoal,
    ),
  );
}

class _BlockFutureYouSheet extends ConsumerStatefulWidget {
  final SettingsProtection currentProtection;
  final bool passwordEnabled;
  final bool passwordConfigured;
  final int unlockGoal;

  const _BlockFutureYouSheet({
    required this.currentProtection,
    required this.passwordEnabled,
    required this.passwordConfigured,
    required this.unlockGoal,
  });

  @override
  ConsumerState<_BlockFutureYouSheet> createState() =>
      _BlockFutureYouSheetState();
}

class _BlockFutureYouSheetState extends ConsumerState<_BlockFutureYouSheet> {
  late SettingsProtection _protection;
  late bool _passwordEnabled;
  var _passwordConfigured = false;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _protection = widget.currentProtection;
    _passwordEnabled = widget.passwordEnabled;
    _passwordConfigured = widget.passwordConfigured;
  }

  bool get _canUsePassword => _protection != SettingsProtection.off;

  Future<void> _setProtection(SettingsProtection chosen) async {
    if (chosen == _protection || _busy) return;
    if (isWeakeningProtection(current: _protection, proposed: chosen)) {
      final ok = await ref
          .read(settingsProtectionServiceProvider)
          .requestProtectedEdit(
            ref,
            context,
            kind: ProtectedEditKind.lowerProtection,
          );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await updateSettingsProtection(ref, protection: chosen.storageValue);
      if (!mounted) return;
      setState(() {
        _protection = chosen;
        _busy = false;
      });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _togglePassword(bool enabled) async {
    if (_busy) return;
    if (enabled) {
      final setup = await showSettingsPasswordSetupSheet(context, ref);
      if (!mounted || setup != true) return;
      setState(() => _busy = true);
      try {
        await updateSettingsProtection(ref, passwordEnabled: true);
        if (!mounted) return;
        setState(() {
          _passwordEnabled = true;
          _passwordConfigured = true;
          _busy = false;
        });
      } catch (_) {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }

    final disabled = await showSettingsPasswordDisableSheet(context, ref);
    if (!mounted || !disabled) return;
    setState(() => _busy = true);
    try {
      await updateSettingsProtection(ref, passwordEnabled: false);
      if (!mounted) return;
      setState(() {
        _passwordEnabled = false;
        _passwordConfigured = false;
        _busy = false;
      });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePassword() async {
    if (_busy) return;
    final changed = await showSettingsPasswordChangeSheet(context, ref);
    if (!mounted || changed != true) return;
    setState(() => _passwordConfigured = true);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(0, 12, 0, bottomInset + 16),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Block future-you',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Adds friction before weakening blocking settings while you '
                'still have reviews left.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.onSurfaceVariant,
                    ),
              ),
            ),
            const SizedBox(height: 8),
            for (final level in SettingsProtection.values)
              ListTile(
                enabled: !_busy,
                title: Text(level.label),
                subtitle: Text(switch (level) {
                  SettingsProtection.off => 'No friction',
                  SettingsProtection.soft => '30s pause before confirming',
                  SettingsProtection.strict =>
                    'Study ${widget.unlockGoal} cards, wait 30s',
                }),
                trailing: _protection == level
                    ? const Icon(Icons.check, color: AppTheme.accent)
                    : null,
                onTap: () => _setProtection(level),
              ),
            if (_canUsePassword) ...[
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.password_outlined),
                title: const Text('Require passphrase'),
                subtitle: const Text(
                  'Generate a phrase to write down or give to someone else',
                ),
                value: _passwordEnabled && _passwordConfigured,
                onChanged: _busy ? null : _togglePassword,
              ),
              if (_passwordEnabled && _passwordConfigured)
                ListTile(
                  enabled: !_busy,
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Change passphrase'),
                  subtitle: const Text('Creates a new recovery code'),
                  onTap: _changePassword,
                ),
            ],
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

/// Setup: generate passphrase, confirm saved, show recovery code.
Future<bool?> showSettingsPasswordSetupSheet(
  BuildContext context,
  WidgetRef ref,
) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: AppTheme.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => const _SettingsPasswordSetupSheet(),
  );
}

class _SettingsPasswordSetupSheet extends ConsumerStatefulWidget {
  const _SettingsPasswordSetupSheet();

  @override
  ConsumerState<_SettingsPasswordSetupSheet> createState() =>
      _SettingsPasswordSetupSheetState();
}

class _SettingsPasswordSetupSheetState
    extends ConsumerState<_SettingsPasswordSetupSheet> {
  static const _stepPassphrase = 0;
  static const _stepRecovery = 1;

  var _step = _stepPassphrase;
  late String _passphrase;
  String? _recoveryCode;
  var _savedChecked = false;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _passphrase =
        ref.read(settingsPasswordServiceProvider).generatePassphrase();
  }

  void _regenerate() {
    setState(() {
      _passphrase =
          ref.read(settingsPasswordServiceProvider).generatePassphrase();
      _savedChecked = false;
    });
  }

  Future<void> _continueToRecovery() async {
    if (!_savedChecked || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(settingsPasswordServiceProvider)
          .setupPassword(_passphrase);
      if (!mounted) return;
      setState(() {
        _recoveryCode = result.recoveryCode;
        _step = _stepRecovery;
        _busy = false;
      });
    } on SettingsPasswordChangeFailure {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    if (_busy) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomInset + 16),
      child: SafeArea(
        child: _step == _stepPassphrase
            ? _buildPassphraseStep(context)
            : _buildRecoveryStep(context),
      ),
    );
  }

  Widget _buildPassphraseStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your accountability passphrase',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Write this down or give it to someone you trust. You will need it '
          'to confirm changes that weaken blocking.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        _SecretCard(
          label: 'Passphrase',
          value: _passphrase,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _regenerate,
          icon: const Icon(Icons.refresh),
          label: const Text('Generate another'),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _savedChecked,
          onChanged: _busy
              ? null
              : (v) => setState(() => _savedChecked = v ?? false),
          title: const Text('I have saved this passphrase'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _savedChecked && !_busy ? _continueToRecovery : null,
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Continue'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildRecoveryStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Recovery code',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Store this separately from your passphrase. Use it to change or '
          'remove the passphrase if you lose the paper.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        _SecretCard(
          label: 'Recovery code',
          value: _recoveryCode ?? '',
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _finish,
          child: const Text('Done'),
        ),
      ],
    );
  }
}

Future<bool?> showSettingsPasswordChangeSheet(
  BuildContext context,
  WidgetRef ref,
) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => const _SettingsPasswordChangeSheet(),
  );
}

class _SettingsPasswordChangeSheet extends ConsumerStatefulWidget {
  const _SettingsPasswordChangeSheet();

  @override
  ConsumerState<_SettingsPasswordChangeSheet> createState() =>
      _SettingsPasswordChangeSheetState();
}

class _SettingsPasswordChangeSheetState
    extends ConsumerState<_SettingsPasswordChangeSheet> {
  final _currentController = TextEditingController();
  var _step = 0;
  late String _newPassphrase;
  String? _recoveryCode;
  var _savedChecked = false;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _newPassphrase =
        ref.read(settingsPasswordServiceProvider).generatePassphrase();
  }

  @override
  void dispose() {
    _currentController.dispose();
    super.dispose();
  }

  Future<void> _verifyCurrent() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ref
        .read(settingsPasswordServiceProvider)
        .verifyPassword(_currentController.text);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'Incorrect passphrase';
      });
      return;
    }
    setState(() {
      _busy = false;
      _step = 1;
    });
  }

  Future<void> _applyChange() async {
    if (!_savedChecked || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(settingsPasswordServiceProvider)
          .changePassword(
            currentPassword: _currentController.text,
            newPassword: _newPassphrase,
          );
      if (!mounted) return;
      setState(() {
        _recoveryCode = result?.recoveryCode;
        _step = 2;
        _busy = false;
      });
    } on SettingsPasswordChangeFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (e) {
          SettingsPasswordChangeFailure.invalidCurrentPassword =>
            'Incorrect passphrase',
          SettingsPasswordChangeFailure.passwordTooShort =>
            'Passphrase is too short',
          _ => 'Could not change passphrase',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomInset + 16),
      child: SafeArea(
        child: switch (_step) {
          0 => _buildCurrentStep(context),
          1 => _buildNewStep(context),
          _ => _buildRecoveryStep(context),
        },
      ),
    );
  }

  Widget _buildCurrentStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Change passphrase',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _currentController,
          autofocus: true,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Current passphrase',
            errorText: _error,
          ),
          onSubmitted: (_) => _verifyCurrent(),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _verifyCurrent,
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Continue'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildNewStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'New passphrase',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Write down the new phrase. Your old passphrase stops working.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        _SecretCard(label: 'New passphrase', value: _newPassphrase),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _newPassphrase = ref
                        .read(settingsPasswordServiceProvider)
                        .generatePassphrase();
                    _savedChecked = false;
                  }),
          icon: const Icon(Icons.refresh),
          label: const Text('Generate another'),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _savedChecked,
          onChanged:
              _busy ? null : (v) => setState(() => _savedChecked = v ?? false),
          title: const Text('I have saved the new passphrase'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _savedChecked && !_busy ? _applyChange : null,
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save new passphrase'),
        ),
      ],
    );
  }

  Widget _buildRecoveryStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'New recovery code',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Your previous recovery code no longer works.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        _SecretCard(label: 'Recovery code', value: _recoveryCode ?? ''),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

Future<bool> showSettingsPasswordDisableSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => const _SettingsPasswordDisableSheet(),
  );
  return result ?? false;
}

class _SettingsPasswordDisableSheet extends ConsumerStatefulWidget {
  const _SettingsPasswordDisableSheet();

  @override
  ConsumerState<_SettingsPasswordDisableSheet> createState() =>
      _SettingsPasswordDisableSheetState();
}

class _SettingsPasswordDisableSheetState
    extends ConsumerState<_SettingsPasswordDisableSheet> {
  final _controller = TextEditingController();
  var _useRecovery = false;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final svc = ref.read(settingsPasswordServiceProvider);
      if (_useRecovery) {
        await svc.disableWithRecovery(recoveryCode: _controller.text);
      } else {
        await svc.disable(currentPassword: _controller.text);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on SettingsPasswordChangeFailure {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            _useRecovery ? 'Incorrect recovery code' : 'Incorrect passphrase';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomInset + 16),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Remove passphrase?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Weakening settings will only use the timer or study steps.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              obscureText: !_useRecovery,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText:
                    _useRecovery ? 'Recovery code' : 'Current passphrase',
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _useRecovery = !_useRecovery;
                        _error = null;
                      }),
              child: Text(
                _useRecovery
                    ? 'Use passphrase instead'
                    : 'Use recovery code instead',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Remove passphrase'),
            ),
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecretCard extends StatelessWidget {
  final String label;
  final String value;

  const _SecretCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTheme.onSurfaceVariant,
                  letterSpacing: 1,
                ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: value.isEmpty
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: value));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied')),
                      );
                    },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy'),
            ),
          ),
        ],
      ),
    );
  }
}
