import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/settings_password_crypto.dart';
import '../utils/settings_password_generator.dart' as pwgen;
import 'settings_password_store.dart';

/// Result of creating or rotating the accountability passphrase.
class SettingsPasswordSetupResult {
  final String recoveryCode;

  const SettingsPasswordSetupResult({required this.recoveryCode});
}

enum SettingsPasswordChangeFailure {
  notConfigured,
  invalidCurrentPassword,
  invalidRecoveryCode,
  passwordTooShort,
}

/// Manages the accountability passphrase used to confirm weakening settings edits.
///
/// Secrets are stored as salted hashes in secure storage. The [enabled] flag in
/// [block_rules] is toggled separately once setup completes (Phase 3 UI).
class SettingsPasswordService {
  SettingsPasswordService(this._store);

  final SettingsPasswordStore _store;

  Future<bool> isConfigured() async => (await _store.read()) != null;

  String generatePassphrase() => pwgen.generateSettingsPassphrase();

  String generateRecoveryCode() => pwgen.generateRecoveryCode();

  Future<bool> verifyPassword(String password) async {
    final creds = await _store.read();
    if (creds == null) return false;
    return verifySecret(
      input: password,
      saltB64: creds.passwordSaltB64,
      expectedHashB64: creds.passwordHashB64,
      normalize: normalizeSettingsPassword,
    );
  }

  Future<bool> verifyRecoveryCode(String code) async {
    final creds = await _store.read();
    if (creds == null) return false;
    return verifySecret(
      input: code,
      saltB64: creds.recoverySaltB64,
      expectedHashB64: creds.recoveryHashB64,
      normalize: normalizeRecoveryCode,
    );
  }

  /// Creates credentials from a new passphrase. Returns the recovery code once.
  Future<SettingsPasswordSetupResult> setupPassword(String password) async {
    _ensureValidPassword(password);
    final recoveryCode = pwgen.generateRecoveryCode();
    await _store.write(_credentialsFor(password: password, recoveryCode: recoveryCode));
    return SettingsPasswordSetupResult(recoveryCode: recoveryCode);
  }

  /// Replaces the passphrase when the current one is known.
  Future<SettingsPasswordSetupResult?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (!await verifyPassword(currentPassword)) {
      throw SettingsPasswordChangeFailure.invalidCurrentPassword;
    }
    return _rotatePassword(newPassword);
  }

  /// Replaces the passphrase using the one-time recovery code.
  Future<SettingsPasswordSetupResult?> changePasswordWithRecovery({
    required String recoveryCode,
    required String newPassword,
  }) async {
    if (!await verifyRecoveryCode(recoveryCode)) {
      throw SettingsPasswordChangeFailure.invalidRecoveryCode;
    }
    return _rotatePassword(newPassword);
  }

  /// Removes stored credentials after verifying the current passphrase.
  Future<void> disable({required String currentPassword}) async {
    if (!await verifyPassword(currentPassword)) {
      throw SettingsPasswordChangeFailure.invalidCurrentPassword;
    }
    await _store.clear();
  }

  /// Removes stored credentials using the recovery code.
  Future<void> disableWithRecovery({required String recoveryCode}) async {
    if (!await verifyRecoveryCode(recoveryCode)) {
      throw SettingsPasswordChangeFailure.invalidRecoveryCode;
    }
    await _store.clear();
  }

  Future<SettingsPasswordSetupResult> _rotatePassword(String newPassword) async {
    _ensureValidPassword(newPassword);
    final recoveryCode = pwgen.generateRecoveryCode();
    await _store.write(_credentialsFor(password: newPassword, recoveryCode: recoveryCode));
    return SettingsPasswordSetupResult(recoveryCode: recoveryCode);
  }

  SettingsPasswordCredentials _credentialsFor({
    required String password,
    required String recoveryCode,
  }) {
    final passwordSalt = generateSaltBase64();
    final recoverySalt = generateSaltBase64();
    final normalizedPassword = normalizeSettingsPassword(password);
    final normalizedRecovery = normalizeRecoveryCode(recoveryCode);
    return SettingsPasswordCredentials(
      passwordHashB64: hashSecret(
        normalizedSecret: normalizedPassword,
        saltB64: passwordSalt,
      ),
      passwordSaltB64: passwordSalt,
      recoveryHashB64: hashSecret(
        normalizedSecret: normalizedRecovery,
        saltB64: recoverySalt,
      ),
      recoverySaltB64: recoverySalt,
    );
  }

  void _ensureValidPassword(String password) {
    if (!isValidSettingsPassword(password)) {
      throw SettingsPasswordChangeFailure.passwordTooShort;
    }
  }
}

final settingsPasswordStoreProvider = Provider<SettingsPasswordStore>((ref) {
  return SecureSettingsPasswordStore();
});

final settingsPasswordServiceProvider = Provider<SettingsPasswordService>((ref) {
  return SettingsPasswordService(ref.watch(settingsPasswordStoreProvider));
});

final settingsPasswordConfiguredProvider = FutureProvider<bool>((ref) async {
  return ref.watch(settingsPasswordServiceProvider).isConfigured();
});
