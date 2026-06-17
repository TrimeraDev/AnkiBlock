package com.example.ankiblock

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

/**
 * Wraps AnkiDroid's public ContentProvider so AnkiBlock can:
 *   - detect whether AnkiDroid is installed,
 *   - request the READ_WRITE_DATABASE runtime permission,
 *   - list decks with their (learn, review, new) counts,
 *   - open AnkiDroid's native reviewer,
 *   - poll schedule snapshots to track delegated-study progress.
 *
 * URIs / column names mirror `com.ichi2.anki.api.FlashCardsContract` — we
 * hard-code them rather than pulling in the AnkiDroid API AAR so the build
 * stays free of an extra Maven dependency.
 */
class AnkiDroidApi(private val context: Context) {

    private val activity: Activity?
        get() = context as? Activity

    companion object {
        const val PACKAGE_NAME = "com.ichi2.anki"
        const val AUTHORITY = "com.ichi2.anki.flashcards"
        const val PERMISSION = "com.ichi2.anki.permission.READ_WRITE_DATABASE"
        const val PERMISSION_REQUEST_CODE = 7710

        private val AUTHORITY_URI: Uri = Uri.parse("content://$AUTHORITY")
        val DECKS_URI: Uri = Uri.withAppendedPath(AUTHORITY_URI, "decks")
        val SCHEDULE_URI: Uri = Uri.withAppendedPath(AUTHORITY_URI, "schedule")

        private const val DECK_ID = "deck_id"
        private const val DECK_NAME = "deck_name"
        private const val DECK_COUNT = "deck_count"

        private const val NOTE_ID = "note_id"
        private const val CARD_ORD = "ord"
    }

    private var pendingPermissionResult: MethodChannel.Result? = null

    fun isInstalled(): Boolean {
        val pm = context.packageManager
        return try {
            pm.getPackageInfo(PACKAGE_NAME, 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    fun hasPermission(): Boolean {
        return ContextCompat.checkSelfPermission(context, PERMISSION) ==
            PackageManager.PERMISSION_GRANTED
    }

    fun requestPermission(result: MethodChannel.Result) {
        if (!isInstalled()) {
            result.error("ANKIDROID_NOT_INSTALLED", "AnkiDroid is not installed", null)
            return
        }
        if (hasPermission()) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error(
                "ALREADY_REQUESTING",
                "A permission request is already in progress",
                null,
            )
            return
        }
        val act = activity
        if (act == null) {
            result.error("NO_ACTIVITY", "Permission request requires an Activity", null)
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            act,
            arrayOf(PERMISSION),
            PERMISSION_REQUEST_CODE,
        )
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val r = pendingPermissionResult
        pendingPermissionResult = null
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        r?.success(granted)
        return true
    }

    fun openAnkiDroid(): Boolean {
        val launch = context.packageManager.getLaunchIntentForPackage(PACKAGE_NAME)
        return if (launch != null) {
            launch.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            context.startActivity(launch)
            true
        } else {
            try {
                val market = Intent(
                    Intent.ACTION_VIEW,
                    Uri.parse("market://details?id=$PACKAGE_NAME"),
                )
                market.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                context.startActivity(market)
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    fun openReviewer(deckId: Long): Boolean {
        val intent = Intent().apply {
            setClassName(PACKAGE_NAME, "com.ichi2.anki.Reviewer")
            action = Intent.ACTION_VIEW
            putExtra("deckId", deckId)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        return try {
            context.startActivity(intent)
            true
        } catch (_: Throwable) {
            openAnkiDroid()
        }
    }

    fun scheduleCardKeys(deckId: Long, limit: Int): List<String> {
        if (!hasPermission()) return emptyList()
        val cr = context.contentResolver
        val selection = "limit=?, deckID=?"
        val args = arrayOf(limit.toString(), deckId.toString())
        val keys = mutableListOf<String>()
        cr.query(SCHEDULE_URI, null, selection, args, null)?.use { c ->
            val noteIdIdx = columnIndex(c, NOTE_ID)
            val cardOrdIdx = columnIndex(c, CARD_ORD, "card_ord")
            while (c.moveToNext()) {
                val noteId = if (noteIdIdx >= 0) c.getLong(noteIdIdx) else continue
                val cardOrd = if (cardOrdIdx >= 0) c.getInt(cardOrdIdx) else 0
                keys.add("$noteId:$cardOrd")
            }
        }
        return keys.distinct()
    }

    fun countReviewedFromSnapshot(
        deckId: Long,
        initialKeys: List<String>,
        pollLimit: Int,
    ): Int {
        if (initialKeys.isEmpty()) return 0
        val current = scheduleCardKeys(deckId, pollLimit).toSet()
        return initialKeys.count { it !in current }
    }

    fun listDecks(): List<Map<String, Any?>> {
        requirePermissionOrThrow()
        val cr = context.contentResolver
        val out = mutableListOf<Map<String, Any?>>()
        cr.query(DECKS_URI, null, null, null, null)?.use { c ->
            val idIdx = c.getColumnIndex(DECK_ID)
            val nameIdx = c.getColumnIndex(DECK_NAME)
            val countsIdx = columnIndex(c, DECK_COUNT, "deck_counts")
            while (c.moveToNext()) {
                val id = if (idIdx >= 0) c.getLong(idIdx) else continue
                val name = if (nameIdx >= 0) c.getString(nameIdx) ?: "" else ""
                val counts = if (countsIdx >= 0) c.getString(countsIdx) else null
                val (learn, review, newC) = parseDeckCounts(counts)
                out.add(
                    mapOf(
                        "id" to id,
                        "name" to name,
                        "learnCount" to learn,
                        "reviewCount" to review,
                        "newCount" to newC,
                    ),
                )
            }
        }
        return out
    }

    private fun parseDeckCounts(raw: String?): Triple<Int, Int, Int> {
        if (raw.isNullOrBlank()) return Triple(0, 0, 0)
        return try {
            val arr = JSONArray(raw)
            Triple(
                if (arr.length() > 0) arr.optInt(0, 0) else 0,
                if (arr.length() > 1) arr.optInt(1, 0) else 0,
                if (arr.length() > 2) arr.optInt(2, 0) else 0,
            )
        } catch (_: Exception) {
            Triple(0, 0, 0)
        }
    }

    private fun columnIndex(
        cursor: android.database.Cursor,
        vararg names: String,
    ): Int {
        for (name in names) {
            val idx = cursor.getColumnIndex(name)
            if (idx >= 0) return idx
        }
        return -1
    }

    private fun requirePermissionOrThrow() {
        if (!isInstalled()) {
            throw AnkiDroidUnavailableException("AnkiDroid is not installed")
        }
        if (!hasPermission()) {
            throw AnkiDroidUnavailableException("READ_WRITE_DATABASE permission not granted")
        }
    }
}

class AnkiDroidUnavailableException(message: String) : RuntimeException(message)
