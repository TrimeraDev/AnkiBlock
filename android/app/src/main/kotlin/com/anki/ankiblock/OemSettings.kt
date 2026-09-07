package com.anki.ankiblock

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log

/**
 * Manufacturer-specific deep links for autostart / battery settings (Honor,
 * Xiaomi, Huawei, Samsung, Oppo/OnePlus). Falls back to app details.
 */
object OemSettings {
    private const val TAG = "AnkiBlock.Oem"

    fun manufacturerKey(): String {
        val m = Build.MANUFACTURER.lowercase()
        return when {
            m.contains("huawei") -> "huawei"
            m.contains("honor") -> "honor"
            m.contains("xiaomi") || m.contains("redmi") || m.contains("poco") -> "xiaomi"
            m.contains("samsung") -> "samsung"
            m.contains("oppo") || m.contains("realme") -> "oppo"
            m.contains("oneplus") -> "oneplus"
            m.contains("vivo") -> "vivo"
            else -> m.ifBlank { "unknown" }
        }
    }

    fun openAutostartSettings(context: Context): Boolean {
        val pkg = context.packageName
        val candidates = intentsForManufacturer(pkg)
        for (intent in candidates) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (intent.resolveActivity(context.packageManager) != null) {
                    context.startActivity(intent)
                    Log.i(TAG, "opened OEM settings via ${intent.component}")
                    return true
                }
            } catch (e: Throwable) {
                Log.w(TAG, "OEM intent failed: ${intent.component}", e)
            }
        }
        return openAppDetails(context)
    }

    private fun intentsForManufacturer(pkg: String): List<Intent> {
        return when (manufacturerKey()) {
            "xiaomi" -> listOf(
                Intent().setComponent(
                    ComponentName(
                        "com.miui.securitycenter",
                        "com.miui.permcenter.autostart.AutoStartManagementActivity",
                    ),
                ),
                Intent("miui.intent.action.OP_AUTO_START").addCategory(Intent.CATEGORY_DEFAULT),
            )
            "huawei", "honor" -> listOf(
                Intent().setComponent(
                    ComponentName(
                        "com.huawei.systemmanager",
                        "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                    ),
                ),
                Intent().setComponent(
                    ComponentName(
                        "com.huawei.systemmanager",
                        "com.huawei.systemmanager.optimize.process.ProtectActivity",
                    ),
                ),
                Intent().setComponent(
                    ComponentName(
                        "com.hihonor.systemmanager",
                        "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                    ),
                ),
            )
            "samsung" -> listOf(
                Intent().setComponent(
                    ComponentName(
                        "com.samsung.android.lool",
                        "com.samsung.android.sm.battery.ui.BatteryActivity",
                    ),
                ),
                Intent().setComponent(
                    ComponentName(
                        "com.samsung.android.sm",
                        "com.samsung.android.sm.ui.battery.BatteryActivity",
                    ),
                ),
            )
            "oppo", "realme" -> listOf(
                Intent().setComponent(
                    ComponentName(
                        "com.coloros.safecenter",
                        "com.coloros.safecenter.permission.startup.StartupAppListActivity",
                    ),
                ),
                Intent().setComponent(
                    ComponentName(
                        "com.oppo.safe",
                        "com.oppo.safe.permission.startup.StartupAppListActivity",
                    ),
                ),
            )
            "oneplus" -> listOf(
                Intent().setComponent(
                    ComponentName(
                        "com.oneplus.security",
                        "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity",
                    ),
                ),
            )
            "vivo" -> listOf(
                Intent().setComponent(
                    ComponentName(
                        "com.iqoo.secure",
                        "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
                    ),
                ),
                Intent().setComponent(
                    ComponentName(
                        "com.vivo.permissionmanager",
                        "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
                    ),
                ),
            )
            else -> emptyList()
        }
    }

    private fun openAppDetails(context: Context): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:${context.packageName}")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }
}
