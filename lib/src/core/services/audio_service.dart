import 'package:flutter/foundation.dart';

/// Stub audio service.
///
/// We intentionally don't depend on a native audio package right now: the
/// available Android audio plugins (audioplayers, just_audio, etc.) all bring
/// JVM-target inconsistencies that force Gradle workarounds. The card
/// renderer still emits `[sound:...]` play buttons; tapping them is a no-op
/// here, and the Anki experience is otherwise complete.
///
/// Drop in a real implementation later by replacing [play] with a call to a
/// well-behaved audio package (and removing this comment).
class AudioService {
  Future<void> play(String absolutePath) async {
    if (kDebugMode) {
      debugPrint('[AudioService] play() called for $absolutePath '
          '(no-op: audio playback not enabled in this build)');
    }
  }

  Future<void> stop() async {}
  Future<void> dispose() async {}
}
