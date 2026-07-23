package com.anki.ankiblock

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Foreground service that polls UsageStatsManager to detect when a blocked
 * app comes to the foreground. When detected, launches MainActivity routed
 * to the study gate.
 *
 * During a delegated AnkiDroid study session, polls every 500 ms and tracks
 * valid reviews via per-card reps/lapses (Again presses are excluded).
 */
class AppMonitorService : Service() {

    companion object {
        const val CHANNEL_ID_SILENT = "ankiblock_monitor_silent"
        const val NOTIFICATION_ID = 4242
        const val PREFS = "ankiblock_block_prefs"
        const val KEY_BLOCKED = "blocked_packages_csv"
        const val KEY_BLOCKED_NAMES = "blocked_names_csv"
        const val ACTION_START = "com.ankiblock.START_MONITOR"
        const val ACTION_STOP = "com.ankiblock.STOP_MONITOR"
        const val ACTION_DELEGATED_START = "com.ankiblock.DELEGATED_START"

        const val KEY_DELEGATED_PKG = "delegated_pkg"
        const val KEY_DELEGATED_APP_NAME = "delegated_app_name"
        const val KEY_DELEGATED_DECK_ID = "delegated_deck_id"
        const val KEY_DELEGATED_DECK_IDS = "delegated_deck_ids"
        const val KEY_DELEGATED_TARGET = "delegated_target"
        const val KEY_DELEGATED_BASELINE = "delegated_baseline"
        const val KEY_DELEGATED_CARD_KEYS = "delegated_card_keys"
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
        private var runningInstance: AppMonitorService? = null

        const val ANKIDROID_PACKAGE = "com.ichi2.anki"
        const val POLL_MS_IDLE = 800L
        const val POLL_MS_DELEGATED = 500L

        const val KEY_UNLOCK_DURATION_MS = "unlock_duration_ms"
        const val KEY_BYPASS_SECONDS = "bypass_seconds"
        const val KEY_IS_ENABLED = "blocking_enabled"
        const val KEY_BYPASS_ENABLED = "bypass_enabled"
        /** Cards required for a temporary unlock (synced from Flutter block rule). */
        const val KEY_UNLOCK_GOAL = "unlock_goal_cards"
        const val DEFAULT_UNLOCK_DURATION_MS = 15 * 60 * 1000L
        const val DEFAULT_BYPASS_SECONDS = 60
        const val DEFAULT_UNLOCK_GOAL = 10

        private fun unlockUntilKey(pkg: String) = "unlock_until_$pkg"

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

        fun setBlockRuleSettings(
            context: Context,
            unlockDurationMinutes: Int,
            bypassSeconds: Int,
            isEnabled: Boolean = true,
            studyMode: String = STUDY_MODE_CARD_COUNT,
            unlockGoal: Int = DEFAULT_UNLOCK_GOAL,
            bypassEnabled: Boolean = true,
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
                .apply()
        }

        fun unlockGoal(prefs: SharedPreferences): Int {
            return prefs.getInt(KEY_UNLOCK_GOAL, DEFAULT_UNLOCK_GOAL).coerceAtLeast(1)
        }

        fun unlockGoal(context: Context): Int {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            return unlockGoal(prefs)
        }

        fun isTemporarilyUnlocked(context: Context, pkg: String): Boolean {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            return isPackageUnlocked(prefs, pkg)
        }

        fun isBlockingEnabled(context: Context): Boolean {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            return prefs.getBoolean(KEY_IS_ENABLED, true)
        }

        fun isRunning(): Boolean = runningInstance != null

        fun grantTempUnlock(
            context: Context,
            pkg: String,
            durationMs: Long? = null,
        ) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val duration = durationMs
                ?: prefs.getLong(KEY_UNLOCK_DURATION_MS, DEFAULT_UNLOCK_DURATION_MS)
            val until = System.currentTimeMillis() + duration.coerceAtLeast(1_000L)
            prefs.edit().putLong(unlockUntilKey(pkg), until).apply()
        }

