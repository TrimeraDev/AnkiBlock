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
            }
            return false
        }
        if (AppMonitorService.isRunning()) return true
        return try {
            val intent = Intent(context, AppMonitorService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            MonitorWatchdog.schedule(context)
            Log.i(TAG, "AppMonitorService start requested")
            true
        } catch (e: Throwable) {
            Log.w(TAG, "Failed to start AppMonitorService", e)
            false
        }
    }

    fun hasBlockedPackages(context: Context): Boolean {
        val prefs = context.getSharedPreferences(AppMonitorService.PREFS, Context.MODE_PRIVATE)
        val blocked = prefs.getString(AppMonitorService.KEY_BLOCKED, "") ?: ""
        val mode = prefs.getString(
            AppMonitorService.KEY_BLOCKING_MODE,
            AppMonitorService.BLOCKING_MODE_SELECTED,
        ) ?: AppMonitorService.BLOCKING_MODE_SELECTED
        return blocked.isNotEmpty() || mode == AppMonitorService.BLOCKING_MODE_LOCKDOWN
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
}
