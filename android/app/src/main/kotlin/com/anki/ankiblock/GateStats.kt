package com.anki.ankiblock

import android.content.Context
import android.content.SharedPreferences

/**
 * Per-study-day counters owned by native (the gate runs without Flutter).
 * Flutter pulls these on resume via `getDailyGoalState` and merges into Drift.
 */
object GateStats {
    private const val KEY_DAY = "gate_stats_day"
    private const val KEY_BLOCKED_ATTEMPTS = "gate_blocked_attempts"
    private const val KEY_BYPASSES_USED = "gate_bypasses_used"
    private const val KEY_UNLOCKS_EARNED = "gate_unlocks_earned"

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(AppMonitorService.PREFS, Context.MODE_PRIVATE)

    /** Resets counters when the 3am study day boundary has passed. */
    private fun ensureDay(prefs: SharedPreferences) {
        val today = AppMonitorService.studyDayKey()
        if (prefs.getString(KEY_DAY, null) == today) return
        prefs.edit()
            .putString(KEY_DAY, today)
            .putInt(KEY_BLOCKED_ATTEMPTS, 0)
            .putInt(KEY_BYPASSES_USED, 0)
            .putInt(KEY_UNLOCKS_EARNED, 0)
            .apply()
    }

    private fun increment(prefs: SharedPreferences, key: String) {
        ensureDay(prefs)
        prefs.edit().putInt(key, prefs.getInt(key, 0) + 1).apply()
    }

    private fun read(prefs: SharedPreferences, key: String): Int {
        ensureDay(prefs)
        return prefs.getInt(key, 0).coerceAtLeast(0)
    }

    fun recordBlockedAttempt(context: Context) = increment(prefs(context), KEY_BLOCKED_ATTEMPTS)
    fun recordBypass(context: Context) = increment(prefs(context), KEY_BYPASSES_USED)
    fun recordUnlockEarned(context: Context) = increment(prefs(context), KEY_UNLOCKS_EARNED)

    fun blockedAttempts(context: Context): Int = read(prefs(context), KEY_BLOCKED_ATTEMPTS)
    fun bypassesUsed(context: Context): Int = read(prefs(context), KEY_BYPASSES_USED)
    fun unlocksEarned(context: Context): Int = read(prefs(context), KEY_UNLOCKS_EARNED)

    fun bypassesRemaining(context: Context): Int {
        val p = prefs(context)
        if (!p.getBoolean(AppMonitorService.KEY_BYPASS_ENABLED, true)) return 0
        val cap = p.getInt(
            AppMonitorService.KEY_BYPASS_DAILY_CAP,
            AppMonitorService.DEFAULT_BYPASS_DAILY_CAP,
        )
        return (cap - bypassesUsed(context)).coerceIn(0, cap.coerceAtLeast(0))
    }
}
