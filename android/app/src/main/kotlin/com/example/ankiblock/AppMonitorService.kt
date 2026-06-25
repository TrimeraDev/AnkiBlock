package com.example.ankiblock

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
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
        const val CHANNEL_ID = "ankiblock_monitor"
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

        const val KEY_DAILY_GOAL = "daily_goal"
        const val KEY_DAILY_REVIEWED = "daily_cards_reviewed"
        const val KEY_STUDY_DAY = "study_day_key"
        const val KEY_PASSIVE_APPLIED_TO_DAILY = "passive_applied_to_daily"

        /** Scoped deck ids for passive AnkiDroid study tracking. */
        const val KEY_SCOPE_DECK_IDS = "scope_deck_ids"

        const val KEY_PASSIVE_STUDY_DAY = "passive_study_day"
        const val KEY_PASSIVE_CARD_KEYS = "passive_card_keys"
        const val KEY_PASSIVE_CREDITED_TOTAL = "passive_credited_total"

        /** Snapshot size when seeding passive card tracking. */
        const val PASSIVE_SNAPSHOT_LIMIT = 30

        /** Voluntary study from the home screen — track cards, no app unlock. */
        const val PRACTICE_PACKAGE = "__ankiblock_practice__"

        private const val TAG = "AnkiBlock.Delegate"

        const val ANKIDROID_PACKAGE = "com.ichi2.anki"
        const val POLL_MS_IDLE = 800L
        const val POLL_MS_DELEGATED = 500L
        // After unlocking an app, ignore it for this many ms
        const val UNLOCK_GRACE_MS = 5 * 60 * 1000L

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

        fun grantTempUnlock(context: Context, pkg: String) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            prefs.edit().putLong("unlock_$pkg", System.currentTimeMillis()).apply()
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

        fun startDelegatedSession(
            context: Context,
            packageName: String,
            appName: String,
            deckId: Long,
            deckIds: List<Long>,
            target: Int,
            baseline: Int,
        ) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            prefs.edit()
                .putString(KEY_DELEGATED_PKG, packageName)
                .putString(KEY_DELEGATED_APP_NAME, appName)
                .putLong(KEY_DELEGATED_DECK_ID, deckId)
                .putString(
                    KEY_DELEGATED_DECK_IDS,
                    deckIds.joinToString(","),
                )
                .putInt(KEY_DELEGATED_TARGET, target)
                .putInt(KEY_DELEGATED_BASELINE, baseline)
                .putInt(KEY_DELEGATED_COMPLETE_STREAK, 0)
                .putLong(KEY_DELEGATED_STARTED_AT, System.currentTimeMillis())
                .remove(KEY_DELEGATED_CARD_KEYS)
                .apply()
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
                .apply()
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
        prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        overlayManager = CompletionOverlayManager(this)
        ankiApi = AnkiDroidApi(applicationContext)
        createChannel()
        clearStaleDelegatedSession()
        repairPassiveMergeState()
        startForeground(NOTIFICATION_ID, buildNotification())
        pollStart = System.currentTimeMillis() - 60_000
        currentForegroundPackage = queryMostRecentForegroundPackage()
        handler.post(pollRunnable)
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
            prefs.edit().remove(KEY_DELEGATED_CARD_KEYS).apply()
            keyTrackers.clear()
            lastReportedProgress = -1
            Log.i(TAG, "delegated session started — expecting AnkiDroid foreground")
        }
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(pollRunnable)
        overlayManager.dismiss()
        super.onDestroy()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val ch = NotificationChannel(
                CHANNEL_ID,
                "App blocking",
                NotificationManager.IMPORTANCE_LOW,
            )
            ch.description = "Monitors blocked apps to enforce study gate."
            nm.createNotificationChannel(ch)
        }
    }

    private fun buildNotification(progressText: String? = null) =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("AnkiBlock active")
            .setContentText(
                progressText ?: when {
                    hasDelegatedSession(prefs) ->
                        "Watching your AnkiDroid study session"
                    currentForegroundPackage == ANKIDROID_PACKAGE ->
                        "Counting AnkiDroid study toward your daily goal"
                    else -> "Watching for blocked apps"
                },
            )
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

    private fun reportProgressIfChanged(completed: Int, target: Int) {
        if (completed == lastReportedProgress) return
        lastReportedProgress = completed
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(
            NOTIFICATION_ID,
            buildNotification("Studied $completed of $target cards"),
        )
        MainActivity.notifyFlutter(
            "onDelegatedProgress",
            mapOf("completed" to completed, "target" to target),
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
                val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                nm.notify(NOTIFICATION_ID, buildNotification())
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
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NOTIFICATION_ID, buildNotification())
        }

        ensurePassiveSnapshot(api, deckIds)
        expandPassiveKeys(api, deckIds)

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

        Log.i(TAG, "passive study +$delta cards (daily=$newDaily passiveTotal=$passiveTotal)")

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val goal = prefs.getInt(KEY_DAILY_GOAL, 0)
        val progressText = if (goal > 0 && newDaily >= goal) {
            "Studied $newDaily cards today"
        } else {
            "Daily goal: $newDaily / $goal cards"
        }
        nm.notify(
            NOTIFICATION_ID,
            buildNotification(progressText),
        )
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

    private fun ensurePassiveSnapshot(api: AnkiDroidApi, deckIds: List<Long>) {
        val existing = prefs.getString(KEY_PASSIVE_CARD_KEYS, null)
        if (!existing.isNullOrBlank()) {
            if (passiveKeyTrackers.isEmpty()) {
                seedTrackers(
                    api,
                    existing.split(",").filter { it.isNotBlank() },
                    passiveKeyTrackers,
                )
            }
            return
        }
        val keys = linkedSetOf<String>()
        for (deckId in deckIds) {
            keys.addAll(api.scheduleCardKeys(deckId, PASSIVE_SNAPSHOT_LIMIT))
        }
        if (keys.isEmpty()) return
        seedTrackers(api, keys.toList(), passiveKeyTrackers)
        prefs.edit()
            .putString(KEY_PASSIVE_CARD_KEYS, keys.joinToString(","))
            .apply()
        Log.i(TAG, "passive snapshot decks=$deckIds keys=${keys.size}")
    }

    private fun expandPassiveKeys(api: AnkiDroidApi, deckIds: List<Long>) {
        val raw = prefs.getString(KEY_PASSIVE_CARD_KEYS, null) ?: return
        val tracked = raw.split(",").filter { it.isNotBlank() }.toMutableSet()
        val fresh = linkedSetOf<String>()
        for (deckId in deckIds) {
            fresh.addAll(api.scheduleCardKeys(deckId, PASSIVE_SNAPSHOT_LIMIT))
        }
        val added = fresh - tracked
        if (added.isEmpty()) return
        tracked.addAll(added)
        seedTrackers(api, added.toList(), passiveKeyTrackers, clearExisting = false)
        prefs.edit()
            .putString(KEY_PASSIVE_CARD_KEYS, tracked.joinToString(","))
            .apply()
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
        if (activePkg != ANKIDROID_PACKAGE) {
            prefs.edit().putInt(KEY_DELEGATED_COMPLETE_STREAK, 0).apply()
            val startedAt = prefs.getLong(KEY_DELEGATED_STARTED_AT, 0L)
            if (startedAt > 0 &&
                System.currentTimeMillis() - startedAt > 10 * 60 * 1000L
            ) {
                Log.i(TAG, "clearing abandoned delegated session — left AnkiDroid")
                clearDelegatedSession(this)
                keyTrackers.clear()
            }
            return
        }

        val pkg = prefs.getString(KEY_DELEGATED_PKG, null) ?: return
        val appName = prefs.getString(KEY_DELEGATED_APP_NAME, pkg) ?: pkg
        val target = prefs.getInt(KEY_DELEGATED_TARGET, 5)
        val baseline = prefs.getInt(KEY_DELEGATED_BASELINE, 0)
        val deckId = prefs.getLong(KEY_DELEGATED_DECK_ID, -1L)
        if (deckId < 0) return

        val api = ankiApi ?: return
        if (!api.hasPermission()) {
            Log.w(TAG, "poll skipped — AnkiDroid READ_WRITE_DATABASE not granted")
            return
        }

        ensureSessionSnapshot(api, deckId, target)
        expandTrackedKeys(api, deckId, target)

        val initialKeys = prefs.getString(KEY_DELEGATED_CARD_KEYS, null)
            ?.split(",")
            ?.filter { it.isNotBlank() }
            ?: emptyList()

        val repsBased = if (initialKeys.isNotEmpty()) {
            try {
                api.countValidReviews(initialKeys, keyTrackers)
            } catch (e: Exception) {
                Log.w(TAG, "reps poll failed", e)
                0
            }
        } else {
            0
        }

        val currentDue = try {
            api.deckDueTotal(deckId)
        } catch (e: Exception) {
            Log.w(TAG, "due-count poll failed", e)
            baseline
        }
        val dueBased = (baseline - currentDue).coerceAtLeast(0)
        val completed = maxOf(repsBased, dueBased).coerceAtMost(target)

        val streak = if (completed >= target) {
            prefs.getInt(KEY_DELEGATED_COMPLETE_STREAK, 0) + 1
        } else {
            0
        }
        prefs.edit().putInt(KEY_DELEGATED_COMPLETE_STREAK, streak).apply()

        reportProgressIfChanged(completed, target)

        Log.d(
            TAG,
            "poll fg=$activePkg completed=$completed/$target (reps=$repsBased due=$dueBased) " +
                "streak=$streak snapshot=${initialKeys.size} keys baseline=$baseline now=$currentDue",
        )

        if (completed < target) return
        if (streak < 2) return

        Log.i(TAG, "session complete — $completed cards for $appName")
        keyTrackers.clear()
        clearDelegatedSession(this)
        dismissGateUi(this)
        MainActivity.notifyFlutter(
            "onDelegatedUnlock",
            mapOf("cardsCompleted" to completed),
        )

        if (pkg == PRACTICE_PACKAGE) {
            return
        }

        grantTempUnlock(this, pkg)
        overlayManager.show(
            appName = appName,
            packageName = pkg,
            cardsCompleted = completed,
            onDismiss = { },
        )
    }

    /** Capture the first N schedule cards once AnkiDroid is in the foreground. */
    private fun ensureSessionSnapshot(api: AnkiDroidApi, deckId: Long, target: Int) {
        val existing = prefs.getString(KEY_DELEGATED_CARD_KEYS, null)
        if (!existing.isNullOrBlank()) {
            if (keyTrackers.isEmpty()) {
                seedTrackers(api, existing.split(",").filter { it.isNotBlank() })
            }
            return
        }
        val keys = api.scheduleCardKeys(deckId, target)
        if (keys.isEmpty()) return
        seedTrackers(api, keys)
        prefs.edit()
            .putString(KEY_DELEGATED_CARD_KEYS, keys.joinToString(","))
            .apply()
        Log.i(TAG, "schedule snapshot deck=$deckId keys=$keys")
    }

    /** Pull newly-due cards into the tracked set as the user studies. */
    private fun expandTrackedKeys(api: AnkiDroidApi, deckId: Long, target: Int) {
        val raw = prefs.getString(KEY_DELEGATED_CARD_KEYS, null) ?: return
        val tracked = raw.split(",").filter { it.isNotBlank() }.toMutableSet()
        val fresh = api.scheduleCardKeys(deckId, target).toSet()
        val added = fresh - tracked
        if (added.isEmpty()) return
        tracked.addAll(added)
        seedTrackers(api, added.toList(), clearExisting = false)
        prefs.edit()
            .putString(KEY_DELEGATED_CARD_KEYS, tracked.joinToString(","))
            .apply()
        Log.d(TAG, "expanded snapshot +${added.size} keys (total ${tracked.size})")
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

        val blockedCsv = prefs.getString(KEY_BLOCKED, "") ?: ""
        if (blockedCsv.isEmpty()) return
        val blocked = blockedCsv.split("|").filter { it.isNotEmpty() }.toSet()
        if (pkg !in blocked) return

        if (isDailyGoalComplete(prefs)) return

        val now = System.currentTimeMillis()
        val unlockTime = prefs.getLong("unlock_$pkg", 0L)
        if (now - unlockTime < UNLOCK_GRACE_MS) return

        val lastTrig = lastTriggerTimes[pkg] ?: 0L
        if (now - lastTrig < 2_000) return
        lastTriggerTimes[pkg] = now

        val displayName = lookupDisplayName(pkg) ?: pkg
        launchGate(pkg, displayName)
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

    private fun launchGate(pkg: String, displayName: String) {
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
        } catch (_: Throwable) {
            val pi = PendingIntent.getActivity(
                this,
                pkg.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val n = NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("$displayName is blocked")
                .setContentText("Tap to study and unlock")
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setFullScreenIntent(pi, true)
                .setContentIntent(pi)
                .setAutoCancel(true)
                .build()
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .notify(pkg.hashCode(), n)
        }
    }
}
