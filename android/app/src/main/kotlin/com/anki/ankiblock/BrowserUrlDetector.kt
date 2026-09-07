package com.anki.ankiblock

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo

/**
 * Reads the address-bar URL from known browsers via Accessibility node IDs.
 * View IDs rot across browser versions; each package may list several candidates.
 */
object BrowserUrlDetector {
    /**
     * Package → candidate URL-bar view IDs (tried in order).
     * Chromium forks typically share `<pkg>:id/url_bar`.
     */
    val SUPPORTED_BROWSERS: Map<String, List<String>> = mapOf(
        "com.android.chrome" to listOf("com.android.chrome:id/url_bar"),
        "com.chrome.beta" to listOf("com.chrome.beta:id/url_bar"),
        "com.chrome.dev" to listOf("com.chrome.dev:id/url_bar"),
        "com.chrome.canary" to listOf("com.chrome.canary:id/url_bar"),
        "com.sec.android.app.sbrowser" to listOf(
            "com.sec.android.app.sbrowser:id/location_bar_edit_text",
            "com.sec.android.app.sbrowser:id/url_bar",
        ),
        "org.mozilla.firefox" to listOf(
            "org.mozilla.firefox:id/mozac_browser_toolbar_url_view",
            "org.mozilla.firefox:id/url_bar_title",
            "org.mozilla.firefox:id/url_bar",
        ),
        "org.mozilla.firefox_beta" to listOf(
            "org.mozilla.firefox_beta:id/mozac_browser_toolbar_url_view",
            "org.mozilla.firefox_beta:id/url_bar_title",
        ),
        "com.microsoft.emmx" to listOf("com.microsoft.emmx:id/url_bar"),
        "com.brave.browser" to listOf("com.brave.browser:id/url_bar"),
        "com.opera.browser" to listOf(
            "com.opera.browser:id/url_field",
            "com.opera.browser:id/url_bar",
        ),
        "com.opera.mini.native" to listOf(
            "com.opera.mini.native:id/url_field",
            "com.opera.mini.native:id/url_bar",
        ),
        "com.vivaldi.browser" to listOf("com.vivaldi.browser:id/url_bar"),
        "com.duckduckgo.mobile.android" to listOf(
            "com.duckduckgo.mobile.android:id/omnibarTextInput",
            "com.duckduckgo.mobile.android:id/url_bar",
        ),
        "com.kiwibrowser.browser" to listOf("com.kiwibrowser.browser:id/url_bar"),
        "com.ecosia.android" to listOf("com.ecosia.android:id/url_bar"),
    )

    /** Marketing names when the package is not installed on the device. */
    private val BROWSER_DISPLAY_NAMES: Map<String, String> = mapOf(
        "com.android.chrome" to "Chrome",
        "com.chrome.beta" to "Chrome Beta",
        "com.chrome.dev" to "Chrome Dev",
        "com.chrome.canary" to "Chrome Canary",
        "com.sec.android.app.sbrowser" to "Samsung Internet",
        "org.mozilla.firefox" to "Firefox",
        "org.mozilla.firefox_beta" to "Firefox Beta",
        "com.microsoft.emmx" to "Microsoft Edge",
        "com.brave.browser" to "Brave",
        "com.opera.browser" to "Opera",
        "com.opera.mini.native" to "Opera Mini",
        "com.vivaldi.browser" to "Vivaldi",
        "com.duckduckgo.mobile.android" to "DuckDuckGo",
        "com.kiwibrowser.browser" to "Kiwi Browser",
        "com.ecosia.android" to "Ecosia",
    )

    fun isSupportedBrowser(pkg: String): Boolean = SUPPORTED_BROWSERS.containsKey(pkg)

    data class BrowserEntry(
        val packageName: String,
        val appName: String,
    )

    data class BrowserCompatibility(
        val supportedInstalled: List<BrowserEntry>,
        val unsupportedInstalled: List<BrowserEntry>,
        val supportedCatalog: List<String>,
    )

