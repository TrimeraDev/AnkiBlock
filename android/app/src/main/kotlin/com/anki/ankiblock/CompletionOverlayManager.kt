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
 * Draws a completion dialog over other apps (including AnkiDroid) using
 * [WindowManager] + [WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY].
 */
class CompletionOverlayManager(private val context: Context) {

    companion object {
        private const val TAG = "AnkiBlock.Delegate"
    }

    private val appContext = context.applicationContext

    private val windowManager =
        context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private var overlayView: View? = null

    fun show(
        appName: String,
        packageName: String,
        cardsCompleted: Int,
        onDismiss: () -> Unit,
    ) {
        mainHandler.post {
            if (!canDrawOverlays()) {
                Log.w(TAG, "overlay permission denied — granting unlock silently")
                completeWithoutOverlay(packageName, onDismiss)
                return@post
            }
            dismissInternal()
            val themedContext = ContextThemeWrapper(
                appContext,
                android.R.style.Theme_DeviceDefault_Light_Dialog,
            )
            val view = LayoutInflater.from(themedContext).inflate(
                R.layout.overlay_completion,
                null,
            )
            view.findViewById<TextView>(R.id.completion_title).text =
                "You've studied $cardsCompleted cards!"
            view.findViewById<TextView>(R.id.completion_subtitle).text =
                "You can open $appName or keep studying in AnkiDroid."

            view.findViewById<Button>(R.id.btn_open_app).apply {
                text = "Open $appName"
                setOnClickListener {
                    AppMonitorService.grantTempUnlock(context, packageName)
                    AppMonitorService.dismissGateUi(context)
                    launchApp(packageName)
                    dismissInternal()
                    onDismiss()
                }
            }
            view.findViewById<Button>(R.id.btn_keep_studying).setOnClickListener {
                AppMonitorService.dismissGateUi(context)
                dismissInternal()
                onDismiss()
            }

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
                overlayView = view
                Log.i(TAG, "completion overlay shown for $appName ($cardsCompleted cards)")
            } catch (e: Exception) {
                Log.e(TAG, "completion overlay addView failed", e)
                completeWithoutOverlay(packageName, onDismiss)
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

    private fun completeWithoutOverlay(packageName: String, onDismiss: () -> Unit) {
        AppMonitorService.grantTempUnlock(context, packageName)
        AppMonitorService.dismissGateUi(context)
        onDismiss()
    }

    private fun canDrawOverlays(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(appContext)
        } else {
            true
        }
    }

    private fun launchApp(packageName: String) {
        val launch = appContext.packageManager.getLaunchIntentForPackage(packageName)
            ?: return
        launch.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        try {
            context.startActivity(launch)
        } catch (_: Throwable) {
        }
    }
}
