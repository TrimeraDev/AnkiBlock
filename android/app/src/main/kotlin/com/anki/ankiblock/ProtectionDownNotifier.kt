package com.anki.ankiblock

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

/**
 * Persistent alert when blocking should be active but the monitor is dead.
 */
object ProtectionDownNotifier {
    fun show(context: Context) {
        GateDiagnostics.recordProtectionAlert(context)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    AppMonitorService.CHANNEL_ID_ALERT,
                    "Protection alerts",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        }
        val open = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        val pi = PendingIntent.getActivity(context, 0, open, flags)
        val notification = NotificationCompat.Builder(
            context,
            AppMonitorService.CHANNEL_ID_ALERT,
        )
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentTitle("AnkiBlock protection is off")
            .setContentText(
                "App blocking stopped. Open AnkiBlock or check battery settings.",
            )
            .setContentIntent(pi)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
        nm.notify(AppMonitorService.PROTECTION_ALERT_NOTIFICATION_ID, notification)
    }

    fun dismiss(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(AppMonitorService.PROTECTION_ALERT_NOTIFICATION_ID)
    }
}
