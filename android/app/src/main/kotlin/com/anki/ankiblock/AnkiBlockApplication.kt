package com.anki.ankiblock

import android.app.Application
import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Pre-warms a [FlutterEngine] so the study gate can paint without a cold start.
 * Tracks engine activity so overnight zombie engines can be recycled.
 */
class AnkiBlockApplication : Application() {

    companion object {
        private const val TAG = "AnkiBlock.App"
        const val ENGINE_ID = "ankiblock_main_engine"
        private const val PREFS = "ankiblock_engine_prefs"
        private const val KEY_LAST_ACTIVITY_MS = "last_engine_activity_ms"
        private const val KEY_ENGINE_RECYCLES = "engine_recycle_count"
        private const val KEY_TASK_REMOVED_RECYCLE = "task_removed_recycle"
        /** Recycle cached engine if idle longer than this before a gate open. */
        private const val STALE_ENGINE_MS = 4L * 60L * 60L * 1000L

        fun warmFlutterEngine(app: Application) {
            if (FlutterEngineCache.getInstance().get(ENGINE_ID) != null) {
                touchEngineActivity(app)
                return
            }
            try {
                val engine = FlutterEngine(app)
                engine.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint.createDefault(),
                )
                FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
                touchEngineActivity(app)
                Log.i(TAG, "Flutter engine pre-warmed")
            } catch (e: Throwable) {
                Log.w(TAG, "Flutter engine pre-warm failed", e)
            }
        }

        fun touchEngineActivity(context: Context) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putLong(KEY_LAST_ACTIVITY_MS, System.currentTimeMillis())
                .apply()
        }

        fun lastEngineActivityMs(context: Context): Long {
            return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getLong(KEY_LAST_ACTIVITY_MS, 0L)
        }

        fun engineRecycleCount(context: Context): Int {
            return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getInt(KEY_ENGINE_RECYCLES, 0)
        }

        fun isEngineStale(context: Context): Boolean {
            val last = lastEngineActivityMs(context)
            if (last <= 0L) return false
            return System.currentTimeMillis() - last > STALE_ENGINE_MS
        }

        /** MainActivity was swiped from recents — cached engine often has a 0×0 surface. */
        fun markActivityTaskRemoved(context: Context) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_TASK_REMOVED_RECYCLE, true)
                .apply()
        }

        private fun consumeTaskRemovedRecycleFlag(context: Context): Boolean {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (!prefs.getBoolean(KEY_TASK_REMOVED_RECYCLE, false)) return false
            prefs.edit().remove(KEY_TASK_REMOVED_RECYCLE).apply()
            return true
        }

        /**
         * Recycle before attaching MainActivity for a study gate. Forces recycle
         * when the task was removed from recents or the Flutter surface is broken.
         */
        fun prepareEngineForGate(app: Application, brokenSurface: Boolean = false): Boolean {
            val force = brokenSurface || consumeTaskRemovedRecycleFlag(app)
            if (force) {
                return recycleFlutterEngineIfNeeded(app, force = true)
            }
            return recycleFlutterEngineIfNeeded(app, force = false)
        }

        /**
         * Destroys the cached engine and creates a fresh one. Call before
         * attaching MainActivity when the process survived overnight with a
         * zombie isolate that no longer paints frames.
         */
        fun recycleFlutterEngineIfNeeded(app: Application, force: Boolean = false): Boolean {
            val cache = FlutterEngineCache.getInstance()
            val existing = cache.get(ENGINE_ID)
            if (existing == null) {
                warmFlutterEngine(app)
                return false
            }
            if (!force && !isEngineStale(app)) return false

            Log.i(TAG, "Recycling Flutter engine (force=$force stale=${isEngineStale(app)})")
            GateFallbackOverlay.resetReadyFlag()
            try {
                cache.remove(ENGINE_ID)
                existing.destroy()
            } catch (e: Throwable) {
                Log.w(TAG, "Engine destroy failed", e)
            }
            app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putInt(KEY_ENGINE_RECYCLES, engineRecycleCount(app) + 1)
                .apply()
            warmFlutterEngine(app)
            return true
        }
    }

    override fun onCreate() {
        super.onCreate()
        warmFlutterEngine(this)
    }
}
