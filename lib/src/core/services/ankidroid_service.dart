import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/services.dart';

import 'study_scope_service.dart';

/// A single deck as exposed by AnkiDroid's ContentProvider, with the live
/// counts AnkiDroid would show in its own deck list.
class AnkiDroidDeck {
  /// AnkiDroid's deck id. Stable across syncs — this is the same `did` AnkiBlock
  /// stores as `decks.ankiDeckId` when a `.apkg` is imported.
  final int id;
  final String name;

  /// Cards currently in a learning/relearning step.
  final int learnCount;

  /// Reviews due today.
  final int reviewCount;

  /// New cards available today (already capped by AnkiDroid's per-deck limit).
  final int newCount;

  const AnkiDroidDeck({
    required this.id,
    required this.name,
    required this.learnCount,
    required this.reviewCount,
    required this.newCount,
  });

  int get totalDue => learnCount + reviewCount + newCount;

  factory AnkiDroidDeck.fromMap(Map<dynamic, dynamic> m) => AnkiDroidDeck(
        id: (m['id'] as num).toInt(),
        name: (m['name'] as String?) ?? '',
        learnCount: (m['learnCount'] as num?)?.toInt() ?? 0,
        reviewCount: (m['reviewCount'] as num?)?.toInt() ?? 0,
        newCount: (m['newCount'] as num?)?.toInt() ?? 0,
      );
}

/// One card returned by AnkiDroid's `schedule` endpoint, pre-rendered.
///
/// Identifying a card to AnkiDroid is done by `(noteId, cardOrd)` — the
/// internal card id is intentionally not surfaced because AnkiDroid uses
/// `(nid, ord)` as the canonical pair when answering.
class AnkiDroidCard {
  final int noteId;
  final int cardOrd;

  /// How many answer buttons this card supports (2, 3, or 4 depending on
  /// AnkiDroid's deck options and the card's state).
  final int buttonCount;

  /// Human-readable interval previews, e.g. `['<1m', '10m', '1d', '4d']`.
  /// Length matches [buttonCount].
  final List<String> nextReviewTimes;

  /// Pre-rendered question HTML (front side), with `{{cloze}}` etc resolved.
  final String questionHtml;

  /// Pre-rendered answer HTML (back side, includes the front).
  final String answerHtml;

  /// Media filenames referenced by this card (from ReviewInfo.MEDIA_FILES).
  final List<String> mediaFiles;

  const AnkiDroidCard({
    required this.noteId,
    required this.cardOrd,
    required this.buttonCount,
    required this.nextReviewTimes,
    required this.questionHtml,
    required this.answerHtml,
    this.mediaFiles = const [],
  });

  factory AnkiDroidCard.fromMap(Map<dynamic, dynamic> m) => AnkiDroidCard(
        noteId: (m['noteId'] as num).toInt(),
        cardOrd: (m['cardOrd'] as num?)?.toInt() ?? 0,
        buttonCount: (m['buttonCount'] as num?)?.toInt() ?? 4,
        nextReviewTimes:
            (m['nextReviewTimes'] as List?)?.cast<String>() ?? const [],
        questionHtml: (m['question'] as String?) ?? '',
        answerHtml: (m['answer'] as String?) ?? '',
        mediaFiles:
            (m['mediaFiles'] as List?)?.cast<String>() ?? const [],
      );
}

/// Rating numbers AnkiDroid expects on its `answer_ease` column.
/// We mirror the same 1..4 mapping Anki uses everywhere.
enum AnkiDroidEase {
  again(1),
  hard(2),
  good(3),
  easy(4);

  final int value;
  const AnkiDroidEase(this.value);
}

/// Thrown when AnkiDroid isn't installed or the permission isn't granted.
/// Callers should fall back to the local scheduler.
class AnkiDroidUnavailable implements Exception {
  final String message;
  AnkiDroidUnavailable(this.message);

  @override
  String toString() => 'AnkiDroidUnavailable: $message';
}

/// Talks to AnkiDroid via the `com.ankiblock/ankidroid` MethodChannel, and
/// to the SAF-backed media folder via `com.ankiblock/ankidroid_media`.
///
/// Every method is a no-op / "false" on non-Android platforms so callers can
/// use the same API on iOS or desktop without conditional code.
class AnkiDroidService {
  static const _channel = MethodChannel('com.ankiblock/ankidroid');
  static const _mediaChannel = MethodChannel('com.ankiblock/ankidroid_media');

  bool get _isSupportedPlatform => Platform.isAndroid;

