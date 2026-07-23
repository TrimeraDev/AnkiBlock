package com.anki.ankiblock

import android.app.Application
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Pre-warms a [FlutterEngine] so the study gate can paint without a cold start.
 */
class AnkiBlockApplication : Application() {

    companion object {
        private const val TAG = "AnkiBlock.App"
        const val ENGINE_ID = "ankiblock_main_engine"

        fun warmFlutterEngine(app: Application) {
            if (FlutterEngineCache.getInstance().get(ENGINE_ID) != null) return
            try {
                val engine = FlutterEngine(app)
                engine.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint.createDefault(),
                )
                FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
                Log.i(TAG, "Flutter engine pre-warmed")
            } catch (e: Throwable) {
                Log.w(TAG, "Flutter engine pre-warm failed", e)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        warmFlutterEngine(this)
    }
}
