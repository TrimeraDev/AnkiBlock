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
import androidx.core.app.NotificationCompat

/**
 * Foreground service that polls UsageStatsManager to detect when a blocked
 * app comes to the foreground. When detected, launches MainActivity routed
 * to the study gate.
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
        // After unlocking an app, ignore it for this many ms
        const val UNLOCK_GRACE_MS = 5 * 60 * 1000L

        fun setBlockedPackages(
            context: Context,
            packages: List<String>,
            names: Map<String, String>
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
    }

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var prefs: SharedPreferences
    private var lastForegroundPackage: String? = null
    private var lastTriggerTimes = HashMap<String, Long>()
    private var pollStart = 0L

    private val pollRunnable = object : Runnable {
        override fun run() {
            try {
                checkForeground()
            } catch (_: Throwable) {}
            handler.postDelayed(this, 800)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        createChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        pollStart = System.currentTimeMillis() - 10_000
        handler.post(pollRunnable)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(pollRunnable)
        super.onDestroy()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val ch = NotificationChannel(
                CHANNEL_ID,
                "App blocking",
                NotificationManager.IMPORTANCE_LOW
            )
            ch.description = "Monitors blocked apps to enforce study gate."
            nm.createNotificationChannel(ch)
        }
    }

    private fun buildNotification() =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("AnkiBlock active")
            .setContentText("Watching for blocked apps")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

    private fun checkForeground() {
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

        val pkg = latestPkg ?: return
        if (pkg == packageName) return // ourselves
        if (pkg == lastForegroundPackage) return
        lastForegroundPackage = pkg

        val blockedCsv = prefs.getString(KEY_BLOCKED, "") ?: ""
        if (blockedCsv.isEmpty()) return
        val blocked = blockedCsv.split("|").filter { it.isNotEmpty() }.toSet()
        if (pkg !in blocked) return

        // grace period after unlock
        val unlockTime = prefs.getLong("unlock_$pkg", 0L)
        if (now - unlockTime < UNLOCK_GRACE_MS) return

        // throttle re-trigger to once per 2s
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
        // Try direct startActivity. If we don't have BG-launch permission,
        // fall back to a full-screen intent notification.
        try {
            startActivity(intent)
        } catch (_: Throwable) {
            val pi = PendingIntent.getActivity(
                this,
                pkg.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
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