  Future<bool> isInstalled() async {
    if (!_isSupportedPlatform) return false;
    try {
      final r = await _channel.invokeMethod<bool>('isInstalled');
      return r ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasPermission() async {
    if (!_isSupportedPlatform) return false;
    try {
      final r = await _channel.invokeMethod<bool>('hasPermission');
      return r ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Shows the system permission dialog. Resolves to `true` if granted.
  ///
  /// Throws [AnkiDroidUnavailable] when AnkiDroid isn't installed (caller
  /// should prompt the user to install it first).
  Future<bool> requestPermission() async {
    if (!_isSupportedPlatform) return false;
    try {
      final r = await _channel.invokeMethod<bool>('requestPermission');
      return r ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'ANKIDROID_NOT_INSTALLED') {
        throw AnkiDroidUnavailable(e.message ?? 'AnkiDroid not installed');
      }
      return false;
    }
  }

  /// Opens AnkiDroid (or its Play Store listing as a fallback) so the user
  /// can install it or grant the permission from system settings.
  Future<bool> openAnkiDroid() async {
    if (!_isSupportedPlatform) return false;
    try {
      final r = await _channel.invokeMethod<bool>('openAnkiDroid');
      return r ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<List<AnkiDroidDeck>> listDecks() async {
    if (!_isSupportedPlatform) return const [];
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('listDecks');
      if (result == null) return const [];
      return result
          .whereType<Map>()
          .map((m) => AnkiDroidDeck.fromMap(m))
          .toList();
    } on PlatformException catch (e) {
      throw _mapException(e);
    }
  }

  Future<List<AnkiDroidCard>> getStudyableCards({
    required int deckId,
    int limit = 50,
  }) async {
    if (!_isSupportedPlatform) return const [];
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'getStudyableCards',
        {'deckId': deckId, 'limit': limit},
      );
      if (result == null) return const [];
      return result
          .whereType<Map>()
          .map((m) => AnkiDroidCard.fromMap(m))
          .toList();
    } on PlatformException catch (e) {
      throw _mapException(e);
    }
  }

  /// Aggregates [getStudyableCards] across every deck enabled by [scope].
  ///
  /// We pull up to [limit] cards **from each deck** then truncate to [limit]
  /// after interleaving — that way a single huge deck cannot crowd out
  /// the rest of the user's collection, and the gate flow always gets a
  /// representative mix.
  ///
  /// Order: round-robin across decks, preserving each deck's internal
  /// AnkiDroid-chosen ordering (which already accounts for new vs learning
  /// vs review balance via AnkiDroid's scheduler).
  Future<List<AnkiDroidCard>> getStudyableCardsForScope({
    required StudyScope scope,
    int limit = 50,
  }) async {
    if (!_isSupportedPlatform || limit <= 0) return const [];
    final allDecks = await listDecks();
    final allowedIds =
        scope.filterDeckIds(allDecks.map((d) => d.id)).toSet();
    if (allowedIds.isEmpty) return const [];

    // Skip decks that AnkiDroid says have nothing studyable right now, so we
    // don't burn round-trips on them.
    final liveDeckIds = allDecks
        .where((d) => allowedIds.contains(d.id) && d.totalDue > 0)
        .map((d) => d.id)
        .toList();
    if (liveDeckIds.isEmpty) return const [];

    final perDeck = <List<AnkiDroidCard>>[];
    for (final id in liveDeckIds) {
      final cards = await getStudyableCards(deckId: id, limit: limit);
      if (cards.isNotEmpty) perDeck.add(cards);
    }
    return _interleave(perDeck, limit);
  }

  static List<AnkiDroidCard> _interleave(
    List<List<AnkiDroidCard>> piles,
    int limit,
  ) {
    final out = <AnkiDroidCard>[];
    final indices = List<int>.filled(piles.length, 0);
    while (out.length < limit) {
      var advanced = false;
      for (var p = 0; p < piles.length && out.length < limit; p++) {
        final i = indices[p];
        if (i < piles[p].length) {
          out.add(piles[p][i]);
          indices[p] = i + 1;
          advanced = true;
        }
      }
      if (!advanced) break;
    }
    return out;
  }

  /// Reports a review to AnkiDroid. Once this returns, AnkiDroid has updated
  /// its scheduler and (if the user has AnkiWeb auto-sync on) will sync the
  /// answer up to the cloud.
  Future<bool> answerCard({
    required int noteId,
    required int cardOrd,
    required AnkiDroidEase ease,
    Duration timeTaken = Duration.zero,
  }) async {
    if (!_isSupportedPlatform) return false;
    try {
      final r = await _channel.invokeMethod<bool>('answerCard', {
        'noteId': noteId,
        'cardOrd': cardOrd,
        'ease': ease.value,
        'timeTakenMs': timeTaken.inMilliseconds,
      });
      return r ?? false;
    } on PlatformException catch (e) {
      throw _mapException(e);
    }
  }

  /// Aggregated (learn / review / new) counts across the decks selected by
  /// [scope]. Used by the Today screen, the study gate, and the deck picker.
  Future<AnkiDroidCounts> getCountsForScope(StudyScope scope) async {
    if (!_isSupportedPlatform) return AnkiDroidCounts.zero;
    final all = await listDecks();
    final allowed = scope.filterDeckIds(all.map((d) => d.id)).toSet();
    if (allowed.isEmpty) return AnkiDroidCounts.zero;
    var learn = 0, review = 0, newC = 0;
    for (final d in all) {
      if (!allowed.contains(d.id)) continue;
      learn += d.learnCount;
      review += d.reviewCount;
      newC += d.newCount;
    }
    return AnkiDroidCounts(
      learnCount: learn,
      reviewCount: review,
      newCount: newC,
    );
  }

  /// Convenience: are we ready to talk to AnkiDroid right now?
  Future<AnkiDroidStatus> getStatus() async {
    final installed = await isInstalled();
    if (!installed) {
      return const AnkiDroidStatus(installed: false, permissionGranted: false);
    }
    final granted = await hasPermission();
    return AnkiDroidStatus(installed: true, permissionGranted: granted);
  }

  // ---------------------------------------------------------------- media

  /// True if the user has previously granted us a tree URI to their
  /// AnkiDroid folder and the grant is still valid.
  Future<bool> hasMediaAccess() async {
    if (!_isSupportedPlatform) return false;
    try {
      final r = await _mediaChannel.invokeMethod<bool>('hasMediaAccess');
      return r ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Launches the system folder picker so the user can grant us read access
  /// to their AnkiDroid folder. Resolves to `true` if the picked folder
  /// contains a `collection.media` subdirectory.
  Future<bool> pickAnkiDroidFolder() async {
    if (!_isSupportedPlatform) return false;
    try {
      final r =
          await _mediaChannel.invokeMethod<bool>('pickAnkiDroidFolder');
      return r ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Releases the tree URI permission and clears caches. Useful for "use a
  /// different folder" or recovering from a stale grant.
  Future<void> forgetMediaFolder() async {
    if (!_isSupportedPlatform) return;
    try {
      await _mediaChannel.invokeMethod('forgetFolder');
    } catch (_) {}
  }

  /// Loads a single file from the AnkiDroid media folder. Returns `null` if
  /// not found, not readable, or the user hasn't granted folder access.
  ///
  /// Cards reference media by bare filename (e.g. `<img src="cat.jpg">`),
  /// so we don't take a path here — only the leaf name.
  Future<Uint8List?> getMediaBytes(String filename) async {
    if (!_isSupportedPlatform || filename.isEmpty) return null;
    try {
      final r = await _mediaChannel.invokeMethod<Uint8List>(
        'getMediaBytes',
        {'filename': filename},
      );
      return r;
    } catch (_) {
      return null;
    }
  }

  /// Debug snapshot: SAF tree URI, resolved `collection.media`, sample files.
  Future<AnkiMediaDebugInfo> getMediaDebugInfo() async {
    if (!_isSupportedPlatform) {
      return const AnkiMediaDebugInfo(
        hasAccess: false,
        persistedPermission: false,
        hint:
            'Media access is only available on Android. Connect AnkiDroid first.',
      );
    }
    try {
      final m = await _mediaChannel.invokeMethod<Map<Object?, Object?>>(
        'getMediaDebugInfo',
      );
      return AnkiMediaDebugInfo.fromMap(m ?? {});
    } catch (_) {
      return const AnkiMediaDebugInfo(
        hasAccess: false,
        persistedPermission: false,
        hint: 'Could not read media debug info.',
      );
    }
  }

  /// Checks whether each [filenames] entry exists under `collection.media`.
  Future<List<AnkiMediaProbe>> probeMediaFiles(List<String> filenames) async {
    if (!_isSupportedPlatform || filenames.isEmpty) return const [];
    try {
      final r = await _mediaChannel.invokeMethod<List<Object?>>(
        'probeMediaFiles',
        {'filenames': filenames},
      );
      if (r == null) return const [];
      return r
          .whereType<Map>()
          .map((e) => AnkiMediaProbe.fromMap(Map<Object?, Object?>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Exception _mapException(PlatformException e) {
    if (e.code == 'UNAVAILABLE' || e.code == 'ANKIDROID_NOT_INSTALLED') {
      return AnkiDroidUnavailable(e.message ?? e.code);
    }
    return e;
  }
}

/// SAF media-folder status for debugging and the settings screen.
class AnkiMediaDebugInfo {
  final bool hasAccess;
  final bool persistedPermission;
  final String pickedFolderName;
  final String treeUri;
  final String mediaDirName;
  final String mediaDirUri;
  final String mediaDbName;
  final int mediaIndexEntries;
  final List<String> sampleFiles;

  /// Lines from a walk of the granted SAF tree (also in logcat: AnkiBlock.media).
  final List<String> folderListing;
  final List<String> mediaDbSchema;

  /// e.g. legacy_public_folder, ok, index_without_media_folder
  final String issue;
  final String recommendedPath;
  final String hint;

  const AnkiMediaDebugInfo({
    required this.hasAccess,
    required this.persistedPermission,
    this.pickedFolderName = '',
    this.treeUri = '',
    this.mediaDirName = '',
    this.mediaDirUri = '',
    this.mediaDbName = '',
    this.mediaIndexEntries = 0,
    this.sampleFiles = const [],
    this.folderListing = const [],
    this.mediaDbSchema = const [],
    this.issue = '',
    this.recommendedPath = '',
    this.hint = '',
  });

  bool get needsScopedAnkiDroidFolder => issue == 'legacy_public_folder';

  factory AnkiMediaDebugInfo.fromMap(Map<Object?, Object?> m) =>
      AnkiMediaDebugInfo(
        hasAccess: m['hasAccess'] == true,
        persistedPermission: m['persistedPermission'] == true,
        pickedFolderName: m['pickedFolderName'] as String? ?? '',
        treeUri: m['treeUri'] as String? ?? '',
        mediaDirName: m['mediaDirName'] as String? ?? '',
        mediaDirUri: m['mediaDirUri'] as String? ?? '',
        mediaDbName: m['mediaDbName'] as String? ?? '',
        mediaIndexEntries: (m['mediaIndexEntries'] as num?)?.toInt() ?? 0,
        sampleFiles: (m['sampleFiles'] as List?)?.cast<String>() ?? const [],
        folderListing: (m['folderListing'] as List?)?.cast<String>() ?? const [],
        mediaDbSchema: (m['mediaDbSchema'] as List?)?.cast<String>() ?? const [],
        issue: m['issue'] as String? ?? '',
        recommendedPath: m['recommendedPath'] as String? ?? '',
        hint: m['hint'] as String? ?? '',
      );
}

/// Logs [info.folderListing] (Kotlin also logs the same tag on Android).
void logMediaDebugToConsole(AnkiMediaDebugInfo info) {
  developer.log('─── folder listing (${info.folderListing.length} lines) ───',
      name: 'AnkiBlock.media');
  for (final line in info.folderListing) {
    developer.log(line, name: 'AnkiBlock.media');
  }
  developer.log('hint: ${info.hint}', name: 'AnkiBlock.media');
}

class AnkiMediaProbe {
  final String filename;
  final String normalized;
  final String diskName;
  final bool found;
  final int bytes;

  const AnkiMediaProbe({
    required this.filename,
    required this.normalized,
    this.diskName = '',
    required this.found,
    required this.bytes,
  });

  factory AnkiMediaProbe.fromMap(Map<Object?, Object?> m) => AnkiMediaProbe(
        filename: m['filename'] as String? ?? '',
        normalized: m['normalized'] as String? ?? '',
        diskName: m['diskName'] as String? ?? '',
        found: m['found'] == true,
        bytes: (m['bytes'] as num?)?.toInt() ?? 0,
      );
}

class AnkiDroidStatus {
  final bool installed;
  final bool permissionGranted;
  const AnkiDroidStatus({
    required this.installed,
    required this.permissionGranted,
  });

  bool get isReady => installed && permissionGranted;
}

/// Aggregated study counts across one or more AnkiDroid decks.
class AnkiDroidCounts {
  final int learnCount;
  final int reviewCount;
  final int newCount;

  const AnkiDroidCounts({
    required this.learnCount,
    required this.reviewCount,
    required this.newCount,
  });

  static const zero =
      AnkiDroidCounts(learnCount: 0, reviewCount: 0, newCount: 0);

  /// What AnkiBlock treats as the "size of the queue" — cards a user can
  /// actually answer right now.
  int get studyable => learnCount + reviewCount + newCount;

  /// Same shape the gate/today UI used to expect from the local DB
  /// (`due` = learn + review, `newCount` = new).
  ({int due, int newCount}) toDueNew() =>
      (due: learnCount + reviewCount, newCount: newCount);
}
