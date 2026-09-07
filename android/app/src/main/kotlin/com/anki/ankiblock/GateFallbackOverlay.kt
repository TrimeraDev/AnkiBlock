package com.anki.ankiblock

import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.ContextThemeWrapper
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView

/**
 * Safety-net UI when Flutter fails to paint the study gate. Shows a minimal
 * native overlay so the user is never stuck on a blank MainActivity.
 */
class GateFallbackOverlay(private val context: Context) {

    companion object {
        private const val TAG = "AnkiBlock.Gate"
        private const val FALLBACK_DELAY_MS = 4_500L

        @Volatile
        private var flutterGateReady = false

        private val mainHandler = Handler(Looper.getMainLooper())
        private var pendingFallback: Runnable? = null
        private var systemOverlayView: View? = null

        fun markFlutterReady() {
            flutterGateReady = true
            Log.i(TAG, "Flutter gate ready")
        }

        fun resetReadyFlag() {
            flutterGateReady = false
        }

        fun isFlutterGateReady(): Boolean = flutterGateReady

        fun isFlutterReady(): Boolean = flutterGateReady

        /**
         * Starts the blank-gate watchdog after MainActivity has delivered the
         * gate to Flutter. Do not call from AppMonitorService — activity launch
         * latency would eat into the deadline.
         */
        fun scheduleActivityFallback(
            context: Context,
            packageName: String,
            appName: String,
        ) {
            resetReadyFlag()
            cancelActivityFallback()
            val appContext = context.applicationContext
            val runnable = Runnable {
                if (isFlutterReady()) return@Runnable
                Log.w(TAG, "Flutter gate not ready in ${FALLBACK_DELAY_MS}ms — showing fallback")
                GateDiagnostics.recordBlankTimeout(appContext)
                showFallbackOverlay(appContext, packageName, appName)
            }
            pendingFallback = runnable
            mainHandler.postDelayed(runnable, FALLBACK_DELAY_MS)
        }

        fun cancelActivityFallback() {
            pendingFallback?.let { mainHandler.removeCallbacks(it) }
            pendingFallback = null
        }

        fun onFlutterGateReady() {
            markFlutterReady()
            cancelActivityFallback()
            dismissSystemOverlay()
        }

        fun inflateGateFallbackView(
            context: Context,
            packageName: String,
            appName: String,
            onStudy: () -> Unit,
        ): View {
            val unlockGoal = AppMonitorService.unlockGoal(context)
            val themedContext = ContextThemeWrapper(
                context,
                android.R.style.Theme_DeviceDefault_Light_Dialog,
            )
            val view = LayoutInflater.from(themedContext).inflate(
                R.layout.overlay_gate_fallback,
                null,
            )
            view.findViewById<TextView>(R.id.gate_fallback_title).text =
                "Unlock $appName"
            view.findViewById<TextView>(R.id.gate_fallback_subtitle).text =
                "Study $unlockGoal cards in AnkiDroid to unlock this app."
            view.findViewById<Button>(R.id.btn_study_anki).setOnClickListener {
                onStudy()
            }
            return view
        }

        fun startStudySession(context: Context, packageName: String, appName: String) {
            val appContext = context.applicationContext
            val unlockGoal = AppMonitorService.unlockGoal(appContext)
            val prefs = appContext.getSharedPreferences(
                AppMonitorService.PREFS,
                Context.MODE_PRIVATE,
            )
            val deckIdsRaw = prefs.getString(AppMonitorService.KEY_SCOPE_DECK_IDS, null)
            val deckIds = deckIdsRaw
                ?.split(",")
                ?.mapNotNull { it.trim().toLongOrNull() }
                ?: emptyList()
            val deckId = deckIds.firstOrNull() ?: -1L
            AppMonitorService.startDelegatedSession(
                appContext,
                packageName,
                appName,
                deckId,
                deckIds,
                unlockGoal,
            )
            val monitorIntent = Intent(appContext, AppMonitorService::class.java).apply {
                action = AppMonitorService.ACTION_DELEGATED_START
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    appContext.startForegroundService(monitorIntent)
                } else {
                    appContext.startService(monitorIntent)
                }
            } catch (e: Throwable) {
                Log.w(TAG, "failed to start monitor for delegated session", e)
            }
            val anki = appContext.packageManager.getLaunchIntentForPackage(
                AppMonitorService.ANKIDROID_PACKAGE,
            )
            if (anki != null) {
                anki.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                try {
                    appContext.startActivity(anki)
                } catch (_: Throwable) {
                }
            }
        }

        private fun showFallbackOverlay(
            appContext: Context,
            packageName: String,
            appName: String,
        ) {
            mainHandler.post {
                if (!canDrawOverlays(appContext)) {
                    Log.w(TAG, "overlay permission denied — using in-activity fallback")
                    MainActivity.showInActivityGateFallback(packageName, appName)
                    return@post
                }
                if (systemOverlayView != null) return@post
                dismissSystemOverlayInternal(appContext)
                val view = inflateGateFallbackView(appContext, packageName, appName) {
                    startStudySession(appContext, packageName, appName)
                    dismissSystemOverlayInternal(appContext)
                }
                val windowManager =
                    appContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
                val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                } else {
                    @Suppress("DEPRECATION")
                    WindowManager.LayoutParams.TYPE_PHONE
                }
                val params = WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.MATCH_PARENT,
                    overlayType,
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                        WindowManager.LayoutParams.FLAG_DIM_BEHIND,
                    PixelFormat.TRANSLUCENT,
                ).apply {
                    gravity = Gravity.CENTER
                    dimAmount = 0.55f
                }
                try {
                    windowManager.addView(view, params)
                    systemOverlayView = view
                    Log.i(TAG, "gate fallback overlay shown for $appName")
                } catch (e: Exception) {
                    Log.e(TAG, "gate fallback addView failed", e)
                    MainActivity.showInActivityGateFallback(packageName, appName)
                }
            }
        }

        private fun dismissSystemOverlay() {
            val view = systemOverlayView ?: return
            val appContext = view.context.applicationContext
            dismissSystemOverlayInternal(appContext)
        }

        private fun dismissSystemOverlayInternal(appContext: Context) {
            val view = systemOverlayView ?: return
            try {
                val windowManager =
                    appContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
                windowManager.removeView(view)
            } catch (_: Throwable) {
            }
            systemOverlayView = null
        }

        private fun canDrawOverlays(context: Context): Boolean {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Settings.canDrawOverlays(context)
            } else {
                true
            }
        }
    }

    private val appContext = context.applicationContext

    fun onFlutterGateReady() {
        Companion.onFlutterGateReady()
    }

    fun dismiss() {
        dismissSystemOverlay()
    }

    fun show(packageName: String, appName: String) {
        showFallbackOverlay(appContext, packageName, appName)
    }
}
