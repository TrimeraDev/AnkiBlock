import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../di/providers.dart';
import '../utils/blocking_goal.dart';
import '../utils/deck_scope_format.dart';
import '../utils/study_day.dart';
import '../widgets/settings_protection_dialog.dart';

const _prefsUnlockUntilKey = 'settings_protection_unlock_until_ms';

/// Central gate for weakening settings edits.
class SettingsProtectionService {
  SettingsProtectionService(this._ref);

  final Ref _ref;

  Future<bool> hasTempUnlock() async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(_prefsUnlockUntilKey) ?? 0;
    return until > DateTime.now().millisecondsSinceEpoch;
  }

  Future<void> grantTempUnlock({required int minutes}) async {
    final prefs = await SharedPreferences.getInstance();
    final until = DateTime.now()
        .add(Duration(minutes: minutes.clamp(1, 120)))
        .millisecondsSinceEpoch;
    await prefs.setInt(_prefsUnlockUntilKey, until);
  }

  Future<void> clearTempUnlock() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsUnlockUntilKey);
  }

  /// Returns true when the edit may proceed without friction.
  Future<bool> canEditFreely() async {
    final rule = await _ref.read(blockRuleProvider.future);
    final protection =
        SettingsProtection.fromStorage(rule?.settingsProtection);
    if (protection == SettingsProtection.off) return true;
    if (!(rule?.isEnabled ?? true)) return true;
    if (await hasTempUnlock()) return true;

    final status = await _ref.read(ankiDroidStatusProvider.future);
    if (!status.isReady) return true;

    final scope = await _ref.read(studyScopeProvider.future);
    final decks = await _ref.read(ankiDroidDecksProvider.future);
    if (decks.isEmpty || !hasDecksInScope(scope, decks)) return true;

    final mode = StudyMode.fromStorage(rule?.studyMode);
    final day = studyDayKey();
    final reviewed =
        (await _ref.read(databaseProvider).getDailyStat(day))?.cardsReviewed ??
            0;
    final due = (await _ref.read(studyCountsProvider.future)).obligationDue;
    if (isBlockingGoalComplete(
      mode: mode,
      dailyCardsGoal: rule?.dailyCardsGoal ?? 30,
      cardsReviewed: reviewed,
      obligationDue: due,
    )) {
      return true;
    }
    return false;
  }

  /// Shows friction UI for a weakening edit. Returns true if the user may apply it.
  Future<bool> requestProtectedEdit(
    BuildContext context, {
    required ProtectedEditKind kind,
  }) async {
    if (await canEditFreely()) return true;

    final rule = await _ref.read(blockRuleProvider.future);
    final protection =
        SettingsProtection.fromStorage(rule?.settingsProtection);
    if (protection == SettingsProtection.off) return true;

    final unlockGoal = rule?.cardsRequired ?? 10;
    final unlockMinutes = rule?.settingsUnlockMinutes ?? 10;

    if (!context.mounted) return false;

    final result = await showSettingsProtectionDialog(
      context,
      level: protection,
      unlockGoal: unlockGoal,
      unlockMinutes: unlockMinutes,
      kind: kind,
    );

    if (result == SettingsProtectionDialogResult.cancelled) return false;
    if (result == SettingsProtectionDialogResult.allowedSoft) return true;
    if (result == SettingsProtectionDialogResult.studyToUnlock) {
      await grantTempUnlock(minutes: unlockMinutes);
      return true;
    }
    return false;
  }
}

final settingsProtectionServiceProvider =
    Provider<SettingsProtectionService>((ref) {
  return SettingsProtectionService(ref);
});
