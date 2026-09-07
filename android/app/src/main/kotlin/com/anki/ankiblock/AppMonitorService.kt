package com.anki.ankiblock

import android.content.Context
import android.content.SharedPreferences
import android.util.Log

/**
 * Shared blocking prefs and MethodChannel-facing APIs.
 * Live detection and AnkiDroid tracking live in [AnkiBlockAccessibilityService].
 */
object AppMonitorService {
    const val PREFS = "ankiblock_block_prefs"
    const val KEY_BLOCKED = "blocked_packages_csv"
    const val KEY_BLOCKED_NAMES = "blocked_names_csv"
    /** JSON array of {pattern, isRegex, label} website rules. */
    const val KEY_BLOCKED_WEBSITES_JSON = "blocked_websites_json"
    /** When true, installed browsers not in BrowserUrlDetector are gated entirely. */
    const val KEY_BLOCK_UNSUPPORTED_BROWSERS = "block_unsupported_browsers"

    const val KEY_DELEGATED_PKG = "delegated_pkg"
    const val KEY_DELEGATED_APP_NAME = "delegated_app_name"
    const val KEY_DELEGATED_DECK_ID = "delegated_deck_id"
    const val KEY_DELEGATED_DECK_IDS = "delegated_deck_ids"
    const val KEY_DELEGATED_TARGET = "delegated_target"
    const val KEY_DELEGATED_BASELINE = "delegated_baseline"
    const val KEY_DELEGATED_CARD_KEYS = "delegated_card_keys"
    /** Serialized per-card review trackers so counting survives process kills. */
    const val KEY_DELEGATED_TRACKERS = "delegated_trackers"
    const val KEY_DELEGATED_COMPLETE_STREAK = "delegated_complete_streak"
    const val KEY_DELEGATED_STARTED_AT = "delegated_started_at"
    const val KEY_DELEGATED_SEEDED = "delegated_seeded_completed"
    const val KEY_DELEGATED_LAST_REPS = "delegated_last_reps"

    /** Soft study bout — recent cards credit temporary unlock. */
    const val KEY_STUDY_BOUT_COUNT = "study_bout_count"
    const val KEY_STUDY_BOUT_LAST_MS = "study_bout_last_ms"
    const val STUDY_BOUT_IDLE_GAP_MS = 5 * 60_000L

    const val KEY_DAILY_GOAL = "daily_goal"
    const val KEY_DAILY_REVIEWED = "daily_cards_reviewed"
    const val KEY_STUDY_DAY = "study_day_key"
    const val KEY_STUDY_MODE = "study_mode"
    const val KEY_PASSIVE_APPLIED_TO_DAILY = "passive_applied_to_daily"

    /** Scoped deck ids for passive AnkiDroid study tracking. */
    const val KEY_SCOPE_DECK_IDS = "scope_deck_ids"

    const val STUDY_MODE_DUE_CARDS = "dueCards"
    const val STUDY_MODE_CARD_COUNT = "cardCount"

    const val KEY_PASSIVE_STUDY_DAY = "passive_study_day"
    const val KEY_PASSIVE_CARD_KEYS = "passive_card_keys"
    const val KEY_PASSIVE_CREDITED_TOTAL = "passive_credited_total"

    /** Snapshot size when seeding passive card tracking. */
    const val PASSIVE_SNAPSHOT_LIMIT = 30

    /** Voluntary study from the home screen — track cards, no app unlock. */
    const val PRACTICE_PACKAGE = "__ankiblock_practice__"

    private const val TAG = "AnkiBlock.Delegate"

    @Volatile
    var engine: AnkiBlockAccessibilityService? = null
        private set

    fun bindEngine(service: AnkiBlockAccessibilityService?) {
        engine = service
    }

    @Volatile
    var lastEventMs: Long = 0L

    const val ANKIDROID_PACKAGE = "com.ichi2.anki"

    const val KEY_UNLOCK_DURATION_MS = "unlock_duration_ms"
    const val KEY_BYPASS_SECONDS = "bypass_seconds"
    const val KEY_IS_ENABLED = "blocking_enabled"
    const val KEY_BYPASS_ENABLED = "bypass_enabled"
    const val KEY_BYPASS_DAILY_CAP = "bypass_daily_cap"
    /** Cards required for a temporary unlock (synced from Flutter block rule). */
    const val KEY_UNLOCK_GOAL = "unlock_goal_cards"
    const val DEFAULT_UNLOCK_DURATION_MS = 15 * 60 * 1000L
    const val DEFAULT_BYPASS_SECONDS = 60
    const val DEFAULT_BYPASS_DAILY_CAP = 3
    const val DEFAULT_UNLOCK_GOAL = 10

