import 'dart:math';

import 'package:ankiblock/src/core/services/settings_password_service.dart';
import 'package:ankiblock/src/core/services/settings_password_store.dart';
import 'package:ankiblock/src/core/utils/settings_password_crypto.dart';
import 'package:ankiblock/src/core/utils/settings_password_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('settings password crypto', () {
    test('normalizeSettingsPassword trims and lowercases', () {
      expect(normalizeSettingsPassword('  Candle   Forest '), 'candle forest');
    });

    test('normalizeRecoveryCode strips separators', () {
      expect(normalizeRecoveryCode('abcd-efgh-ijkl'), 'ABCDEFGHIJKL');
    });

    test('verifySecret matches hashed value', () {
      const secret = 'candle forest marble quiet';
      final salt = generateSaltBase64();
      final hash = hashSecret(
        normalizedSecret: normalizeSettingsPassword(secret),
        saltB64: salt,
      );
      expect(
        verifySecret(
          input: '  Candle   Forest Marble Quiet ',
          saltB64: salt,
          expectedHashB64: hash,
          normalize: normalizeSettingsPassword,
        ),
        isTrue,
      );
      expect(
        verifySecret(
          input: 'wrong passphrase',
          saltB64: salt,
          expectedHashB64: hash,
          normalize: normalizeSettingsPassword,
        ),
        isFalse,
      );
    });
  });

  group('settings password generator', () {
    test('generateSettingsPassphrase returns four words', () {
      final phrase = generateSettingsPassphrase(
        random: _FakeRandom(List.generate(4, (i) => i)),
      );
      expect(phrase.split(' '), hasLength(4));
    });

    test('generateRecoveryCode formats groups', () {
      final code = generateRecoveryCode(
        random: _FakeRandom(List.generate(12, (i) => i)),
      );
      expect(code, matches(RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$')));
    });
  });

  group('SettingsPasswordService', () {
    late InMemorySettingsPasswordStore store;
    late SettingsPasswordService service;

    setUp(() {
      store = InMemorySettingsPasswordStore();
      service = SettingsPasswordService(store);
    });

    test('setup stores credentials and returns recovery code', () async {
      expect(await service.isConfigured(), isFalse);
      final result = await service.setupPassword('candle forest marble quiet');
      expect(result.recoveryCode, isNotEmpty);
      expect(await service.isConfigured(), isTrue);
      expect(await service.verifyPassword('candle forest marble quiet'), isTrue);
      expect(await service.verifyRecoveryCode(result.recoveryCode), isTrue);
    });

    test('changePassword requires current password', () async {
      await service.setupPassword('candle forest marble quiet');
      await expectLater(
        () => service.changePassword(
          currentPassword: 'wrong passphrase',
          newPassword: 'river stone silver dawn',
        ),
        throwsA(SettingsPasswordChangeFailure.invalidCurrentPassword),
      );
    });

    test('changePassword rotates passphrase and recovery code', () async {
      final first = await service.setupPassword('candle forest marble quiet');
      final second = await service.changePassword(
        currentPassword: 'candle forest marble quiet',
        newPassword: 'river stone silver dawn',
      );
      expect(second, isNotNull);
      expect(second!.recoveryCode, isNot(equals(first.recoveryCode)));
      expect(await service.verifyPassword('river stone silver dawn'), isTrue);
      expect(await service.verifyPassword('candle forest marble quiet'), isFalse);
      expect(await service.verifyRecoveryCode(first.recoveryCode), isFalse);
      expect(await service.verifyRecoveryCode(second.recoveryCode), isTrue);
    });

    test('changePasswordWithRecovery works without current password', () async {
      final first = await service.setupPassword('candle forest marble quiet');
      final second = await service.changePasswordWithRecovery(
        recoveryCode: first.recoveryCode,
        newPassword: 'river stone silver dawn',
      );
      expect(second, isNotNull);
      expect(await service.verifyPassword('river stone silver dawn'), isTrue);
      expect(await service.verifyRecoveryCode(first.recoveryCode), isFalse);
    });

    test('disable clears credentials after password check', () async {
      await service.setupPassword('candle forest marble quiet');
      await service.disable(currentPassword: 'candle forest marble quiet');
      expect(await service.isConfigured(), isFalse);
    });

    test('disableWithRecovery clears credentials', () async {
      final setup = await service.setupPassword('candle forest marble quiet');
      await service.disableWithRecovery(recoveryCode: setup.recoveryCode);
      expect(await service.isConfigured(), isFalse);
    });

    test('rejects passwords shorter than minimum', () async {
      await expectLater(
        () => service.setupPassword('short'),
        throwsA(SettingsPasswordChangeFailure.passwordTooShort),
      );
    });
  });
}

class _FakeRandom implements Random {
  _FakeRandom(this.values);

  final List<int> values;
  var _index = 0;

  @override
  int nextInt(int max) => values[_index++ % values.length] % max;

  @override
  bool nextBool() => nextInt(2) == 0;

  @override
  double nextDouble() => nextInt(1 << 30) / (1 << 30);
}
