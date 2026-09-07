package com.anki.ankiblock

import android.content.Context
import android.os.Build

/**
 * Persists gate / monitor health counters for the Flutter diagnostics panel.
 */
object GateDiagnostics {
    private const val PREFS = "ankiblock_gate_diagnostics"
    private const val KEY_LAST_GATE_LAUNCH_MS = "last_gate_launch_ms"
    private const val KEY_LAST_GATE_READY_MS = "last_gate_ready_ms"
    private const val KEY_LAST_BLANK_TIMEOUT_MS = "last_blank_timeout_ms"
    private const val KEY_BLANK_TIMEOUT_COUNT = "blank_timeout_count"
    private const val KEY_LAST_POLL_MS = "last_poll_ms"
    private const val KEY_MONITOR_RESTARTS = "monitor_restarts"
    private const val KEY_LAST_ERROR = "last_error"
    private const val KEY_GATE_LAUNCH_COUNT = "gate_launch_count"
    private const val KEY_ERROR_COUNT = "error_count"
    private const val KEY_POLL_STALE_COUNT = "poll_stale_count"
    private const val KEY_PROTECTION_ALERT_COUNT = "protection_alert_count"

    fun recordGateLaunch(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .putLong(KEY_LAST_GATE_LAUNCH_MS, System.currentTimeMillis())
            .putInt(KEY_GATE_LAUNCH_COUNT, prefs.getInt(KEY_GATE_LAUNCH_COUNT, 0) + 1)
            .apply()
    }

