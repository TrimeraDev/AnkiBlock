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
 * due-count delta via AnkiDroid's ContentProvider.
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

    private val pollRunnable = object : Runnable {
        override fun run() {
            try {
                tick()
            } catch (_: Throwable) {
            }
            val interval = if (hasDelegatedSession(prefs)) {
                POLL_MS_DELEGATED
            } else {
                POLL_MS_IDLE
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
        startForeground(NOTIFICATION_ID, buildNotification())
        pollStart = System.currentTimeMillis() - 10_000
        handler.post(pollRunnable)
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

    private fun buildNotification() =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("AnkiBlock active")
            .setContentText(
                if (hasDelegatedSession(prefs)) {
                    "Watching your AnkiDroid study session"
                } else {
                    "Watching for blocked apps"
                },
            )
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

    private fun tick() {
        val foreground = queryLatestForegroundPackage()
        if (hasDelegatedSession(prefs)) {
            checkDelegatedProgress(foreground)
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
        // Usage events only fire on app switches. While the user stays in
        // AnkiDroid there are no new events — keep the last known foreground.
        if (latestPkg != null) {
            currentForegroundPackage = latestPkg
        }
        return currentForegroundPackage
    }

    private fun checkDelegatedProgress(foreground: String?) {
        val activePkg = foreground ?: return
        if (activePkg != ANKIDROID_PACKAGE) {
            prefs.edit().putInt(KEY_DELEGATED_COMPLETE_STREAK, 0).apply()
            return
        }

        val pkg = prefs.getString(KEY_DELEGATED_PKG, null) ?: return
        val appName = prefs.getString(KEY_DELEGATED_APP_NAME, pkg) ?: pkg
        val target = prefs.getInt(KEY_DELEGATED_TARGET, 5)
        val deckId = prefs.getLong(KEY_DELEGATED_DECK_ID, -1L)
        if (deckId < 0) return

        val api = ankiApi ?: return
        if (!api.hasPermission()) {
            Log.w(TAG, "poll skipped — AnkiDroid READ_WRITE_DATABASE not granted")
            return
        }

        ensureSessionSnapshot(api, deckId, target)

        val initialKeys = prefs.getString(KEY_DELEGATED_CARD_KEYS, null)
            ?.split(",")
            ?.filter { it.isNotBlank() }
            ?: emptyList()
        if (initialKeys.isEmpty()) {
            Log.w(TAG, "poll skipped — no schedule snapshot yet for deck $deckId")
            return
        }

        val completed = try {
            api.countReviewedFromSnapshot(
                deckId,
                initialKeys,
                initialKeys.size + target,
            )
        } catch (e: Exception) {
            Log.w(TAG, "schedule poll failed", e)
            return
        }

        val streak = if (completed >= target) {
            prefs.getInt(KEY_DELEGATED_COMPLETE_STREAK, 0) + 1
        } else {
            0
        }
        prefs.edit().putInt(KEY_DELEGATED_COMPLETE_STREAK, streak).apply()

        Log.d(
            TAG,
            "poll fg=$activePkg completed=$completed/$target streak=$streak " +
                "snapshot=${initialKeys.size} keys",
        )

        if (completed < target) return
        if (streak < 2) return

        Log.i(TAG, "unlock earned — showing completion UI for $appName")
        grantTempUnlock(this, pkg)
        clearDelegatedSession(this)
        dismissGateUi(this)
        MainActivity.notifyFlutter(
            "onDelegatedUnlock",
            mapOf("cardsCompleted" to completed),
        )
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
        if (!existing.isNullOrBlank()) return
        val keys = api.scheduleCardKeys(deckId, target)
        if (keys.isEmpty()) return
        prefs.edit()
            .putString(KEY_DELEGATED_CARD_KEYS, keys.joinToString(","))
            .apply()
        Log.i(TAG, "schedule snapshot deck=$deckId keys=$keys")
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
