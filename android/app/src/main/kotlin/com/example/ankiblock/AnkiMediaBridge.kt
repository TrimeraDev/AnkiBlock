package com.example.ankiblock

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * SAF (Storage Access Framework) bridge that lets AnkiBlock read the user's
 * AnkiDroid media folder without requiring `MANAGE_EXTERNAL_STORAGE` (which
 * the Play Store rejects).
 *
 * Flow:
 *   1. [pickAnkiDroidFolder] launches a folder picker scoped to the AnkiDroid
 *      directory; the user confirms the selection.
 *   2. We `takePersistableUriPermission` so the grant survives reboot.
 *   3. [getMediaBytes] looks up `<treeUri>/collection.media/<filename>` on
 *      demand to serve images and audio referenced in card HTML.
 *
 * The picked tree URI is cached in [SharedPreferences] so this is a
 * one-time setup step.
 */
class AnkiMediaBridge(private val activity: Activity) {

    companion object {
        const val REQUEST_PICK_FOLDER = 7711

        private const val PREFS = "ankidroid_media"
        private const val KEY_TREE_URI = "tree_uri"

        /// Subdirectory inside the user's AnkiDroid folder that holds media.
        private const val MEDIA_DIR = "collection.media"
    }

    private var pendingResult: MethodChannel.Result? = null

    /// Cached `collection.media` DocumentFile — re-resolved when needed.
    private var cachedMediaDir: DocumentFile? = null

    /// In-memory filename → uri cache. Cleared whenever the tree URI changes
    /// or the user explicitly forgets the folder.
    private val uriCache = HashMap<String, Uri>()

    // ------------------------------------------------------------------ state

    private fun prefs() = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun savedTreeUri(): Uri? {
        val raw = prefs().getString(KEY_TREE_URI, null) ?: return null
        return try {
            Uri.parse(raw)
        } catch (_: Exception) {
            null
        }
    }

    /// True if we have a persisted tree URI **and** it still resolves to a
    /// folder that contains `collection.media`. Catches the user revoking
    /// access from system settings.
    fun hasMediaAccess(): Boolean {
        val uri = savedTreeUri() ?: return false
        return try {
            val granted = activity.contentResolver.persistedUriPermissions
                .any { it.uri == uri && it.isReadPermission }
            if (!granted) return false
            mediaDir() != null
        } catch (_: Exception) {
            false
        }
    }

    fun forgetFolder() {
        val uri = savedTreeUri()
        if (uri != null) {
            try {
                activity.contentResolver.releasePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            } catch (_: Exception) {}
        }
        prefs().edit().remove(KEY_TREE_URI).apply()
        cachedMediaDir = null
        uriCache.clear()
    }

    // ------------------------------------------------------------------ pick

    /**
     * Launches the system folder picker. The Flutter [result] is held until
     * [onActivityResult] dispatches back; resolves to `true` if the user
     * confirmed a folder we can read from.
     */
    fun pickAnkiDroidFolder(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error(
                "ALREADY_PICKING",
                "A folder picker is already in progress",
                null,
            )
            return
        }
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
            // Try to nudge the picker to start in the AnkiDroid folder.
            // Cosmetic — the user can still navigate anywhere.
            putExtra(
                DocumentsContract.EXTRA_INITIAL_URI,
                DocumentsContract.buildDocumentUri(
                    "com.android.externalstorage.documents",
                    "primary:AnkiDroid",
                ),
            )
        }
        try {
            activity.startActivityForResult(intent, REQUEST_PICK_FOLDER)
        } catch (e: Exception) {
            pendingResult = null
            result.error("PICKER_FAILED", e.message, null)
        }
    }

    /**
     * Returns true if [requestCode] matched our picker so [MainActivity]
     * knows not to fall through to the platform default.
     */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_PICK_FOLDER) return false
        val r = pendingResult
        pendingResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            r?.success(false)
            return true
        }
        val treeUri = data.data!!
        try {
            activity.contentResolver.takePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        } catch (e: Exception) {
            r?.error("PERSIST_FAILED", e.message, null)
            return true
        }
        prefs().edit().putString(KEY_TREE_URI, treeUri.toString()).apply()
        cachedMediaDir = null
        uriCache.clear()

        // Confirm we can actually see `collection.media` inside the chosen
        // folder. If not, surface a clear error rather than silently failing
        // at the first card render.
        val ok = mediaDir() != null
        r?.success(ok)
        return true
    }

    // ----------------------------------------------------------------- lookup

    private fun mediaDir(): DocumentFile? {
        val cached = cachedMediaDir
        if (cached != null && cached.exists()) return cached
        val tree = savedTreeUri() ?: return null
        val root = DocumentFile.fromTreeUri(activity, tree) ?: return null
        if (!root.exists() || !root.isDirectory) return null
        // If the user selected the `collection.media` folder directly, use it;
        // if they selected the parent AnkiDroid folder, look inside it.
        val candidate = if (root.name == MEDIA_DIR) {
            root
        } else {
            root.findFile(MEDIA_DIR)
        }
        if (candidate != null && candidate.isDirectory) {
            cachedMediaDir = candidate
            return candidate
        }
        return null
    }

    /// Reads `<media-dir>/<filename>` and returns the raw bytes, or `null`
    /// if not found / not readable.
    fun getMediaBytes(filename: String): ByteArray? {
        if (filename.isEmpty()) return null
        val uri = uriCache[filename] ?: run {
            val dir = mediaDir() ?: return null
            val file = dir.findFile(filename) ?: return null
            if (!file.exists() || file.isDirectory) return null
            uriCache[filename] = file.uri
            file.uri
        }
        return try {
            activity.contentResolver.openInputStream(uri)?.use { stream ->
                val baos = ByteArrayOutputStream()
                val buf = ByteArray(16 * 1024)
                while (true) {
                    val n = stream.read(buf)
                    if (n <= 0) break
                    baos.write(buf, 0, n)
                }
                baos.toByteArray()
            }
        } catch (_: Exception) {
            null
        }
    }
}
