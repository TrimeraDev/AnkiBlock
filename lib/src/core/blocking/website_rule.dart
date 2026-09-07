// Website block-rule matching — Dart mirror of Kotlin WebsiteRules.
//
// Keep behavior in sync with android/.../WebsiteRules.kt.

class WebsiteRule {
  const WebsiteRule({
    required this.pattern,
    this.isRegex = false,
    String? label,
  }) : label = label ?? pattern;

  final String pattern;
  final bool isRegex;
  final String label;

  WebsiteRule copyWith({String? pattern, bool? isRegex, String? label}) {
    return WebsiteRule(
      pattern: pattern ?? this.pattern,
      isRegex: isRegex ?? this.isRegex,
      label: label ?? this.label,
    );
  }
}

/// Lowercase, strip scheme, strip leading www., drop fragment.
String normalizeWebsiteUrl(String raw) {
  var s = raw.trim().toLowerCase();
  if (s.isEmpty) return '';
  final schemeIdx = s.indexOf('://');
  if (schemeIdx >= 0) {
    s = s.substring(schemeIdx + 3);
  }
  // Drop credentials (user:pass@host) only in the authority, before path.
  final slash = s.indexOf('/');
  final authority = slash < 0 ? s : s.substring(0, slash);
  final at = authority.lastIndexOf('@');
  if (at >= 0) {
    final rest = slash < 0 ? '' : s.substring(slash);
    s = '${authority.substring(at + 1)}$rest';
  }
  final hash = s.indexOf('#');
  if (hash >= 0) s = s.substring(0, hash);
  if (s.startsWith('www.')) s = s.substring(4);
  return s;
}

String hostOfNormalized(String normalized) {
  final slash = normalized.indexOf('/');
  var host = slash < 0 ? normalized : normalized.substring(0, slash);
  // Drop port: youtube.com:443
  final colon = host.indexOf(':');
  if (colon > 0) host = host.substring(0, colon);
  return host;
}

String pathOfNormalized(String normalized) {
  final slash = normalized.indexOf('/');
  return slash < 0 ? '' : normalized.substring(slash);
}

/// Strip common mobile/amp vanity prefixes so m.youtube.com ≡ youtube.com.
/// Does not strip meaningful product subdomains (music., mail., etc.).
const _kVanityHostPrefixes = ['www.', 'm.', 'mobile.', 'mobi.', 'amp.'];

String canonicalHost(String host) {
  var h = host.trim().toLowerCase();
  if (h.isEmpty) return '';
  final colon = h.indexOf(':');
  if (colon > 0) h = h.substring(0, colon);
  var changed = true;
  while (changed) {
    changed = false;
    for (final prefix in _kVanityHostPrefixes) {
      if (h.startsWith(prefix) && h.length > prefix.length) {
        h = h.substring(prefix.length);
        changed = true;
        break;
      }
    }
  }
  return h;
}

/// Validates a user-entered pattern. Returns an error message or null.
String? validateWebsitePattern(String pattern, {required bool isRegex}) {
  final p = pattern.trim();
  if (p.isEmpty) return 'Enter a domain or pattern';
  if (isRegex) {
    try {
      RegExp(p, caseSensitive: false);
    } catch (_) {
      return 'Invalid regular expression';
    }
    return null;
  }
  // Simple: host[/path], optional *.
  final lower = p.toLowerCase();
  final slash = lower.indexOf('/');
  var host = slash < 0 ? lower : lower.substring(0, slash);
  if (host.startsWith('*.')) host = host.substring(2);
  if (host.isEmpty || !host.contains('.')) {
    return 'Use a domain like reddit.com or youtube.com/shorts';
  }
  if (host.contains(' ') || host.contains('://')) {
    return 'Do not include http:// — just the domain';
  }
  return null;
}

bool matchesSimplePattern(String pattern, String host, String path) {
  final p = pattern.trim().toLowerCase();
  if (p.isEmpty) return false;
  final slash = p.indexOf('/');
  var hostPat = slash < 0 ? p : p.substring(0, slash);
  final pathPat = slash < 0 ? '' : p.substring(slash);
  if (hostPat.startsWith('*.')) hostPat = hostPat.substring(2);
  if (hostPat.isEmpty) return false;

  final hostCanon = canonicalHost(host);
  final patCanon = canonicalHost(hostPat);
  // Exact apex, vanity-equivalent (m./www.), or real subdomain (music.youtube.com).
  final hostOk = hostCanon == patCanon ||
      host == patCanon ||
      host.endsWith('.$patCanon') ||
      hostCanon.endsWith('.$patCanon');
  if (!hostOk) return false;
  if (pathPat.isEmpty) return true;
  return path == pathPat ||
      path.startsWith('$pathPat/') ||
      path.startsWith(pathPat);
}

bool matchesRegexPattern(String pattern, String normalized) {
  try {
    return RegExp(pattern, caseSensitive: false).hasMatch(normalized);
  } catch (_) {
    return false;
  }
}

WebsiteRule? matchWebsiteRules(String rawUrl, List<WebsiteRule> rules) {
  if (rules.isEmpty) return null;
  final normalized = normalizeWebsiteUrl(rawUrl);
  if (normalized.isEmpty) return null;
  final host = hostOfNormalized(normalized);
  final path = pathOfNormalized(normalized);
  for (final rule in rules) {
    if (rule.isRegex) {
      if (matchesRegexPattern(rule.pattern, normalized)) return rule;
    } else if (matchesSimplePattern(rule.pattern, host, path)) {
      return rule;
    }
  }
  return null;
}

/// Suggested starter rules shown in the add-website UI.
const kSuggestedWebsitePatterns = <String>[
  'reddit.com',
  'x.com',
  'instagram.com',
  'tiktok.com',
  'youtube.com/shorts',
  'youtube.com',
];
