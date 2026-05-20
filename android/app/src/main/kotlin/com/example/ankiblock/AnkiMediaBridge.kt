package com.example.ankiblock

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.net.Uri
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.URLDecoder

/**
 * SAF bridge for AnkiDroid media.
 *
 * ## How Anki stores media (2024+)
 *
 * There are **two** pieces — cards only reference filenames; bytes live on disk:
 *
 * 1. **`collection.media` folder** — actual image/audio files (`photo.jpg`, etc.)
 * 2. **Media index SQLite** — maps logical names → on-disk names (hash suffixes, etc.)
 *
 * Index file names vary by collection format:
 * - `collection.media.db2` — modern (Python: `media_folder + ".db2"`)
 * - `collection.media.ad.db2` — variant seen on some Android installs
 * - `collection.mdb` — Rust backend path for `collection.anki21b`
 * - `collection.media.db` — legacy
 *
 * The index DB does **not** contain image bytes. Opening `collection.media.db2`
 * alone is not enough — we still need the `collection.media` directory.
 *
 * Card HTML uses `<img src="foo.jpg">` / `[sound:bar.mp3]`; we resolve via the
 * index then read bytes from the media folder.
 */
class AnkiMediaBridge(private val activity: Activity) {

    companion object {
        const val REQUEST_PICK_FOLDER = 7711

        private const val PREFS = "ankidroid_media"
        private const val KEY_TREE_URI = "tree_uri"

        private const val MEDIA_DIR_NAME = "collection.media"

        private val MEDIA_DB_EXACT = setOf(
            "collection.mdb",
            "collection.media.db",
            "collection.media.db2",
            "collection.media.ad.db2",
        )

        /** e.g. collection.media.db2, collection.media.ad.db2 */
        private val MEDIA_DB_PATTERN =
            Regex("(?i)^collection\\.media(\\.[a-z0-9]+)*\\.db2$")

        private val COLLECTION_FILE_PATTERN =
            Regex("(?i)^collection\\.anki2([0-9a-z]*)?$")

        private const val SEARCH_DEPTH = 8
        private const val DEBUG_SAMPLE_LIMIT = 8

        /** How deep to print the granted-folder tree in debug output. */
        private const val LISTING_DEPTH = 5

        private const val LISTING_MAX_LINES = 200

        private const val LOG_TAG = "AnkiBlock.media"

        private val HASH_SUFFIX =
            Regex("^(.+)-[a-f0-9]{40}(\\.[^.]+)$", RegexOption.IGNORE_CASE)

        private val MEDIA_EXTENSIONS = setOf(
            "jpg", "jpeg", "png", "gif", "webp", "svg", "bmp",
            "mp3", "ogg", "wav", "m4a", "mp4", "webm",
        )
    }

    private data class AnkiMediaLayout(
        val mediaDir: DocumentFile?,
        val mediaDb: DocumentFile?,
    )

    private var pendingResult: MethodChannel.Result? = null
    private var cachedLayout: AnkiMediaLayout? = null
    private var cachedMediaIndex: Map<String, String>? = null
    private val uriCache = HashMap<String, Uri>()

    private fun prefs() = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun savedTreeUri(): Uri? {
        val raw = prefs().getString(KEY_TREE_URI, null) ?: return null
        return try {
            Uri.parse(raw)
        } catch (_: Exception) {
            null
        }
    }