    fun browserCompatibility(context: Context): BrowserCompatibility {
        val installed = installedBrowsers(context)
        val self = context.packageName
        val supportedInstalled = SUPPORTED_BROWSERS.keys
            .filter { it in installed }
            .map { BrowserEntry(it, resolveAppLabel(context, it)) }
            .sortedBy { it.appName.lowercase() }
        val unsupportedInstalled = installed
            .filter { it != self && it !in SUPPORTED_BROWSERS }
            .map { BrowserEntry(it, resolveAppLabel(context, it)) }
            .sortedBy { it.appName.lowercase() }
        val supportedCatalog = SUPPORTED_BROWSERS.keys
            .map { BROWSER_DISPLAY_NAMES[it] ?: it }
            .distinct()
            .sorted()
        return BrowserCompatibility(
            supportedInstalled = supportedInstalled,
            unsupportedInstalled = unsupportedInstalled,
            supportedCatalog = supportedCatalog,
        )
    }

    private fun resolveAppLabel(context: Context, pkg: String): String {
        return try {
            val pm = context.packageManager
            val ai = pm.getApplicationInfo(pkg, 0)
            pm.getApplicationLabel(ai)?.toString()?.takeIf { it.isNotBlank() }
        } catch (_: Throwable) {
            null
        } ?: BROWSER_DISPLAY_NAMES[pkg] ?: pkg
    }

    @Volatile
    private var cachedInstalledBrowsers: Set<String>? = null

    fun invalidateInstalledBrowsersCache() {
        cachedInstalledBrowsers = null
    }

    /** Packages that can handle https VIEW intents (browsers). */
    fun installedBrowsers(context: Context): Set<String> {
        cachedInstalledBrowsers?.let { return it }
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://example.com")).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PackageManager.MATCH_ALL
        } else {
            0
        }
        @Suppress("DEPRECATION")
        val resolveInfos = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.queryIntentActivities(
                intent,
                PackageManager.ResolveInfoFlags.of(flags.toLong()),
            )
        } else {
            pm.queryIntentActivities(intent, flags)
        }
        val pkgs = resolveInfos.mapNotNull { it.activityInfo?.packageName }.toSet()
        cachedInstalledBrowsers = pkgs
        return pkgs
    }

    /**
     * Read the current address-bar text for [pkg], or null if unavailable /
     * the user is actively typing in the omnibox.
     */
    fun readUrl(service: AccessibilityService, pkg: String): String? {
        val viewIds = SUPPORTED_BROWSERS[pkg] ?: return null
        val root = findApplicationRoot(service, pkg) ?: return null
        try {
            for (viewId in viewIds) {
                val nodes = root.findAccessibilityNodeInfosByViewId(viewId)
                if (nodes.isNullOrEmpty()) continue
                try {
                    for (node in nodes) {
                        // Skip while the user is editing the omnibox (search query,
                        // incomplete URL) — only gate on a settled page URL.
                        if (node.isFocused) return null
                        val text = node.text?.toString()?.trim()
                        if (!text.isNullOrEmpty()) return text
                    }
                } finally {
                    for (node in nodes) recycleQuietly(node)
                }
            }
        } finally {
            recycleQuietly(root)
        }
        return null
    }

    private fun findApplicationRoot(
        service: AccessibilityService,
        pkg: String,
    ): AccessibilityNodeInfo? {
        // Prefer the browser's application window over our focused overlay.
        val windows = try {
            service.windows
        } catch (_: Throwable) {
            null
        }
        if (windows != null) {
            for (window in windows) {
                if (window.type != AccessibilityWindowInfo.TYPE_APPLICATION) continue
                val root = try {
                    window.root
                } catch (_: Throwable) {
                    null
                } ?: continue
                val rootPkg = root.packageName?.toString()
                if (rootPkg == pkg) return root
                recycleQuietly(root)
            }
        }
        // Fallback: rootInActiveWindow may be our overlay — only use if it matches.
        val active = try {
            service.rootInActiveWindow
        } catch (_: Throwable) {
            null
        } ?: return null
        return if (active.packageName?.toString() == pkg) {
            active
        } else {
            recycleQuietly(active)
            null
        }
    }

    private fun recycleQuietly(node: AccessibilityNodeInfo?) {
        if (node == null) return
        if (Build.VERSION.SDK_INT >= 34) return // recycled automatically
        try {
            @Suppress("DEPRECATION")
            node.recycle()
        } catch (_: Throwable) {
        }
    }
}
