package com.anki.ankiblock

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * Unlock / study notifications:
 * - Low-importance study progress while working toward an unlock
 * - Low-importance ongoing timer while unlocked
 * - Default-importance alert ~60s before the window ends
 *
 * In-process Handlers keep the shade snappy while alive; [UnlockAlarmReceiver]
 * alarms survive OEM process kills for warning + expiry.
 */
object UnlockNotificationManager {
    private const val TAG = "AnkiBlock.UnlockNotif"

    private const val CHANNEL_STATUS = "unlock_status"
    private const val CHANNEL_WARNING = "unlock_warning"
    private const val ID_PROGRESS = 7100
    private const val ID_STATUS = 7101
    private const val ID_WARNING = 7102

    const val WARNING_LEAD_MS = 60_000L
    private const val TICK_SLOW_MS = 15_000L
    private const val TICK_FAST_MS = 1_000L
    private const val FAST_THRESHOLD_MS = 2 * 60_000L

    private val mainHandler = Handler(Looper.getMainLooper())
    private var tickRunnable: Runnable? = null
    private var warningRunnable: Runnable? = null
    private var warningFiredForUntil = 0L

    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_STATUS,
                "Unlock timer",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Silent study progress and unlock timer in the shade"
                setShowBadge(false)
            },
        )
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_WARNING,
                "Unlock ending soon",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Alert about one minute before apps and sites lock again"
            },
        )
    }

    fun canPost(context: Context): Boolean {
        val nm = context.getSystemService(NotificationManager::class.java)
        if (nm != null && !nm.areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    /** Start or refresh timer + warning schedules from current unlock prefs. */
    fun sync(context: Context) {
        ensureChannels(context)
        val prefs = context.getSharedPreferences(AppMonitorService.PREFS, Context.MODE_PRIVATE)
        val remaining = AppMonitorService.unlockRemainingMs(prefs)
        if (remaining <= 0L) {
            clear(context)
            return
        }
        val until = prefs.getLong(AppMonitorService.KEY_UNLOCK_UNTIL, 0L)
        val showTimer = prefs.getBoolean(
            AppMonitorService.KEY_UNLOCK_TIMER_NOTIF,
            true,
        )
        val showWarning = prefs.getBoolean(
            AppMonitorService.KEY_UNLOCK_WARNING_NOTIF,
            true,
        )
        val allowed = canPost(context)
        if (!allowed) {
            Log.w(TAG, "cannot post notifications (permission or app notifications off)")
        }

        // Process-death backup for warning + expiry, regardless of shade toggles.
        UnlockAlarmReceiver.schedule(context, until, remaining)

        if (showTimer && allowed) {
            postStatus(context, remaining)
            scheduleTick(context)
        } else {
            cancelStatus(context)
            cancelTick()
        }

        if (showWarning && allowed) {
            scheduleWarning(context, until, remaining)
        } else {
            cancelWarningSchedule()
        }
    }

    fun clear(context: Context) {
        cancelTick()
        cancelWarningSchedule()
        UnlockAlarmReceiver.cancelAll(context)
        warningFiredForUntil = 0L
        cancelStatus(context)
        cancelWarningNotification(context)
    }

    /**
     * Silent, ongoing study-progress notification while a delegated session
     * is in flight: "N / target · keep going".
     */
    fun postProgress(context: Context, completed: Int, target: Int) {
        ensureChannels(context)
        val prefs = context.getSharedPreferences(AppMonitorService.PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(AppMonitorService.KEY_PROGRESS_NOTIF, true)) return
        if (!canPost(context)) {
            Log.w(TAG, "cannot post progress (permission or app notifications off)")
            return
        }
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        val safeTarget = target.coerceAtLeast(1)
        val done = completed.coerceIn(0, safeTarget)
        val dueMode = prefs.getString(
            AppMonitorService.KEY_STUDY_MODE,
            AppMonitorService.STUDY_MODE_CARD_COUNT,
        ) == AppMonitorService.STUDY_MODE_DUE_CARDS
        val unit = if (dueMode) "due" else "cards"
        val text = if (done >= safeTarget) {
            "Goal reached — unlocking…"
        } else {
            "$done / $safeTarget $unit · keep going!"
        }
        val notif = NotificationCompat.Builder(context, CHANNEL_STATUS)
            .setSmallIcon(R.drawable.ic_stat_unlock)
            .setContentTitle("Study progress")
            .setContentText(text)
            .setProgress(safeTarget, done, false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(openAppPendingIntent(context))
            .setShowWhen(false)
            .build()
        try {
            nm.notify(ID_PROGRESS, notif)
            Log.i(TAG, "progress posted ($text)")
        } catch (e: Throwable) {
            Log.w(TAG, "progress notify failed", e)
            GateDiagnostics.recordError(context, "progress notif: ${e.message}")
        }
    }

    fun clearProgress(context: Context) {
        try {
            context.getSystemService(NotificationManager::class.java)?.cancel(ID_PROGRESS)
        } catch (_: Throwable) {
        }
    }

    /** Alarm path: fire the 60s warning even if the process was killed. */
    fun onWarningAlarm(context: Context) {
        ensureChannels(context)
        val prefs = context.getSharedPreferences(AppMonitorService.PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(AppMonitorService.KEY_UNLOCK_WARNING_NOTIF, true)) return
        val left = AppMonitorService.unlockRemainingMs(prefs)
        if (left <= 0L) return
        val until = prefs.getLong(AppMonitorService.KEY_UNLOCK_UNTIL, 0L)
        if (until == warningFiredForUntil) return
        if (!canPost(context)) return
        warningFiredForUntil = until
        postWarning(context, left)
    }

    /** Alarm path: clear unlock prefs and ask the a11y engine to re-gate. */
    fun onExpiryAlarm(context: Context) {
        val prefs = context.getSharedPreferences(AppMonitorService.PREFS, Context.MODE_PRIVATE)
        val remaining = AppMonitorService.unlockRemainingMs(prefs)
        if (remaining > 0L) {
            // Window was extended after this alarm was scheduled.
            sync(context)
            AppMonitorService.engine?.onTemporaryUnlock()
            return
        }
        prefs.edit().remove(AppMonitorService.KEY_UNLOCK_UNTIL).apply()
        clear(context)
        clearProgress(context)
        AppMonitorService.engine?.onUnlockWindowExpired()
        Log.i(TAG, "expiry alarm — unlock cleared, re-gate requested")
    }

    private fun scheduleTick(context: Context) {
        cancelTick()
        val appCtx = context.applicationContext
        val r = object : Runnable {
            override fun run() {
                tickRunnable = null
                val prefs = appCtx.getSharedPreferences(
                    AppMonitorService.PREFS,
                    Context.MODE_PRIVATE,
                )
                val remaining = AppMonitorService.unlockRemainingMs(prefs)
                if (remaining <= 0L ||
                    !prefs.getBoolean(AppMonitorService.KEY_UNLOCK_TIMER_NOTIF, true)
                ) {
                    cancelStatus(appCtx)
                    return
                }
                if (!canPost(appCtx)) return
                postStatus(appCtx, remaining)
                val delay = if (remaining <= FAST_THRESHOLD_MS) TICK_FAST_MS else TICK_SLOW_MS
                tickRunnable = this
                mainHandler.postDelayed(this, delay)
            }
        }
        tickRunnable = r
        val remaining = AppMonitorService.unlockRemainingMs(
            context.getSharedPreferences(AppMonitorService.PREFS, Context.MODE_PRIVATE),
        )
        val delay = if (remaining <= FAST_THRESHOLD_MS) TICK_FAST_MS else TICK_SLOW_MS
        mainHandler.postDelayed(r, delay)
    }

    private fun cancelTick() {
        tickRunnable?.let { mainHandler.removeCallbacks(it) }
        tickRunnable = null
    }

    private fun scheduleWarning(context: Context, until: Long, remaining: Long) {
        cancelWarningSchedule()
        if (until <= 0L || until == warningFiredForUntil) return
        val appCtx = context.applicationContext
        val delay = (remaining - WARNING_LEAD_MS).coerceAtLeast(0L)
        val r = Runnable {
            warningRunnable = null
            val prefs = appCtx.getSharedPreferences(
                AppMonitorService.PREFS,
                Context.MODE_PRIVATE,
            )
            if (!prefs.getBoolean(AppMonitorService.KEY_UNLOCK_WARNING_NOTIF, true)) return@Runnable
            val left = AppMonitorService.unlockRemainingMs(prefs)
            if (left <= 0L) return@Runnable
            val currentUntil = prefs.getLong(AppMonitorService.KEY_UNLOCK_UNTIL, 0L)
            if (currentUntil != until) return@Runnable
            if (!canPost(appCtx)) return@Runnable
            warningFiredForUntil = until
            postWarning(appCtx, left)
        }
        warningRunnable = r
        mainHandler.postDelayed(r, delay)
    }

    private fun cancelWarningSchedule() {
        warningRunnable?.let { mainHandler.removeCallbacks(it) }
        warningRunnable = null
    }

    private fun postStatus(context: Context, remainingMs: Long) {
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        val text = "Unlocked · ${formatRemaining(remainingMs)} left"
        val notif = NotificationCompat.Builder(context, CHANNEL_STATUS)
            .setSmallIcon(R.drawable.ic_stat_unlocked)
            .setContentTitle("AnkiBlock")
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(openAppPendingIntent(context))
            .setShowWhen(false)
            .build()
        try {
            nm.notify(ID_STATUS, notif)
            Log.i(TAG, "status posted ($text)")
        } catch (e: Throwable) {
            Log.w(TAG, "status notify failed", e)
            GateDiagnostics.recordError(context, "unlock notif: ${e.message}")
        }
    }

    private fun postWarning(context: Context, remainingMs: Long) {
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        val seconds = ((remainingMs + 999) / 1000).toInt().coerceAtLeast(1)
        val text = if (seconds >= 60) {
            "About 1 minute left — apps and sites lock soon"
        } else {
            "$seconds seconds left — apps and sites lock soon"
        }
        val notif = NotificationCompat.Builder(context, CHANNEL_WARNING)
            .setSmallIcon(R.drawable.ic_stat_warning)
            .setContentTitle("Unlock ending soon")
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(openAppPendingIntent(context))
            .build()
        try {
            nm.notify(ID_WARNING, notif)
            Log.i(TAG, "warning posted ($seconds s left)")
        } catch (e: Throwable) {
            Log.w(TAG, "warning notify failed", e)
            GateDiagnostics.recordError(context, "unlock warn: ${e.message}")
        }
    }

    private fun cancelStatus(context: Context) {
        try {
            context.getSystemService(NotificationManager::class.java)
                ?.cancel(ID_STATUS)
        } catch (_: Throwable) {
        }
    }

    private fun cancelWarningNotification(context: Context) {
        try {
            context.getSystemService(NotificationManager::class.java)
                ?.cancel(ID_WARNING)
        } catch (_: Throwable) {
        }
    }

    private fun openAppPendingIntent(context: Context): PendingIntent {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)
        launch.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        return PendingIntent.getActivity(context, 0, launch, flags)
    }

    fun formatRemaining(ms: Long): String {
        val totalSec = ((ms + 999) / 1000).toInt().coerceAtLeast(0)
        val h = totalSec / 3600
        val m = (totalSec % 3600) / 60
        val s = totalSec % 60
        return when {
            h > 0 -> String.format("%d:%02d:%02d", h, m, s)
            else -> String.format("%d:%02d", m, s)
        }
    }
}
