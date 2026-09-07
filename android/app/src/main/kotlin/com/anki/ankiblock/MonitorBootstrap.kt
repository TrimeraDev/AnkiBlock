package com.anki.ankiblock

import android.app.AppOpsManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Process
import android.provider.Settings
import android.util.Log

/** Permission / configuration checks shared by protection status and diagnostics. */
object MonitorBootstrap {
    private const val TAG = "AnkiBlock.Bootstrap"

    /** True when blocking is configured such that the a11y service should be gating. */
    fun shouldStartMonitor(context: Context): Boolean {
        if (!hasBlockedPackages(context)) return false
        if (!AppMonitorService.isBlockingEnabled(context)) return false
        if (!AnkiBlockAccessibilityService.isEnabled(context)) return false
        return true
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

    /**
     * Opens Accessibility settings, deep-linked to AnkiBlock's own service page
     * (the screen with the on/off toggle) where the platform supports it.
     * Android never lets an app enable an AccessibilityService itself, and the
     * system confirmation dialog after the toggle is mandatory; this just
     * removes the "find AnkiBlock in the list" step.
     */
    fun openAccessibilitySettings(context: Context) {
        val component = ComponentName(context, AnkiBlockAccessibilityService::class.java)
            .flattenToString()
        val deepLink = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
            // Undocumented but long-standing SettingsActivity extras (AOSP,
            // Pixel, Samsung, most OEMs): open the fragment for one service.
            putExtra(EXTRA_FRAGMENT_ARG_KEY, component)
            putExtra(
                EXTRA_SHOW_FRAGMENT_ARGS,
                Bundle().apply { putString(EXTRA_FRAGMENT_ARG_KEY, component) },
            )
        }
        try {
            context.startActivity(deepLink)
            return
        } catch (e: Throwable) {
            Log.w(TAG, "accessibility deep link failed, falling back", e)
        }
        try {
            context.startActivity(
                Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                },
            )
        } catch (e: Throwable) {
            Log.w(TAG, "openAccessibilitySettings failed", e)
        }
    }

    private const val EXTRA_FRAGMENT_ARG_KEY = ":settings:fragment_args_key"
    private const val EXTRA_SHOW_FRAGMENT_ARGS = ":settings:show_fragment_args"
}
