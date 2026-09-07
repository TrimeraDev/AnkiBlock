package com.anki.ankiblock

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Survives process death for unlock warning + expiry. [UnlockNotificationManager]
 * still uses in-process Handlers while alive for snappy UI; these alarms are the
 * backup so the 60s warning and re-lock still fire after an OEM kill.
 */
class UnlockAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            ACTION_WARNING -> UnlockNotificationManager.onWarningAlarm(context)
            ACTION_EXPIRED -> UnlockNotificationManager.onExpiryAlarm(context)
            else -> Log.w(TAG, "unknown action ${intent?.action}")
        }
    }

    companion object {
        private const val TAG = "AnkiBlock.UnlockAlarm"

        const val ACTION_WARNING = "com.anki.ankiblock.action.UNLOCK_WARNING"
        const val ACTION_EXPIRED = "com.anki.ankiblock.action.UNLOCK_EXPIRED"

        private const val REQ_WARNING = 7201
        private const val REQ_EXPIRED = 7202

        fun schedule(context: Context, untilMs: Long, remainingMs: Long) {
            if (untilMs <= 0L || remainingMs <= 0L) {
                cancelAll(context)
                return
            }
            val appCtx = context.applicationContext
            val am = appCtx.getSystemService(AlarmManager::class.java) ?: return
            val now = System.currentTimeMillis()

            val warnAt = untilMs - UnlockNotificationManager.WARNING_LEAD_MS
            if (warnAt > now) {
                setAlarm(am, warnAt, warningPendingIntent(appCtx))
            } else {
                cancel(am, warningPendingIntent(appCtx))
            }
            setAlarm(am, untilMs, expiredPendingIntent(appCtx))
            Log.i(TAG, "alarms armed warnAt=$warnAt expireAt=$untilMs")
        }

        fun cancelAll(context: Context) {
            val appCtx = context.applicationContext
            val am = appCtx.getSystemService(AlarmManager::class.java) ?: return
            cancel(am, warningPendingIntent(appCtx))
            cancel(am, expiredPendingIntent(appCtx))
        }

        private fun setAlarm(am: AlarmManager, triggerAt: Long, pi: PendingIntent) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                        !am.canScheduleExactAlarms()
                    ) {
                        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
                    } else {
                        am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
                    }
                } else {
                    @Suppress("DEPRECATION")
                    am.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pi)
                }
            } catch (e: SecurityException) {
                Log.w(TAG, "exact alarm denied — falling back to inexact", e)
                try {
                    am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
                } catch (e2: Throwable) {
                    Log.w(TAG, "alarm schedule failed", e2)
                }
            } catch (e: Throwable) {
                Log.w(TAG, "alarm schedule failed", e)
            }
        }

        private fun cancel(am: AlarmManager, pi: PendingIntent) {
            try {
                am.cancel(pi)
            } catch (_: Throwable) {
            }
            try {
                pi.cancel()
            } catch (_: Throwable) {
            }
        }

        private fun warningPendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, UnlockAlarmReceiver::class.java).setAction(ACTION_WARNING)
            return PendingIntent.getBroadcast(context, REQ_WARNING, intent, pendingFlags())
        }

        private fun expiredPendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, UnlockAlarmReceiver::class.java).setAction(ACTION_EXPIRED)
            return PendingIntent.getBroadcast(context, REQ_EXPIRED, intent, pendingFlags())
        }

        private fun pendingFlags(): Int {
            return PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE
                } else {
                    0
                }
        }
    }
}
