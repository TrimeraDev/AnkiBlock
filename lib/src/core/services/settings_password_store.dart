import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storageKey = 'settings_password_credentials_v1';

/// Persisted credential bundle (hashes only — never plaintext secrets).
class SettingsPasswordCredentials {
  final String passwordHashB64;
  final String passwordSaltB64;
  final String recoveryHashB64;
  final String recoverySaltB64;

  const SettingsPasswordCredentials({
    required this.passwordHashB64,
    required this.passwordSaltB64,
    required this.recoveryHashB64,
    required this.recoverySaltB64,
  });

  Map<String, String> toJson() => {
        'passwordHashB64': passwordHashB64,
        'passwordSaltB64': passwordSaltB64,
        'recoveryHashB64': recoveryHashB64,
        'recoverySaltB64': recoverySaltB64,
      };

  factory SettingsPasswordCredentials.fromJson(Map<String, dynamic> json) {
    return SettingsPasswordCredentials(
      passwordHashB64: json['passwordHashB64'] as String,
      passwordSaltB64: json['passwordSaltB64'] as String,
      recoveryHashB64: json['recoveryHashB64'] as String,
      recoverySaltB64: json['recoverySaltB64'] as String,
    );
  }
}

abstract class SettingsPasswordStore {
  Future<SettingsPasswordCredentials?> read();
  Future<void> write(SettingsPasswordCredentials credentials);
  Future<void> clear();
}

class SecureSettingsPasswordStore implements SettingsPasswordStore {
  SecureSettingsPasswordStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<SettingsPasswordCredentials?> read() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return SettingsPasswordCredentials.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(SettingsPasswordCredentials credentials) async {
    await _storage.write(
      key: _storageKey,
      value: jsonEncode(credentials.toJson()),
    );
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _storageKey);
  }
}

/// In-memory store for unit tests.
class InMemorySettingsPasswordStore implements SettingsPasswordStore {
  SettingsPasswordCredentials? _credentials;

  @override
  Future<void> clear() async {
    _credentials = null;
  }

  @override
  Future<SettingsPasswordCredentials?> read() async => _credentials;

  @override
  Future<void> write(SettingsPasswordCredentials credentials) async {
    _credentials = credentials;
  }
}
