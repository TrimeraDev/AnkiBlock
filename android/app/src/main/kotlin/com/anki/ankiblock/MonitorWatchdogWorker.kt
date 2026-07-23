package com.anki.ankiblock

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

/**
 * Periodically verifies that [AppMonitorService] is still running and restarts
 * it when OEM battery killers stop the service mid-day.
 */
class MonitorWatchdogWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        return if (MonitorBootstrap.startMonitorIfNeeded(applicationContext)) {
            Result.success()
        } else {
            Result.success()
        }
    }
}