    fun hasMediaAccess(): Boolean {
        val uri = savedTreeUri() ?: return false
        return try {
            val granted = activity.contentResolver.persistedUriPermissions
                .any { it.uri == uri && it.isReadPermission }
            if (!granted) return false
            discoverLayout().mediaDir != null
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
        clearCaches()
    }

    private fun clearCaches() {
        cachedLayout = null
        cachedMediaIndex = null
        uriCache.clear()
    }

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
            putExtra(
                DocumentsContract.EXTRA_INITIAL_URI,
                DocumentsContract.buildDocumentUri(
                    "com.android.externalstorage.documents",
                    "primary:Android/data/com.ichi2.anki/files/AnkiDroid",
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
        clearCaches()
        val layout = discoverLayout()
        r?.success(layout.mediaDir != null)
        return true
    }

    private fun treeRoot(): DocumentFile? {
        val tree = savedTreeUri() ?: return null
        return DocumentFile.fromTreeUri(activity, tree)?.takeIf { it.exists() }
    }

    private fun discoverLayout(): AnkiMediaLayout {
        val cached = cachedLayout
        if (cached != null && cached.mediaDir?.exists() == true) {
            return cached
        }
        val root = treeRoot() ?: return AnkiMediaLayout(null, null).also {
            cachedLayout = it
        }
        val layout = if (!root.isDirectory) {
            AnkiMediaLayout(null, null)
        } else {
            scanForAnkiMedia(root)
        }
        cachedLayout = layout
        return layout
    }

    private fun scanForAnkiMedia(root: DocumentFile): AnkiMediaLayout {
        if (isMediaFolder(root)) {
            return AnkiMediaLayout(root, findMediaDbInTree(root))
        }

        var bestDir: DocumentFile? = null
        var bestDb: DocumentFile? = null

        data class Node(val dir: DocumentFile, val depth: Int)
        val queue = ArrayDeque<Node>()
        queue.add(Node(root, 0))

        while (queue.isNotEmpty()) {
            val (dir, depth) = queue.removeFirst()
            if (depth > SEARCH_DEPTH) continue

            val (dirCandidate, dbCandidate) = inspectDirectory(dir)
            if (bestDir == null && dirCandidate != null) bestDir = dirCandidate
            if (bestDb == null && dbCandidate != null) bestDb = dbCandidate

            if (bestDir != null && bestDb != null) break

            if (depth < SEARCH_DEPTH) {
                try {
                    for (child in dir.listFiles()) {
                        if (child.isDirectory) queue.add(Node(child, depth + 1))
                    }
                } catch (_: Exception) {}
            }
        }

        return AnkiMediaLayout(bestDir, bestDb)
    }

    /**
     * Inspects one directory (siblings of collection.anki21b / index DB / media folder).
     */
    private fun inspectDirectory(dir: DocumentFile): Pair<DocumentFile?, DocumentFile?> {
        val children = try {
            dir.listFiles()
        } catch (_: Exception) {
            return Pair(null, null)
        }

        var mediaDir: DocumentFile? = null
        var mediaDb: DocumentFile? = null
        var hasCollection = false

        for (child in children) {
            val name = child.name ?: continue
            when {
                child.isDirectory && isMediaFolderName(name) -> mediaDir = child
                child.isFile && isMediaDbName(name) -> mediaDb = child
                child.isFile && isCollectionFile(name) -> hasCollection = true
            }
        }

        if (mediaDir == null && (hasCollection || mediaDb != null)) {
            mediaDir = children
                .firstOrNull { it.isDirectory && isMediaFolderName(it.name) }
                ?: dir.findFile(MEDIA_DIR_NAME)?.takeIf { it.isDirectory }
        }

        if (mediaDb == null && (hasCollection || mediaDir != null)) {
            mediaDb = children.firstOrNull { it.isFile && isMediaDbName(it.name) }
        }

        return Pair(mediaDir, mediaDb)
    }

    private fun findMediaDbInTree(start: DocumentFile): DocumentFile? {
        data class Node(val dir: DocumentFile, val depth: Int)
        val queue = ArrayDeque<Node>()
        queue.add(Node(start, 0))
        while (queue.isNotEmpty()) {
            val (dir, depth) = queue.removeFirst()
            if (depth > SEARCH_DEPTH) continue
            try {
                for (child in dir.listFiles()) {
                    if (child.isFile && isMediaDbName(child.name)) return child
                    if (child.isDirectory && depth < SEARCH_DEPTH) {
                        queue.add(Node(child, depth + 1))
                    }
                }
            } catch (_: Exception) {}
        }
        return null
    }

    private fun isMediaFolder(file: DocumentFile): Boolean =
        file.isDirectory && isMediaFolderName(file.name)

    private fun isMediaFolderName(name: String?): Boolean {
        if (name == null) return false
        return name.equals(MEDIA_DIR_NAME, ignoreCase = true)
    }

    private fun isMediaDbName(name: String?): Boolean {
        if (name == null) return false
        if (MEDIA_DB_EXACT.any { it.equals(name, ignoreCase = true) }) return true
        return MEDIA_DB_PATTERN.matches(name)
    }

    private fun isCollectionFile(name: String): Boolean =
        COLLECTION_FILE_PATTERN.matches(name)

    private fun mediaDir(): DocumentFile? = discoverLayout().mediaDir

    private fun mediaDbFile(): DocumentFile? = discoverLayout().mediaDb

    private fun resolveDiskFilename(requested: String): String {
        val index = mediaIndex()
        index[requested]?.let { return it }
        index[requested.lowercase()]?.let { return it }
        return requested
    }

    private fun mediaIndex(): Map<String, String> {
        cachedMediaIndex?.let { return it }
        val dbFile = mediaDbFile() ?: return emptyMap<String, String>().also {
            cachedMediaIndex = it
        }
        val built = buildMediaIndex(dbFile)
        cachedMediaIndex = built
        return built
    }

    private fun buildMediaIndex(dbFile: DocumentFile): Map<String, String> {
        val map = HashMap<String, String>()
        val suffix = dbFile.name?.substringAfterLast('.', "db2") ?: "db2"
        val temp = File(
            activity.cacheDir,
            "anki_media_index_${dbFile.uri.hashCode()}.$suffix",
        )
        try {
            activity.contentResolver.openInputStream(dbFile.uri)?.use { input ->
                temp.outputStream().use { output -> input.copyTo(output) }
            } ?: return map
            val db = SQLiteDatabase.openDatabase(
                temp.path,
                null,
                SQLiteDatabase.OPEN_READONLY,
            )
            // fname = on-disk name; csum null means deleted
            db.rawQuery(
                "SELECT fname FROM media WHERE csum IS NOT NULL AND fname IS NOT NULL",
                null,
            ).use { c ->
                val idx = c.getColumnIndex("fname")
                if (idx < 0) return map
                while (c.moveToNext()) {
                    val fname = c.getString(idx) ?: continue
                    if (fname.isBlank()) continue
                    map[fname] = fname
                    map[fname.lowercase()] = fname
                    logicalAlias(fname)?.let { alias ->
                        map.putIfAbsent(alias, fname)
                        map.putIfAbsent(alias.lowercase(), fname)
                    }
                }
            }
            db.close()
        } catch (_: Exception) {
        } finally {
            temp.delete()
        }
        return map
    }

    private fun logicalAlias(diskFname: String): String? {
        val m = HASH_SUFFIX.matchEntire(diskFname) ?: return null
        return m.groupValues[1] + m.groupValues[2]
    }

    private fun normalizeFilename(filename: String): String {
        val trimmed = filename.trim()
        if (trimmed.isEmpty()) return trimmed
        return try {
            URLDecoder.decode(trimmed, "UTF-8")
        } catch (_: Exception) {
            trimmed
        }
    }

    private fun candidateFilenames(requested: String): List<String> {
        val disk = resolveDiskFilename(requested)
        val index = mediaIndex()
        val out = LinkedHashSet<String>()
        out.add(disk)
        out.add(requested)
        index[requested]?.let { out.add(it) }
        index[requested.lowercase()]?.let { out.add(it) }
        return out.toList()
    }

    private fun findMediaFile(dir: DocumentFile, requested: String): DocumentFile? {
        for (name in candidateFilenames(requested)) {
            findMediaFileExact(dir, name)?.let { return it }
        }
        return findMediaFileByHashSuffix(dir, requested)
    }

    private fun findMediaFileExact(dir: DocumentFile, filename: String): DocumentFile? {
        try {
            val direct = dir.findFile(filename)
            if (direct != null && direct.exists() && direct.isFile) return direct
        } catch (_: Exception) {}

        try {
            for (child in dir.listFiles()) {
                if (!child.isFile) continue
                if (child.name.equals(filename, ignoreCase = true)) return child
            }
        } catch (_: Exception) {}
        return null
    }

    private fun findMediaFileByHashSuffix(
        dir: DocumentFile,
        requested: String,
    ): DocumentFile? {
        val dot = requested.lastIndexOf('.')
        val stem = if (dot > 0) requested.substring(0, dot) else requested
        val ext = if (dot > 0) requested.substring(dot) else ""
        val prefix = "$stem-"
        try {
            for (child in dir.listFiles()) {
                if (!child.isFile) continue
                val name = child.name ?: continue
                if (!name.startsWith(prefix, ignoreCase = true)) continue
                if (ext.isNotEmpty() && !name.endsWith(ext, ignoreCase = true)) continue
                if (HASH_SUFFIX.matchEntire(name) != null) return child
            }
        } catch (_: Exception) {}
        return null
    }

    fun getMediaBytes(filename: String): ByteArray? {
        val name = normalizeFilename(filename)
        if (name.isEmpty()) return null
        val uri = uriCache[name] ?: run {
            val dir = mediaDir() ?: return null
            val file = findMediaFile(dir, name) ?: return null
            uriCache[name] = file.uri
            file.uri
        }
        return readUriBytes(uri)
    }

    private fun readUriBytes(uri: Uri): ByteArray? {
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

    /**
     * Walks the SAF-granted tree and returns human-readable lines for debugging.
     * Also printed to logcat under [LOG_TAG].
     */
    fun buildTreeListing(): List<String> {
        val root = treeRoot()
        if (root == null) return listOf("(no folder grant — connect media first)")

        val lines = mutableListOf<String>()
        lines.add("TREE ${root.name ?: "?"}/ (uri=${savedTreeUri()})")

        fun walk(dir: DocumentFile, indent: String, depth: Int) {
            if (lines.size >= LISTING_MAX_LINES) return
            if (depth > LISTING_DEPTH) return

            val children = try {
                dir.listFiles().sortedBy { it.name?.lowercase() ?: "" }
            } catch (e: Exception) {
                lines.add("${indent}(listFiles failed: ${e.message})")
                return
            }

            if (children.isEmpty()) {
                lines.add("${indent}(empty)")
                return
            }

            for (child in children) {
                if (lines.size >= LISTING_MAX_LINES) {
                    lines.add("${indent}… truncated (${LISTING_MAX_LINES} line cap)")
                    return
                }
                val name = child.name ?: "?"
                val kind = when {
                    child.isDirectory -> "DIR "
                    child.isFile -> "FILE"
                    else -> "????"
                }
                val flags = buildString {
                    if (isMediaFolderName(name)) append(" ← media folder")
                    if (isMediaDbName(name)) append(" ← media index DB")
                    if (isCollectionFile(name)) append(" ← collection DB")
                }
                lines.add("$indent$kind $name$flags")
                if (child.isDirectory && depth < LISTING_DEPTH) {
                    walk(child, "$indent  ", depth + 1)
                }
            }
        }

        walk(root, "  ", 0)
        return lines
    }

    private fun logTreeListing(lines: List<String>) {
        Log.i(LOG_TAG, "─── SAF folder listing (${lines.size} lines) ───")
        for (line in lines) {
            Log.i(LOG_TAG, line)
        }
        Log.i(LOG_TAG, "─── end listing ───")
    }

    /**
     * True when the user granted the legacy public `/AnkiDroid` tree (Play Store
     * builds usually keep image bytes under app-specific storage instead).
     */
    private fun isLegacyPublicAnkiDroidGrant(tree: Uri?, rootName: String?): Boolean {
        val uri = tree?.toString()?.lowercase() ?: return false
        if (uri.contains("primary%3aankidroid") && !uri.contains("android/data")) {
            return true
        }
        return rootName.equals("AnkiDroid", ignoreCase = true) &&
            !uri.contains("com.ichi2.anki")
    }

    /** Logs SQLite tables/columns so we can tell index-only vs blob storage. */
    private fun inspectMediaDbSchema(dbFile: DocumentFile): List<String> {
        val lines = mutableListOf<String>()
        val suffix = dbFile.name?.substringAfterLast('.', "db2") ?: "db2"
        val temp = File(
            activity.cacheDir,
            "anki_media_schema_${dbFile.uri.hashCode()}.$suffix",
        )
        try {
            activity.contentResolver.openInputStream(dbFile.uri)?.use { input ->
                temp.outputStream().use { output -> input.copyTo(output) }
            } ?: return listOf("(could not open ${dbFile.name})")
            val db = SQLiteDatabase.openDatabase(
                temp.path,
                null,
                SQLiteDatabase.OPEN_READONLY,
            )
            db.rawQuery(
                "SELECT name, sql FROM sqlite_master WHERE type IN ('table','view') " +
                    "ORDER BY name",
                null,
            ).use { c ->
                while (c.moveToNext()) {
                    val name = c.getString(0) ?: "?"
                    lines.add("TABLE $name")
                    db.rawQuery("PRAGMA table_info($name)", null).use { info ->
                        while (info.moveToNext()) {
                            val col = info.getString(1) ?: "?"
                            val type = info.getString(2) ?: ""
                            lines.add("  $col $type")
                        }
                    }
                }
            }
            db.close()
        } catch (e: Exception) {
            lines.add("(schema read failed: ${e.message})")
        } finally {
            temp.delete()
        }
        return lines
    }

    private fun classifyIssue(
        tree: Uri?,
        root: DocumentFile?,
        layout: AnkiMediaLayout,
    ): String {
        if (root == null) return "no_grant"
        if (layout.mediaDir != null) return "ok"
        if (isLegacyPublicAnkiDroidGrant(tree, root.name) && layout.mediaDb != null) {
            return "legacy_public_folder"
        }
        if (layout.mediaDb != null) return "index_without_media_folder"
        return "no_media_layout"
    }

    fun getMediaDebugInfo(): Map<String, Any?> {
        val tree = savedTreeUri()
        val root = treeRoot()
        val layout = if (tree != null) discoverLayout() else AnkiMediaLayout(null, null)
        val dir = layout.mediaDir
        val db = layout.mediaDb
        val index = if (db != null) mediaIndex() else emptyMap()
        val samples = if (dir != null) listSampleFilenames(dir) else emptyList()
        val listing = buildTreeListing()
        logTreeListing(listing)
        val schema = if (db != null) inspectMediaDbSchema(db) else emptyList()
        for (line in schema) {
            Log.i(LOG_TAG, "SCHEMA $line")
        }
        val issue = classifyIssue(tree, root, layout)
        val granted = tree != null && activity.contentResolver.persistedUriPermissions
            .any { it.uri == tree && it.isReadPermission }
        return mapOf(
            "hasAccess" to hasMediaAccess(),
            "persistedPermission" to granted,
            "issue" to issue,
            "pickedFolderName" to (root?.name ?: ""),
            "treeUri" to (tree?.toString() ?: ""),
            "mediaDirName" to (dir?.name ?: ""),
            "mediaDirUri" to (dir?.uri?.toString() ?: ""),
            "mediaDbName" to (db?.name ?: ""),
            "mediaIndexEntries" to index.size,
            "sampleFiles" to samples,
            "folderListing" to listing,
            "mediaDbSchema" to schema,
            "recommendedPath" to
                "Android → data → com.ichi2.anki → files → AnkiDroid",
            "hint" to mediaHint(tree, root, layout, index.size, issue),
        )
    }

    private fun mediaHint(
        tree: Uri?,
        root: DocumentFile?,
        layout: AnkiMediaLayout,
        indexSize: Int,
        issue: String,
    ): String {
        if (root == null) {
            return "Pick the AnkiDroid folder. AnkiBlock finds collection.media " +
                "(images) and opens the media index DB for you."
        }
        if (issue == "legacy_public_folder") {
            return "You connected legacy storage/AnkiDroid. That folder has " +
                "${layout.mediaDb?.name ?: "the index DB"} but no collection.media " +
                "directory with images. On Play Store AnkiDroid, photos are under " +
                "Android/data/com.ichi2.anki/files/AnkiDroid — pick that folder instead."
        }
        if (layout.mediaDir == null && layout.mediaDb != null) {
            return "Found index ${layout.mediaDb.name} ($indexSize names) but no " +
                "collection.media folder with image files."
        }
        if (layout.mediaDir == null) {
            return "Could not find collection.media. Select the AnkiDroid folder " +
                "that contains a collection.media directory."
        }
        val dbPart = if (layout.mediaDb != null) {
            " Index: ${layout.mediaDb.name} ($indexSize names)."
        } else {
            " No media index DB; using direct filenames only."
        }
        return "Media folder: ${layout.mediaDir.name}.$dbPart"
    }

    private fun listSampleFilenames(dir: DocumentFile): List<String> {
        return try {
            dir.listFiles()
                .asSequence()
                .filter { it.isFile }
                .mapNotNull { it.name }
                .filter { name ->
                    val ext = name.substringAfterLast('.', "").lowercase()
                    ext.isEmpty() || ext in MEDIA_EXTENSIONS || name.startsWith("_")
                }
                .take(DEBUG_SAMPLE_LIMIT)
                .toList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun probeMediaFiles(filenames: List<String>): List<Map<String, Any?>> {
        val dir = mediaDir()
        return filenames.map { raw ->
            val name = normalizeFilename(raw)
            val diskName = if (name.isNotEmpty()) resolveDiskFilename(name) else name
            val file =
                if (dir != null && name.isNotEmpty()) findMediaFile(dir, name) else null
            val bytes = if (file != null) readUriBytes(file.uri) else null
            mapOf(
                "filename" to raw,
                "normalized" to name,
                "diskName" to diskName,
                "found" to (bytes != null),
                "bytes" to (bytes?.size ?: 0),
            )
        }
    }
}
