package com.anki.ankiblock

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings

object ProtectionStatus {
    fun snapshot(context: Context): Map<String, Any> {
        val usage = MonitorBootstrap.hasUsageAccess(context)
        val overlay = hasOverlayPermission(context)
        val batteryUnrestricted = isIgnoringBatteryOptimizations(context)
        val monitorRunning = AppMonitorService.isRunning() &&
            !AppMonitorService.isPollStale()
        val hasBlockedApps = MonitorBootstrap.hasBlockedPackages(context)
        val blockingEnabled = AppMonitorService.isBlockingEnabled(context)
        val protectionActive = hasBlockedApps &&
            blockingEnabled &&
            usage &&
            monitorRunning

        return mapOf(
            "usage" to usage,
            "overlay" to overlay,
            "batteryUnrestricted" to batteryUnrestricted,
            "monitorRunning" to monitorRunning,
            "hasBlockedApps" to hasBlockedApps,
            "blockingEnabled" to blockingEnabled,
            "protectionActive" to protectionActive,
            "oemManufacturer" to OemSettings.manufacturerKey(),
        )
    }

    fun hasOverlayPermission(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(context)
        } else {
            true
        }
    }

    fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    fun requestBatteryOptimizationExemption(context: Context): Boolean {
        if (isIgnoringBatteryOptimizations(context)) return true
        return try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:${context.packageName}")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
            true
        } catch (_: Throwable) {
            openBatterySettings(context)
            false
        }
    }

    fun openBatterySettings(context: Context) {
        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        try {
            context.startActivity(intent)
        } catch (_: Throwable) {
            val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:${context.packageName}")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(fallback)
        }
    }
}