    /** Single global window: an earned unlock or bypass opens every blocked app. */
    const val KEY_UNLOCK_UNTIL = "unlock_until"
    /** Silent shade timer while unlocked. */
    const val KEY_UNLOCK_TIMER_NOTIF = "unlock_timer_notif"
    /** Silent shade progress while studying toward an unlock. */
    const val KEY_PROGRESS_NOTIF = "progress_notif"
    /** Heads-up ~60s before unlock ends. */
    const val KEY_UNLOCK_WARNING_NOTIF = "unlock_warning_notif"

    fun setBlockedPackages(
        context: Context,
        packages: List<String>,
        names: Map<String, String>,
    ) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val pairs = packages.joinToString("|") { it }
        val nameLines = packages.joinToString("|") {
            "${it}=${names[it] ?: it}"
        }
        prefs.edit()
            .putString(KEY_BLOCKED, pairs)
            .putString(KEY_BLOCKED_NAMES, nameLines)
            .apply()
    }

    fun setBlockedWebsites(
        context: Context,
        rulesJson: String,
        blockUnsupported: Boolean,
    ) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_BLOCKED_WEBSITES_JSON, rulesJson)
            .putBoolean(KEY_BLOCK_UNSUPPORTED_BROWSERS, blockUnsupported)
            .apply()
        WebsiteRules.invalidateCache()
    }

    fun hasWebsiteRules(prefs: SharedPreferences): Boolean {
        return WebsiteRules.load(prefs).isNotEmpty()
    }

    fun blockUnsupportedBrowsers(prefs: SharedPreferences): Boolean {
        return prefs.getBoolean(KEY_BLOCK_UNSUPPORTED_BROWSERS, false)
    }

    fun setBlockRuleSettings(
        context: Context,
        unlockDurationMinutes: Int,
        bypassSeconds: Int,
        isEnabled: Boolean = true,
        studyMode: String = STUDY_MODE_CARD_COUNT,
        unlockGoal: Int = DEFAULT_UNLOCK_GOAL,
        bypassEnabled: Boolean = true,
        bypassDailyCap: Int = DEFAULT_BYPASS_DAILY_CAP,
    ) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val unlockMs = (unlockDurationMinutes.coerceAtLeast(1) * 60 * 1000L)
        val mode = if (studyMode == STUDY_MODE_DUE_CARDS) {
            STUDY_MODE_DUE_CARDS
        } else {
            STUDY_MODE_CARD_COUNT
        }
        prefs.edit()
            .putLong(KEY_UNLOCK_DURATION_MS, unlockMs)
            .putInt(KEY_BYPASS_SECONDS, bypassSeconds.coerceAtLeast(1))
            .putBoolean(KEY_IS_ENABLED, isEnabled)
            .putString(KEY_STUDY_MODE, mode)
            .putInt(KEY_UNLOCK_GOAL, unlockGoal.coerceAtLeast(1))
            .putBoolean(KEY_BYPASS_ENABLED, bypassEnabled)
            .putInt(KEY_BYPASS_DAILY_CAP, bypassDailyCap.coerceAtLeast(0))
            .apply()
    }

    fun unlockGoal(prefs: SharedPreferences): Int {
        return prefs.getInt(KEY_UNLOCK_GOAL, DEFAULT_UNLOCK_GOAL).coerceAtLeast(1)
    }

    fun unlockGoal(context: Context): Int {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return unlockGoal(prefs)
    }

    fun isBlockingEnabled(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return prefs.getBoolean(KEY_IS_ENABLED, true)
    }

    fun isRunning(): Boolean = engine != null

    /** Earned unlock: opens all blocked apps for the configured duration. */
    fun grantTempUnlock(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        grantUnlockFor(prefs, prefs.getLong(KEY_UNLOCK_DURATION_MS, DEFAULT_UNLOCK_DURATION_MS))
        UnlockNotificationManager.sync(context)
    }

    /** Emergency bypass: short global unlock (native gate hold action). */
    fun grantBypass(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        grantUnlockFor(prefs, prefs.getInt(KEY_BYPASS_SECONDS, DEFAULT_BYPASS_SECONDS) * 1000L)
        UnlockNotificationManager.sync(context)
    }

    private fun grantUnlockFor(prefs: SharedPreferences, durationMs: Long) {
        val until = System.currentTimeMillis() + durationMs.coerceAtLeast(1_000L)
        // Never shorten a longer window that is already running.
        if (until <= prefs.getLong(KEY_UNLOCK_UNTIL, 0L)) return
        // commit() so an immediate app (re)launch cannot race ahead of the unlock.
        prefs.edit().putLong(KEY_UNLOCK_UNTIL, until).commit()
        Log.i(TAG, "unlock until=$until (${durationMs / 1000}s)")
    }

    fun setUnlockNotificationSettings(
        context: Context,
        timerEnabled: Boolean,
        warningEnabled: Boolean,
        progressEnabled: Boolean = true,
    ) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_UNLOCK_TIMER_NOTIF, timerEnabled)
            .putBoolean(KEY_UNLOCK_WARNING_NOTIF, warningEnabled)
            .putBoolean(KEY_PROGRESS_NOTIF, progressEnabled)
            .apply()
        UnlockNotificationManager.sync(context)
        if (!progressEnabled) {
            UnlockNotificationManager.clearProgress(context)
        }
    }

    fun unlockNotificationSettings(context: Context): Map<String, Any> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return mapOf(
            "timerEnabled" to prefs.getBoolean(KEY_UNLOCK_TIMER_NOTIF, true),
            "warningEnabled" to prefs.getBoolean(KEY_UNLOCK_WARNING_NOTIF, true),
            "progressEnabled" to prefs.getBoolean(KEY_PROGRESS_NOTIF, true),
            "canPost" to UnlockNotificationManager.canPost(context),
        )
    }

    /** Milliseconds left in the current unlock window, 0 when locked. */
    fun unlockRemainingMs(prefs: SharedPreferences): Long {
        val remaining = prefs.getLong(KEY_UNLOCK_UNTIL, 0L) - System.currentTimeMillis()
        return remaining.coerceAtLeast(0L)
    }

    fun isUnlocked(prefs: SharedPreferences): Boolean = unlockRemainingMs(prefs) > 0L

    fun setDailyGoalState(
        context: Context,
        studyDayKey: String,
        dailyGoal: Int,
        cardsReviewed: Int,
    ) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val storedDay = prefs.getString(KEY_STUDY_DAY, null)
        val nativeReviewed = prefs.getInt(KEY_DAILY_REVIEWED, 0)
        // Never let Flutter overwrite a higher native count for the same study
        // day (native credits reviews while Flutter may still hold a stale
        // mirror). Different day → trust the Flutter push (day rollover).
        val mergedReviewed = if (storedDay == studyDayKey) {
            maxOf(nativeReviewed, cardsReviewed.coerceAtLeast(0))
        } else {
            cardsReviewed.coerceAtLeast(0)
        }
        val editor = prefs.edit()
            .putString(KEY_STUDY_DAY, studyDayKey)
            .putInt(KEY_DAILY_GOAL, dailyGoal)
            .putInt(KEY_DAILY_REVIEWED, mergedReviewed)
        // Only advance the passive merge watermark — never reset it to the
        // full daily total (that blocked organic study after gate sessions).
        val passiveMerged = prefs.getInt(KEY_PASSIVE_APPLIED_TO_DAILY, 0)
        val passiveTotal = prefs.getInt(KEY_PASSIVE_CREDITED_TOTAL, 0)
        if (passiveTotal > passiveMerged) {
            editor.putInt(KEY_PASSIVE_APPLIED_TO_DAILY, passiveTotal)
        }
        editor.apply()
    }

    fun setStudyScopeDeckIds(context: Context, deckIds: List<Long>) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_SCOPE_DECK_IDS, deckIds.joinToString(","))
            .apply()
    }

    fun getDailyGoalState(context: Context): Map<String, Any> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return mapOf(
            "studyDayKey" to (prefs.getString(KEY_STUDY_DAY, "") ?: ""),
            "dailyGoal" to prefs.getInt(KEY_DAILY_GOAL, 0),
            "cardsReviewed" to prefs.getInt(KEY_DAILY_REVIEWED, 0),
            // Native-owned gate counters (the gate runs without Flutter).
            "blockedAttempts" to GateStats.blockedAttempts(context),
            "bypassesUsed" to GateStats.bypassesUsed(context),
            "unlocksEarned" to GateStats.unlocksEarned(context),
        )
    }

    fun parseScopeDeckIds(raw: String?): List<Long> {
        if (raw.isNullOrBlank()) return emptyList()
        return raw.split(",")
            .mapNotNull { it.trim().toLongOrNull() }
    }

    /** Study day rolls over at 3:00 AM local time. */
    fun studyDayKey(nowMs: Long = System.currentTimeMillis()): String {
        val cal = java.util.Calendar.getInstance()
        cal.timeInMillis = nowMs
        cal.add(java.util.Calendar.HOUR_OF_DAY, -3)
        return String.format(
            "%04d-%02d-%02d",
            cal.get(java.util.Calendar.YEAR),
            cal.get(java.util.Calendar.MONTH) + 1,
            cal.get(java.util.Calendar.DAY_OF_MONTH),
        )
    }

    fun isDailyGoalComplete(prefs: SharedPreferences): Boolean {
        val goal = prefs.getInt(KEY_DAILY_GOAL, 0)
        if (goal <= 0) return false
        val day = prefs.getString(KEY_STUDY_DAY, null)
        if (day.isNullOrBlank() || day != studyDayKey()) return false
        return prefs.getInt(KEY_DAILY_REVIEWED, 0) >= goal
    }

    /** Hides the native study gate overlay if it is showing. */
    fun dismissGate() {
        engine?.dismissGate()
    }

    fun peekStudyBoutCount(prefs: SharedPreferences): Int {
        val last = prefs.getLong(KEY_STUDY_BOUT_LAST_MS, 0L)
        if (last > 0 &&
            System.currentTimeMillis() - last > STUDY_BOUT_IDLE_GAP_MS
        ) {
            return 0
        }
        return prefs.getInt(KEY_STUDY_BOUT_COUNT, 0).coerceAtLeast(0)
    }

    fun peekStudyBoutCount(context: Context): Int {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return peekStudyBoutCount(prefs)
    }

    fun recordStudyBoutCredit(prefs: SharedPreferences, delta: Int) {
        if (delta <= 0) return
        val now = System.currentTimeMillis()
        val last = prefs.getLong(KEY_STUDY_BOUT_LAST_MS, 0L)
        val current = if (last > 0 && now - last > STUDY_BOUT_IDLE_GAP_MS) {
            0
        } else {
            prefs.getInt(KEY_STUDY_BOUT_COUNT, 0).coerceAtLeast(0)
        }
        prefs.edit()
            .putInt(KEY_STUDY_BOUT_COUNT, current + delta)
            .putLong(KEY_STUDY_BOUT_LAST_MS, now)
            .apply()
        Log.d(TAG, "study bout +$delta → ${current + delta}")
    }

    fun consumeStudyBout(prefs: SharedPreferences) {
        prefs.edit()
            .putInt(KEY_STUDY_BOUT_COUNT, 0)
            .remove(KEY_STUDY_BOUT_LAST_MS)
            .apply()
    }

    /** Active gate/practice session progress for Flutter UI restore. */
    fun getDelegatedSessionState(context: Context): Map<String, Any>? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val pkg = prefs.getString(KEY_DELEGATED_PKG, null) ?: return null
        if (pkg.isBlank()) return null
        val target = prefs.getInt(KEY_DELEGATED_TARGET, 0).coerceAtLeast(1)
        val seeded = prefs.getInt(KEY_DELEGATED_SEEDED, 0).coerceAtLeast(0)
        val reps = prefs.getInt(KEY_DELEGATED_LAST_REPS, 0).coerceAtLeast(0)
        val completed = (seeded + reps).coerceAtMost(target)
        return mapOf(
            "packageName" to pkg,
            "appName" to (prefs.getString(KEY_DELEGATED_APP_NAME, pkg) ?: pkg),
            "target" to target,
            "seeded" to seeded,
            "completed" to completed,
        )
    }

    /**
     * If a recent study bout already meets [target], grant temp unlock and
     * return true. Used when a blocked app is opened before Study is tapped.
     */
    fun tryUnlockFromRecentBout(
        context: Context,
        packageName: String,
        appName: String,
        target: Int,
    ): Boolean {
        if (packageName == PRACTICE_PACKAGE) return false
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val safeTarget = target.coerceAtLeast(1)
        val bout = peekStudyBoutCount(prefs)
        if (bout < safeTarget) return false
        Log.i(TAG, "bout gate auto-unlock bout=$bout target=$safeTarget")
        consumeStudyBout(prefs)
        grantTempUnlock(context)
        GateStats.recordUnlockEarned(context)
        clearDelegatedSession(context)
        MainActivity.notifyFlutter(
            "onDelegatedUnlock",
            mapOf("cardsCompleted" to safeTarget),
        )
        engine?.onTemporaryUnlock()
        engine?.showUnlockOverlay(
            appName = appName,
            packageName = packageName,
            cardsCompleted = safeTarget,
        )
        return true
    }

    /**
     * Starts a delegated study session, or immediately unlocks when a recent
     * study bout already meets [target] (gate packages only).
     *
     * @return map with `unlocked` (Boolean), `seeded` (Int), `target` (Int)
     */
    fun startDelegatedSession(
        context: Context,
        packageName: String,
        appName: String,
        deckId: Long,
        deckIds: List<Long>,
        target: Int,
    ): Map<String, Any> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val safeTarget = target.coerceAtLeast(1)
        val isPractice = packageName == PRACTICE_PACKAGE
        val bout = peekStudyBoutCount(prefs)

        if (!isPractice && bout >= safeTarget) {
            tryUnlockFromRecentBout(context, packageName, appName, safeTarget)
            return mapOf(
                "unlocked" to true,
                "seeded" to safeTarget,
                "target" to safeTarget,
            )
        }

        val seed = if (isPractice) 0 else bout.coerceAtMost(safeTarget)

        val existingPkg = prefs.getString(KEY_DELEGATED_PKG, null)
        if (!isPractice &&
            existingPkg == packageName &&
            existingPkg != PRACTICE_PACKAGE &&
            prefs.getInt(KEY_DELEGATED_TARGET, 0) == safeTarget
        ) {
            val existingSeeded = prefs.getInt(KEY_DELEGATED_SEEDED, 0)
            val existingReps = prefs.getInt(KEY_DELEGATED_LAST_REPS, 0)
            val existingCompleted =
                (existingSeeded + existingReps).coerceAtMost(safeTarget)
            if (existingCompleted > 0 && existingCompleted < safeTarget) {
                Log.i(
                    TAG,
                    "delegated resume pkg=$packageName " +
                        "completed=$existingCompleted/$safeTarget",
                )
                engine?.onDelegatedSessionSeeded(existingCompleted)
                engine?.ensureStudyTrackingActive()
                UnlockNotificationManager.postProgress(context, existingCompleted, safeTarget)
                return mapOf(
                    "unlocked" to false,
                    "seeded" to existingCompleted,
                    "target" to safeTarget,
                )
            }
        }

        engine?.resetDelegatedTrackers()

        prefs.edit()
            .putString(KEY_DELEGATED_PKG, packageName)
            .putString(KEY_DELEGATED_APP_NAME, appName)
            .putLong(KEY_DELEGATED_DECK_ID, deckId)
            .putString(
                KEY_DELEGATED_DECK_IDS,
                deckIds.joinToString(","),
            )
            .putInt(KEY_DELEGATED_TARGET, safeTarget)
            .putInt(KEY_DELEGATED_SEEDED, seed)
            .putInt(KEY_DELEGATED_LAST_REPS, 0)
            .putInt(KEY_DELEGATED_COMPLETE_STREAK, 0)
            .putLong(KEY_DELEGATED_STARTED_AT, System.currentTimeMillis())
            .remove(KEY_DELEGATED_CARD_KEYS)
            .remove(KEY_DELEGATED_BASELINE)
            .remove(KEY_DELEGATED_TRACKERS)
            .commit()

        engine?.onDelegatedSessionSeeded(seed)
        engine?.ensureStudyTrackingActive()
        UnlockNotificationManager.postProgress(context, seed, safeTarget)
        Log.i(TAG, "delegated start pkg=$packageName seed=$seed target=$safeTarget")
        return mapOf(
            "unlocked" to false,
            "seeded" to seed,
            "target" to safeTarget,
        )
    }

    fun clearDelegatedSession(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .remove(KEY_DELEGATED_PKG)
            .remove(KEY_DELEGATED_APP_NAME)
            .remove(KEY_DELEGATED_DECK_ID)
            .remove(KEY_DELEGATED_DECK_IDS)
            .remove(KEY_DELEGATED_TARGET)
            .remove(KEY_DELEGATED_BASELINE)
            .remove(KEY_DELEGATED_CARD_KEYS)
            .remove(KEY_DELEGATED_COMPLETE_STREAK)
            .remove(KEY_DELEGATED_STARTED_AT)
            .remove(KEY_DELEGATED_SEEDED)
            .remove(KEY_DELEGATED_LAST_REPS)
            .remove(KEY_DELEGATED_TRACKERS)
            .apply()
        engine?.onDelegatedSessionEnded()
    }

    fun hasDelegatedSession(prefs: SharedPreferences): Boolean {
        return !prefs.getString(KEY_DELEGATED_PKG, null).isNullOrBlank()
    }

    fun parseDelegatedDeckIds(raw: String?): Set<Long> {
        if (raw.isNullOrBlank()) return emptySet()
        return raw.split(",")
            .mapNotNull { it.trim().toLongOrNull() }
            .toSet()
    }
}
