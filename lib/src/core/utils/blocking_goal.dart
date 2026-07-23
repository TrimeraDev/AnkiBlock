// Study mode and settings-protection helpers shared by Flutter + edit paths.

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
        StudyMode.dueCards => 'Clear learning & reviews',
        StudyMode.cardCount => 'Card count',
      };

  String get shortLabel => switch (this) {
        StudyMode.dueCards => 'Learning & reviews',
        StudyMode.cardCount => 'Card count',
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
/// [obligationDue] is Anki's learning + to-review count (excludes new cards).
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
}

bool isWeakeningDailyGoal({required int current, required int proposed}) =>
    proposed < current;

bool isWeakeningUnlockGoal({required int current, required int proposed}) =>
    proposed < current;

bool isWeakeningBypassCap({required int current, required int proposed}) =>
    proposed > current;

/// Fixed emergency bypass window (no longer user-configurable).
const int kBypassSeconds = 60;

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

/// Switching from due-cards to card-count is treated as weaker when learning
/// or reviews remain (due mode requires finishing Anki's obligation).
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
