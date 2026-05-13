import 'dart:convert';
import 'dart:typed_data';

import 'ankidroid_service.dart';

/// Pre-processes Anki-rendered HTML so it can be displayed offline inside a
/// WebView without needing a custom resource loader.
///
/// What it does: scans `src=` references in `<img>`, `<audio>`, `<source>`
/// and `<video>` tags. For each bare filename (e.g. `cat.jpg`), it looks the
/// file up in the user's AnkiDroid media folder via [AnkiDroidService] and
/// rewrites the `src` to a `data:…;base64,…` URI.
///
/// Anything else — absolute URLs, `data:` URIs, `file://`, `https://` — is
/// left alone.
///
/// We deliberately don't try to parse HTML "properly". Anki templates can be
/// arbitrarily messy and the cost of bringing in an HTML parser dependency
/// dwarfs the value. A small regex over `src=` is faster, predictable, and
/// covers the 99% case.
class CardHtmlProcessor {
  final AnkiDroidService service;

  /// Filename → data: URI cache. Keeps repeat answers / cloze siblings from
  /// re-reading the same image. Bounded only by the size of the user's
  /// media folder — fine for a study session.
  final Map<String, String> _cache = {};

  CardHtmlProcessor(this.service);

  /// Matches `src="foo.jpg"` and `src='foo.jpg'` (single- and double-quoted).
  /// Captures the quote in group 1 and the value in group 2. We do NOT
  /// support unquoted `src=foo.jpg` — Anki always emits quotes.
  static final RegExp _srcPattern =
      RegExp(r'''src=(["'])([^"']+)\1''', caseSensitive: false);

  /// Process [html], returning a new string with media references inlined.
  /// If [hasMediaAccess] was never granted, returns [html] unchanged so the
  /// WebView shows broken-image icons rather than blocking on missing
  /// permissions.
  Future<String> process(String html) async {
    final matches = _srcPattern.allMatches(html).toList();
    if (matches.isEmpty) return html;

    // Resolve all references in parallel — DocumentFile lookups are
    // independent and Kotlin runs each on its own worker thread anyway.
    final filenames = matches
        .map((m) => m.group(2)!)
        .where(_needsResolving)
        .toSet()
        .toList();
    if (filenames.isEmpty) return html;

    await Future.wait(filenames.map(_resolve));

    // Walk the matches in reverse and patch the string. Going in reverse
    // means earlier match offsets stay valid as we splice.
    final buf = StringBuffer();
    var cursor = 0;
    for (final m in matches) {
      final quote = m.group(1)!;
      final value = m.group(2)!;
      if (!_needsResolving(value)) continue;
      final dataUri = _cache[value];
      if (dataUri == null) continue; // not found — leave the original src
      buf.write(html.substring(cursor, m.start));
      buf.write('src=$quote$dataUri$quote');
      cursor = m.end;
    }
    buf.write(html.substring(cursor));
    return buf.toString();
  }

  bool _needsResolving(String value) {
    if (value.isEmpty) return false;
    if (value.startsWith('data:')) return false;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return false;
    }
    if (value.startsWith('file://')) return false;
    // Anki references are always bare filenames; if it looks like a path
    // (contains a slash), it's probably a template asset we don't own.
    if (value.contains('/')) return false;
    return true;
  }

  Future<void> _resolve(String filename) async {
    if (_cache.containsKey(filename)) return;
    final bytes = await service.getMediaBytes(filename);
    if (bytes == null || bytes.isEmpty) return;
    _cache[filename] = _toDataUri(filename, bytes);
  }

  static String _toDataUri(String filename, Uint8List bytes) {
    final mime = _mimeFor(filename);
    final b64 = base64Encode(bytes);
    return 'data:$mime;base64,$b64';
  }

  static String _mimeFor(String filename) {
    final dot = filename.lastIndexOf('.');
    final ext = dot < 0 ? '' : filename.substring(dot + 1).toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'svg' => 'image/svg+xml',
      'bmp' => 'image/bmp',
      'mp3' => 'audio/mpeg',
      'ogg' => 'audio/ogg',
      'wav' => 'audio/wav',
      'm4a' => 'audio/mp4',
      'mp4' => 'video/mp4',
      'webm' => 'video/webm',
      _ => 'application/octet-stream',
    };
  }
}
