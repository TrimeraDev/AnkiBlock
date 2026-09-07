package com.anki.ankiblock

import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.Calendar
import java.util.concurrent.Executors

/**
 * Hosts the Flutter app (Today / Apps / Decks / Settings) and its MethodChannels.
 * Blocking itself runs entirely in [AnkiBlockAccessibilityService]; this activity
 * only mirrors configuration into native prefs and reads native state back.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL_NAME = "com.ankiblock/permissions"

        @Volatile
        private var flutterEventChannel: MethodChannel? = null

        /** Best-effort push to Flutter when its engine is alive (progress, unlocks). */
        fun notifyFlutter(method: String, arguments: Any?) {
            val channel = flutterEventChannel ?: return
            Handler(Looper.getMainLooper()).post {
                try {
                    channel.invokeMethod(method, arguments)
                } catch (_: Throwable) {
                }
            }
        }
    }

    private val ankiDroidChannelName = "com.ankiblock/ankidroid"
    private var ankiDroidApi: AnkiDroidApi? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val appsIoExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME
        )
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
                "hasAccessibilityPermission" -> {
                    result.success(AnkiBlockAccessibilityService.isEnabled(this))
                }
                "openAccessibilitySettings" -> {
                    MonitorBootstrap.openAccessibilitySettings(this)
                    result.success(true)
                }
                "getInstalledApps" -> {
                    val includeIcons = call.argument<Boolean>("icons") ?: false
                    // Offload icon rasterization off the platform thread.
                    appsIoExecutor.execute {
                        try {
                            val apps = getInstalledApps(includeIcons)
                            mainHandler.post { result.success(apps) }
                        } catch (e: Throwable) {
                            mainHandler.post {
                                result.error("APPS_SCAN", e.message, null)
                            }
                        }
                    }
                }
                "getUsageStats" -> {
                    val thisWeek = call.argument<Boolean>("thisWeek") ?: false
                    if (thisWeek) {
                        val end = System.currentTimeMillis()
                        result.success(getUsageStatsSince(startOfWeekMillis(), end))
                    } else {
                        val days = call.argument<Int>("days") ?: 7
                        result.success(getUsageStats(days))
                    }
                }
                "setBlockedPackages" -> {
                    val pkgs = (call.argument<List<String>>("packages") ?: emptyList())
                    val names = (call.argument<Map<String, String>>("names") ?: emptyMap())
                    AppMonitorService.setBlockedPackages(this, pkgs, names)
                    result.success(true)
                }
                "setBlockedWebsites" -> {
                    @Suppress("UNCHECKED_CAST")
                    val rulesArg = call.argument<List<Map<String, Any?>>>("rules")
                        ?: emptyList()
                    val blockUnsupported =
                        call.argument<Boolean>("blockUnsupportedBrowsers") ?: false
                    val rules = rulesArg.mapNotNull { m ->
                        val pattern = (m["pattern"] as? String)?.trim().orEmpty()
                        if (pattern.isEmpty()) return@mapNotNull null
                        WebsiteRules.Rule(
                            pattern = pattern,
                            isRegex = m["isRegex"] as? Boolean ?: false,
                            label = (m["label"] as? String)?.ifBlank { pattern } ?: pattern,
                        )
                    }
                    AppMonitorService.setBlockedWebsites(
                        this,
                        WebsiteRules.toJson(rules),
                        blockUnsupported,
                    )
                    result.success(true)
                }
                "getSupportedBrowsers" -> {
                    val compat = BrowserUrlDetector.browserCompatibility(this)
                    result.success(
                        mapOf(
                            "supportedInstalled" to compat.supportedInstalled.map {
                                mapOf("packageName" to it.packageName, "appName" to it.appName)
                            },
                            "unsupportedInstalled" to compat.unsupportedInstalled.map {
                                mapOf("packageName" to it.packageName, "appName" to it.appName)
                            },
                            "supportedCatalog" to compat.supportedCatalog,
                        ),
                    )
                }
                "getGateDiagnostics" -> {
                    result.success(GateDiagnostics.snapshot(this))
                }
                "openOemAutostartSettings" -> {
                    result.success(OemSettings.openAutostartSettings(this))
                }
                "getOemManufacturer" -> {
                    result.success(OemSettings.manufacturerKey())
                }
                "syncBlockRuleSettings" -> {
                    val unlockDurationMinutes =
                        call.argument<Int>("unlockDurationMinutes") ?: 15
                    val bypassSeconds = call.argument<Int>("bypassSeconds") ?: 60
                    val isEnabled = call.argument<Boolean>("isEnabled") ?: true
                    val studyMode = call.argument<String>("studyMode") ?: "cardCount"
                    val unlockGoal = call.argument<Int>("unlockGoal") ?: 10
                    val bypassEnabled = call.argument<Boolean>("bypassEnabled") ?: true
                    val bypassDailyCap = call.argument<Int>("bypassDailyCap")
                        ?: AppMonitorService.DEFAULT_BYPASS_DAILY_CAP
                    AppMonitorService.setBlockRuleSettings(
                        this,
                        unlockDurationMinutes,
                        bypassSeconds,
                        isEnabled,
                        studyMode,
                        unlockGoal,
                        bypassEnabled,
                        bypassDailyCap,
                    )
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
                "getDelegatedSessionState" -> {
                    result.success(AppMonitorService.getDelegatedSessionState(this))
                }
                "startDelegatedSession" -> {
                    val pkg = call.argument<String>("packageName") ?: ""
                    val appName = call.argument<String>("appName") ?: pkg
                    val deckId = (call.argument<Number>("deckId"))?.toLong() ?: -1L
                    val target = call.argument<Int>("target") ?: 5
                    @Suppress("UNCHECKED_CAST")
                    val deckIds = (call.argument<List<*>>("deckIds") ?: emptyList<Any?>())
                        .mapNotNull { (it as? Number)?.toLong() }
                    val session = AppMonitorService.startDelegatedSession(
                        this,
                        pkg,
                        appName,
                        deckId,
                        deckIds,
                        target,
                    )
                    result.success(session)
                }
                "getProtectionStatus" -> {
                    result.success(ProtectionStatus.snapshot(this))
                }
                "isIgnoringBatteryOptimizations" -> {
                    result.success(ProtectionStatus.isIgnoringBatteryOptimizations(this))
                }
                "requestBatteryOptimizationExemption" -> {
                    result.success(
                        ProtectionStatus.requestBatteryOptimizationExemption(this),
                    )
                }
                "openBatterySettings" -> {
                    ProtectionStatus.openBatterySettings(this)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
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
        val end = System.currentTimeMillis()
        val cal = Calendar.getInstance()
        cal.timeInMillis = end
        cal.add(Calendar.DAY_OF_YEAR, -days)
        return getUsageStatsSince(cal.timeInMillis, end)
    }

    private fun getUsageStatsSince(start: Long, end: Long): Map<String, Long> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return emptyMap()
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, start, end)
            ?: return emptyMap()
        val totals = HashMap<String, Long>()
        for (s in stats) {
            val prev = totals[s.packageName] ?: 0L
            totals[s.packageName] = prev + s.totalTimeInForeground
        }
        return totals
    }

    private fun startOfWeekMillis(): Long {
        val cal = Calendar.getInstance()
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        cal.set(Calendar.DAY_OF_WEEK, cal.firstDayOfWeek)
        return cal.timeInMillis
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

    override fun onDestroy() {
        if (flutterEventChannel != null) flutterEventChannel = null
        super.onDestroy()
    }

    private fun hasUsageAccess(): Boolean = MonitorBootstrap.hasUsageAccess(this)
}
