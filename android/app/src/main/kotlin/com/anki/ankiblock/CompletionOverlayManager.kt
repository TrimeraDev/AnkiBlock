package com.anki.ankiblock

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.ContextThemeWrapper
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView

/**
 * "You've studied N cards" dialog drawn over AnkiDroid with
 * TYPE_ACCESSIBILITY_OVERLAY from [AnkiBlockAccessibilityService].
 */
class CompletionOverlayManager(private val service: AccessibilityService) {

    companion object {
        private const val TAG = "AnkiBlock.Delegate"
    }

    private val windowManager =
        service.getSystemService(android.content.Context.WINDOW_SERVICE) as WindowManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private var overlayView: View? = null

    fun show(appName: String, packageName: String, cardsCompleted: Int) {
        mainHandler.post {
            dismissInternal()
            val themedContext = ContextThemeWrapper(
                service,
                android.R.style.Theme_DeviceDefault_Light_Dialog,
            )
            val view = LayoutInflater.from(themedContext).inflate(
                R.layout.overlay_completion,
                null,
            )
            view.findViewById<TextView>(R.id.completion_title).text =
                "You've studied $cardsCompleted cards!"
            view.findViewById<TextView>(R.id.completion_subtitle).text =
                "All blocked apps and sites are unlocked for a bit. Open $appName or keep studying."

            view.findViewById<Button>(R.id.btn_open_app).apply {
                text = "Open $appName"
                setOnClickListener {
                    dismissInternal()
                    launchApp(packageName)
                }
            }
            view.findViewById<Button>(R.id.btn_keep_studying).setOnClickListener {
                dismissInternal()
            }

            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_DIM_BEHIND,
                PixelFormat.TRANSLUCENT,
            ).apply {
                gravity = Gravity.CENTER
                dimAmount = 0.55f
            }
            try {
                windowManager.addView(view, params)
                overlayView = view
                Log.i(TAG, "completion overlay shown for $appName ($cardsCompleted cards)")
            } catch (e: Exception) {
                // Unlock was already granted by the caller; UI is best-effort.
                Log.e(TAG, "completion overlay addView failed", e)
                GateDiagnostics.recordError(service, "completion addView: ${e.message}")
            }
        }
    }

    fun dismiss() {
        mainHandler.post { dismissInternal() }
    }

    private fun dismissInternal() {
        val view = overlayView ?: return
        try {
            windowManager.removeView(view)
        } catch (_: Throwable) {
        }
        overlayView = null
    }

    private fun launchApp(packageName: String) {
        val launch = service.packageManager.getLaunchIntentForPackage(packageName)
            ?: return
        launch.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        try {
            service.startActivity(launch)
        } catch (_: Throwable) {
        }
    }
}
