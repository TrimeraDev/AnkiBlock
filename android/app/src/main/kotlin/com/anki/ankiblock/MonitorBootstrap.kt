package com.anki.ankiblock

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Process
import android.util.Log

/**
 * Shared logic for starting [AppMonitorService] after boot, on app resume, or
 * from the periodic watchdog.
 */
object MonitorBootstrap {
    private const val TAG = "AnkiBlock.Bootstrap"

    fun shouldStartMonitor(context: Context): Boolean {
        if (!hasBlockedPackages(context)) return false
        if (!AppMonitorService.isBlockingEnabled(context)) return false
        if (!hasUsageAccess(context)) return false
        return true
    }

    fun startMonitorIfNeeded(context: Context): Boolean {
        if (!shouldStartMonitor(context)) {
            if (!hasBlockedPackages(context)) {
                MonitorWatchdog.cancel(context)
                MonitorAlarmReceiver.cancel(context)
            } else {
                // Still schedule watchdogs so we retry when usage access returns.
                MonitorWatchdog.schedule(context)
                MonitorAlarmReceiver.schedule(context)
            }
            return false
        }
        if (AppMonitorService.isRunning()) {
            if (AppMonitorService.isPollStale()) {
                Log.w(TAG, "Monitor poll stale — forcing restart")
                GateDiagnostics.recordPollStale(context)
                forceStopMonitor(context)
            } else {
                ProtectionDownNotifier.dismiss(context)
                MonitorWatchdog.schedule(context)
                MonitorAlarmReceiver.schedule(context)
                return true
            }
        }
        return try {
            val intent = Intent(context, AppMonitorService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            MonitorWatchdog.schedule(context)
            MonitorAlarmReceiver.schedule(context)
            ProtectionDownNotifier.dismiss(context)
            Log.i(TAG, "AppMonitorService start requested")
            true
        } catch (e: Throwable) {
            Log.w(TAG, "Failed to start AppMonitorService", e)
            GateDiagnostics.recordError(context, "monitor start failed: ${e.message}")
            MonitorWatchdog.schedule(context)
            MonitorAlarmReceiver.schedule(context)
            false
        }
    }

    fun hasBlockedPackages(context: Context): Boolean {
        val prefs = context.getSharedPreferences(AppMonitorService.PREFS, Context.MODE_PRIVATE)
        val blocked = prefs.getString(AppMonitorService.KEY_BLOCKED, "") ?: ""
        return blocked.isNotEmpty()
    }

    fun hasUsageAccess(context: Context): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun forceStopMonitor(context: Context) {
        try {
            val intent = Intent(context, AppMonitorService::class.java).apply {
                action = AppMonitorService.ACTION_STOP
            }
            context.stopService(intent)
        } catch (e: Throwable) {
            Log.w(TAG, "force stop monitor failed", e)
        }
    }
}
