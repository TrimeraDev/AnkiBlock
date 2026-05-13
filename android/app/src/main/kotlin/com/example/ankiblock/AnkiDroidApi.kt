package com.example.ankiblock

import android.app.Activity
import android.content.ContentValues
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
 *   - pull due cards for a deck,
 *   - submit a review (ease + time taken) back to AnkiDroid.
 *
 * AnkiDroid then handles AnkiWeb sync, so this is also our piggyback path
 * to keep the user's collection in sync across devices.
 *
 * URIs / column names mirror `com.ichi2.anki.api.FlashCardsContract` — we
 * hard-code them rather than pulling in the AnkiDroid API AAR so the build
 * stays free of an extra Maven dependency.
 */
class AnkiDroidApi(private val activity: Activity) {

    companion object {
        const val PACKAGE_NAME = "com.ichi2.anki"
        const val AUTHORITY = "com.ichi2.anki.flashcards"
        const val PERMISSION = "com.ichi2.anki.permission.READ_WRITE_DATABASE"
        const val PERMISSION_REQUEST_CODE = 7710

        private val AUTHORITY_URI: Uri = Uri.parse("content://$AUTHORITY")
        val DECKS_URI: Uri = Uri.withAppendedPath(AUTHORITY_URI, "decks")
        val SCHEDULE_URI: Uri = Uri.withAppendedPath(AUTHORITY_URI, "schedule")

        // Deck columns
        private const val DECK_ID = "deck_id"
        private const val DECK_NAME = "deck_name"
        private const val DECK_COUNTS = "deck_counts"

        // Schedule / ReviewInfo columns
        private const val NOTE_ID = "note_id"
        private const val CARD_ORD = "card_ord"
        private const val BUTTON_COUNT = "button_count"
        private const val NEXT_REVIEW_TIMES = "next_review_times"
        private const val QUESTION = "question"
        private const val ANSWER = "answer"
        private const val ANSWER_EASE = "answer_ease"
        private const val TIME_TAKEN = "time_taken"
    }

    private var pendingPermissionResult: MethodChannel.Result? = null

    fun isInstalled(): Boolean {
        val pm = activity.packageManager
        return try {
            pm.getPackageInfo(PACKAGE_NAME, 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    fun hasPermission(): Boolean {
        return ContextCompat.checkSelfPermission(activity, PERMISSION) ==
            PackageManager.PERMISSION_GRANTED
    }

    /**
     * Triggers the OS permission prompt for [PERMISSION]. The Flutter caller's
     * [MethodChannel.Result] is held until [onRequestPermissionsResult] fires.
     *
     * If the prompt is already in flight we fail-fast with an error so the
     * UI can recover instead of leaking a dangling result.
     */
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
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            activity,
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

    /**
     * Opens AnkiDroid (or its Play Store listing if not installed). Useful as
     * a fallback when permission was denied "Don't ask again" — the user has
     * to grant via system settings.
     */
    fun openAnkiDroid(): Boolean {
        val launch = activity.packageManager.getLaunchIntentForPackage(PACKAGE_NAME)
        return if (launch != null) {
            launch.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            activity.startActivity(launch)
            true
        } else {
            try {
                val market = Intent(
                    Intent.ACTION_VIEW,
                    Uri.parse("market://details?id=$PACKAGE_NAME"),
                )
                market.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                activity.startActivity(market)
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    /**
     * Lists every deck in the user's AnkiDroid collection.
     *
     * `deck_counts` from the provider is a JSON array in the form
     * `[learn, review, new]`. We split it into named fields so Dart never
     * has to know the ordering.
     */
    fun listDecks(): List<Map<String, Any?>> {
        requirePermissionOrThrow()
        val cr = activity.contentResolver
        val out = mutableListOf<Map<String, Any?>>()
        cr.query(DECKS_URI, null, null, null, null)?.use { c ->
            val idIdx = c.getColumnIndex(DECK_ID)
            val nameIdx = c.getColumnIndex(DECK_NAME)
            val countsIdx = c.getColumnIndex(DECK_COUNTS)
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

    /**
     * Pulls up to [limit] cards that are currently studyable in [deckId].
     * The schedule provider returns a mix of due reviews, learning steps,
     * and new cards (subject to AnkiDroid's per-deck new-cards-per-day limit).
     *
     * `nextReviewTimes` is a JSON string array sized [buttonCount] —
     * the human-readable interval previews for Again/Hard/Good/Easy.
     */
    fun getStudyableCards(deckId: Long, limit: Int): List<Map<String, Any?>> {
        requirePermissionOrThrow()
        val cr = activity.contentResolver
        val selection = "limit=?, deckID=?"
        val args = arrayOf(limit.toString(), deckId.toString())
        val out = mutableListOf<Map<String, Any?>>()
        cr.query(SCHEDULE_URI, null, selection, args, null)?.use { c ->
            val noteIdIdx = c.getColumnIndex(NOTE_ID)
            val cardOrdIdx = c.getColumnIndex(CARD_ORD)
            val buttonCountIdx = c.getColumnIndex(BUTTON_COUNT)
            val nextTimesIdx = c.getColumnIndex(NEXT_REVIEW_TIMES)
            val questionIdx = c.getColumnIndex(QUESTION)
            val answerIdx = c.getColumnIndex(ANSWER)
            while (c.moveToNext()) {
                val noteId = if (noteIdIdx >= 0) c.getLong(noteIdIdx) else continue
                val cardOrd = if (cardOrdIdx >= 0) c.getInt(cardOrdIdx) else 0
                val buttonCount =
                    if (buttonCountIdx >= 0) c.getInt(buttonCountIdx) else 4
                val nextTimesRaw =
                    if (nextTimesIdx >= 0) c.getString(nextTimesIdx) else null
                val question = if (questionIdx >= 0) c.getString(questionIdx) else null
                val answer = if (answerIdx >= 0) c.getString(answerIdx) else null
                out.add(
                    mapOf(
                        "noteId" to noteId,
                        "cardOrd" to cardOrd,
                        "buttonCount" to buttonCount,
                        "nextReviewTimes" to parseStringArray(nextTimesRaw),
                        "question" to (question ?: ""),
                        "answer" to (answer ?: ""),
                    ),
                )
            }
        }
        return out
    }

    private fun parseStringArray(raw: String?): List<String> {
        if (raw.isNullOrBlank()) return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { arr.optString(it, "") }
        } catch (_: Exception) {
            emptyList()
        }
    }

    /**
     * Submits a review back to AnkiDroid. [ease] is 1..4 (Again, Hard, Good,
     * Easy in 4-button mode; for 2/3-button cards AnkiDroid clamps).
     * [timeTakenMs] is what we record as the user's reaction time.
     *
     * Cards are identified by `(noteId, cardOrd)` — AnkiDroid maps that pair
     * to the canonical card id internally.
     */
    fun answerCard(noteId: Long, cardOrd: Int, ease: Int, timeTakenMs: Long): Boolean {
        requirePermissionOrThrow()
        val cr = activity.contentResolver
        val values = ContentValues().apply {
            put(NOTE_ID, noteId)
            put(CARD_ORD, cardOrd)
            put(ANSWER_EASE, ease)
            put(TIME_TAKEN, timeTakenMs)
        }
        val updated = cr.update(SCHEDULE_URI, values, null, null)
        return updated > 0
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
