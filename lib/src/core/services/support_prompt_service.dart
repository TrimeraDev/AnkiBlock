import 'package:shared_preferences/shared_preferences.dart';

/// Tracks app opens and when to show the optional support/review prompt.
class SupportPromptService {
  static const _launchCountKey = 'app_launch_count';
  static const _dismissedAtLaunchKey = 'support_prompt_dismissed_at_launch';
  static const showEvery = 4;

  Future<int> recordLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final count = (prefs.getInt(_launchCountKey) ?? 0) + 1;
    await prefs.setInt(_launchCountKey, count);
    return count;
  }

  Future<bool> shouldShowPrompt(int launchCount) async {
    if (launchCount < showEvery || launchCount % showEvery != 0) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    final dismissedAt = prefs.getInt(_dismissedAtLaunchKey) ?? 0;
    return launchCount > dismissedAt;
  }

  Future<void> dismissPrompt(int launchCount) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dismissedAtLaunchKey, launchCount);
  }
}
