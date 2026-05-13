import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// How AnkiBlock decides which AnkiDroid cards to study.
///
/// * [all]    — no filter, every deck contributes its due cards
///              (mirrors AnkiDroid's "study all decks" home behavior).
/// * [multi]  — user toggles individual decks on/off; cards are aggregated
///              across whichever are currently enabled. **Default.**
/// * [single] — exactly one deck is active at a time. The user picks it
///              from the AnkiDroid deck list.
enum StudyScopeMode { all, multi, single }

extension StudyScopeModeX on StudyScopeMode {
  String get storageKey => switch (this) {
        StudyScopeMode.all => 'all',
        StudyScopeMode.multi => 'multi',
        StudyScopeMode.single => 'single',
      };

  static StudyScopeMode fromStorageKey(String? raw) => switch (raw) {
        'all' => StudyScopeMode.all,
        'single' => StudyScopeMode.single,
        _ => StudyScopeMode.multi,
      };
}

/// Snapshot of the user's study-scope preferences. Immutable, cheap to pass
/// through Riverpod.
class StudyScope {
  /// Which selection strategy is in effect.
  final StudyScopeMode mode;

  /// In [StudyScopeMode.multi]: decks the user has explicitly disabled.
  /// Empty set means "all enabled" (the sane default after first connect).
  final Set<int> disabledDeckIds;

  /// In [StudyScopeMode.single]: the active deck. `null` means the user has
  /// not picked one yet.
  final int? activeDeckId;

  const StudyScope({
    required this.mode,
    required this.disabledDeckIds,
    required this.activeDeckId,
  });

  static const initial = StudyScope(
    mode: StudyScopeMode.multi,
    disabledDeckIds: <int>{},
    activeDeckId: null,
  );

  /// Apply this scope to a deck listing returned by AnkiDroid. The returned
  /// list preserves the input order and is what AnkiBlock should aggregate
  /// study cards from.
  List<int> filterDeckIds(Iterable<int> all) {
    switch (mode) {
      case StudyScopeMode.all:
        return all.toList();
      case StudyScopeMode.multi:
        return all.where((id) => !disabledDeckIds.contains(id)).toList();
      case StudyScopeMode.single:
        if (activeDeckId == null) return const [];
        return all.where((id) => id == activeDeckId).toList();
    }
  }

  StudyScope copyWith({
    StudyScopeMode? mode,
    Set<int>? disabledDeckIds,
    int? activeDeckId,
    bool clearActiveDeckId = false,
  }) {
    return StudyScope(
      mode: mode ?? this.mode,
      disabledDeckIds: disabledDeckIds ?? this.disabledDeckIds,
      activeDeckId:
          clearActiveDeckId ? null : (activeDeckId ?? this.activeDeckId),
    );
  }
}

/// Persists [StudyScope] in `SharedPreferences`. No Drift dependency on
/// purpose — these settings are user prefs, not collection data.
class StudyScopeService {
  static const _kMode = 'ankidroid_scope_mode';
  static const _kDisabledDeckIds = 'ankidroid_scope_disabled_deck_ids';
  static const _kActiveDeckId = 'ankidroid_scope_active_deck_id';

  Future<StudyScope> load() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = StudyScopeModeX.fromStorageKey(prefs.getString(_kMode));
    final disabledJson = prefs.getString(_kDisabledDeckIds);
    final disabled = <int>{};
    if (disabledJson != null && disabledJson.isNotEmpty) {
      try {
        final list = (jsonDecode(disabledJson) as List).cast<num>();
        disabled.addAll(list.map((n) => n.toInt()));
      } catch (_) {
        // Corrupt prefs — fall back to empty, never crash the app.
      }
    }
    final active = prefs.getInt(_kActiveDeckId);
    return StudyScope(
      mode: mode,
      disabledDeckIds: disabled,
      activeDeckId: active,
    );
  }

  Future<void> setMode(StudyScopeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMode, mode.storageKey);
  }

  Future<void> setDeckEnabled(int deckId, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await load();
    final next = Set<int>.from(current.disabledDeckIds);
    if (enabled) {
      next.remove(deckId);
    } else {
      next.add(deckId);
    }
    await prefs.setString(_kDisabledDeckIds, jsonEncode(next.toList()));
  }

  Future<void> setActiveDeck(int? deckId) async {
    final prefs = await SharedPreferences.getInstance();
    if (deckId == null) {
      await prefs.remove(_kActiveDeckId);
    } else {
      await prefs.setInt(_kActiveDeckId, deckId);
    }
  }
}
