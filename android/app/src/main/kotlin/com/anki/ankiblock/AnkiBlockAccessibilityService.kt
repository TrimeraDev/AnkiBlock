package com.anki.ankiblock

import android.accessibilityservice.AccessibilityService
import android.content.SharedPreferences
import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.accessibility.AccessibilityEvent

/**
 * Event-driven blocker: detects foreground package changes via Accessibility
 * events, reads browser address bars for website rules, draws the native study
 * gate, and tracks AnkiDroid reviews with ContentObserver + a short poll.
 */
class AnkiBlockAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "AnkiBlock.A11y"
        private const val URL_CHECK_THROTTLE_MS = 400L

        /** Windows from these packages never count as "the user switched app". */
        private val TRANSIENT_PACKAGES = setOf(
            "com.android.systemui",
            "android",
        )

        fun isEnabled(context: android.content.Context): Boolean {
            val expected =
                "${context.packageName}/${AnkiBlockAccessibilityService::class.java.canonicalName}"
            val enabled = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            ) ?: return false
            return enabled.split(':').any { it.equals(expected, ignoreCase = true) }
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var prefs: SharedPreferences
    private lateinit var overlayManager: CompletionOverlayManager
    private lateinit var gateOverlay: GateOverlayManager
    private var ankiApi: AnkiDroidApi? = null

    private var currentForegroundPackage: String? = null
    private var lastEventDiagnosticsMs = 0L
    private val keyTrackers = mutableMapOf<String, AnkiDroidApi.KeyTracker>()
    private val passiveKeyTrackers = mutableMapOf<String, AnkiDroidApi.KeyTracker>()
    private var lastReportedProgress = -1
    private var delegatedCompleteStreak = 0
    private var lastPassiveWatching = false
    private var lastStudyDayRolloverCheckMs = 0L
    private var studyTrackingActive = false
    private var contentObserverRegistered = false
    private var scheduledExpireRunnable: Runnable? = null
    private var scheduledUrlCheckRunnable: Runnable? = null
    private var pendingUrlCheckPkg: String? = null
    private var lastUrlCheckMs = 0L
    private var lastUrlHost: String = ""

    private val studyPollRunnable = object : Runnable {
        override fun run() {
            try {
                tickStudyProgress()
            } catch (e: Throwable) {
                Log.w(TAG, "study poll failed", e)
                GateDiagnostics.recordError(this@AnkiBlockAccessibilityService, "study: ${e.message}")
            }
            if (studyTrackingActive) {
                handler.postDelayed(this, AppMonitorService.STUDY_POLL_MS)
            }
        }
    }

    private val ankiContentObserver = object : ContentObserver(handler) {
        override fun onChange(selfChange: Boolean) {
            onChange(selfChange, null)
        }

        override fun onChange(selfChange: Boolean, uri: Uri?) {
            if (!studyTrackingActive) return
            try {
                tickStudyProgress()
            } catch (e: Throwable) {
                Log.w(TAG, "content observer tick failed", e)
            }
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        prefs = getSharedPreferences(AppMonitorService.PREFS, MODE_PRIVATE)
        val api = AnkiDroidApi(applicationContext)
        ankiApi = api
        overlayManager = CompletionOverlayManager(this)
        gateOverlay = GateOverlayManager(this, api)
        AppMonitorService.bindEngine(this)
        AppMonitorService.lastEventMs = System.currentTimeMillis()
        BrowserUrlDetector.invalidateInstalledBrowsersCache()
        BrowserUrlDetector.installedBrowsers(this)
        clearStaleDelegatedSession()
        repairPassiveMergeState()
        ensureStudyDayRollover()
        GateDiagnostics.recordMonitorRestart(this)
        Log.i(TAG, "AccessibilityService connected")
        if (AppMonitorService.hasDelegatedSession(prefs) ||
            currentForegroundPackage == AppMonitorService.ANKIDROID_PACKAGE
        ) {
            ensureStudyTrackingActive()
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val now = System.currentTimeMillis()
        AppMonitorService.lastEventMs = now
        if (now - lastEventDiagnosticsMs > 30_000L) {
            lastEventDiagnosticsMs = now
            GateDiagnostics.recordEvent(this)
        }

        val type = event.eventType
        if (type != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            type != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
        ) {
            return
        }

        val pkg = event.packageName?.toString() ?: return

        // Our own overlays / activity and system UI (shade, recents chrome,
        // dialogs) don't change which app the user is in.
        if (pkg == packageName || pkg in TRANSIENT_PACKAGES) return

        // Ignore noisy content-changed events except AnkiDroid (study tracking)
        // and supported browsers (website rules).
        if (type == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) {
            val allowBrowser = BrowserUrlDetector.isSupportedBrowser(pkg) &&
                AppMonitorService.hasWebsiteRules(prefs)
            if (pkg != AppMonitorService.ANKIDROID_PACKAGE && !allowBrowser) {
                return
            }
        }

        val previous = currentForegroundPackage
        currentForegroundPackage = pkg
        if (previous != pkg) {
            cancelUnlockExpiryCheck()
            cancelUrlCheck()
            // User moved to a different app: the gate for the previous one is moot.
            if (gateOverlay.isShowing && !gateOverlay.isShowingFor(pkg)) {
                gateOverlay.dismiss()
            }
        }

        if (now - lastStudyDayRolloverCheckMs > 60_000L) {
            lastStudyDayRolloverCheckMs = now
            ensureStudyDayRollover()
        }

        if (pkg == AppMonitorService.ANKIDROID_PACKAGE ||
            AppMonitorService.hasDelegatedSession(prefs)
        ) {
            ensureStudyTrackingActive()
        } else if (studyTrackingActive && previous == AppMonitorService.ANKIDROID_PACKAGE) {
            // Left Anki — one more progress check, then tear down tracking soon.
            tickStudyProgress()
            maybeStopStudyTracking()
        }

        if (BrowserUrlDetector.isSupportedBrowser(pkg) &&
            AppMonitorService.hasWebsiteRules(prefs)
        ) {
            scheduleUrlCheck(pkg)
            return
        }

        if (type == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            if (shouldGateUnsupportedBrowser(pkg)) {
                checkUnsupportedBrowserGate(pkg)
            } else {
                checkBlockedAppGate(pkg)
            }
        }
    }

    override fun onInterrupt() {
        cancelUnlockExpiryCheck()
        cancelUrlCheck()
        Log.i(TAG, "AccessibilityService interrupted")
    }

    override fun onDestroy() {
        cancelUnlockExpiryCheck()
        cancelUrlCheck()
        stopStudyTracking()
        overlayManager.dismiss()
        gateOverlay.dismiss()
        if (AppMonitorService.engine === this) {
            AppMonitorService.bindEngine(null)
        }
        super.onDestroy()
    }

    fun isGateShowing(): Boolean = gateOverlay.isShowing

    fun dismissGate() = gateOverlay.dismiss()

    /** Diagnostics: last URL host we inspected (no path). */
    fun lastInspectedUrlHost(): String = lastUrlHost

    /** Diagnostics: wall-clock of last URL bar read. */
    fun lastUrlCheckAtMs(): Long = lastUrlCheckMs

    /**
     * An unlock window was just granted (bypass / bout / session) while a
     * blocked app may already be in the foreground: arm the expiry re-gate
     * now, since no new window event will arrive to do it.
     */
    fun onTemporaryUnlock() {
        val remaining = AppMonitorService.unlockRemainingMs(prefs)
        if (remaining > 0L) {
            handler.post { scheduleUnlockExpiryCheck(remaining) }
        }
    }

    fun ensureStudyTrackingActive() {
        if (studyTrackingActive) return
        studyTrackingActive = true
        registerAnkiObserver()
        handler.removeCallbacks(studyPollRunnable)
        handler.post(studyPollRunnable)
        Log.i(TAG, "study tracking started")
    }

    private fun maybeStopStudyTracking() {
        if (AppMonitorService.hasDelegatedSession(prefs)) return
        if (currentForegroundPackage == AppMonitorService.ANKIDROID_PACKAGE) return
        // Keep passive trackers consolidating briefly after leaving Anki.
        handler.postDelayed({
            if (currentForegroundPackage != AppMonitorService.ANKIDROID_PACKAGE &&
                !AppMonitorService.hasDelegatedSession(prefs)
            ) {
                stopStudyTracking()
            }
        }, 3_000L)
    }

    private fun stopStudyTracking() {
        if (!studyTrackingActive) return
        studyTrackingActive = false
        handler.removeCallbacks(studyPollRunnable)
        unregisterAnkiObserver()
        if (lastPassiveWatching) {
            consolidatePassiveTrackers()
            lastPassiveWatching = false
        }
        Log.i(TAG, "study tracking stopped")
    }

    private fun registerAnkiObserver() {
        if (contentObserverRegistered) return
        try {
            contentResolver.registerContentObserver(
                AnkiDroidApi.CARDS_URI,
                true,
                ankiContentObserver,
            )
            contentResolver.registerContentObserver(
                AnkiDroidApi.SCHEDULE_URI,
                true,
                ankiContentObserver,
            )
            contentObserverRegistered = true
        } catch (e: Throwable) {
            Log.w(TAG, "registerContentObserver failed — poll fallback only", e)
        }
    }

    private fun unregisterAnkiObserver() {
        if (!contentObserverRegistered) return
        try {
            contentResolver.unregisterContentObserver(ankiContentObserver)
        } catch (_: Throwable) {
        }
        contentObserverRegistered = false
    }

    private fun tickStudyProgress() {
        val foreground = currentForegroundPackage
        if (AppMonitorService.hasDelegatedSession(prefs)) {
            checkDelegatedProgress(foreground)
        } else {
            checkPassiveStudy(foreground)
            if (foreground != AppMonitorService.ANKIDROID_PACKAGE) {
                maybeStopStudyTracking()
            }
        }
    }

    private fun clearStaleDelegatedSession() {
        if (!AppMonitorService.hasDelegatedSession(prefs)) return
        val startedAt = prefs.getLong(AppMonitorService.KEY_DELEGATED_STARTED_AT, 0L)
        val age = System.currentTimeMillis() - startedAt
        if (startedAt == 0L || age > 30 * 60 * 1000L) {
            Log.i(TAG, "clearing stale delegated session (age=${age}ms)")
            AppMonitorService.clearDelegatedSession(this)
            keyTrackers.clear()
        }
    }

    private fun repairPassiveMergeState() {
        val passiveTotal = prefs.getInt(AppMonitorService.KEY_PASSIVE_CREDITED_TOTAL, 0)
        val merged = prefs.getInt(AppMonitorService.KEY_PASSIVE_APPLIED_TO_DAILY, 0)
        if (merged > passiveTotal) {
            prefs.edit().putInt(AppMonitorService.KEY_PASSIVE_APPLIED_TO_DAILY, passiveTotal).apply()
            Log.i(TAG, "repaired passive merge watermark $merged -> $passiveTotal")
        }
    }

    private fun ensureStudyDayRollover() {
        val today = AppMonitorService.studyDayKey()
        val stored = prefs.getString(AppMonitorService.KEY_STUDY_DAY, null)
        if (stored == today) {
            ensurePassiveStudyDay()
            return
        }
        Log.i(TAG, "study day rollover $stored -> $today")
        prefs.edit()
            .putString(AppMonitorService.KEY_STUDY_DAY, today)
            .putInt(AppMonitorService.KEY_DAILY_REVIEWED, 0)
            .putInt(AppMonitorService.KEY_PASSIVE_APPLIED_TO_DAILY, 0)
            .apply()
        ensurePassiveStudyDay()
        if (!AppMonitorService.isUnlocked(prefs)) {
            prefs.edit().remove(AppMonitorService.KEY_UNLOCK_UNTIL).apply()
        }
    }

    fun showUnlockOverlay(
        appName: String,
        packageName: String,
        cardsCompleted: Int,
    ) {
        gateOverlay.dismiss()
        overlayManager.show(
            appName = appName,
            packageName = packageName,
            cardsCompleted = cardsCompleted,
        )
    }

    fun onDelegatedSessionSeeded(seed: Int) {
        lastReportedProgress = seed
        delegatedCompleteStreak = 0
    }

    fun resetDelegatedTrackers() {
        keyTrackers.clear()
        lastReportedProgress = -1
        delegatedCompleteStreak = 0
    }

    fun onDelegatedSessionEnded() {
        lastReportedProgress = -1
        delegatedCompleteStreak = 0
        if (currentForegroundPackage != AppMonitorService.ANKIDROID_PACKAGE) {
            stopStudyTracking()
        }
    }

    private fun reportProgressIfChanged(completed: Int, target: Int) {
        if (completed == lastReportedProgress) return
        lastReportedProgress = completed
        val pkg = prefs.getString(AppMonitorService.KEY_DELEGATED_PKG, "") ?: ""
        MainActivity.notifyFlutter(
            "onDelegatedProgress",
            mapOf(
                "completed" to completed,
                "target" to target,
                "packageName" to pkg,
            ),
        )
    }

    private fun checkPassiveStudy(foreground: String?) {
        if (foreground != AppMonitorService.ANKIDROID_PACKAGE) {
            if (lastPassiveWatching) {
                consolidatePassiveTrackers()
                lastPassiveWatching = false
            }
            return
        }

        val api = ankiApi ?: return
        if (!api.hasPermission()) {
            Log.w(TAG, "passive skipped — AnkiDroid READ_WRITE_DATABASE not granted")
            return
        }

        lastPassiveWatching = true
        ensurePassiveStudyDay()
        val deckIds = resolvePassiveDeckIds(api)
        if (deckIds.isEmpty()) return

        ensureMultiDeckSnapshot(
            api,
            deckIds,
            AppMonitorService.KEY_PASSIVE_CARD_KEYS,
            passiveKeyTrackers,
            AppMonitorService.PASSIVE_SNAPSHOT_LIMIT,
        )
        expandMultiDeckKeys(
            api,
            deckIds,
            AppMonitorService.KEY_PASSIVE_CARD_KEYS,
            passiveKeyTrackers,
            AppMonitorService.PASSIVE_SNAPSHOT_LIMIT,
        )

        val keys = prefs.getString(AppMonitorService.KEY_PASSIVE_CARD_KEYS, null)
            ?.split(",")
            ?.filter { it.isNotBlank() }
            ?: return
        if (keys.isEmpty()) return

        val credited = try {
            api.countValidReviews(keys, passiveKeyTrackers)
        } catch (e: Exception) {
            Log.w(TAG, "passive reps poll failed", e)
            return
        }
        if (credited <= 0) return

        for (tracker in passiveKeyTrackers.values) {
            tracker.credited = 0
        }
        AppMonitorService.recordStudyBoutCredit(prefs, credited)
        val prevTotal = prefs.getInt(AppMonitorService.KEY_PASSIVE_CREDITED_TOTAL, 0)
        val newTotal = prevTotal + credited
        val merged = prefs.getInt(AppMonitorService.KEY_PASSIVE_APPLIED_TO_DAILY, 0)
        val delta = (newTotal - merged).coerceAtLeast(0)
        val newDaily = prefs.getInt(AppMonitorService.KEY_DAILY_REVIEWED, 0) + delta
        prefs.edit()
            .putInt(AppMonitorService.KEY_PASSIVE_CREDITED_TOTAL, newTotal)
            .putInt(AppMonitorService.KEY_PASSIVE_APPLIED_TO_DAILY, newTotal)
            .putInt(AppMonitorService.KEY_DAILY_REVIEWED, newDaily)
            .apply()

        MainActivity.notifyFlutter(
            "onPassiveStudyProgress",
            mapOf("delta" to delta, "cardsReviewed" to newDaily),
        )
    }

    private fun resolvePassiveDeckIds(api: AnkiDroidApi): List<Long> {
        val scoped = AppMonitorService.parseScopeDeckIds(
            prefs.getString(AppMonitorService.KEY_SCOPE_DECK_IDS, null),
        )
        if (scoped.isNotEmpty()) return scoped
        return try {
            api.listDecks().mapNotNull { (it["id"] as? Number)?.toLong() }
        } catch (e: Exception) {
            Log.w(TAG, "passive deck fallback failed", e)
            emptyList()
        }
    }

    private fun ensurePassiveStudyDay() {
        val today = AppMonitorService.studyDayKey()
        val stored = prefs.getString(AppMonitorService.KEY_PASSIVE_STUDY_DAY, null)
        if (stored == today) return
        consolidatePassiveTrackers()
        passiveKeyTrackers.clear()
        prefs.edit()
            .putString(AppMonitorService.KEY_PASSIVE_STUDY_DAY, today)
            .remove(AppMonitorService.KEY_PASSIVE_CARD_KEYS)
            .putInt(AppMonitorService.KEY_PASSIVE_CREDITED_TOTAL, 0)
            .putInt(AppMonitorService.KEY_PASSIVE_APPLIED_TO_DAILY, 0)
            .apply()
        AppMonitorService.consumeStudyBout(prefs)
    }

    private fun consolidatePassiveTrackers() {
        val sum = passiveKeyTrackers.values.sumOf { it.credited }
        if (sum <= 0) return
        val total = prefs.getInt(AppMonitorService.KEY_PASSIVE_CREDITED_TOTAL, 0) + sum
        prefs.edit().putInt(AppMonitorService.KEY_PASSIVE_CREDITED_TOTAL, total).apply()
        for (tracker in passiveKeyTrackers.values) {
            tracker.credited = 0
        }
    }

    private fun resolveDelegatedDeckIds(): List<Long> {
        val fromCsv = AppMonitorService.parseDelegatedDeckIds(
            prefs.getString(AppMonitorService.KEY_DELEGATED_DECK_IDS, null),
        ).toList()
        if (fromCsv.isNotEmpty()) return fromCsv
        val launchDeck = prefs.getLong(AppMonitorService.KEY_DELEGATED_DECK_ID, -1L)
        if (launchDeck >= 0) return listOf(launchDeck)
        return emptyList()
    }

    private fun aggregateDeckObligationDue(api: AnkiDroidApi, deckIds: List<Long>): Int {
        var total = 0
        for (deckId in deckIds) {
            total += try {
                api.deckObligationDue(deckId)
            } catch (e: Exception) {
                Log.w(TAG, "obligation-due for deck=$deckId failed", e)
                0
            }
        }
        return total
    }

    private fun isBlockingGoalComplete(): Boolean {
        val mode = prefs.getString(
            AppMonitorService.KEY_STUDY_MODE,
            AppMonitorService.STUDY_MODE_CARD_COUNT,
        ) ?: AppMonitorService.STUDY_MODE_CARD_COUNT
        if (mode == AppMonitorService.STUDY_MODE_DUE_CARDS) {
            val api = ankiApi ?: return false
            if (!api.hasPermission()) return false
            val deckIds = AppMonitorService.parseScopeDeckIds(
                prefs.getString(AppMonitorService.KEY_SCOPE_DECK_IDS, null),
            )
            if (deckIds.isEmpty()) return false
            return try {
                aggregateDeckObligationDue(api, deckIds) <= 0
            } catch (e: Exception) {
                Log.w(TAG, "due-goal check failed", e)
                false
            }
        }
        return AppMonitorService.isDailyGoalComplete(prefs)
    }

    private fun ensureMultiDeckSnapshot(
        api: AnkiDroidApi,
        deckIds: List<Long>,
        keysPrefKey: String,
        trackers: MutableMap<String, AnkiDroidApi.KeyTracker>,
        perDeckLimit: Int,
    ) {
        val existing = prefs.getString(keysPrefKey, null)
        if (!existing.isNullOrBlank()) {
            if (trackers.isEmpty()) {
                seedTrackers(
                    api,
                    existing.split(",").filter { it.isNotBlank() },
                    trackers,
                )
            }
            return
        }
        val keys = linkedSetOf<String>()
        for (deckId in deckIds) {
            keys.addAll(api.scheduleCardKeys(deckId, perDeckLimit))
        }
        if (keys.isEmpty()) return
        seedTrackers(api, keys.toList(), trackers)
        prefs.edit()
            .putString(keysPrefKey, keys.joinToString(","))
            .apply()
        Log.i(TAG, "multi-deck snapshot decks=$deckIds keys=${keys.size}")
    }

    private fun expandMultiDeckKeys(
        api: AnkiDroidApi,
        deckIds: List<Long>,
        keysPrefKey: String,
        trackers: MutableMap<String, AnkiDroidApi.KeyTracker>,
        perDeckLimit: Int,
    ) {
        val raw = prefs.getString(keysPrefKey, null) ?: return
        val tracked = raw.split(",").filter { it.isNotBlank() }.toMutableSet()
        val fresh = linkedSetOf<String>()
        for (deckId in deckIds) {
            fresh.addAll(api.scheduleCardKeys(deckId, perDeckLimit))
        }
        val added = fresh - tracked
        if (added.isEmpty()) return
        tracked.addAll(added)
        seedTrackers(api, added.toList(), trackers, clearExisting = false)
        prefs.edit()
            .putString(keysPrefKey, tracked.joinToString(","))
            .apply()
        Log.d(TAG, "expanded multi-deck snapshot +${added.size} keys (total ${tracked.size})")
    }

    private fun checkDelegatedProgress(foreground: String?) {
        var activePkg = foreground
        if (activePkg == null && AppMonitorService.hasDelegatedSession(prefs)) {
            val startedAt = prefs.getLong(AppMonitorService.KEY_DELEGATED_STARTED_AT, 0L)
            if (startedAt > 0 &&
                System.currentTimeMillis() - startedAt < 60_000
            ) {
                activePkg = AppMonitorService.ANKIDROID_PACKAGE
            }
        }
        if (activePkg == null) return

        val pkg = prefs.getString(AppMonitorService.KEY_DELEGATED_PKG, null) ?: return
        val appName = prefs.getString(AppMonitorService.KEY_DELEGATED_APP_NAME, pkg) ?: pkg
        val target = prefs.getInt(AppMonitorService.KEY_DELEGATED_TARGET, 5)
        val deckIds = resolveDelegatedDeckIds()
        if (deckIds.isEmpty()) return

        val api = ankiApi ?: return
        if (!api.hasPermission()) {
            Log.w(TAG, "poll skipped — AnkiDroid READ_WRITE_DATABASE not granted")
            return
        }

        val inAnki = activePkg == AppMonitorService.ANKIDROID_PACKAGE

        ensureMultiDeckSnapshot(
            api,
            deckIds,
            AppMonitorService.KEY_DELEGATED_CARD_KEYS,
            keyTrackers,
            AppMonitorService.PASSIVE_SNAPSHOT_LIMIT,
        )
        expandMultiDeckKeys(
            api,
            deckIds,
            AppMonitorService.KEY_DELEGATED_CARD_KEYS,
            keyTrackers,
            AppMonitorService.PASSIVE_SNAPSHOT_LIMIT,
        )

        val initialKeys = prefs.getString(AppMonitorService.KEY_DELEGATED_CARD_KEYS, null)
            ?.split(",")
            ?.filter { it.isNotBlank() }
            ?: emptyList()

        val seeded = prefs.getInt(AppMonitorService.KEY_DELEGATED_SEEDED, 0).coerceAtLeast(0)
        val repsBased = if (initialKeys.isEmpty()) {
            if (inAnki) {
                Log.d(TAG, "delegated waiting for schedule snapshot decks=$deckIds")
            }
            0
        } else {
            try {
                api.countValidReviews(initialKeys, keyTrackers)
            } catch (e: Exception) {
                Log.w(TAG, "reps poll failed", e)
                0
            }
        }
        val prevReps = prefs.getInt(AppMonitorService.KEY_DELEGATED_LAST_REPS, 0)
        val effectiveReps = maxOf(repsBased, prevReps)
        if (repsBased > prevReps) {
            val delta = repsBased - prevReps
            AppMonitorService.recordStudyBoutCredit(prefs, delta)
            val newDaily = prefs.getInt(AppMonitorService.KEY_DAILY_REVIEWED, 0) + delta
            prefs.edit()
                .putInt(AppMonitorService.KEY_DAILY_REVIEWED, newDaily)
                .putInt(AppMonitorService.KEY_DELEGATED_LAST_REPS, repsBased)
                .commit()
        }
        val completed = (seeded + effectiveReps).coerceAtMost(target)

        if (completed >= target) {
            delegatedCompleteStreak += 1
        } else {
            delegatedCompleteStreak = 0
        }
        prefs.edit()
            .putInt(AppMonitorService.KEY_DELEGATED_COMPLETE_STREAK, delegatedCompleteStreak)
            .apply()

        if (inAnki || completed > lastReportedProgress) {
            reportProgressIfChanged(completed, target)
        }

        if (completed >= target && delegatedCompleteStreak >= 1) {
            finalizeDelegatedUnlock(
                pkg = pkg,
                appName = appName,
                completed = completed,
            )
            return
        }

        if (!inAnki) {
            val startedAt = prefs.getLong(AppMonitorService.KEY_DELEGATED_STARTED_AT, 0L)
            if (startedAt > 0 &&
                System.currentTimeMillis() - startedAt > 10 * 60 * 1000L
            ) {
                Log.i(TAG, "clearing abandoned delegated session — left AnkiDroid")
                AppMonitorService.clearDelegatedSession(this)
                keyTrackers.clear()
            }
        }
    }

    private fun finalizeDelegatedUnlock(
        pkg: String,
        appName: String,
        completed: Int,
    ) {
        Log.i(TAG, "session complete — $completed cards for $appName")
        keyTrackers.clear()
        val isPractice = pkg == AppMonitorService.PRACTICE_PACKAGE
        if (!isPractice) {
            AppMonitorService.consumeStudyBout(prefs)
            AppMonitorService.grantTempUnlock(this)
            GateStats.recordUnlockEarned(this)
        }
        AppMonitorService.clearDelegatedSession(this)
        gateOverlay.dismiss()
        MainActivity.notifyFlutter(
            "onDelegatedUnlock",
            mapOf("cardsCompleted" to completed),
        )

        if (isPractice) return

        onTemporaryUnlock()
        overlayManager.show(
            appName = appName,
            packageName = pkg,
            cardsCompleted = completed,
        )
    }

    private fun seedTrackers(
        api: AnkiDroidApi,
        keys: List<String>,
        into: MutableMap<String, AnkiDroidApi.KeyTracker>,
        clearExisting: Boolean = true,
    ) {
        if (clearExisting) into.clear()
        for (key in keys) {
            if (into.containsKey(key)) continue
            val (noteId, cardOrd) = api.parseCardKey(key) ?: continue
            val card = api.queryCard(noteId, cardOrd) ?: continue
            into[key] = AnkiDroidApi.KeyTracker(
                lastReps = card.reps,
                lastLapses = card.lapses,
                lastDue = card.due,
                lastType = card.type,
            )
        }
    }

    private fun checkBlockedAppGate(pkg: String) {
        if (gateOverlay.isShowingFor(pkg)) return
        if (!AppMonitorService.isBlockingEnabled(this)) return

        if (!isBlockedPackage(pkg)) return

        if (isBlockingGoalComplete()) return
        val remaining = AppMonitorService.unlockRemainingMs(prefs)
        if (remaining > 0L) {
            scheduleUnlockExpiryCheck(remaining)
            return
        }

        val displayName = lookupDisplayName(pkg) ?: pkg
        if (AppMonitorService.tryUnlockFromRecentBout(
                this,
                pkg,
                displayName,
                AppMonitorService.unlockGoal(prefs),
            )
        ) {
            Log.i(TAG, "skipped gate — recent study bout unlocked $displayName")
            return
        }

        showGate(pkg, displayName, website = false)
    }

    private fun shouldGateUnsupportedBrowser(pkg: String): Boolean {
        if (!AppMonitorService.hasWebsiteRules(prefs)) return false
        if (!AppMonitorService.blockUnsupportedBrowsers(prefs)) return false
        if (BrowserUrlDetector.isSupportedBrowser(pkg)) return false
        return pkg in BrowserUrlDetector.installedBrowsers(this)
    }

    private fun checkUnsupportedBrowserGate(pkg: String) {
        if (gateOverlay.isShowingFor(pkg)) return
        if (!AppMonitorService.isBlockingEnabled(this)) return
        if (isBlockingGoalComplete()) return
        val remaining = AppMonitorService.unlockRemainingMs(prefs)
        if (remaining > 0L) {
            scheduleUnlockExpiryCheck(remaining)
            return
        }
        val browserName = lookupInstalledAppName(pkg) ?: pkg
        val displayName = "Unsupported browser · $browserName"
        if (AppMonitorService.tryUnlockFromRecentBout(
                this,
                pkg,
                displayName,
                AppMonitorService.unlockGoal(prefs),
            )
        ) {
            Log.i(TAG, "skipped gate — recent study bout unlocked $displayName")
            return
        }
        showGate(pkg, displayName, website = false)
    }

    private fun scheduleUrlCheck(pkg: String) {
        pendingUrlCheckPkg = pkg
        if (scheduledUrlCheckRunnable != null) return
        val elapsed = System.currentTimeMillis() - lastUrlCheckMs
        val delay = (URL_CHECK_THROTTLE_MS - elapsed).coerceAtLeast(0L)
        val r = Runnable {
            scheduledUrlCheckRunnable = null
            val target = pendingUrlCheckPkg ?: return@Runnable
            pendingUrlCheckPkg = null
            runUrlCheck(target)
        }
        scheduledUrlCheckRunnable = r
        handler.postDelayed(r, delay)
    }

    private fun cancelUrlCheck() {
        scheduledUrlCheckRunnable?.let { handler.removeCallbacks(it) }
        scheduledUrlCheckRunnable = null
        pendingUrlCheckPkg = null
    }

    private fun runUrlCheck(pkg: String) {
        if (currentForegroundPackage != pkg) return
        if (!AppMonitorService.hasWebsiteRules(prefs)) return
        lastUrlCheckMs = System.currentTimeMillis()
        val raw = try {
            BrowserUrlDetector.readUrl(this, pkg)
        } catch (e: Throwable) {
            Log.w(TAG, "readUrl failed for $pkg", e)
            GateDiagnostics.recordError(this, "readUrl: ${e.message}")
            null
        }
        if (raw == null) return
        val host = WebsiteRules.hostOf(WebsiteRules.normalize(raw))
        lastUrlHost = host
        checkBlockedWebsiteGate(pkg, raw)
    }

    private fun checkBlockedWebsiteGate(pkg: String, rawUrl: String) {
        if (!AppMonitorService.isBlockingEnabled(this)) return
        val rules = WebsiteRules.load(prefs)
        val matched = WebsiteRules.match(rawUrl, rules)
        if (matched == null) {
            // Navigated away from a blocked site in this browser.
            if (gateOverlay.isShowingFor(pkg) && gateOverlay.isWebsiteGate) {
                gateOverlay.dismiss()
            }
            return
        }
        if (isBlockingGoalComplete()) return
        val remaining = AppMonitorService.unlockRemainingMs(prefs)
        if (remaining > 0L) {
            scheduleUnlockExpiryCheck(remaining)
            return
        }
        val host = WebsiteRules.hostOf(WebsiteRules.normalize(rawUrl))
        val browserName = lookupInstalledAppName(pkg) ?: pkg
        val displayName = "${matched.label.ifBlank { host }} · $browserName"
        if (gateOverlay.isShowingFor(pkg) && gateOverlay.isWebsiteGate) {
            // Already covering this browser; refresh label if host changed.
            return
        }
        if (AppMonitorService.tryUnlockFromRecentBout(
                this,
                pkg,
                displayName,
                AppMonitorService.unlockGoal(prefs),
            )
        ) {
            Log.i(TAG, "skipped website gate — recent study bout unlocked $displayName")
            return
        }
        showGate(pkg, displayName, website = true)
    }

    /**
     * When the unlock window ends, re-gate whatever blocked app / website is
     * in the foreground at that moment.
     */
    private fun scheduleUnlockExpiryCheck(delayMs: Long) {
        cancelUnlockExpiryCheck()
        val r = Runnable {
            scheduledExpireRunnable = null
            val pkg = currentForegroundPackage ?: return@Runnable
            if (AppMonitorService.isUnlocked(prefs)) {
                // Window was extended after we were scheduled.
                scheduleUnlockExpiryCheck(AppMonitorService.unlockRemainingMs(prefs))
                return@Runnable
            }
            prefs.edit().remove(AppMonitorService.KEY_UNLOCK_UNTIL).apply()
            if (!AppMonitorService.isBlockingEnabled(this) || isBlockingGoalComplete()) {
                return@Runnable
            }
            if (BrowserUrlDetector.isSupportedBrowser(pkg) &&
                AppMonitorService.hasWebsiteRules(prefs)
            ) {
                scheduleUrlCheck(pkg)
                return@Runnable
            }
            if (shouldGateUnsupportedBrowser(pkg)) {
                checkUnsupportedBrowserGate(pkg)
                return@Runnable
            }
            if (isBlockedPackage(pkg)) {
                showGate(pkg, lookupDisplayName(pkg) ?: pkg, website = false)
            }
        }
        scheduledExpireRunnable = r
        handler.postDelayed(r, delayMs + 50L)
    }

    private fun isBlockedPackage(pkg: String): Boolean {
        val csv = prefs.getString(AppMonitorService.KEY_BLOCKED, "") ?: ""
        return csv.split("|").any { it == pkg }
    }

    private fun cancelUnlockExpiryCheck() {
        scheduledExpireRunnable?.let {
            handler.removeCallbacks(it)
            scheduledExpireRunnable = null
        }
    }

    private fun lookupDisplayName(pkg: String): String? {
        val csv = prefs.getString(AppMonitorService.KEY_BLOCKED_NAMES, "") ?: ""
        for (entry in csv.split("|")) {
            val idx = entry.indexOf('=')
            if (idx > 0 && entry.substring(0, idx) == pkg) {
                return entry.substring(idx + 1)
            }
        }
        return null
    }

    private fun lookupInstalledAppName(pkg: String): String? {
        return try {
            val ai = packageManager.getApplicationInfo(pkg, 0)
            packageManager.getApplicationLabel(ai)?.toString()
        } catch (_: Throwable) {
            null
        }
    }

    private fun showGate(pkg: String, displayName: String, website: Boolean = false) {
        Log.i(TAG, "showGate $displayName ($pkg) website=$website")
        gateOverlay.show(pkg, displayName, website)
    }
}
