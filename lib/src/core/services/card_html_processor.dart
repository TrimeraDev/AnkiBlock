import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'ankidroid_service.dart';

/// Result of inlining media into card HTML — useful for debug logging.
class MediaProcessResult {
  final List<String> referencedInHtml;
  final List<String> fromAnkiDroid;
  final List<String> resolved;
  final List<String> missing;

  const MediaProcessResult({
    this.referencedInHtml = const [],
    this.fromAnkiDroid = const [],
    this.resolved = const [],
    this.missing = const [],
  });

  bool get hasMissing => missing.isNotEmpty;
}

/// Pre-processes Anki-rendered HTML so it can be displayed offline inside a
/// WebView without needing a custom resource loader.
///
/// What it does: scans `src=` references in `<img>`, `<audio>`, `<source>`
/// and `<video>` tags. For each bare filename (e.g. `cat.jpg`), it looks the
/// file up in the user's AnkiDroid media folder via [AnkiDroidService] and
/// rewrites the `src` to a `data:…;base64,…` URI.
///
/// Also tries filenames from AnkiDroid's [AnkiDroidCard.mediaFiles] when a
/// direct lookup fails (disk name may differ from the name in HTML).
class CardHtmlProcessor {
  final AnkiDroidService service;

  /// Filename → data: URI cache. Keeps repeat answers / cloze siblings from
  /// re-reading the same image. Bounded only by the size of the user's
  /// media folder — fine for a study session.
  final Map<String, String> _cache = {};

  CardHtmlProcessor(this.service);

  /// Matches `src="foo.jpg"` and `src='foo.jpg'` (single- and double-quoted).
  static final RegExp _srcPattern =
      RegExp(r'''src=(["'])([^"']+)\1''', caseSensitive: false);

  /// Filenames referenced by `src=` in card HTML (bare names only).
  static List<String> filenamesInHtml(String html) {
    return _srcPattern
        .allMatches(html)
        .map((m) => m.group(2)!)
        .where(_needsResolving)
        .toSet()
        .toList();
  }

  /// Process [html], returning a new string with media references inlined.
  /// Pass [cardMediaFiles] from AnkiDroid's schedule row when available.
  Future<String> process(
    String html, {
    List<String> cardMediaFiles = const [],
  }) async {
    final result = await processWithReport(
      html,
      cardMediaFiles: cardMediaFiles,
    );
    return result.html;
  }

  Future<({String html, MediaProcessResult report})> processWithReport(
    String html, {
    List<String> cardMediaFiles = const [],
  }) async {
    final inHtml = filenamesInHtml(html);
    final fromAnki = cardMediaFiles
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && _needsResolving(s))
        .toSet()
        .toList();

    final toResolve = {...inHtml, ...fromAnki}.toList();
    if (toResolve.isEmpty) {
      return (html: html, report: MediaProcessResult(referencedInHtml: inHtml));
    }

    final hasAccess = await service.hasMediaAccess();
    if (!hasAccess) {
      _logMedia(
        'No media folder access — ${inHtml.length} src= in HTML, '
        '${fromAnki.length} from AnkiDroid media_files. '
        'Connect folder in Settings → AnkiDroid sync.',
        inHtml,
        fromAnki,
      );
      return (
        html: html,
        report: MediaProcessResult(
          referencedInHtml: inHtml,
          fromAnkiDroid: fromAnki,
          missing: toResolve,
        ),
      );
    }

    final resolved = <String>[];
    final missing = <String>[];

    await Future.wait(
      toResolve.map((name) async {
        final ok = await _resolve(name, fallbackNames: fromAnki);
        if (ok) {
          resolved.add(name);
        } else {
          missing.add(name);
        }
      }),
    );

    if (missing.isNotEmpty || kDebugMode) {
      _logMedia(
        'Media: ${resolved.length} resolved, ${missing.length} missing '
        '(html=${inHtml.length}, anki=${fromAnki.length})',
        inHtml,
        fromAnki,
        missing: missing,
      );
      if (missing.isNotEmpty && kDebugMode) {
        final probes = await service.probeMediaFiles(missing);
        for (final p in probes) {
          developer.log(
            '  probe ${p.filename} → disk=${p.diskName} found=${p.found} '
            'bytes=${p.bytes}',
            name: 'AnkiBlock.media',
          );
        }
      }
    }

    final patched = _patchHtml(html);
    return (
      html: patched,
      report: MediaProcessResult(
        referencedInHtml: inHtml,
        fromAnkiDroid: fromAnki,
        resolved: resolved,
        missing: missing,
      ),
    );
  }

  void _logMedia(
    String summary,
    List<String> inHtml,
    List<String> fromAnki, {
    List<String> missing = const [],
  }) {
    developer.log(summary, name: 'AnkiBlock.media');
    if (inHtml.isNotEmpty) {
      developer.log('  html src: ${inHtml.join(", ")}', name: 'AnkiBlock.media');
    }
    if (fromAnki.isNotEmpty) {
      developer.log(
        '  anki media_files: ${fromAnki.join(", ")}',
        name: 'AnkiBlock.media',
      );
    }
    if (missing.isNotEmpty) {
      developer.log('  missing: ${missing.join(", ")}', name: 'AnkiBlock.media');
    }
  }

  String _patchHtml(String html) {
    final matches = _srcPattern.allMatches(html).toList();
    if (matches.isEmpty) return html;

    final buf = StringBuffer();
    var cursor = 0;
    for (final m in matches) {
      final quote = m.group(1)!;
      final value = m.group(2)!;
      if (!_needsResolving(value)) continue;
      final dataUri = _cache[value];
      if (dataUri == null) continue;
      buf.write(html.substring(cursor, m.start));
      buf.write('src=$quote$dataUri$quote');
      cursor = m.end;
    }
    buf.write(html.substring(cursor));
    return buf.toString();
  }

  Future<bool> _resolve(
    String filename, {
    List<String> fallbackNames = const [],
  }) async {
    if (_cache.containsKey(filename)) return true;

    var bytes = await service.getMediaBytes(filename);
    if (bytes != null && bytes.isNotEmpty) {
      _cache[filename] = _toDataUri(filename, bytes);
      return true;
    }

    // HTML may reference a logical name while the file on disk uses another
    // name listed in ReviewInfo.media_files.
    for (final alt in fallbackNames) {
      if (alt == filename || _cache.containsKey(alt)) continue;
      bytes = await service.getMediaBytes(alt);
      if (bytes != null && bytes.isNotEmpty) {
        _cache[filename] = _toDataUri(filename, bytes);
        return true;
      }
    }

    return false;
  }

  static bool _needsResolving(String value) {
    if (value.isEmpty) return false;
    if (value.startsWith('data:')) return false;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return false;
    }
    if (value.startsWith('file://')) return false;
    if (value.contains('/')) return false;
    return true;
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
