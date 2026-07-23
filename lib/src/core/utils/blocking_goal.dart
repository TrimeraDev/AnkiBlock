// Study mode, blocking mode, and settings-protection helpers.

enum StudyMode {
  dueCards,
  cardCount;

  static const String dueCardsValue = 'dueCards';
  static const String cardCountValue = 'cardCount';

  String get storageValue => switch (this) {
        StudyMode.dueCards => dueCardsValue,
        StudyMode.cardCount => cardCountValue,
      };

  static StudyMode fromStorage(String? raw) {
    if (raw == dueCardsValue) return StudyMode.dueCards;
    return StudyMode.cardCount;
  }

  String get label => switch (this) {
        StudyMode.dueCards => 'Anki queue',
        StudyMode.cardCount => 'Card count',
      };

  String get shortLabel => switch (this) {
        StudyMode.dueCards => 'Anki queue',
        StudyMode.cardCount => 'Card count',
      };

  String get subtitle => switch (this) {
        StudyMode.dueCards =>
          'Unlock when learning & reviews are done (AnkiDroid)',
        StudyMode.cardCount => 'Unlock after a fixed daily card goal',
      };
}

enum BlockingMode {
  selectedApps,
  lockdown;

  static const String selectedAppsValue = 'selectedApps';
  static const String lockdownValue = 'lockdown';

  String get storageValue => switch (this) {
        BlockingMode.selectedApps => selectedAppsValue,
        BlockingMode.lockdown => lockdownValue,
      };

  static BlockingMode fromStorage(String? raw) {
    if (raw == lockdownValue) return BlockingMode.lockdown;
    return BlockingMode.selectedApps;
  }

  String get label => switch (this) {
        BlockingMode.selectedApps => 'Block selected apps',
        BlockingMode.lockdown => 'Lock down phone',
      };
}

enum SettingsProtection {
  off,
  soft,
  strict;

  static const String offValue = 'off';
  static const String softValue = 'soft';
  static const String strictValue = 'strict';

  String get storageValue => switch (this) {
        SettingsProtection.off => offValue,
        SettingsProtection.soft => softValue,
        SettingsProtection.strict => strictValue,
      };

  static SettingsProtection fromStorage(String? raw) {
    if (raw == softValue) return SettingsProtection.soft;
    if (raw == strictValue) return SettingsProtection.strict;
    return SettingsProtection.off;
  }

  String get label => switch (this) {
        SettingsProtection.off => 'Off',
        SettingsProtection.soft => 'Soft',
        SettingsProtection.strict => 'Strict',
      };
}

/// Whether the active blocking goal is complete for the study day.
///
/// For [StudyMode.dueCards], [obligationDue] is learn + review (not new).
bool isBlockingGoalComplete({
  required StudyMode mode,
  required int dailyCardsGoal,
  required int cardsReviewed,
  required int obligationDue,
}) {
  return switch (mode) {
    StudyMode.dueCards => obligationDue <= 0,
    StudyMode.cardCount =>
      dailyCardsGoal > 0 && cardsReviewed >= dailyCardsGoal,
  };
}

/// Kinds of settings edits that may need protection.
enum ProtectedEditKind {
  disableBlocking,
  lowerDailyGoal,
  lowerUnlockGoal,
  unblockApp,
  shrinkDeckScope,
  loosenBypass,
  lowerProtection,
  switchToWeakerStudyMode,
  weakenBlockingMode,
}

bool isWeakeningDailyGoal({required int current, required int proposed}) =>
    proposed < current;

bool isWeakeningUnlockGoal({required int current, required int proposed}) =>
    proposed < current;

bool isWeakeningBypassCap({required int current, required int proposed}) =>
    proposed > current;

bool isWeakeningBypassSeconds({required int current, required int proposed}) =>
    proposed > current;

bool isWeakeningProtection({
  required SettingsProtection current,
  required SettingsProtection proposed,
}) {
  const rank = {
    SettingsProtection.off: 0,
    SettingsProtection.soft: 1,
    SettingsProtection.strict: 2,
  };
  return (rank[proposed] ?? 0) < (rank[current] ?? 0);
}

/// Lockdown → selected apps is weaker (fewer apps blocked).
bool isWeakeningBlockingMode({
  required BlockingMode current,
  required BlockingMode proposed,
}) {
  return current == BlockingMode.lockdown &&
      proposed == BlockingMode.selectedApps;
}

/// Switching from Anki-queue to card-count is weaker when obligation remains.
bool isWeakerStudyMode({
  required StudyMode current,
  required StudyMode proposed,
  required int obligationDue,
}) {
  if (current == proposed) return false;
  if (current == StudyMode.dueCards && proposed == StudyMode.cardCount) {
    return obligationDue > 0;
  }
  return false;
}
