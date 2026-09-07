package com.anki.ankiblock

import android.animation.ObjectAnimator
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.KeyEvent
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.LinearInterpolator
import android.widget.Button
import android.widget.ProgressBar
import android.widget.TextView
import android.util.DisplayMetrics
import java.util.concurrent.Executors

/**
 * Full-screen study gate drawn by [AnkiBlockAccessibilityService] with
 * TYPE_ACCESSIBILITY_OVERLAY. No Activity, no Flutter engine, no permission
 * beyond Accessibility: it appears in the same event that detects the blocked
 * app and is torn down when the user leaves for another app.
 */
class GateOverlayManager(
    private val service: AnkiBlockAccessibilityService,
    private val ankiApi: AnkiDroidApi,
) {
    companion object {
        private const val TAG = "AnkiBlock.Gate"
        private const val BYPASS_HOLD_MS = 2_000L
    }

    private val windowManager =
        service.getSystemService(android.content.Context.WINDOW_SERVICE) as WindowManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private val prefs get() = service.getSharedPreferences(
        AppMonitorService.PREFS,
        android.content.Context.MODE_PRIVATE,
    )

    private var view: View? = null
    private var bypassRunnable: Runnable? = null
    private var bypassAnimator: ObjectAnimator? = null
    private var showToken = 0

    /** Package the gate is currently covering, or null when hidden. */
    var packageName: String? = null
        private set

    /** True when the gate was shown for a blocked website (not a blocked app). */
    var isWebsiteGate: Boolean = false
        private set

    val isShowing: Boolean get() = view != null

    fun isShowingFor(pkg: String): Boolean = view != null && packageName == pkg

    fun show(pkg: String, appName: String, website: Boolean = false) {
        mainHandler.post { showInternal(pkg, appName, website) }
    }

    /** Update the gate title while it's already showing (website host change). */
    fun updateTitle(appName: String) {
        mainHandler.post {
            val root = view ?: return@post
            root.findViewById<TextView>(R.id.gate_app_name).text = appName
        }
    }

    fun dismiss() {
        mainHandler.post { dismissInternal() }
    }

    // ---------------------------------------------------------------- render

    private data class Model(
        val mode: String,
        val dailyGoal: Int,
        val reviewed: Int,
        val unlockGoal: Int,
        val unlockDone: Int,
        val unlockTarget: Int,
        val bypassesLeft: Int,
        val bypassSeconds: Int,
        val ankiReady: Boolean,
        val hasScope: Boolean,
        val obligationDue: Int?, // null until the AnkiDroid query returns
    )

    private fun buildModel(pkg: String, withAnki: Boolean): Model {
        val p = prefs
        val mode = p.getString(
            AppMonitorService.KEY_STUDY_MODE,
            AppMonitorService.STUDY_MODE_CARD_COUNT,
        ) ?: AppMonitorService.STUDY_MODE_CARD_COUNT
        val unlockGoal = AppMonitorService.unlockGoal(p)

        // Per-app unlock progress: active delegated session for this app, else soft bout.
        val session = AppMonitorService.getDelegatedSessionState(service)
            ?.takeIf { it["packageName"] == pkg }
        val unlockDone = if (session != null) {
            (session["completed"] as? Int) ?: 0
        } else {
            AppMonitorService.peekStudyBoutCount(p).coerceAtMost(unlockGoal)
        }
        val unlockTarget = if (session != null) {
            ((session["target"] as? Int) ?: unlockGoal).coerceAtLeast(1)
        } else {
            unlockGoal
        }

        val scopeIds = AppMonitorService.parseScopeDeckIds(
            p.getString(AppMonitorService.KEY_SCOPE_DECK_IDS, null),
        )
        val ankiReady = ankiApi.isInstalled() && ankiApi.hasPermission()
        val obligation = if (withAnki && ankiReady && scopeIds.isNotEmpty()) {
            var total = 0
            for (id in scopeIds) {
                total += try {
                    ankiApi.deckObligationDue(id)
                } catch (_: Throwable) {
                    0
                }
            }
            total
        } else {
            null
        }

        return Model(
            mode = mode,
            dailyGoal = p.getInt(AppMonitorService.KEY_DAILY_GOAL, 0),
            reviewed = p.getInt(AppMonitorService.KEY_DAILY_REVIEWED, 0),
            unlockGoal = unlockGoal,
            unlockDone = unlockDone,
            unlockTarget = unlockTarget,
            bypassesLeft = GateStats.bypassesRemaining(service),
            bypassSeconds = p.getInt(
                AppMonitorService.KEY_BYPASS_SECONDS,
                AppMonitorService.DEFAULT_BYPASS_SECONDS,
            ),
            ankiReady = ankiReady,
            hasScope = scopeIds.isNotEmpty(),
            obligationDue = obligation,
        )
    }

    private fun render(root: View, appName: String, m: Model) {
        root.findViewById<TextView>(R.id.gate_app_name).text = appName

        val dueMode = m.mode == AppMonitorService.STUDY_MODE_DUE_CARDS
        val remaining = (m.unlockTarget - m.unlockDone).coerceAtLeast(0)
        val hasProgress = m.unlockDone > 0

        root.findViewById<TextView>(R.id.gate_status).text = if (hasProgress) {
            "${m.unlockDone} / ${m.unlockTarget} to unlock"
        } else {
            "${m.unlockGoal} cards to unlock"
        }

        val progress = root.findViewById<ProgressBar>(R.id.gate_progress)
        progress.progress = if (m.unlockTarget > 0) {
            (m.unlockDone * 1000 / m.unlockTarget).coerceIn(0, 1000)
        } else {
            0
        }

        val freedom = if (dueMode) {
            when (val due = m.obligationDue) {
                null -> "Clear learning & reviews for the rest of the day."
                else -> "$due learning & reviews left for freedom today."
            }
        } else {
            val left = (m.dailyGoal - m.reviewed).coerceAtLeast(0)
            if (m.dailyGoal > 0) "$left left for freedom until 3am." else ""
        }
        val head = if (hasProgress) {
            "$remaining more for a temporary unlock."
        } else {
            "Study ${m.unlockGoal} cards for a temporary unlock."
        }
        root.findViewById<TextView>(R.id.gate_detail).text = "$head $freedom".trim()

        val study = root.findViewById<Button>(R.id.gate_btn_study)
        study.text = when {
            !m.ankiReady -> "Set up AnkiDroid in AnkiBlock"
            !m.hasScope -> "Select decks in AnkiBlock"
            m.obligationDue == 0 && dueMode -> "No cards due"
            hasProgress -> "Continue studying"
            else -> "Study in AnkiDroid"
        }
        study.isEnabled = !(dueMode && m.obligationDue == 0)

        val bypass = root.findViewById<Button>(R.id.gate_btn_bypass)
        val hint = root.findViewById<TextView>(R.id.gate_bypass_hint)
        if (m.bypassesLeft > 0) {
            bypass.visibility = View.VISIBLE
            bypass.text = "Hold for emergency bypass"
            hint.text = "${m.bypassSeconds}s access · ${m.bypassesLeft} left today"
        } else {
            bypass.visibility = View.GONE
            hint.text = if (prefs.getBoolean(AppMonitorService.KEY_BYPASS_ENABLED, true)) {
                "No emergency bypasses left today."
            } else {
                ""
            }
        }
    }

    private fun showInternal(pkg: String, appName: String, website: Boolean) {
        // Already covering this exact target — keep the overlay, refresh title.
        if (isShowingFor(pkg) && isWebsiteGate == website) {
            view?.findViewById<TextView>(R.id.gate_app_name)?.text = appName
            return
        }

        // Gate already up for a different app/site: swap content in place so we
        // never removeView→blank frame→addView (the blocked→blocked flicker).
        val existing = view
        if (existing != null) {
            cancelBypassHold()
            val token = ++showToken
            packageName = pkg
            isWebsiteGate = website
            val quick = buildModel(pkg, withAnki = false)
            render(existing, appName, quick)
            wireActions(existing, pkg, appName, quick, website)
            existing.requestFocus()
            GateDiagnostics.recordGateShown(service)
            GateStats.recordBlockedAttempt(service)
            Log.i(TAG, "gate swapped to $appName ($pkg) website=$website")
            io.execute {
                val full = try {
                    buildModel(pkg, withAnki = true)
                } catch (e: Throwable) {
                    Log.w(TAG, "gate anki refresh failed", e)
                    return@execute
                }
                mainHandler.post {
                    if (token != showToken || view !== existing) return@post
                    render(existing, appName, full)
                    wireActions(existing, pkg, appName, full, website)
                }
            }
            return
        }

        val token = ++showToken
        packageName = pkg
        isWebsiteGate = website

        val root = LayoutInflater.from(service).inflate(R.layout.overlay_gate, null)
        // Instant paint from prefs; Anki counts fill in asynchronously.
        val quick = buildModel(pkg, withAnki = false)
        render(root, appName, quick)
        wireActions(root, pkg, appName, quick, website)

        // Leave the status-bar strip uncovered so a swipe from the top can open
        // the notification shade (full-screen TYPE_ACCESSIBILITY_OVERLAY would
        // otherwise eat that gesture).
        val statusBarHeight = statusBarHeightPx()
        val screenH = screenHeightPx()
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            (screenH - statusBarHeight).coerceAtLeast(1),
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            y = statusBarHeight
        }

        try {
            windowManager.addView(root, params)
        } catch (e: Throwable) {
            Log.e(TAG, "gate addView failed for $appName", e)
            GateDiagnostics.recordError(service, "gate addView: ${e.message}")
            packageName = null
            isWebsiteGate = false
            return
        }
        view = root
        root.requestFocus()
        GateDiagnostics.recordGateShown(service)
        GateStats.recordBlockedAttempt(service)
        Log.i(TAG, "gate shown for $appName ($pkg) website=$website")

        io.execute {
            val full = try {
                buildModel(pkg, withAnki = true)
            } catch (e: Throwable) {
                Log.w(TAG, "gate anki refresh failed", e)
                return@execute
            }
            mainHandler.post {
                if (token != showToken || view !== root) return@post
                render(root, appName, full)
                wireActions(root, pkg, appName, full, website)
            }
        }
    }

    private fun dismissInternal() {
        cancelBypassHold()
        val v = view ?: run {
            packageName = null
            isWebsiteGate = false
            return
        }
        try {
            windowManager.removeView(v)
        } catch (_: Throwable) {
        }
        view = null
        packageName = null
        isWebsiteGate = false
    }

    // --------------------------------------------------------------- actions

    private fun wireActions(
        root: View,
        pkg: String,
        appName: String,
        m: Model,
        website: Boolean,
    ) {
        root.findViewById<Button>(R.id.gate_btn_study).setOnClickListener {
            if (!m.ankiReady || !m.hasScope) {
                openAnkiBlock()
            } else {
                startStudy(pkg, appName)
            }
        }
        root.findViewById<Button>(R.id.gate_btn_open_ankiblock).setOnClickListener {
            openAnkiBlock()
        }
        wireBypassHold(
            root.findViewById(R.id.gate_btn_bypass),
            root.findViewById(R.id.gate_bypass_progress),
            pkg,
        )

        root.setOnKeyListener { _, keyCode, event ->
            if (keyCode == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_UP) {
                if (website) {
                    // Navigate the tab back; next URL check re-gates if still blocked.
                    service.performGlobalAction(
                        android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK,
                    )
                } else {
                    // Back = leave the blocked app, not peek at it.
                    service.performGlobalAction(
                        android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_HOME,
                    )
                }
                dismissInternal()
                true
            } else {
                false
            }
        }
    }

    private fun startStudy(pkg: String, appName: String) {
        val p = prefs
        val deckIds = AppMonitorService.parseScopeDeckIds(
            p.getString(AppMonitorService.KEY_SCOPE_DECK_IDS, null),
        )
        if (deckIds.isEmpty()) {
            openAnkiBlock()
            return
        }
        val target = AppMonitorService.unlockGoal(p)
        io.execute {
            // Launch deck = the scoped deck with the most learning/review due.
            var launchDeck = deckIds.first()
            var best = -1
            for (id in deckIds) {
                val due = try {
                    ankiApi.deckObligationDue(id)
                } catch (_: Throwable) {
                    0
                }
                if (due > best) {
                    best = due
                    launchDeck = id
                }
            }
            val result = AppMonitorService.startDelegatedSession(
                service,
                pkg,
                appName,
                launchDeck,
                deckIds,
                target,
            )
            mainHandler.post {
                dismissInternal()
                if (result["unlocked"] == true) {
                    // Recent bout already covered the goal; completion overlay
                    // is shown by tryUnlockFromRecentBout.
                    return@post
                }
                // Guard against the blocked app re-gating before AnkiDroid fronts.
                service.noteStudyLaunch(pkg)
                ankiApi.openReviewer(launchDeck)
            }
        }
    }

    private fun wireBypassHold(button: Button, bar: ProgressBar, pkg: String) {
        button.setOnTouchListener { v, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    cancelBypassHold()
                    button.text = "Keep holding…"
                    bar.progress = 0
                    bar.visibility = View.VISIBLE
                    bypassAnimator = ObjectAnimator.ofInt(bar, "progress", 0, bar.max).apply {
                        duration = BYPASS_HOLD_MS
                        interpolator = LinearInterpolator()
                        start()
                    }
                    val r = Runnable {
                        bypassRunnable = null
                        performBypass(pkg)
                    }
                    bypassRunnable = r
                    mainHandler.postDelayed(r, BYPASS_HOLD_MS)
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (bypassRunnable != null) {
                        // Released early: reset the hold.
                        cancelBypassHold()
                        button.text = "Hold for emergency bypass"
                        bar.visibility = View.INVISIBLE
                        bar.progress = 0
                        if (event.actionMasked == MotionEvent.ACTION_UP) v.performClick()
                    }
                    true
                }
                else -> false
            }
        }
    }

    private fun cancelBypassHold() {
        bypassRunnable?.let { mainHandler.removeCallbacks(it) }
        bypassRunnable = null
        bypassAnimator?.cancel()
        bypassAnimator = null
    }

    private fun performBypass(pkg: String) {
        if (GateStats.bypassesRemaining(service) <= 0) {
            dismissInternal()
            return
        }
        val seconds = prefs.getInt(
            AppMonitorService.KEY_BYPASS_SECONDS,
            AppMonitorService.DEFAULT_BYPASS_SECONDS,
        )
        GateStats.recordBypass(service)
        AppMonitorService.grantBypass(service)
        Log.i(TAG, "bypass granted from $pkg (${seconds}s)")
        dismissInternal()
        service.onTemporaryUnlock()
        launchApp(pkg)
    }

    private fun openAnkiBlock() {
        dismissInternal()
        val launch = service.packageManager.getLaunchIntentForPackage(service.packageName)
            ?: return
        launch.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        try {
            service.startActivity(launch)
        } catch (e: Throwable) {
            Log.w(TAG, "open AnkiBlock failed", e)
        }
    }

    private fun launchApp(pkg: String) {
        val launch = service.packageManager.getLaunchIntentForPackage(pkg) ?: return
        launch.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        try {
            service.startActivity(launch)
        } catch (e: Throwable) {
            Log.w(TAG, "launch $pkg failed", e)
        }
    }

    private fun statusBarHeightPx(): Int {
        val resId = service.resources.getIdentifier("status_bar_height", "dimen", "android")
        if (resId > 0) {
            return service.resources.getDimensionPixelSize(resId)
        }
        return (24 * service.resources.displayMetrics.density).toInt()
    }

    private fun screenHeightPx(): Int {
        return try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                val bounds = windowManager.currentWindowMetrics.bounds
                bounds.height()
            } else {
                val metrics = DisplayMetrics()
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay.getRealMetrics(metrics)
                metrics.heightPixels
            }
        } catch (_: Throwable) {
            service.resources.displayMetrics.heightPixels
        }
    }
}
