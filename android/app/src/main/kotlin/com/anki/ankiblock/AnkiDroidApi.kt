package com.anki.ankiblock

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
        val CARDS_URI: Uri = Uri.withAppendedPath(AUTHORITY_URI, "cards")

        private const val CARD_ID = "_id"

        private const val DECK_ID = "deck_id"
        private const val DECK_NAME = "deck_name"
        private const val DECK_COUNT = "deck_count"

        private const val NOTE_ID = "note_id"
        private const val CARD_ORD = "ord"

        private const val CARD_REPS = "reps"
        private const val CARD_LAPSES = "lapses"
        private const val CARD_TYPE = "type"
        private const val CARD_QUEUE = "queue"
        private const val CARD_DUE = "due"
        private const val CARD_INTERVAL = "interval"

        /** Anki card type codes from the collection. */
        const val CARD_TYPE_NEW = 0
        const val CARD_TYPE_LEARNING = 1
        const val CARD_TYPE_REVIEW = 2
        const val CARD_TYPE_RELEARNING = 3

        /**
         * Learning/relearning Again reschedules due within a few minutes.
         * Hard/Good/Easy push the due horizon further out.
         */
        const val AGAIN_LEARNING_MAX_DUE_SECONDS = 180L
    }

    data class CardSnapshot(
        val reps: Int,
        val lapses: Int,
        val type: Int,
        val queue: Int,
        val due: Long,
        val interval: Int = 0,
    )

    /**
     * Tracks per-card reps/lapses while the user studies in AnkiDroid so we can
     * ignore "Again" presses (lapse++) and learning-cycle Agains that re-enter
     * the schedule shortly after leaving it.
     */
    data class KeyTracker(
        var lastReps: Int,
        var lastLapses: Int,
        var lastDue: Long = 0L,
        var lastType: Int = CARD_TYPE_NEW,
        var credited: Int = 0,
    )

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

    private var pathScheduleSupported: Boolean? = null

    fun scheduleCardKeys(deckId: Long, limit: Int): List<String> {
        if (!hasPermission()) return emptyList()
        val keys = linkedSetOf<String>()

        // Legacy selection-args API (all supported AnkiDroid versions).
        val legacyQueries = listOf(
            "limit=? AND deckID=?" to arrayOf(limit.toString(), deckId.toString()),
            "limit=?, deckID=?" to arrayOf(limit.toString(), deckId.toString()),
        )
        for ((selection, args) in legacyQueries) {
            safeReadScheduleRows(SCHEDULE_URI, selection, args, keys)
            if (keys.isNotEmpty()) break
        }

        // Path-based API (AnkiDroid 2.17+) — optional fallback only.
        if (keys.size < limit && pathScheduleSupported != false) {
            val before = keys.size
            val pathUri = Uri.withAppendedPath(SCHEDULE_URI, deckId.toString())
                .buildUpon()
                .appendQueryParameter("limit", limit.toString())
                .build()
            safeReadScheduleRows(pathUri, null, null, keys)
            if (keys.size == before) {
                pathScheduleSupported = false
            }
        }

        return keys.toList()
    }

    private fun safeReadScheduleRows(
        uri: Uri,
        selection: String?,
        args: Array<String>?,
        keys: MutableSet<String>,
    ) {
        try {
            readScheduleRows(uri, selection, args, keys)
        } catch (e: Exception) {
            android.util.Log.d(
                "AnkiBlock.Delegate",
                "schedule query skipped for $uri: ${e.message}",
            )
        }
    }

    private fun readScheduleRows(
        uri: Uri,
        selection: String?,
        args: Array<String>?,
        keys: MutableSet<String>,
    ) {
        val cr = context.contentResolver
        cr.query(uri, null, selection, args, null)?.use { c ->
            val noteIdIdx = columnIndex(c, NOTE_ID)
            val cardOrdIdx = columnIndex(c, CARD_ORD, "card_ord")
            while (c.moveToNext()) {
                val noteId = if (noteIdIdx >= 0) c.getLong(noteIdIdx) else continue
                val cardOrd = if (cardOrdIdx >= 0) c.getInt(cardOrdIdx) else 0
                keys.add(cardKey(noteId, cardOrd))
            }
        }
    }

    /** learn + review + new counts for one deck (matches Flutter's totalDue). */
    fun deckDueTotal(deckId: Long): Int {
        if (!hasPermission()) return 0
        val deckUri = Uri.withAppendedPath(DECKS_URI, deckId.toString())
        val cr = context.contentResolver
        cr.query(deckUri, null, null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                val countsIdx = columnIndex(c, DECK_COUNT, "deck_counts")
                val counts = if (countsIdx >= 0) c.getString(countsIdx) else null
                val (learn, review, newC) = parseDeckCounts(counts)
                return learn + review + newC
            }
        }
        for (deck in listDecks()) {
            val id = (deck["id"] as? Number)?.toLong() ?: continue
            if (id == deckId) {
                val learn = (deck["learnCount"] as? Number)?.toInt() ?: 0
                val review = (deck["reviewCount"] as? Number)?.toInt() ?: 0
                val newC = (deck["newCount"] as? Number)?.toInt() ?: 0
                return learn + review + newC
            }
        }
        return 0
    }

    fun parseCardKey(key: String): Pair<Long, Int>? {
        val parts = key.split(":")
        if (parts.size != 2) return null
        val noteId = parts[0].toLongOrNull() ?: return null
        val cardOrd = parts[1].toIntOrNull() ?: return null
        return noteId to cardOrd
    }

    fun cardKey(noteId: Long, cardOrd: Int): String = "$noteId:$cardOrd"

    private val cardStatsProjection = arrayOf(
        CARD_ID,
        NOTE_ID,
        CARD_ORD,
        CARD_REPS,
        CARD_LAPSES,
        CARD_TYPE,
        CARD_QUEUE,
        CARD_DUE,
        CARD_INTERVAL,
    )

    fun queryCard(noteId: Long, cardOrd: Int): CardSnapshot? {
        if (!hasPermission()) return null
        val cr = context.contentResolver

        // reps/lapses are opt-in columns on the /cards collection URI.
        try {
            cr.query(CARDS_URI, cardStatsProjection, "nid:$noteId", null, null)?.use { c ->
                while (c.moveToNext()) {
                    val ord = intColumn(c, CARD_ORD)
                    if (ord == cardOrd) return cursorToCardSnapshot(c)
                }
            }
        } catch (e: Exception) {
            android.util.Log.d(
                "AnkiBlock.Delegate",
                "cards query nid:$noteId failed: ${e.message}",
            )
        }

        // Fallback: resolve card id via note URI, then read stats from /cards/{id}.
        val noteUri = Uri.withAppendedPath(
            Uri.withAppendedPath(AUTHORITY_URI, "notes"),
            noteId.toString(),
        )
        val noteCardUri = Uri.withAppendedPath(
            Uri.withAppendedPath(noteUri, "cards"),
            cardOrd.toString(),
        )
        val cardId = cr.query(noteCardUri, arrayOf(CARD_ID), null, null, null)?.use { c ->
            if (c.moveToFirst()) longColumn(c, CARD_ID) else null
        } ?: return null

        return try {
            val cardUri = Uri.withAppendedPath(CARDS_URI, cardId.toString())
            cr.query(cardUri, cardStatsProjection, null, null, null)?.use { c ->
                if (c.moveToFirst()) cursorToCardSnapshot(c) else null
            }
        } catch (e: Exception) {
            android.util.Log.d(
                "AnkiBlock.Delegate",
                "cards query id:$cardId failed: ${e.message}",
            )
            null
        }
    }

    private fun cursorToCardSnapshot(c: android.database.Cursor): CardSnapshot {
        return CardSnapshot(
            reps = intColumn(c, CARD_REPS),
            lapses = intColumn(c, CARD_LAPSES),
            type = intColumn(c, CARD_TYPE),
            queue = intColumn(c, CARD_QUEUE),
            due = longColumn(c, CARD_DUE),
            interval = intColumn(c, CARD_INTERVAL),
        )
    }

    /**
     * True when the answer should count as studied: Hard, Good, or Easy — not Again.
     *
     * Review Again increments lapses. Learning/relearning Again reschedules due
     * within a few minutes without bumping lapses.
     */
    private fun shouldCreditStudy(
        card: CardSnapshot,
        tracker: KeyTracker,
        lapseInc: Int,
    ): Boolean {
        if (lapseInc > 0) return false

        when (card.type) {
            CARD_TYPE_REVIEW -> return true
            CARD_TYPE_LEARNING, CARD_TYPE_RELEARNING -> {
                val nowSec = System.currentTimeMillis() / 1000
                val secondsUntilDue = card.due - nowSec
                if (secondsUntilDue in 0 until AGAIN_LEARNING_MAX_DUE_SECONDS) {
                    return false
                }
                if (card.due >= tracker.lastDue + AGAIN_LEARNING_MAX_DUE_SECONDS) {
                    return true
                }
                return secondsUntilDue >= AGAIN_LEARNING_MAX_DUE_SECONDS
            }
            else -> return true
        }
    }

    /**
     * Counts cards studied toward the daily / session target.
     *
     * Hard, Good, and Easy count; Again does not (review lapse++, or learning
     * cards rescheduled within [AGAIN_LEARNING_MAX_DUE_SECONDS]).
     */
    fun countValidReviews(
        snapshotKeys: List<String>,
        trackers: MutableMap<String, KeyTracker>,
    ): Int {
        if (snapshotKeys.isEmpty()) return 0

        for (key in snapshotKeys) {
            val (noteId, cardOrd) = parseCardKey(key) ?: continue
            val card = queryCard(noteId, cardOrd)
            val tracker = trackers.getOrPut(key) {
                KeyTracker(
                    lastReps = card?.reps ?: 0,
                    lastLapses = card?.lapses ?: 0,
                    lastDue = card?.due ?: 0L,
                    lastType = card?.type ?: CARD_TYPE_NEW,
                )
            }
            if (card == null) continue

            if (card.reps <= tracker.lastReps) continue

            val repDelta = card.reps - tracker.lastReps
            val lapseInc = card.lapses - tracker.lastLapses

            // Stale baseline (e.g. first poll after upgrading query path).
            if (repDelta > 1) {
                tracker.lastReps = card.reps
                tracker.lastLapses = card.lapses
                tracker.lastDue = card.due
                tracker.lastType = card.type
                continue
            }

            if (shouldCreditStudy(card, tracker, lapseInc)) {
                tracker.credited += 1
            }
            tracker.lastReps = card.reps
            tracker.lastLapses = card.lapses
            tracker.lastDue = card.due
            tracker.lastType = card.type
        }

        return trackers.values.sumOf { it.credited }
    }

    private fun longColumn(cursor: android.database.Cursor, name: String): Long {
        val idx = cursor.getColumnIndex(name)
        return if (idx >= 0) cursor.getLong(idx) else 0L
    }

    private fun intColumn(cursor: android.database.Cursor, name: String): Int {
        val idx = cursor.getColumnIndex(name)
        return if (idx >= 0) cursor.getInt(idx) else 0
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
