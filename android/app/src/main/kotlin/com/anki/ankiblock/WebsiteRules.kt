package com.anki.ankiblock

import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * Website block-rule matching. Pure logic (no Android Context) so it stays
 * easy to reason about and keep in sync with the Dart mirror.
 *
 * Simple patterns: `host[/path-prefix]` e.g. `reddit.com`, `youtube.com/shorts`,
 * `*.tiktok.com`. Host matches exact, vanity mobile prefixes (m./www./mobile.),
 * or real subdomains (ends with `.host`). Pattern `m.youtube.com` ≡ `youtube.com`.
 * Regex patterns: case-insensitive [containsMatchIn] against normalized URL.
 */
object WebsiteRules {
    data class Rule(
        val pattern: String,
        val isRegex: Boolean,
        val label: String,
    )

    /** Lowercase, strip scheme, strip leading www., drop fragment. */
    fun normalize(raw: String): String {
        var s = raw.trim().lowercase()
        if (s.isEmpty()) return ""
        // Strip scheme://
        val schemeIdx = s.indexOf("://")
        if (schemeIdx >= 0) {
            s = s.substring(schemeIdx + 3)
        }
        // Drop credentials (user:pass@host) only in the authority, before path.
        val slash = s.indexOf('/')
        val authority = if (slash < 0) s else s.substring(0, slash)
        val at = authority.lastIndexOf('@')
        if (at >= 0) {
            val rest = if (slash < 0) "" else s.substring(slash)
            s = authority.substring(at + 1) + rest
        }
        // Drop fragment
        val hash = s.indexOf('#')
        if (hash >= 0) s = s.substring(0, hash)
        // Strip leading www.
        if (s.startsWith("www.")) s = s.substring(4)
        return s
    }

    /** Host portion of a normalized URL (before first `/`), without port. */
    fun hostOf(normalized: String): String {
        val slash = normalized.indexOf('/')
        var host = if (slash < 0) normalized else normalized.substring(0, slash)
        val colon = host.indexOf(':')
        if (colon > 0) host = host.substring(0, colon)
        return host
    }

    /** Path+query portion including leading `/`, or empty. */
    fun pathOf(normalized: String): String {
        val slash = normalized.indexOf('/')
        return if (slash < 0) "" else normalized.substring(slash)
    }

    /**
     * Strip common mobile/amp vanity prefixes so m.youtube.com ≡ youtube.com.
     * Does not strip meaningful product subdomains (music., mail., etc.).
     */
    fun canonicalHost(host: String): String {
        var h = host.trim().lowercase()
        if (h.isEmpty()) return ""
        val colon = h.indexOf(':')
        if (colon > 0) h = h.substring(0, colon)
        var changed = true
        while (changed) {
            changed = false
            for (prefix in VANITY_HOST_PREFIXES) {
                if (h.startsWith(prefix) && h.length > prefix.length) {
                    h = h.substring(prefix.length)
                    changed = true
                    break
                }
            }
        }
        return h
    }

    private val VANITY_HOST_PREFIXES = listOf("www.", "m.", "mobile.", "mobi.", "amp.")

    fun match(rawUrl: String, rules: List<Rule>): Rule? {
        if (rules.isEmpty()) return null
        val normalized = normalize(rawUrl)
        if (normalized.isEmpty()) return null
        val host = hostOf(normalized)
        val path = pathOf(normalized)
        for (rule in rules) {
            if (rule.isRegex) {
                if (matchesRegex(rule.pattern, normalized)) return rule
            } else if (matchesSimple(rule.pattern, host, path)) {
                return rule
            }
        }
        return null
    }

    fun matchesSimple(pattern: String, host: String, path: String): Boolean {
        val p = pattern.trim().lowercase()
        if (p.isEmpty()) return false
        val slash = p.indexOf('/')
        var hostPat = if (slash < 0) p else p.substring(0, slash)
        val pathPat = if (slash < 0) "" else p.substring(slash)
        if (hostPat.startsWith("*.")) hostPat = hostPat.substring(2)
        if (hostPat.isEmpty()) return false

        val hostCanon = canonicalHost(host)
        val patCanon = canonicalHost(hostPat)
        // Exact apex, vanity-equivalent (m./www.), or real subdomain (music.youtube.com).
        val hostOk = hostCanon == patCanon ||
            host == patCanon ||
            host.endsWith(".$patCanon") ||
            hostCanon.endsWith(".$patCanon")
        if (!hostOk) return false
        if (pathPat.isEmpty()) return true
        // Path prefix: `/shorts` matches `/shorts` and `/shorts/abc`
        return path == pathPat || path.startsWith("$pathPat/") || path.startsWith(pathPat)
    }

    private fun matchesRegex(pattern: String, normalized: String): Boolean {
        return try {
            Regex(pattern, RegexOption.IGNORE_CASE).containsMatchIn(normalized)
        } catch (_: Throwable) {
            false
        }
    }

    // ---------------------------------------------------------------- prefs

    @Volatile
    private var cachedJson: String? = null

    @Volatile
    private var cachedRules: List<Rule> = emptyList()

    fun load(prefs: SharedPreferences): List<Rule> {
        val json = prefs.getString(AppMonitorService.KEY_BLOCKED_WEBSITES_JSON, null) ?: "[]"
        if (json == cachedJson) return cachedRules
        val parsed = parseJson(json)
        cachedJson = json
        cachedRules = parsed
        return parsed
    }

    fun invalidateCache() {
        cachedJson = null
        cachedRules = emptyList()
    }

    fun parseJson(json: String): List<Rule> {
        return try {
            val arr = JSONArray(json)
            val out = ArrayList<Rule>(arr.length())
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                val pattern = obj.optString("pattern", "").trim()
                if (pattern.isEmpty()) continue
                out.add(
                    Rule(
                        pattern = pattern,
                        isRegex = obj.optBoolean("isRegex", false),
                        label = obj.optString("label", pattern).ifBlank { pattern },
                    ),
                )
            }
            out
        } catch (_: Throwable) {
            emptyList()
        }
    }

    fun toJson(rules: List<Rule>): String {
        val arr = JSONArray()
        for (rule in rules) {
            arr.put(
                JSONObject()
                    .put("pattern", rule.pattern)
                    .put("isRegex", rule.isRegex)
                    .put("label", rule.label),
            )
        }
        return arr.toString()
    }
}
