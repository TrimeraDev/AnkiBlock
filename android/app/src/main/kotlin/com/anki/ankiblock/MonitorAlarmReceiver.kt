package com.anki.ankiblock

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log

/**
 * AlarmManager backup for [MonitorWatchdog]. WorkManager's 15-minute floor can
 * stretch under doze; a tighter alarm helps resurrect the monitor after OEM kills.
 */
class MonitorAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        Log.i(TAG, "alarm fired — ensuring monitor")
        val app = context.applicationContext
        val started = MonitorBootstrap.startMonitorIfNeeded(app)
        if (!started && MonitorBootstrap.shouldStartMonitor(app) &&
            (!AppMonitorService.isRunning() || AppMonitorService.isPollStale())
        ) {
            // Blocking should be on but service is dead — alert the user.
            ProtectionDownNotifier.show(app)
        }
        schedule(app)
    }

    companion object {
        private const val TAG = "AnkiBlock.Alarm"
        private const val ACTION = "com.ankiblock.MONITOR_ALARM"
        private const val REQUEST_CODE = 7101
        private const val INTERVAL_MS = 5L * 60L * 1000L

        fun schedule(context: Context) {
            if (!MonitorBootstrap.shouldStartMonitor(context) &&
                !MonitorBootstrap.hasBlockedPackages(context)
            ) {
                cancel(context)
                return
            }
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pi = pendingIntent(context)
            val triggerAt = SystemClock.elapsedRealtime() + INTERVAL_MS
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    am.setAndAllowWhileIdle(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        triggerAt,
                        pi,
                    )
                } else {
                    @Suppress("DEPRECATION")
                    am.set(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, pi)
                }
            } catch (e: Throwable) {
                Log.w(TAG, "schedule failed", e)
            }
        }

        fun scheduleImmediate(context: Context) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pi = pendingIntent(context)
            val triggerAt = SystemClock.elapsedRealtime() + 2_000L
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    am.setAndAllowWhileIdle(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        triggerAt,
                        pi,
                    )
                } else {
                    @Suppress("DEPRECATION")
                    am.set(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, pi)
                }
            } catch (e: Throwable) {
                Log.w(TAG, "immediate schedule failed", e)
            }
        }

        fun cancel(context: Context) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.cancel(pendingIntent(context))
        }

        private fun pendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, MonitorAlarmReceiver::class.java).apply {
                action = ACTION
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE
                } else {
                    0
                }
            return PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)
        }
    }
}
