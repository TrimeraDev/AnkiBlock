import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../di/providers.dart';
import '../utils/blocking_goal.dart';
import '../utils/deck_scope_format.dart';
import '../utils/study_day.dart';
import '../widgets/settings_protection_dialog.dart';
import 'settings_password_service.dart';
import 'study_launcher.dart';

const _prefsUnlockUntilKey = 'settings_protection_unlock_until_ms';
const _prefsStrictStudyPendingKey = 'settings_protection_strict_study_pending';
const _prefsStrictStudyCompletedAtKey =
    'settings_protection_strict_study_completed_at_ms';

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

  Future<void> _setStrictStudyPending(bool pending) async {
    final prefs = await SharedPreferences.getInstance();
    if (pending) {
      await prefs.setBool(_prefsStrictStudyPendingKey, true);
    } else {
      await prefs.remove(_prefsStrictStudyPendingKey);
    }
  }

  Future<bool> consumeStrictStudyPending() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_prefsStrictStudyPendingKey) ?? false)) return false;
    await prefs.remove(_prefsStrictStudyPendingKey);
    return true;
  }

  Future<void> recordStrictStudyCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _prefsStrictStudyCompletedAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> clearStrictStudyProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsStrictStudyPendingKey);
    await prefs.remove(_prefsStrictStudyCompletedAtKey);
  }

  Future<({StrictProtectionPhase phase, int waitRemaining})?>
      _strictDialogState() async {
    final prefs = await SharedPreferences.getInstance();
    final studiedAt = prefs.getInt(_prefsStrictStudyCompletedAtKey);
    if (studiedAt == null) {
      return (phase: StrictProtectionPhase.needsStudy, waitRemaining: 0);
    }
    final elapsed = DateTime.now().millisecondsSinceEpoch - studiedAt;
    final waitMs = kSettingsProtectionStrictWaitSeconds * 1000;
    if (elapsed < waitMs) {
      final remaining =
          ((waitMs - elapsed) / 1000).ceil().clamp(1, kSettingsProtectionStrictWaitSeconds);
      return (phase: StrictProtectionPhase.waiting, waitRemaining: remaining);
    }
    return (phase: StrictProtectionPhase.ready, waitRemaining: 0);
  }

  Future<void> _launchStrictStudySession(WidgetRef ref) async {
    final scope = await ref.read(studyScopeProvider.future);
    final decks = await ref.read(ankiDroidDecksProvider.future);
    final rule = await ref.read(blockRuleProvider.future);
    final unlockGoal = rule?.cardsRequired ?? 10;
    await startScopedStudySession(
      ref: ref,
      scope: scope,
      decks: decks,
      cardsRequired: unlockGoal,
      forGate: false,
    );
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
    WidgetRef ref,
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

    StrictProtectionPhase? strictPhase;
    var strictWaitRemaining = 0;
    if (protection == SettingsProtection.strict) {
      final strict = await _strictDialogState();
      if (strict != null) {
        strictPhase = strict.phase;
        strictWaitRemaining = strict.waitRemaining;
      }
    }

    final passwordRequired = (rule?.settingsPasswordEnabled ?? false) &&
        await _ref.read(settingsPasswordServiceProvider).isConfigured();
    final passwordService = _ref.read(settingsPasswordServiceProvider);

    final result = await showSettingsProtectionDialog(
      context,
      level: protection,
      unlockGoal: unlockGoal,
      unlockMinutes: unlockMinutes,
      kind: kind,
      strictPhase: strictPhase,
      strictWaitRemaining: strictWaitRemaining,
      passwordRequired: passwordRequired,
      onVerifyPassword:
          passwordRequired ? passwordService.verifyPassword : null,
    );

    if (result == SettingsProtectionDialogResult.cancelled) return false;
    if (result == SettingsProtectionDialogResult.allowedSoft) return true;
    if (result == SettingsProtectionDialogResult.allowedStrict) {
      await clearStrictStudyProgress();
      return true;
    }
    if (result == SettingsProtectionDialogResult.studyToUnlock) {
      await _setStrictStudyPending(true);
      await _launchStrictStudySession(ref);
      return false;
    }
    return false;
  }
}

final settingsProtectionServiceProvider =
    Provider<SettingsProtectionService>((ref) {
  return SettingsProtectionService(ref);
});
