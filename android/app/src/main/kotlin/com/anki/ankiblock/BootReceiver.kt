package com.anki.ankiblock

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Restarts [AppMonitorService] after reboot or app update so blocking works
 * without requiring the user to open AnkiBlock first.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        when (action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            ACTION_QUICKBOOT_POWERON,
            -> {
                Log.i(TAG, "Received $action — checking monitor")
                MonitorBootstrap.startMonitorIfNeeded(context.applicationContext)
            }
        }
    }

    companion object {
        private const val TAG = "AnkiBlock.Boot"
        private const val ACTION_QUICKBOOT_POWERON =
            "android.intent.action.QUICKBOOT_POWERON"
    }
}
