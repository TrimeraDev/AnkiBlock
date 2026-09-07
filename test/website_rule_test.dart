import 'package:ankiblock/src/core/blocking/website_rule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeWebsiteUrl', () {
    test('strips scheme, www, and fragment', () {
      expect(
        normalizeWebsiteUrl('https://www.YouTube.com/shorts/abc#frag'),
        'youtube.com/shorts/abc',
      );
    });
  });

  group('simple patterns', () {
    test('host matches subdomains but not sibling domains', () {
      final rule = WebsiteRule(pattern: 'reddit.com');
      expect(
        matchWebsiteRules('https://old.reddit.com/r/foo', [rule])?.pattern,
        'reddit.com',
      );
      expect(
        matchWebsiteRules('https://m.reddit.com/', [rule])?.pattern,
        'reddit.com',
      );
      expect(matchWebsiteRules('https://notreddit.com/', [rule]), isNull);
    });

    test('youtube.com matches m.youtube.com and www', () {
      final rule = WebsiteRule(pattern: 'youtube.com');
      expect(
        matchWebsiteRules('https://m.youtube.com/watch?v=1', [rule])?.pattern,
        'youtube.com',
      );
      expect(
        matchWebsiteRules('https://www.youtube.com/', [rule])?.pattern,
        'youtube.com',
      );
      expect(
        matchWebsiteRules('https://music.youtube.com/', [rule])?.pattern,
        'youtube.com',
      );
      expect(
        matchWebsiteRules('https://notyoutube.com/', [rule]),
        isNull,
      );
    });

    test('m.youtube.com pattern also matches apex youtube.com', () {
      final rule = WebsiteRule(pattern: 'm.youtube.com');
      expect(
        matchWebsiteRules('https://youtube.com/', [rule])?.pattern,
        'm.youtube.com',
      );
      expect(
        matchWebsiteRules('https://www.youtube.com/watch', [rule])?.pattern,
        'm.youtube.com',
      );
      expect(
        matchWebsiteRules('https://m.youtube.com/shorts/x', [rule])?.pattern,
        'm.youtube.com',
      );
    });

    test('path prefix matches shorts', () {
      final rule = WebsiteRule(pattern: 'youtube.com/shorts');
      expect(
        matchWebsiteRules('m.youtube.com/shorts/xyz', [rule])?.pattern,
        'youtube.com/shorts',
      );
      expect(
        matchWebsiteRules('youtube.com/watch?v=1', [rule]),
        isNull,
      );
      expect(
        matchWebsiteRules('youtube.com/shorts', [rule])?.pattern,
        'youtube.com/shorts',
      );
    });

    test('*. prefix is accepted', () {
      final rule = WebsiteRule(pattern: '*.tiktok.com');
      expect(
        matchWebsiteRules('https://www.tiktok.com/@x', [rule])?.pattern,
        '*.tiktok.com',
      );
    });
  });

  group('regex patterns', () {
    test('matches path substring', () {
      final rule = WebsiteRule(pattern: r'youtube\.com/shorts', isRegex: true);
      expect(
        matchWebsiteRules('youtube.com/shorts/abc', [rule]),
        isNotNull,
      );
      expect(matchWebsiteRules('youtube.com/watch', [rule]), isNull);
    });

    test('invalid regex is ignored', () {
      final rule = WebsiteRule(pattern: r'(unclosed', isRegex: true);
      expect(matchWebsiteRules('anything.com', [rule]), isNull);
    });
  });

  group('validateWebsitePattern', () {
    test('rejects empty and scheme', () {
      expect(validateWebsitePattern('', isRegex: false), isNotNull);
      expect(
        validateWebsitePattern('https://reddit.com', isRegex: false),
        isNotNull,
      );
    });

    test('accepts host and path', () {
      expect(
        validateWebsitePattern('youtube.com/shorts', isRegex: false),
        isNull,
      );
    });
  });
}
