package com.anki.ankiblock

import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ProgressBar
import android.widget.TextView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.Calendar
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        const val ACTION_OPEN_GATE = "com.ankiblock.OPEN_GATE"
        const val ACTION_DISMISS_GATE = "com.ankiblock.DISMISS_GATE"

        private const val CHANNEL_NAME = "com.ankiblock/permissions"
        private const val TAG = "AnkiBlock.Gate"
        private const val GATE_PREFS = "ankiblock_pending_gate"
        private const val KEY_PENDING_PKG = "pending_pkg"
        private const val KEY_PENDING_NAME = "pending_name"
        private const val KEY_PENDING_AT = "pending_at_ms"
        private const val PENDING_GATE_TTL_MS = 120_000L

        @Volatile
        private var activeInstance: MainActivity? = null

        /** In-activity fallback when system overlay permission is unavailable. */
        fun showInActivityGateFallback(packageName: String, appName: String) {
            val activity = activeInstance ?: return
            activity.runOnUiThread {
                activity.showInActivityGateFallbackInternal(packageName, appName)
            }
        }

        @Volatile
        private var flutterEventChannel: MethodChannel? = null

        fun notifyFlutter(method: String, arguments: Any?) {
            val channel = flutterEventChannel
            if (channel != null) {
                channel.invokeMethod(method, arguments)
                return
            }
            // Pre-warmed engine may run Dart before MainActivity configures the channel.
            val engine = FlutterEngineCache.getInstance()
                .get(AnkiBlockApplication.ENGINE_ID)
                ?: return
            MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)
                .invokeMethod(method, arguments)
        }
    }

    private val channelName = CHANNEL_NAME
    private val ankiDroidChannelName = "com.ankiblock/ankidroid"
    private var methodChannel: MethodChannel? = null
    private var pendingGate: Map<String, String>? = null
    private var ankiDroidApi: AnkiDroidApi? = null
    private var gateLoadingOverlay: FrameLayout? = null
    private var inActivityFallbackOverlay: View? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val appsIoExecutor = Executors.newSingleThreadExecutor()

    override fun getCachedEngineId(): String = AnkiBlockApplication.ENGINE_ID

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        activeInstance = this
        if (intent?.action == ACTION_DISMISS_GATE) {
            super.onCreate(savedInstanceState)
            removeGateFromRecents()
            return
        }
        if (intent?.action == ACTION_OPEN_GATE) {
            prepareEngineForGateOpen(fromNewIntent = false)
            showGateLoadingSplash()
            GateDiagnostics.recordGateLaunch(this)
            Log.i(TAG, "OPEN_GATE onCreate")
        }
        super.onCreate(savedInstanceState)
        AnkiBlockApplication.touchEngineActivity(this)
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
                    result.success(MonitorBootstrap.startMonitorIfNeeded(this))
                }
                "stopAppMonitor" -> {
                    val intent = Intent(this, AppMonitorService::class.java)
                    intent.action = AppMonitorService.ACTION_STOP
                    stopService(intent)
                    MonitorWatchdog.cancel(this)
                    MonitorAlarmReceiver.cancel(this)
                    result.success(true)
                }
                "consumePendingGate" -> {
                    val p = pendingGate ?: loadPersistedPendingGate()
                    pendingGate = null
                    clearPersistedPendingGate()
                    result.success(p)
                }
                "onGateReady" -> {
                    GateDiagnostics.recordGateReady(this)
                    GateFallbackOverlay.onFlutterGateReady()
                    dismissGateLoadingSplash()
                    dismissInActivityGateFallback()
                    AppMonitorService.onFlutterGateReady(this)
                    result.success(true)
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
                "grantTempUnlock" -> {
                    val pkg = call.argument<String>("packageName") ?: ""
                    val durationMs = (call.argument<Number>("durationMs"))?.toLong()
                    if (pkg.isNotEmpty()) {
                        AppMonitorService.grantTempUnlock(this, pkg, durationMs)
                    }
                    result.success(true)
                }
                "grantBypass" -> {
                    val pkg = call.argument<String>("packageName") ?: ""
                    val durationMs = (call.argument<Number>("durationMs"))?.toLong()
                    if (pkg.isNotEmpty()) {
                        AppMonitorService.grantBypass(this, pkg, durationMs)
                    }
                    result.success(true)
                }
                "syncBlockRuleSettings" -> {
                    val unlockDurationMinutes =
                        call.argument<Int>("unlockDurationMinutes") ?: 15
                    val bypassSeconds = call.argument<Int>("bypassSeconds") ?: 60
                    val isEnabled = call.argument<Boolean>("isEnabled") ?: true
                    val studyMode = call.argument<String>("studyMode") ?: "cardCount"
                    val unlockGoal = call.argument<Int>("unlockGoal") ?: 10
                    val bypassEnabled = call.argument<Boolean>("bypassEnabled") ?: true
                    AppMonitorService.setBlockRuleSettings(
                        this,
                        unlockDurationMinutes,
                        bypassSeconds,
                        isEnabled,
                        studyMode,
                        unlockGoal,
                        bypassEnabled,
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
                "tryUnlockFromRecentBout" -> {
                    val pkg = call.argument<String>("packageName") ?: ""
                    val appName = call.argument<String>("appName") ?: pkg
                    val target = call.argument<Int>("target") ?: 10
                    val unlocked = AppMonitorService.tryUnlockFromRecentBout(
                        this,
                        pkg,
                        appName,
                        target,
                    )
                    result.success(unlocked)
                }
                "isTemporarilyUnlocked" -> {
                    val pkg = call.argument<String>("packageName") ?: ""
                    result.success(AppMonitorService.isTemporarilyUnlocked(this, pkg))
                }
                "getStudyBoutCount" -> {
                    result.success(AppMonitorService.peekStudyBoutCountPublic(this))
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
                    val unlocked = session["unlocked"] as? Boolean == true
                    if (!unlocked) {
                        val monitorIntent = Intent(this, AppMonitorService::class.java).apply {
                            action = AppMonitorService.ACTION_DELEGATED_START
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(monitorIntent)
                        } else {
                            startService(monitorIntent)
                        }
                        MonitorWatchdog.schedule(this)
                    }
                    result.success(session)
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
                "isAppMonitorRunning" -> {
                    result.success(
                        AppMonitorService.isRunning() &&
                            !AppMonitorService.isPollStale(),
                    )
                }
                else -> result.notImplemented()
            }
        }

        // If launched with a gate intent, surface it once channel is ready.
        // Launcher opens must not revive a leftover pending gate.
        if (isLauncherIntent(intent)) {
            handleLauncherOpen()
        } else {
            consumeGateIntent(intent)
            if (pendingGate == null) {
                pendingGate = loadPersistedPendingGate()
            }
            deliverPendingGateToFlutter()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.action == ACTION_DISMISS_GATE) {
            GateFallbackOverlay.cancelActivityFallback()
            dismissGateLoadingSplash()
            dismissInActivityGateFallback()
            removeGateFromRecents()
            return
        }
        if (isLauncherIntent(intent)) {
            handleLauncherOpen()
            return
        }
        if (intent.action == ACTION_OPEN_GATE) {
            if (prepareEngineForGateOpen(fromNewIntent = true)) {
                return
            }
            showGateLoadingSplash()
            GateDiagnostics.recordGateLaunch(this)
            Log.i(TAG, "OPEN_GATE onNewIntent")
        }
        consumeGateIntent(intent)
        deliverPendingGateToFlutter()
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

    private fun isLauncherIntent(intent: Intent?): Boolean {
        if (intent == null) return false
        if (intent.action != Intent.ACTION_MAIN) return false
        val categories = intent.categories ?: return false
        return categories.contains(Intent.CATEGORY_LAUNCHER)
    }

    /** Icon tap — clear stale gate state and reset Flutter to the home screen. */
    private fun handleLauncherOpen() {
        pendingGate = null
        clearPersistedPendingGate()
        GateFallbackOverlay.cancelActivityFallback()
        dismissGateLoadingSplash()
        dismissInActivityGateFallback()
        notifyHomeToFlutter()
    }

    private fun consumeGateIntent(intent: Intent?) {
        if (intent?.action == ACTION_OPEN_GATE) {
            val pkg = intent.getStringExtra("packageName") ?: return
            val name = intent.getStringExtra("appName") ?: pkg
            val payload = mapOf("packageName" to pkg, "appName" to name)
            pendingGate = payload
            persistPendingGate(payload)
            Log.i(TAG, "pendingGate set for $name ($pkg)")
        }
    }

    private fun persistPendingGate(payload: Map<String, String>) {
        getSharedPreferences(GATE_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PENDING_PKG, payload["packageName"])
            .putString(KEY_PENDING_NAME, payload["appName"])
            .putLong(KEY_PENDING_AT, System.currentTimeMillis())
            .commit()
    }

    private fun loadPersistedPendingGate(): Map<String, String>? {
        val prefs = getSharedPreferences(GATE_PREFS, Context.MODE_PRIVATE)
        val pkg = prefs.getString(KEY_PENDING_PKG, null) ?: return null
        val at = prefs.getLong(KEY_PENDING_AT, 0L)
        if (at <= 0L || System.currentTimeMillis() - at > PENDING_GATE_TTL_MS) {
            clearPersistedPendingGate()
            return null
        }
        val name = prefs.getString(KEY_PENDING_NAME, null) ?: pkg
        return mapOf("packageName" to pkg, "appName" to name)
    }

    private fun clearPersistedPendingGate() {
        getSharedPreferences(GATE_PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }

    private fun notifyGateToFlutter(payload: Map<String, String>) {
        // Prefer companion so pre-warmed engines without a ready MainActivity
        // channel still receive openGate (same path as openHome).
        notifyFlutter("openGate", payload)
    }

    private fun deliverPendingGateToFlutter() {
        val gate = pendingGate ?: return
        val pkg = gate["packageName"] ?: return
        val name = gate["appName"] ?: pkg
        notifyGateToFlutter(gate)
        GateFallbackOverlay.scheduleActivityFallback(this, pkg, name)
    }

    /**
     * @return true when [recreate] was called and the current intent handling
     *     should stop (engine was replaced while this activity instance was alive).
     */
    private fun prepareEngineForGateOpen(fromNewIntent: Boolean): Boolean {
        val brokenSurface = fromNewIntent && isFlutterSurfaceBroken()
        val recycled = AnkiBlockApplication.prepareEngineForGate(
            application,
            brokenSurface = brokenSurface,
        )
        if (recycled && fromNewIntent) {
            Log.i(TAG, "recreate MainActivity after engine recycle (broken=$brokenSurface)")
            recreate()
            return true
        }
        if (recycled) {
            Log.i(TAG, "engine recycled for gate (brokenSurface=$brokenSurface)")
        }
        return false
    }

    /** True when the cached engine survived task removal with a 0×0 viewport. */
    private fun isFlutterSurfaceBroken(): Boolean {
        val view = findFlutterView(window?.decorView) ?: return false
        return view.width == 0 && view.height == 0 && view.isAttachedToWindow
    }

    private fun findFlutterView(root: View?): FlutterView? {
        if (root == null) return null
        if (root is FlutterView) return root
        if (root is android.view.ViewGroup) {
            for (i in 0 until root.childCount) {
                findFlutterView(root.getChildAt(i))?.let { return it }
            }
        }
        return null
    }

    private fun notifyHomeToFlutter() {
        methodChannel?.invokeMethod("openHome", null)
        // Channel may not be ready yet on very early resume; companion works too.
        notifyFlutter("openHome", null)
    }

    private fun showGateLoadingSplash() {
        mainHandler.post {
            if (gateLoadingOverlay != null) return@post
            val overlay = FrameLayout(this).apply {
                setBackgroundColor(Color.parseColor("#FF081020"))
                isClickable = true
            }
            val progress = ProgressBar(this).apply {
                isIndeterminate = true
            }
            val label = TextView(this).apply {
                text = "Loading study gate…"
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                gravity = Gravity.CENTER
            }
            val column = android.widget.LinearLayout(this).apply {
                orientation = android.widget.LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                addView(progress)
                addView(
                    label,
                    android.widget.LinearLayout.LayoutParams(
                        android.widget.LinearLayout.LayoutParams.WRAP_CONTENT,
                        android.widget.LinearLayout.LayoutParams.WRAP_CONTENT,
                    ).apply { topMargin = 24 },
                )
            }
            overlay.addView(
                column,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    Gravity.CENTER,
                ),
            )
            addContentView(
                overlay,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
            gateLoadingOverlay = overlay
            // Splash stays until Flutter signals ready or fallback UI takes over.
        }
    }

    private fun showInActivityGateFallbackInternal(packageName: String, appName: String) {
        if (inActivityFallbackOverlay != null) return
        if (GateFallbackOverlay.isFlutterReady()) return
        dismissGateLoadingSplash()
        val view = GateFallbackOverlay.inflateGateFallbackView(
            this,
            packageName,
            appName,
        ) {
            GateFallbackOverlay.startStudySession(this, packageName, appName)
            dismissInActivityGateFallback()
        }
        addContentView(
            view,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        inActivityFallbackOverlay = view
        Log.i(TAG, "in-activity gate fallback shown for $appName")
    }

    private fun dismissInActivityGateFallback() {
        val view = inActivityFallbackOverlay ?: return
        try {
            (view.parent as? android.view.ViewGroup)?.removeView(view)
        } catch (_: Throwable) {
        }
        inActivityFallbackOverlay = null
    }

    private fun dismissGateLoadingSplash() {
        mainHandler.post {
            val overlay = gateLoadingOverlay ?: return@post
            try {
                (overlay.parent as? android.view.ViewGroup)?.removeView(overlay)
            } catch (_: Throwable) {
            }
            gateLoadingOverlay = null
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

    override fun onDestroy() {
        if (activeInstance === this) activeInstance = null
        dismissInActivityGateFallback()
        dismissGateLoadingSplash()
        super.onDestroy()
    }

    private fun hasUsageAccess(): Boolean = MonitorBootstrap.hasUsageAccess(this)
}
