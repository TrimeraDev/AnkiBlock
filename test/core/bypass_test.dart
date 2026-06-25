import 'package:flutter_test/flutter_test.dart';

import 'package:ankiblock/src/core/utils/bypass.dart';

void main() {
  group('bypassesRemaining', () {
    test('returns zero when disabled', () {
      expect(
        bypassesRemaining(
          bypassEnabled: false,
          bypassDailyCap: 2,
          bypassesUsed: 0,
        ),
        0,
      );
    });

    test('subtracts used bypasses from cap', () {
      expect(
        bypassesRemaining(
          bypassEnabled: true,
          bypassDailyCap: 2,
          bypassesUsed: 1,
        ),
        1,
      );
    });

    test('never goes negative', () {
      expect(
        bypassesRemaining(
          bypassEnabled: true,
          bypassDailyCap: 2,
          bypassesUsed: 5,
        ),
        0,
      );
    });
  });

  group('canUseBypass', () {
    test('true when bypasses remain', () {
      expect(
        canUseBypass(
          bypassEnabled: true,
          bypassDailyCap: 2,
          bypassesUsed: 0,
        ),
        isTrue,
      );
    });

    test('false when cap exhausted', () {
      expect(
        canUseBypass(
          bypassEnabled: true,
          bypassDailyCap: 2,
          bypassesUsed: 2,
        ),
        isFalse,
      );
    });
  });
}