    fun recordGateReady(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_LAST_GATE_READY_MS, System.currentTimeMillis())
            .apply()
        AnkiBlockApplication.touchEngineActivity(context)
    }

    fun recordBlankTimeout(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .putLong(KEY_LAST_BLANK_TIMEOUT_MS, System.currentTimeMillis())
            .putInt(KEY_BLANK_TIMEOUT_COUNT, prefs.getInt(KEY_BLANK_TIMEOUT_COUNT, 0) + 1)
            .apply()
    }

    fun recordPoll(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_LAST_POLL_MS, System.currentTimeMillis())
            .apply()
    }

    fun recordMonitorRestart(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .putInt(KEY_MONITOR_RESTARTS, prefs.getInt(KEY_MONITOR_RESTARTS, 0) + 1)
            .apply()
    }

    fun recordPollStale(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .putInt(KEY_POLL_STALE_COUNT, prefs.getInt(KEY_POLL_STALE_COUNT, 0) + 1)
            .apply()
    }

    fun recordProtectionAlert(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .putInt(
                KEY_PROTECTION_ALERT_COUNT,
                prefs.getInt(KEY_PROTECTION_ALERT_COUNT, 0) + 1,
            )
            .apply()
    }

    fun recordError(context: Context, message: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_LAST_ERROR, message.take(500))
            .putInt(KEY_ERROR_COUNT, prefs.getInt(KEY_ERROR_COUNT, 0) + 1)
            .apply()
    }

    fun snapshot(context: Context): Map<String, Any> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val blockPrefs = context.getSharedPreferences(
            AppMonitorService.PREFS,
            Context.MODE_PRIVATE,
        )
        val blocked = (blockPrefs.getString(AppMonitorService.KEY_BLOCKED, "") ?: "")
            .split("|")
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        val now = System.currentTimeMillis()
        var activeUnlocks = 0
        for (pkg in blocked) {
            val until = blockPrefs.getLong("unlock_until_$pkg", 0L)
            if (until > now) activeUnlocks++
        }
        val monitorAlive = AppMonitorService.isRunning()
        val pollStale = AppMonitorService.isPollStale()
        val protection = ProtectionStatus.snapshot(context)
        val delegated = AppMonitorService.getDelegatedSessionState(context)
        val unlockMs = blockPrefs.getLong(
            AppMonitorService.KEY_UNLOCK_DURATION_MS,
            AppMonitorService.DEFAULT_UNLOCK_DURATION_MS,
        )
        val versionInfo = run {
            try {
                val pi = context.packageManager.getPackageInfo(context.packageName, 0)
                val build = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    pi.longVersionCode
                } else {
                    @Suppress("DEPRECATION")
                    pi.versionCode.toLong()
                }
                Pair(pi.versionName ?: "unknown", build)
            } catch (_: Throwable) {
                Pair("unknown", 0L)
            }
        }

        val out = linkedMapOf<String, Any>(
            // Device / app
            "deviceManufacturer" to Build.MANUFACTURER,
            "deviceModel" to Build.MODEL,
            "androidSdk" to Build.VERSION.SDK_INT,
            "appVersion" to versionInfo.first,
            "appBuild" to versionInfo.second,
            // Permissions / protection
            "usage" to (protection["usage"] ?: false),
            "overlay" to (protection["overlay"] ?: false),
            "batteryUnrestricted" to (protection["batteryUnrestricted"] ?: false),
            "hasBlockedApps" to (protection["hasBlockedApps"] ?: false),
            "blockingEnabled" to (protection["blockingEnabled"] ?: false),
            "protectionActive" to (protection["protectionActive"] ?: false),
            "oemManufacturer" to (protection["oemManufacturer"] ?: "unknown"),
            // Blocking config (native mirror of Flutter block rule)
            "blockedAppCount" to blocked.size,
            "activeUnlockCount" to activeUnlocks,
            "studyMode" to (
                blockPrefs.getString(
                    AppMonitorService.KEY_STUDY_MODE,
                    AppMonitorService.STUDY_MODE_CARD_COUNT,
                ) ?: AppMonitorService.STUDY_MODE_CARD_COUNT
            ),
            "unlockGoalCards" to AppMonitorService.unlockGoal(blockPrefs),
            "unlockDurationMin" to (unlockMs / 60_000L).toInt().coerceAtLeast(1),
            "bypassEnabled" to blockPrefs.getBoolean(
                AppMonitorService.KEY_BYPASS_ENABLED,
                true,
            ),
            "bypassSeconds" to blockPrefs.getInt(
                AppMonitorService.KEY_BYPASS_SECONDS,
                AppMonitorService.DEFAULT_BYPASS_SECONDS,
            ),
            "dailyGoal" to blockPrefs.getInt(AppMonitorService.KEY_DAILY_GOAL, 0),
            "dailyReviewed" to blockPrefs.getInt(
                AppMonitorService.KEY_DAILY_REVIEWED,
                0,
            ),
            "studyDayKey" to (blockPrefs.getString(AppMonitorService.KEY_STUDY_DAY, "") ?: ""),
            "studyBoutCount" to AppMonitorService.peekStudyBoutCountPublic(context),
            // Monitor health
            "shouldStartMonitor" to MonitorBootstrap.shouldStartMonitor(context),
            "monitorProcessAlive" to monitorAlive,
            "pollStale" to pollStale,
            "monitorRunning" to (monitorAlive && !pollStale),
            "lastPollAgeMs" to run {
                val last = AppMonitorService.lastPollMs
                if (last <= 0L) 0L else now - last
            },
            "lastGateLaunchMs" to prefs.getLong(KEY_LAST_GATE_LAUNCH_MS, 0L),
            "lastGateReadyMs" to prefs.getLong(KEY_LAST_GATE_READY_MS, 0L),
            "lastBlankTimeoutMs" to prefs.getLong(KEY_LAST_BLANK_TIMEOUT_MS, 0L),
            "blankTimeoutCount" to prefs.getInt(KEY_BLANK_TIMEOUT_COUNT, 0),
            "lastPollMs" to prefs.getLong(KEY_LAST_POLL_MS, 0L),
            "monitorRestarts" to prefs.getInt(KEY_MONITOR_RESTARTS, 0),
            "gateLaunchCount" to prefs.getInt(KEY_GATE_LAUNCH_COUNT, 0),
            "errorCount" to prefs.getInt(KEY_ERROR_COUNT, 0),
            "pollStaleCount" to prefs.getInt(KEY_POLL_STALE_COUNT, 0),
            "protectionAlertCount" to prefs.getInt(KEY_PROTECTION_ALERT_COUNT, 0),
            // Flutter engine
            "engineAgeMs" to run {
                val last = AnkiBlockApplication.lastEngineActivityMs(context)
                if (last <= 0L) 0L else now - last
            },
            "engineRecycleCount" to AnkiBlockApplication.engineRecycleCount(context),
            "engineStale" to AnkiBlockApplication.isEngineStale(context),
            "flutterGateReady" to GateFallbackOverlay.isFlutterGateReady(),
            "lastError" to (prefs.getString(KEY_LAST_ERROR, "") ?: ""),
        )

        out["delegatedSessionActive"] = delegated != null
        if (delegated != null) {
            out["delegatedPackage"] = delegated["packageName"] ?: ""
            out["delegatedTarget"] = delegated["target"] ?: 0
            out["delegatedCompleted"] = delegated["completed"] ?: 0
        }

        return out
    }
}
