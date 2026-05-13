import 'package:shared_preferences/shared_preferences.dart';

/// How AnkiBlock picks which AnkiDroid decks count as "in scope" when
/// building a study session or aggregating counts.
enum DeckScopeMode {
  /// Use every deck AnkiDroid knows about. Mirrors AnkiDroid's own home
  /// screen behavior. [enabledDeckIds] is ignored.
  all,

  /// Use a user-curated subset of decks. The default mode — every deck
  /// starts enabled, and the user can toggle individual decks off.
  multi,

  /// Use exactly one deck. [enabledDeckIds] holds a single id.
  single;

  static DeckScopeMode fromString(String? raw) {
    return switch (raw) {
      'all' => DeckScopeMode.all,
      'single' => DeckScopeMode.single,
      _ => DeckScopeMode.multi,
    };
  }

  String get key => switch (this) {
        DeckScopeMode.all => 'all',
        DeckScopeMode.multi => 'multi',
        DeckScopeMode.single => 'single',
      };
}

/// Resolved view of the user's deck scope: the [mode] they chose plus the
/// concrete set of AnkiDroid deck ids that mode currently selects.
///
/// For [DeckScopeMode.all] we keep [enabledDeckIds] empty — callers should
/// treat that as "no filter". Use [resolveAgainst] to materialize the
/// effective set given the live AnkiDroid deck list.
class DeckScope {
  final DeckScopeMode mode;
  final Set<int> enabledDeckIds;

  const DeckScope({required this.mode, required this.enabledDeckIds});

  /// Returns the set of deck ids that should actually be studied / counted,
  /// given the live AnkiDroid deck ids in [available].
  ///
  /// - [DeckScopeMode.all] → every available deck.
  /// - [DeckScopeMode.multi] → intersection (drops stale ids from removed decks).
  /// - [DeckScopeMode.single] → the single stored id, if still present.
  Set<int> resolveAgainst(Iterable<int> available) {
    final avail = available.toSet();
    switch (mode) {
      case DeckScopeMode.all:
        return avail;
      case DeckScopeMode.multi:
        if (enabledDeckIds.isEmpty) return avail;
        return enabledDeckIds.intersection(avail);
      case DeckScopeMode.single:
        return enabledDeckIds.intersection(avail);
    }
  }
}

/// Persists which AnkiDroid decks AnkiBlock should treat as "studyable".
///
/// Stored in [SharedPreferences] (rather than Drift) because:
/// 1. The list is tiny.
/// 2. AnkiDroid is the source of truth for the deck list itself — we only
///    keep references, not deck metadata, so a relational table would be
///    overkill.
/// 3. We can wipe / restore without touching the user's study data.
class DeckScopeService {
  static const String _kMode = 'deck_scope_mode';
  static const String _kEnabledIds = 'deck_scope_enabled_ids';
  static const String _kFirstSyncDone = 'deck_scope_first_sync_done';

  final Future<SharedPreferences> _prefsFuture;

  DeckScopeService({Future<SharedPreferences>? prefs})
      : _prefsFuture = prefs ?? SharedPreferences.getInstance();

  Future<DeckScope> read() async {
    final prefs = await _prefsFuture;
    final mode = DeckScopeMode.fromString(prefs.getString(_kMode));
    final ids = (prefs.getStringList(_kEnabledIds) ?? const <String>[])
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
    return DeckScope(mode: mode, enabledDeckIds: ids);
  }

  Future<void> setMode(DeckScopeMode mode) async {
    final prefs = await _prefsFuture;
    await prefs.setString(_kMode, mode.key);
  }

  /// In multi-deck mode, flip one deck on/off.
  Future<void> setDeckEnabled(int deckId, bool enabled) async {
    final prefs = await _prefsFuture;
    final ids = (prefs.getStringList(_kEnabledIds) ?? const <String>[]).toSet();
    if (enabled) {
      ids.add(deckId.toString());
    } else {
      ids.remove(deckId.toString());
    }
    await prefs.setStringList(_kEnabledIds, ids.toList());
  }

  /// In single-deck mode, pick the one active deck.
  Future<void> setSingleDeck(int deckId) async {
    final prefs = await _prefsFuture;
    await prefs.setStringList(_kEnabledIds, [deckId.toString()]);
  }

  /// Replaces the enabled set with [ids] verbatim. Used by "Enable all" /
  /// "Disable all" buttons in the UI.
  Future<void> setEnabledIds(Iterable<int> ids) async {
    final prefs = await _prefsFuture;
    await prefs.setStringList(
      _kEnabledIds,
      ids.map((i) => i.toString()).toList(),
    );
  }

  /// First-run bootstrap: the very first time we see the user's AnkiDroid
  /// deck list, enable every deck so the default "multi-deck, all on"
  /// behavior matches user expectation. Idempotent — only runs once.
  Future<void> ensureFirstSyncDefaults(Iterable<int> availableIds) async {
    final prefs = await _prefsFuture;
    if (prefs.getBool(_kFirstSyncDone) ?? false) return;
    await prefs.setStringList(
      _kEnabledIds,
      availableIds.map((i) => i.toString()).toList(),
    );
    await prefs.setBool(_kFirstSyncDone, true);
  }

  /// Test helper: wipes everything so the next [ensureFirstSyncDefaults]
  /// behaves as if we'd never seen any decks before.
  Future<void> resetForTest() async {
    final prefs = await _prefsFuture;
    await prefs.remove(_kMode);
    await prefs.remove(_kEnabledIds);
    await prefs.remove(_kFirstSyncDone);
  }
}