        /** Temporary unlock for every currently blocked app (gate unlock grace). */
        fun grantTempUnlockAllBlocked(
            context: Context,
            durationMs: Long? = null,
        ) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val duration = durationMs
                ?: prefs.getLong(KEY_UNLOCK_DURATION_MS, DEFAULT_UNLOCK_DURATION_MS)
            val until = System.currentTimeMillis() + duration.coerceAtLeast(1_000L)
            val blocked = (prefs.getString(KEY_BLOCKED, "") ?: "")
                .split("|")
                .map { it.trim() }
                .filter { it.isNotEmpty() }
            if (blocked.isEmpty()) return
            val editor = prefs.edit()
            for (pkg in blocked) {
                editor.putLong(unlockUntilKey(pkg), until)
            }
            // commit() so the next blocked-app open cannot race ahead of unlock.
            editor.commit()
            Log.i(TAG, "temp unlock all blocked (${blocked.size}) until=$until")
        }

        fun grantBypass(
            context: Context,
            pkg: String,
            durationMs: Long? = null,
        ) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val duration = durationMs
                ?: (prefs.getInt(KEY_BYPASS_SECONDS, DEFAULT_BYPASS_SECONDS) * 1000L)
            val until = System.currentTimeMillis() + duration.coerceAtLeast(1_000L)
            prefs.edit().putLong(unlockUntilKey(pkg), until).apply()
        }

        private fun isPackageUnlocked(prefs: SharedPreferences, pkg: String): Boolean {
            val until = prefs.getLong(unlockUntilKey(pkg), 0L)
            return until > System.currentTimeMillis()
        }

        private fun hadUnlockThatExpired(
            prefs: SharedPreferences,
            pkg: String,
            now: Long = System.currentTimeMillis(),
        ): Boolean {
            val until = prefs.getLong(unlockUntilKey(pkg), 0L)
            return until > 0L && now >= until
        }

        fun setDailyGoalState(
            context: Context,
            studyDayKey: String,
            dailyGoal: Int,
            cardsReviewed: Int,
        ) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val editor = prefs.edit()
                .putString(KEY_STUDY_DAY, studyDayKey)
                .putInt(KEY_DAILY_GOAL, dailyGoal)
                .putInt(KEY_DAILY_REVIEWED, cardsReviewed)
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
            )
        }

        private fun parseScopeDeckIds(raw: String?): List<Long> {
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

        /** Closes the study-gate [MainActivity] and removes it from recents. */
        fun dismissGateUi(context: Context) {
            val intent = Intent(context, MainActivity::class.java).apply {
                action = MainActivity.ACTION_DISMISS_GATE
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            try {
                context.startActivity(intent)
            } catch (_: Throwable) {
            }
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

        fun clearStudyBout(prefs: SharedPreferences) = consumeStudyBout(prefs)

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

        fun peekStudyBoutCountPublic(context: Context): Int {
            return peekStudyBoutCount(context)
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
            grantTempUnlockAllBlocked(context)
            clearDelegatedSession(context)
            // Best-effort UI sync — unlock already committed in prefs.
            MainActivity.notifyFlutter(
                "onDelegatedUnlock",
                mapOf("cardsCompleted" to safeTarget),
            )
            runningInstance?.showUnlockOverlay(
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

            // Resume only a matching *gate* session — never treat home practice
            // progress as unlock progress for a blocked app.
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
                    runningInstance?.onDelegatedSessionSeeded(existingCompleted)
                    return mapOf(
                        "unlocked" to false,
                        "seeded" to existingCompleted,
                        "target" to safeTarget,
                    )
                }
            }

            // Replacing practice (or any other) session — wipe trackers so gate
            // counting starts clean; bout seed carries recent study credit.
            runningInstance?.resetDelegatedTrackers()

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
                .commit()

            runningInstance?.onDelegatedSessionSeeded(seed)
            Log.i(TAG, "delegated start pkg=$packageName seed=$seed target=$safeTarget")
            return mapOf(
                "unlocked" to false,
                "seeded" to seed,
                "target" to safeTarget,
            )
        }

        fun cancelDelegatedSession(context: Context) {
            clearDelegatedSession(context)
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
                .apply()
            runningInstance?.onDelegatedSessionEnded()
        }

        private fun hasDelegatedSession(prefs: SharedPreferences): Boolean {
            return !prefs.getString(KEY_DELEGATED_PKG, null).isNullOrBlank()
        }

        private fun parseDelegatedDeckIds(raw: String?): Set<Long> {
            if (raw.isNullOrBlank()) return emptySet()
            return raw.split(",")
                .mapNotNull { it.trim().toLongOrNull() }
                .toSet()
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var prefs: SharedPreferences
    private var lastForegroundPackage: String? = null
    private var currentForegroundPackage: String? = null
    private var lastTriggerTimes = HashMap<String, Long>()
    private var pollStart = 0L
    private lateinit var overlayManager: CompletionOverlayManager
    private var ankiApi: AnkiDroidApi? = null
    private val keyTrackers = mutableMapOf<String, AnkiDroidApi.KeyTracker>()
    private val passiveKeyTrackers = mutableMapOf<String, AnkiDroidApi.KeyTracker>()
    private var lastReportedProgress = -1
    /** In-memory streak — prefs apply() can lose increments across 500ms polls. */
    private var delegatedCompleteStreak = 0
    private var lastPassiveWatching = false

    private val pollRunnable = object : Runnable {
        override fun run() {
            try {
                tick()
            } catch (_: Throwable) {
            }
            val interval = when {
                hasDelegatedSession(prefs) -> POLL_MS_DELEGATED
                currentForegroundPackage == ANKIDROID_PACKAGE -> POLL_MS_DELEGATED
                else -> POLL_MS_IDLE
            }
            handler.postDelayed(this, interval)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        runningInstance = this
        prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        overlayManager = CompletionOverlayManager(this)
        ankiApi = AnkiDroidApi(applicationContext)
        AnkiBlockApplication.warmFlutterEngine(application as android.app.Application)
        createChannels()
        clearStaleDelegatedSession()
        repairPassiveMergeState()
        promoteToForeground()
        pollStart = System.currentTimeMillis() - 60_000
        currentForegroundPackage = queryMostRecentForegroundPackage()
        handler.post(pollRunnable)
    }

    private fun promoteToForeground() {
        val notification = buildIdleNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun clearStaleDelegatedSession() {
        if (!hasDelegatedSession(prefs)) return
        val startedAt = prefs.getLong(KEY_DELEGATED_STARTED_AT, 0L)
        val age = System.currentTimeMillis() - startedAt
        if (startedAt == 0L || age > 30 * 60 * 1000L) {
            Log.i(TAG, "clearing stale delegated session (age=${age}ms)")
            clearDelegatedSession(this)
            keyTrackers.clear()
        }
    }

    /** Fixes watermark left by older builds that reset passive merge to daily total. */
    private fun repairPassiveMergeState() {
        val passiveTotal = prefs.getInt(KEY_PASSIVE_CREDITED_TOTAL, 0)
        val merged = prefs.getInt(KEY_PASSIVE_APPLIED_TO_DAILY, 0)
        if (merged > passiveTotal) {
            prefs.edit().putInt(KEY_PASSIVE_APPLIED_TO_DAILY, passiveTotal).apply()
            Log.i(TAG, "repaired passive merge watermark $merged -> $passiveTotal")
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            overlayManager.dismiss()
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_DELEGATED_START) {
            currentForegroundPackage = ANKIDROID_PACKAGE
            val hasProgress = prefs.getInt(KEY_DELEGATED_LAST_REPS, 0) > 0 ||
                !prefs.getString(KEY_DELEGATED_CARD_KEYS, null).isNullOrBlank()
            if (!hasProgress) {
                // Fresh session only — never wipe an in-progress snapshot/reps.
                prefs.edit().remove(KEY_DELEGATED_CARD_KEYS).apply()
                keyTrackers.clear()
                delegatedCompleteStreak = 0
                lastReportedProgress = prefs.getInt(KEY_DELEGATED_SEEDED, 0)
            }
            Log.i(TAG, "delegated session started — expecting AnkiDroid foreground")
        }
        return START_STICKY
    }

    override fun onDestroy() {
        if (runningInstance === this) runningInstance = null
        handler.removeCallbacks(pollRunnable)
        overlayManager.dismiss()
        super.onDestroy()
    }

    private fun createChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID_SILENT,
                    "Background monitoring",
                    NotificationManager.IMPORTANCE_MIN,
                ).apply {
                    description =
                        "Required by Android while app blocking runs in the background."
                    setShowBadge(false)
                },
            )
        }
    }

    private fun buildIdleNotification(): Notification {
        val builder = NotificationCompat.Builder(this, CHANNEL_ID_SILENT)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentTitle("AnkiBlock")
            .setContentText("Monitoring blocked apps")
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setShowWhen(false)
            .setSilent(true)
            .setOnlyAlertOnce(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setForegroundServiceBehavior(
                NotificationCompat.FOREGROUND_SERVICE_DEFERRED,
            )
        }
        return builder.build()
    }

    private fun resetForegroundNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, buildIdleNotification())
    }

    private fun onDelegatedSessionEnded() {
        lastReportedProgress = -1
        delegatedCompleteStreak = 0
        resetForegroundNotification()
    }

    private fun onDelegatedSessionSeeded(seed: Int) {
        // Flutter applies seed from startDelegatedSession result; avoid a
        // progress event that would double-count cards already in today's ledger.
        lastReportedProgress = seed
        delegatedCompleteStreak = 0
    }

    private fun resetDelegatedTrackers() {
        keyTrackers.clear()
        lastReportedProgress = -1
        delegatedCompleteStreak = 0
    }

    private fun showUnlockOverlay(
        appName: String,
        packageName: String,
        cardsCompleted: Int,
    ) {
        overlayManager.show(
            appName = appName,
            packageName = packageName,
            cardsCompleted = cardsCompleted,
            onDismiss = { },
        )
    }

    private fun reportProgressIfChanged(completed: Int, target: Int) {
        if (completed == lastReportedProgress) return
        lastReportedProgress = completed
        val pkg = prefs.getString(KEY_DELEGATED_PKG, "") ?: ""
        MainActivity.notifyFlutter(
            "onDelegatedProgress",
            mapOf(
                "completed" to completed,
                "target" to target,
                "packageName" to pkg,
            ),
        )
    }

    private fun tick() {
        val foreground = queryLatestForegroundPackage()
        if (hasDelegatedSession(prefs)) {
            checkDelegatedProgress(foreground)
        } else {
            checkPassiveStudy(foreground)
        }
        checkBlockedAppGate(foreground)
        checkExpiredUnlockWhileForeground(foreground)
    }

    private fun queryLatestForegroundPackage(): String? {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val events = usm.queryEvents(pollStart, now)
        val ev = UsageEvents.Event()
        var latestPkg: String? = null
        var latestTime = 0L
        while (events.hasNextEvent()) {
            events.getNextEvent(ev)
            if (ev.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                if (ev.timeStamp >= latestTime) {
                    latestTime = ev.timeStamp
                    latestPkg = ev.packageName
                }
            }
        }
        pollStart = now
        if (latestPkg != null) {
            currentForegroundPackage = latestPkg
        } else if (currentForegroundPackage == null) {
            currentForegroundPackage = queryMostRecentForegroundPackage()
        }
        return currentForegroundPackage
    }

    /** Best-effort current foreground when usage events have not fired yet. */
    private fun queryMostRecentForegroundPackage(): String? {
        return try {
            val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val now = System.currentTimeMillis()
            val stats = usm.queryUsageStats(
                UsageStatsManager.INTERVAL_BEST,
                now - 120_000,
                now,
            ) ?: return null
            stats.maxByOrNull { it.lastTimeUsed }?.packageName
        } catch (_: Throwable) {
            null
        }
    }

    /** Credits organic AnkiDroid study toward the daily goal (no delegated session). */
    private fun checkPassiveStudy(foreground: String?) {
        if (foreground != ANKIDROID_PACKAGE) {
            if (lastPassiveWatching) {
                consolidatePassiveTrackers()
                lastPassiveWatching = false
                resetForegroundNotification()
            }
            return
        }

        val api = ankiApi ?: return
        if (!api.hasPermission()) {
            Log.w(TAG, "passive skipped — AnkiDroid READ_WRITE_DATABASE not granted")
            return
        }

        ensurePassiveStudyDay()
        val deckIds = resolvePassiveDeckIds(api)
        if (deckIds.isEmpty()) {
            Log.w(TAG, "passive skipped — no scoped decks (sync deck scope in AnkiBlock)")
            return
        }

        if (!lastPassiveWatching) {
            lastPassiveWatching = true
            Log.i(TAG, "passive watching AnkiDroid decks=$deckIds")
        }

        ensureMultiDeckSnapshot(
            api,
            deckIds,
            KEY_PASSIVE_CARD_KEYS,
            passiveKeyTrackers,
            PASSIVE_SNAPSHOT_LIMIT,
        )
        expandMultiDeckKeys(
            api,
            deckIds,
            KEY_PASSIVE_CARD_KEYS,
            passiveKeyTrackers,
            PASSIVE_SNAPSHOT_LIMIT,
        )

        val keys = prefs.getString(KEY_PASSIVE_CARD_KEYS, null)
            ?.split(",")
            ?.filter { it.isNotBlank() }
            ?: emptyList()
        if (keys.isEmpty()) {
            Log.d(TAG, "passive skipped — schedule snapshot empty for decks=$deckIds")
            return
        }

        val inMemoryCredited = try {
            api.countValidReviews(keys, passiveKeyTrackers)
        } catch (e: Exception) {
            Log.w(TAG, "passive reps poll failed", e)
            0
        }

        val persistedCredited = prefs.getInt(KEY_PASSIVE_CREDITED_TOTAL, 0)
        val passiveTotal = persistedCredited + inMemoryCredited
        val lastMerged = prefs.getInt(KEY_PASSIVE_APPLIED_TO_DAILY, 0)
        if (passiveTotal <= lastMerged) return

        val delta = passiveTotal - lastMerged
        val newDaily = prefs.getInt(KEY_DAILY_REVIEWED, 0) + delta
        prefs.edit()
            .putInt(KEY_DAILY_REVIEWED, newDaily)
            .putInt(KEY_PASSIVE_APPLIED_TO_DAILY, passiveTotal)
            .apply()
        recordStudyBoutCredit(prefs, delta)

        Log.i(TAG, "passive study +$delta cards (daily=$newDaily passiveTotal=$passiveTotal)")

        MainActivity.notifyFlutter(
            "onPassiveStudyProgress",
            mapOf("delta" to delta, "cardsReviewed" to newDaily),
        )
    }

    private fun resolvePassiveDeckIds(api: AnkiDroidApi): List<Long> {
        val scoped = parseScopeDeckIds(prefs.getString(KEY_SCOPE_DECK_IDS, null))
        if (scoped.isNotEmpty()) return scoped
        return try {
            api.listDecks().mapNotNull { (it["id"] as? Number)?.toLong() }
        } catch (e: Exception) {
            Log.w(TAG, "passive deck fallback failed", e)
            emptyList()
        }
    }

    private fun ensurePassiveStudyDay() {
        val today = studyDayKey()
        val stored = prefs.getString(KEY_PASSIVE_STUDY_DAY, null)
        if (stored == today) return
        consolidatePassiveTrackers()
        passiveKeyTrackers.clear()
        prefs.edit()
            .putString(KEY_PASSIVE_STUDY_DAY, today)
            .remove(KEY_PASSIVE_CARD_KEYS)
            .putInt(KEY_PASSIVE_CREDITED_TOTAL, 0)
            .putInt(KEY_PASSIVE_APPLIED_TO_DAILY, 0)
            .apply()
        clearStudyBout(prefs)
    }

    private fun consolidatePassiveTrackers() {
        val sum = passiveKeyTrackers.values.sumOf { it.credited }
        if (sum <= 0) return
        val total = prefs.getInt(KEY_PASSIVE_CREDITED_TOTAL, 0) + sum
        prefs.edit().putInt(KEY_PASSIVE_CREDITED_TOTAL, total).apply()
        for (tracker in passiveKeyTrackers.values) {
            tracker.credited = 0
        }
    }

    private fun resolveDelegatedDeckIds(): List<Long> {
        val fromCsv = parseDelegatedDeckIds(
            prefs.getString(KEY_DELEGATED_DECK_IDS, null),
        ).toList()
        if (fromCsv.isNotEmpty()) return fromCsv
        val launchDeck = prefs.getLong(KEY_DELEGATED_DECK_ID, -1L)
        if (launchDeck >= 0) return listOf(launchDeck)
        return emptyList()
    }

    private fun aggregateDeckObligationDue(api: AnkiDroidApi, deckIds: List<Long>): Int {
        var total = 0
        for (deckId in deckIds) {
            total += try {
                api.deckObligationDue(deckId)
            } catch (e: Exception) {
                Log.w(TAG, "obligation-due for deck=$deckId failed", e)
                0
            }
        }
        return total
    }

    /** Mode-aware goal: card count, or Anki learning+reviews cleared. */
    private fun isBlockingGoalComplete(): Boolean {
        val mode = prefs.getString(KEY_STUDY_MODE, STUDY_MODE_CARD_COUNT)
            ?: STUDY_MODE_CARD_COUNT
        if (mode == STUDY_MODE_DUE_CARDS) {
            val api = ankiApi ?: return false
            if (!api.hasPermission()) return false
            val deckIds = parseScopeDeckIds(prefs.getString(KEY_SCOPE_DECK_IDS, null))
            if (deckIds.isEmpty()) return false
            return try {
                aggregateDeckObligationDue(api, deckIds) <= 0
            } catch (e: Exception) {
                Log.w(TAG, "due-goal check failed", e)
                false
            }
        }
        return isDailyGoalComplete(prefs)
    }

    private fun ensureMultiDeckSnapshot(
        api: AnkiDroidApi,
        deckIds: List<Long>,
        keysPrefKey: String,
        trackers: MutableMap<String, AnkiDroidApi.KeyTracker>,
        perDeckLimit: Int,
    ) {
        val existing = prefs.getString(keysPrefKey, null)
        if (!existing.isNullOrBlank()) {
            if (trackers.isEmpty()) {
                seedTrackers(
                    api,
                    existing.split(",").filter { it.isNotBlank() },
                    trackers,
                )
            }
            return
        }
        val keys = linkedSetOf<String>()
        for (deckId in deckIds) {
            keys.addAll(api.scheduleCardKeys(deckId, perDeckLimit))
        }
        if (keys.isEmpty()) return
        seedTrackers(api, keys.toList(), trackers)
        prefs.edit()
            .putString(keysPrefKey, keys.joinToString(","))
            .apply()
        Log.i(TAG, "multi-deck snapshot decks=$deckIds keys=${keys.size}")
    }

    private fun expandMultiDeckKeys(
        api: AnkiDroidApi,
        deckIds: List<Long>,
        keysPrefKey: String,
        trackers: MutableMap<String, AnkiDroidApi.KeyTracker>,
        perDeckLimit: Int,
    ) {
        val raw = prefs.getString(keysPrefKey, null) ?: return
        val tracked = raw.split(",").filter { it.isNotBlank() }.toMutableSet()
        val fresh = linkedSetOf<String>()
        for (deckId in deckIds) {
            fresh.addAll(api.scheduleCardKeys(deckId, perDeckLimit))
        }
        val added = fresh - tracked
        if (added.isEmpty()) return
        tracked.addAll(added)
        seedTrackers(api, added.toList(), trackers, clearExisting = false)
        prefs.edit()
            .putString(keysPrefKey, tracked.joinToString(","))
            .apply()
        Log.d(TAG, "expanded multi-deck snapshot +${added.size} keys (total ${tracked.size})")
    }

    private fun checkDelegatedProgress(foreground: String?) {
        var activePkg = foreground
        if (activePkg == null && hasDelegatedSession(prefs)) {
            val startedAt = prefs.getLong(KEY_DELEGATED_STARTED_AT, 0L)
            if (startedAt > 0 &&
                System.currentTimeMillis() - startedAt < 60_000
            ) {
                activePkg = ANKIDROID_PACKAGE
            }
        }
        if (activePkg == null) return

        val pkg = prefs.getString(KEY_DELEGATED_PKG, null) ?: return
        val appName = prefs.getString(KEY_DELEGATED_APP_NAME, pkg) ?: pkg
        val target = prefs.getInt(KEY_DELEGATED_TARGET, 5)
        val deckIds = resolveDelegatedDeckIds()
        if (deckIds.isEmpty()) return

        val api = ankiApi ?: return
        if (!api.hasPermission()) {
            Log.w(TAG, "poll skipped — AnkiDroid READ_WRITE_DATABASE not granted")
            return
        }

        val inAnki = activePkg == ANKIDROID_PACKAGE

        // Always refresh snapshot / progress while a session exists — including
        // when the user just left Anki after the last card (otherwise unlock
        // never finalizes and the gate reappears with a cleared Flutter session).
        ensureMultiDeckSnapshot(
            api,
            deckIds,
            KEY_DELEGATED_CARD_KEYS,
            keyTrackers,
            PASSIVE_SNAPSHOT_LIMIT,
        )
        expandMultiDeckKeys(
            api,
            deckIds,
            KEY_DELEGATED_CARD_KEYS,
            keyTrackers,
            PASSIVE_SNAPSHOT_LIMIT,
        )

        val initialKeys = prefs.getString(KEY_DELEGATED_CARD_KEYS, null)
            ?.split(",")
            ?.filter { it.isNotBlank() }
            ?: emptyList()

        val seeded = prefs.getInt(KEY_DELEGATED_SEEDED, 0).coerceAtLeast(0)
        val repsBased = if (initialKeys.isEmpty()) {
            if (inAnki) {
                Log.d(TAG, "delegated waiting for schedule snapshot decks=$deckIds")
            }
            0
        } else {
            try {
                api.countValidReviews(initialKeys, keyTrackers)
            } catch (e: Exception) {
                Log.w(TAG, "reps poll failed", e)
                0
            }
        }
        val prevReps = prefs.getInt(KEY_DELEGATED_LAST_REPS, 0)
        // Prefer live credited reps; fall back to persisted last reps after
        // service restart (in-memory trackers are re-seeded at current baselines).
        val effectiveReps = maxOf(repsBased, prevReps)
        if (repsBased > prevReps) {
            val delta = repsBased - prevReps
            recordStudyBoutCredit(prefs, delta)
            val newDaily = prefs.getInt(KEY_DAILY_REVIEWED, 0) + delta
            prefs.edit()
                .putInt(KEY_DAILY_REVIEWED, newDaily)
                .putInt(KEY_DELEGATED_LAST_REPS, repsBased)
                .commit()
        }
        val completed = (seeded + effectiveReps).coerceAtMost(target)

        if (completed >= target) {
            delegatedCompleteStreak += 1
        } else {
            delegatedCompleteStreak = 0
        }
        prefs.edit().putInt(KEY_DELEGATED_COMPLETE_STREAK, delegatedCompleteStreak).apply()

        if (inAnki || completed > lastReportedProgress) {
            reportProgressIfChanged(completed, target)
        }

        Log.d(
            TAG,
            "poll fg=$activePkg completed=$completed/$target " +
                "seed=$seeded reps=$effectiveReps streak=$delegatedCompleteStreak " +
                "snapshot=${initialKeys.size} keys decks=$deckIds",
        )

        if (completed >= target && delegatedCompleteStreak >= 1) {
            finalizeDelegatedUnlock(
                pkg = pkg,
                appName = appName,
                completed = completed,
            )
            return
        }

        if (!inAnki) {
            val startedAt = prefs.getLong(KEY_DELEGATED_STARTED_AT, 0L)
            if (startedAt > 0 &&
                System.currentTimeMillis() - startedAt > 10 * 60 * 1000L
            ) {
                Log.i(TAG, "clearing abandoned delegated session — left AnkiDroid")
                clearDelegatedSession(this)
                keyTrackers.clear()
            }
        }
    }

    private fun finalizeDelegatedUnlock(
        pkg: String,
        appName: String,
        completed: Int,
    ) {
        Log.i(TAG, "session complete — $completed cards for $appName")
        keyTrackers.clear()
        if (pkg != PRACTICE_PACKAGE) {
            consumeStudyBout(prefs)
        }
        // Grant unlock BEFORE notifying Flutter / dismissing UI so a quick
        // return to the blocked app cannot race an empty unlock window.
        if (pkg != PRACTICE_PACKAGE) {
            grantTempUnlockAllBlocked(this)
        }
        clearDelegatedSession(this)
        dismissGateUi(this)
        MainActivity.notifyFlutter(
            "onDelegatedUnlock",
            mapOf("cardsCompleted" to completed),
        )

        if (pkg == PRACTICE_PACKAGE) {
            return
        }

        overlayManager.show(
            appName = appName,
            packageName = pkg,
            cardsCompleted = completed,
            onDismiss = { },
        )
    }

    private fun seedTrackers(
        api: AnkiDroidApi,
        keys: List<String>,
        into: MutableMap<String, AnkiDroidApi.KeyTracker> = keyTrackers,
        clearExisting: Boolean = true,
    ) {
        if (clearExisting) into.clear()
        for (key in keys) {
            if (into.containsKey(key)) continue
            val (noteId, cardOrd) = api.parseCardKey(key) ?: continue
            val card = api.queryCard(noteId, cardOrd) ?: continue
            into[key] = AnkiDroidApi.KeyTracker(
                lastReps = card.reps,
                lastLapses = card.lapses,
                lastDue = card.due,
                lastType = card.type,
            )
        }
    }

    private fun checkBlockedAppGate(foreground: String?) {
        val pkg = foreground ?: return
        if (pkg == packageName) return
        if (pkg == lastForegroundPackage) return
        lastForegroundPackage = pkg

        if (!AppMonitorService.isBlockingEnabled(this)) return

        val blockedCsv = prefs.getString(KEY_BLOCKED, "") ?: ""
        if (blockedCsv.isEmpty()) return
        val blocked = blockedCsv.split("|").filter { it.isNotEmpty() }.toSet()
        if (pkg !in blocked) return

        if (isBlockingGoalComplete()) return
        if (isPackageUnlocked(prefs, pkg)) return

        val now = System.currentTimeMillis()
        val lastTrig = lastTriggerTimes[pkg] ?: 0L
        if (now - lastTrig < 2_000) return
        lastTriggerTimes[pkg] = now

        val displayName = lookupDisplayName(pkg) ?: pkg
        // Pure-native bout unlock — do not wait for Flutter MainActivity.
        if (tryUnlockFromRecentBout(
                this,
                pkg,
                displayName,
                unlockGoal(prefs),
            )
        ) {
            Log.i(TAG, "skipped gate — recent study bout unlocked $displayName")
            return
        }

        launchFlutterGate(pkg, displayName)
    }

    private fun checkExpiredUnlockWhileForeground(foreground: String?) {
        val pkg = foreground ?: return
        if (pkg == packageName) return

        if (!AppMonitorService.isBlockingEnabled(this)) return

        val blockedCsv = prefs.getString(KEY_BLOCKED, "") ?: ""
        if (blockedCsv.isEmpty()) return
        val blocked = blockedCsv.split("|").filter { it.isNotEmpty() }.toSet()
        if (pkg !in blocked) return

        if (isBlockingGoalComplete()) return
        if (!hadUnlockThatExpired(prefs, pkg)) return

        val now = System.currentTimeMillis()
        val lastTrig = lastTriggerTimes[pkg] ?: 0L
        if (now - lastTrig < 2_000) return
        lastTriggerTimes[pkg] = now

        val displayName = lookupDisplayName(pkg) ?: pkg
        prefs.edit().remove(unlockUntilKey(pkg)).apply()
        launchFlutterGate(pkg, displayName)
    }

    private fun lookupDisplayName(pkg: String): String? {
        val csv = prefs.getString(KEY_BLOCKED_NAMES, "") ?: ""
        for (entry in csv.split("|")) {
            val idx = entry.indexOf('=')
            if (idx > 0 && entry.substring(0, idx) == pkg) {
                return entry.substring(idx + 1)
            }
        }
        return null
    }

    private fun launchFlutterGate(pkg: String, displayName: String) {
        val intent = Intent(this, MainActivity::class.java).apply {
            action = MainActivity.ACTION_OPEN_GATE
            putExtra("packageName", pkg)
            putExtra("appName", displayName)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        try {
            startActivity(intent)
        } catch (e: Throwable) {
            Log.w(TAG, "Flutter gate launch failed for $displayName", e)
        }
    }
}
