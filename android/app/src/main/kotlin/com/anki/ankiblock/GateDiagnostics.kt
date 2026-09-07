package com.anki.ankiblock

import android.content.Context
import android.os.Build

/**
 * Persists gate / monitor health counters for the Flutter diagnostics panel.
 */
object GateDiagnostics {
    private const val PREFS = "ankiblock_gate_diagnostics"
    private const val KEY_LAST_GATE_SHOWN_MS = "last_gate_shown_ms"
    private const val KEY_GATE_SHOWN_COUNT = "gate_shown_count"
    private const val KEY_LAST_EVENT_MS = "last_event_ms"
    private const val KEY_MONITOR_RESTARTS = "monitor_restarts"
    private const val KEY_LAST_ERROR = "last_error"
    private const val KEY_ERROR_COUNT = "error_count"

    fun recordGateShown(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .putLong(KEY_LAST_GATE_SHOWN_MS, System.currentTimeMillis())
            .putInt(KEY_GATE_SHOWN_COUNT, prefs.getInt(KEY_GATE_SHOWN_COUNT, 0) + 1)
            .apply()
    }

    /** Called on every accessibility window event (throttled by the caller). */
    fun recordEvent(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_LAST_EVENT_MS, System.currentTimeMillis())
            .apply()
    }

    fun recordMonitorRestart(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .putInt(KEY_MONITOR_RESTARTS, prefs.getInt(KEY_MONITOR_RESTARTS, 0) + 1)
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
        val engineConnected = AppMonitorService.isRunning()
        val a11yEnabled = AnkiBlockAccessibilityService.isEnabled(context)
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
            "accessibility" to a11yEnabled,
            "batteryUnrestricted" to (protection["batteryUnrestricted"] ?: false),
            "hasBlockedApps" to (protection["hasBlockedApps"] ?: false),
            "hasAnythingToBlock" to (protection["hasAnythingToBlock"] ?: false),
            "blockingEnabled" to (protection["blockingEnabled"] ?: false),
            "protectionActive" to (protection["protectionActive"] ?: false),
            "oemManufacturer" to (protection["oemManufacturer"] ?: "unknown"),
            // Blocking config (native mirror of Flutter block rule)
            "blockedAppCount" to blocked.size,
            "websiteRuleCount" to WebsiteRules.load(blockPrefs).size,
            "blockUnsupportedBrowsers" to AppMonitorService.blockUnsupportedBrowsers(blockPrefs),
            "lastUrlCheckMs" to (AppMonitorService.engine?.lastUrlCheckAtMs() ?: 0L),
            "lastUrlHost" to (AppMonitorService.engine?.lastInspectedUrlHost() ?: ""),
            "supportedBrowsersInstalled" to BrowserUrlDetector.SUPPORTED_BROWSERS.keys.count {
                try {
                    context.packageManager.getApplicationInfo(it, 0)
                    true
                } catch (_: Throwable) {
                    false
                }
            },
            "unlockRemainingMs" to AppMonitorService.unlockRemainingMs(blockPrefs),
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
            "bypassDailyCap" to blockPrefs.getInt(
                AppMonitorService.KEY_BYPASS_DAILY_CAP,
                AppMonitorService.DEFAULT_BYPASS_DAILY_CAP,
            ),
            "dailyGoal" to blockPrefs.getInt(AppMonitorService.KEY_DAILY_GOAL, 0),
            "dailyReviewed" to blockPrefs.getInt(
                AppMonitorService.KEY_DAILY_REVIEWED,
                0,
            ),
            "studyDayKey" to (blockPrefs.getString(AppMonitorService.KEY_STUDY_DAY, "") ?: ""),
            "studyBoutCount" to AppMonitorService.peekStudyBoutCount(context),
            // Today's native gate counters
            "blockedAttempts" to GateStats.blockedAttempts(context),
            "bypassesUsed" to GateStats.bypassesUsed(context),
            "unlocksEarned" to GateStats.unlocksEarned(context),
            // Monitor health (AccessibilityService)
            "shouldStartMonitor" to MonitorBootstrap.shouldStartMonitor(context),
            "accessibilityEnabled" to a11yEnabled,
            "engineConnected" to engineConnected,
            "monitorRunning" to (a11yEnabled && engineConnected),
            "lastEventAgeMs" to run {
                val last = AppMonitorService.lastEventMs
                if (last <= 0L) 0L else now - last
            },
            "lastEventMs" to prefs.getLong(KEY_LAST_EVENT_MS, 0L),
            "monitorRestarts" to prefs.getInt(KEY_MONITOR_RESTARTS, 0),
            // Study gate (native overlay)
            "gateShowing" to (AppMonitorService.engine?.isGateShowing() ?: false),
            "lastGateShownMs" to prefs.getLong(KEY_LAST_GATE_SHOWN_MS, 0L),
            "gateShownCount" to prefs.getInt(KEY_GATE_SHOWN_COUNT, 0),
            "errorCount" to prefs.getInt(KEY_ERROR_COUNT, 0),
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
