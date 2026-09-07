import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

const int kSettingsPasswordSaltBytes = 16;
const int kSettingsPasswordMinLength = 8;

/// Normalizes passphrases for comparison (trim, lowercase, collapse spaces).
String normalizeSettingsPassword(String input) {
  return input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

/// Normalizes recovery codes (strip separators, uppercase).
String normalizeRecoveryCode(String input) {
  return input
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[\s-]'), '');
}

bool isValidSettingsPassword(String input) {
  return normalizeSettingsPassword(input).length >= kSettingsPasswordMinLength;
}

String generateSaltBase64() {
  final bytes = List<int>.generate(
    kSettingsPasswordSaltBytes,
    (_) => Random.secure().nextInt(256),
  );
  return base64Encode(bytes);
}

String hashSecret({required String normalizedSecret, required String saltB64}) {
  final salt = base64Decode(saltB64);
  final digest = sha256.convert([...salt, ...utf8.encode(normalizedSecret)]);
  return base64Encode(digest.bytes);
}

bool verifySecret({
  required String input,
  required String saltB64,
  required String expectedHashB64,
  required String Function(String) normalize,
}) {
  final normalized = normalize(input);
  if (normalized.isEmpty) return false;
  final actual = hashSecret(normalizedSecret: normalized, saltB64: saltB64);
  return _constantTimeEquals(actual, expectedHashB64);
}

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
