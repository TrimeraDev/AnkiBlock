import 'dart:io';

import 'package:flutter/services.dart';

import 'study_scope_service.dart';

/// A single deck as exposed by AnkiDroid's ContentProvider, with the live
/// counts AnkiDroid would show in its own deck list.
class AnkiDroidDeck {
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

/// Thrown when AnkiDroid isn't installed or the permission isn't granted.
class AnkiDroidUnavailable implements Exception {
  final String message;
  AnkiDroidUnavailable(this.message);

  @override
  String toString() => 'AnkiDroidUnavailable: $message';
}

/// Talks to AnkiDroid via the `com.ankiblock/ankidroid` MethodChannel.
///
/// Every method is a no-op / "false" on non-Android platforms so callers can
/// use the same API on iOS or desktop without conditional code.
class AnkiDroidService {
  static const _channel = MethodChannel('com.ankiblock/ankidroid');

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

  /// Opens AnkiDroid's reviewer for [deckId] (native study UI with media).
  Future<bool> openAnkiDroidReviewer(int deckId) async {
    if (!_isSupportedPlatform) return false;
    try {
      final r = await _channel.invokeMethod<bool>(
        'openAnkiDroidReviewer',
        {'deckId': deckId},
      );
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

  Exception _mapException(PlatformException e) {
    if (e.code == 'UNAVAILABLE' || e.code == 'ANKIDROID_NOT_INSTALLED') {
      return AnkiDroidUnavailable(e.message ?? e.code);
    }
    return e;
  }
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
