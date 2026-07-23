package com.anki.ankiblock

import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build
import java.util.Calendar

/** Today's pickups and screen time for blocked apps (gate usage line). */
object UsageStatsHelper {

    data class FocusUsage(
        val focusPickups: Int,
        val focusScreenTimeMs: Long,
    )

    fun focusUsageToday(context: Context, focusPackage: String): FocusUsage {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            return FocusUsage(0, 0L)
        }
        val start = startOfTodayMillis()
        val end = System.currentTimeMillis()
        val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

        var focusScreenMs = 0L
        val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, start, end)
            ?: emptyList()
        for (s in stats) {
            if (s.packageName == focusPackage) {
                focusScreenMs += s.totalTimeInForeground
            }
        }

        var focusPickups = 0
        val events = usm.queryEvents(start, end)
        val ev = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(ev)
            if (ev.eventType != UsageEvents.Event.MOVE_TO_FOREGROUND) continue
            if (ev.packageName == focusPackage) focusPickups++
        }

        return FocusUsage(focusPickups, focusScreenMs)
    }

    private fun startOfTodayMillis(): Long {
        val cal = Calendar.getInstance()
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }

    fun formatFocusUsage(pickups: Int, screenMs: Long): String {
        val opens = if (pickups == 1) "1 open" else "$pickups opens"
        val totalMin = (screenMs / 60_000).toInt()
        val h = totalMin / 60
        val m = totalMin % 60
        val duration = if (h > 0) "${h}h, $m min" else "$m min"
        return "$opens today · $duration on this app"
    }
}
