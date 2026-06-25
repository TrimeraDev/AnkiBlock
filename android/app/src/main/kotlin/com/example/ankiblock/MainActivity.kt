package com.example.ankiblock

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.Calendar

class MainActivity : FlutterActivity() {
    companion object {
        const val ACTION_OPEN_GATE = "com.ankiblock.OPEN_GATE"
        const val ACTION_DISMISS_GATE = "com.ankiblock.DISMISS_GATE"

        @Volatile
        private var flutterEventChannel: MethodChannel? = null

        fun notifyFlutter(method: String, arguments: Any?) {
            flutterEventChannel?.invokeMethod(method, arguments)
        }
    }

    private val channelName = "com.ankiblock/permissions"
    private val ankiDroidChannelName = "com.ankiblock/ankidroid"
    private var methodChannel: MethodChannel? = null
    private var pendingGate: Map<String, String>? = null
    private var ankiDroidApi: AnkiDroidApi? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        if (intent?.action == ACTION_DISMISS_GATE) {
            super.onCreate(savedInstanceState)
            removeGateFromRecents()
            return
        }
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        )
        methodChannel = ch
        flutterEventChannel = ch
        registerAnkiDroidChannel(flutterEngine)
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasUsageAccess" -> result.success(hasUsageAccess())
                "openUsageAccessSettings" -> {
                    val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                    intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    startActivity(intent)
                    result.success(true)
                }
                "hasOverlayPermission" -> {
                    val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        Settings.canDrawOverlays(this)
                    } else true
                    result.success(granted)
                }
                "openOverlaySettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                    }
                    result.success(true)
                }
                "getInstalledApps" -> {
                    val includeIcons = call.argument<Boolean>("icons") ?: false
                    result.success(getInstalledApps(includeIcons))
                }
                "getUsageStats" -> {
                    val days = call.argument<Int>("days") ?: 7
                    result.success(getUsageStats(days))
                }
                "getTodayBlockedUsage" -> {
                    @Suppress("UNCHECKED_CAST")
                    val packages = (call.argument<List<*>>("packages") ?: emptyList<Any?>())
                        .mapNotNull { it as? String }
                    val focus = call.argument<String>("focusPackage")
                    result.success(getTodayBlockedUsage(packages, focus))
                }
                "setBlockedPackages" -> {
                    val pkgs = (call.argument<List<String>>("packages") ?: emptyList())
                    val names = (call.argument<Map<String, String>>("names") ?: emptyMap())
                    AppMonitorService.setBlockedPackages(this, pkgs, names)
                    result.success(true)
                }
                "startAppMonitor" -> {
                    val intent = Intent(this, AppMonitorService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "stopAppMonitor" -> {
                    val intent = Intent(this, AppMonitorService::class.java)
                    intent.action = AppMonitorService.ACTION_STOP
                    stopService(intent)
                    result.success(true)
                }
                "consumePendingGate" -> {
                    val p = pendingGate
                    pendingGate = null
                    result.success(p)
                }
                "grantTempUnlock" -> {
                    val pkg = call.argument<String>("packageName") ?: ""
                    if (pkg.isNotEmpty()) {
                        AppMonitorService.grantTempUnlock(this, pkg)
                    }
                    result.success(true)
                }
                "syncDailyGoalState" -> {
                    val studyDayKey = call.argument<String>("studyDayKey") ?: ""
                    val dailyGoal = call.argument<Int>("dailyGoal") ?: 0
                    val cardsReviewed = call.argument<Int>("cardsReviewed") ?: 0
                    AppMonitorService.setDailyGoalState(
                        this,
                        studyDayKey,
                        dailyGoal,
                        cardsReviewed,
                    )
                    result.success(true)
                }
                "syncStudyScope" -> {
                    @Suppress("UNCHECKED_CAST")
                    val deckIds = (call.argument<List<*>>("deckIds") ?: emptyList<Any?>())
                        .mapNotNull { (it as? Number)?.toLong() }
                    AppMonitorService.setStudyScopeDeckIds(this, deckIds)
                    result.success(true)
                }
                "getDailyGoalState" -> {
                    result.success(AppMonitorService.getDailyGoalState(this))
                }
                "startDelegatedSession" -> {
                    val pkg = call.argument<String>("packageName") ?: ""
                    val appName = call.argument<String>("appName") ?: pkg
                    val deckId = (call.argument<Number>("deckId"))?.toLong() ?: -1L
                    val target = call.argument<Int>("target") ?: 5
                    val baseline = call.argument<Int>("baseline") ?: 0
                    @Suppress("UNCHECKED_CAST")
                    val deckIds = (call.argument<List<*>>("deckIds") ?: emptyList<Any?>())
                        .mapNotNull { (it as? Number)?.toLong() }
                    AppMonitorService.startDelegatedSession(
                        this,
                        pkg,
                        appName,
                        deckId,
                        deckIds,
                        target,
                        baseline,
                    )
                    val monitorIntent = Intent(this, AppMonitorService::class.java).apply {
                        action = AppMonitorService.ACTION_DELEGATED_START
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(monitorIntent)
                    } else {
                        startService(monitorIntent)
                    }
                    result.success(true)
                }
                "cancelDelegatedSession" -> {
                    AppMonitorService.cancelDelegatedSession(this)
                    result.success(true)
                }
                "launchApp" -> {
                    val pkg = call.argument<String>("packageName") ?: ""
                    val launch = packageManager.getLaunchIntentForPackage(pkg)
                    if (launch != null) {
                        launch.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(launch)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // If launched with a gate intent, surface it once channel is ready
        consumeGateIntent(intent)
        pendingGate?.let { notifyGateToFlutter(it) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.action == ACTION_DISMISS_GATE) {
            removeGateFromRecents()
            return
        }
        consumeGateIntent(intent)
        pendingGate?.let { notifyGateToFlutter(it) }
    }

    /** Drop the gate task from recents so it doesn't linger after unlock. */
    private fun removeGateFromRecents() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            finishAndRemoveTask()
        } else {
            @Suppress("DEPRECATION")
            finish()
        }
    }

    private fun consumeGateIntent(intent: Intent?) {
        if (intent?.action == ACTION_OPEN_GATE) {
            val pkg = intent.getStringExtra("packageName") ?: return
            val name = intent.getStringExtra("appName") ?: pkg
            pendingGate = mapOf("packageName" to pkg, "appName" to name)
        }
    }

    private fun notifyGateToFlutter(payload: Map<String, String>) {
        methodChannel?.invokeMethod("openGate", payload)
    }

    private fun getInstalledApps(includeIcons: Boolean): List<Map<String, Any?>> {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val resolveInfos = pm.queryIntentActivities(intent, 0)
        val seen = HashSet<String>()
        val out = mutableListOf<Map<String, Any?>>()
        for (ri in resolveInfos) {
            val ai = ri.activityInfo.applicationInfo
            if (!seen.add(ai.packageName)) continue
            // Skip ourselves
            if (ai.packageName == packageName) continue
            val isSystem = (ai.flags and ApplicationInfo.FLAG_SYSTEM) != 0 &&
                    (ai.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) == 0
            val item = mutableMapOf<String, Any?>(
                "packageName" to ai.packageName,
                "appName" to pm.getApplicationLabel(ai).toString(),
                "isSystem" to isSystem,
            )
            if (includeIcons) {
                try {
                    val icon = pm.getApplicationIcon(ai)
                    item["icon"] = drawableToPngBytes(icon)
                } catch (_: Exception) {}
            }
            out.add(item)
        }
        out.sortBy { (it["appName"] as? String)?.lowercase() ?: "" }
        return out
    }

    private fun drawableToPngBytes(drawable: Drawable): ByteArray {
        val size = 96
        val bmp = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            Bitmap.createScaledBitmap(drawable.bitmap, size, size, true)
        } else {
            val b = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val c = Canvas(b)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(c)
            b
        }
        val baos = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 90, baos)
        return baos.toByteArray()
    }

    private fun getUsageStats(days: Int): Map<String, Long> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return emptyMap()
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val end = System.currentTimeMillis()
        val cal = Calendar.getInstance()
        cal.timeInMillis = end
        cal.add(Calendar.DAY_OF_YEAR, -days)
        val start = cal.timeInMillis
        val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, start, end)
            ?: return emptyMap()
        val totals = HashMap<String, Long>()
        for (s in stats) {
            val prev = totals[s.packageName] ?: 0L
            totals[s.packageName] = prev + s.totalTimeInForeground
        }
        return totals
    }

    private fun startOfTodayMillis(): Long {
        val cal = Calendar.getInstance()
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }

    /**
     * Today's pickups (foreground launches) and screen time for [packages].
     * Optionally highlights [focusPackage] (the app that triggered the gate).
     */
    private fun getTodayBlockedUsage(
        packages: List<String>,
        focusPackage: String?,
    ): Map<String, Any> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP || packages.isEmpty()) {
            return mapOf(
                "totalPickups" to 0,
                "totalScreenTimeMs" to 0L,
                "focusPickups" to 0,
                "focusScreenTimeMs" to 0L,
            )
        }
        val packageSet = packages.toSet()
        val start = startOfTodayMillis()
        val end = System.currentTimeMillis()
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

        var totalScreenMs = 0L
        val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, start, end)
            ?: emptyList()
        var focusScreenMs = 0L
        for (s in stats) {
            if (s.packageName !in packageSet) continue
            totalScreenMs += s.totalTimeInForeground
            if (s.packageName == focusPackage) {
                focusScreenMs += s.totalTimeInForeground
            }
        }

        var totalPickups = 0
        var focusPickups = 0
        val events = usm.queryEvents(start, end)
        val ev = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(ev)
            if (ev.eventType != UsageEvents.Event.MOVE_TO_FOREGROUND) continue
            if (ev.packageName !in packageSet) continue
            totalPickups++
            if (ev.packageName == focusPackage) focusPickups++
        }

        return mapOf(
            "totalPickups" to totalPickups,
            "totalScreenTimeMs" to totalScreenMs,
            "focusPickups" to focusPickups,
            "focusScreenTimeMs" to focusScreenMs,
        )
    }

    /**
     * Sets up `com.ankiblock/ankidroid`, a MethodChannel that delegates each
     * call to [AnkiDroidApi]. We dispatch the blocking ContentProvider calls
     * to a background thread so the platform thread stays responsive.
     */
    private fun registerAnkiDroidChannel(flutterEngine: FlutterEngine) {
        val api = AnkiDroidApi(this)
        ankiDroidApi = api
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ankiDroidChannelName,
        )
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "isInstalled" -> result.success(api.isInstalled())
                    "hasPermission" -> result.success(api.hasPermission())
                    "requestPermission" -> api.requestPermission(result)
                    "openAnkiDroid" -> result.success(api.openAnkiDroid())
                    "openAnkiDroidReviewer" -> {
                        val deckId = (call.argument<Number>("deckId"))?.toLong()
                        if (deckId == null) {
                            result.error("BAD_ARGS", "deckId is required", null)
                            return@setMethodCallHandler
                        }
                        result.success(api.openReviewer(deckId))
                    }
                    "listDecks" -> {
                        Thread {
                            try {
                                val decks = api.listDecks()
                                runOnUiThread { result.success(decks) }
                            } catch (e: AnkiDroidUnavailableException) {
                                runOnUiThread {
                                    result.error("UNAVAILABLE", e.message, null)
                                }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("ANKIDROID_ERROR", e.message, null)
                                }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("ANKIDROID_ERROR", e.message, null)
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        val handled = ankiDroidApi
            ?.onRequestPermissionsResult(requestCode, permissions, grantResults)
            ?: false
        if (!handled) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }

    private fun hasUsageAccess(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }
}
