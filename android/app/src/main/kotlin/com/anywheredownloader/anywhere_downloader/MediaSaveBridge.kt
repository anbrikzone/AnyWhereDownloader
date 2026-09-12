package com.anywheredownloader.anywhere_downloader

import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.IntentSender
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * Saves an audio file into the MediaStore audio collection (`<root>/<album>/`,
 * `root` defaulting to `Music/` — user-configurable since 2026-09-13, see
 * `AppSettingsService.AudioSaveRoot`) — `photo_manager` has no audio save
 * API — silently
 * prunes old files from an app-owned gallery album, decodes a thumbnail
 * frame from a local (private) video file, and (backlog #7) reads/rewrites
 * raw MediaStore `RELATIVE_PATH`s so Library's nested playlist-folder model
 * can identify and migrate buckets `photo_manager`'s own bucket-name-only
 * API can't see the hierarchy of. Same defensive try/catch → channel-error
 * style as [MediaNotificationBridge].
 */
class MediaSaveBridge(
    private val appContext: Context,
    private val launchWriteRequest: (IntentSender) -> Unit,
) {

    companion object {
        private const val TAG = "MediaSaveBridge"

        // Every top-level directory a download might live under, across
        // every `MediaSaveRoot`/`AudioSaveRoot` choice the Dart-side
        // Settings screen offers (backlog #18, 2026-09-13, widened the same
        // day to Android's complete official per-collection directory
        // list) — not just whichever one is configured *today*, since past
        // downloads may have used a since-changed choice and still need to
        // be found. Kept in sync with `AppSettingsService.MediaSaveRoot`/
        // `AudioSaveRoot` by hand.
        private val ALL_SAVE_ROOTS = listOf(
            "Pictures", "DCIM", "Movies",
            "Music", "Podcasts", "Audiobooks", "Alarms", "Notifications", "Ringtones", "Recordings",
        )
    }

    // Set while a `requestWriteAccess` call is waiting on the system
    // consent dialog `launchWriteRequest` triggers; resolved from
    // `onWriteRequestResult` once `MainActivity.onActivityResult` fires
    // (see bug #5 in `moveBucket`'s doc).
    private var pendingWriteRequestResult: MethodChannel.Result? = null

    /** Called by `MainActivity.onActivityResult` for the write-request flow. */
    fun onWriteRequestResult(granted: Boolean) {
        pendingWriteRequestResult?.success(granted)
        pendingWriteRequestResult = null
    }

    // MethodChannel handlers run on the platform (main) thread. These ops
    // hit the filesystem / MediaMetadataRetriever / ContentResolver and
    // must not block it — a burst of archived-video thumbnail decodes on
    // the main thread was stuttering the WhatsApp "Archived" tab's first
    // open. Same background-Executor + main-Handler shape as YtDlpBridge.
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    private fun runAsync(
        result: MethodChannel.Result,
        errorCode: String,
        op: () -> Any?,
    ) {
        executor.execute {
            val outcome = runCatching(op)
            outcome.onFailure { Log.e(TAG, "$errorCode: ${it.message}", it) }
            mainHandler.post {
                outcome.fold(
                    onSuccess = { result.success(it) },
                    onFailure = { result.error(errorCode, it.message, null) },
                )
            }
        }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "saveAudio" -> {
                val path = call.argument<String>("path")
                val album = call.argument<String>("album")
                val title = call.argument<String>("title")
                val mimeType = call.argument<String>("mimeType") ?: "audio/mpeg"
                val root = call.argument<String>("root") ?: Environment.DIRECTORY_MUSIC
                if (path == null || album == null || title == null) {
                    result.error("bad_args", "Missing path/album/title", null)
                    return
                }
                runAsync(result, "save_failed") {
                    saveAudio(path, album, title, mimeType, root)
                }
            }

            "pruneAlbum" -> {
                val album = call.argument<String>("album")
                val olderThanMillis = (call.argument<Number>("olderThanMillis"))?.toLong()
                if (album == null || olderThanMillis == null) {
                    result.error("bad_args", "Missing album/olderThanMillis", null)
                    return
                }
                runAsync(result, "prune_failed") { pruneAlbum(album, olderThanMillis) }
            }

            "cleanupEmptyAlbumDir" -> {
                val album = call.argument<String>("album")
                val root = call.argument<String>("root") ?: Environment.DIRECTORY_PICTURES
                if (album == null) {
                    result.error("bad_args", "Missing album", null)
                    return
                }
                runAsync(result, "cleanup_failed") { cleanupEmptyAlbumDir(album, root) }
            }

            "queryLibraryBucketPaths" -> {
                runAsync(result, "query_failed") { queryLibraryBucketPaths() }
            }

            "moveBucket" -> {
                val oldRelativePath = call.argument<String>("oldRelativePath")
                val newRelativePath = call.argument<String>("newRelativePath")
                if (oldRelativePath == null || newRelativePath == null) {
                    result.error("bad_args", "Missing oldRelativePath/newRelativePath", null)
                    return
                }
                runAsync(result, "move_failed") { moveBucket(oldRelativePath, newRelativePath) }
            }

            "requestWriteAccess" -> {
                val uriStrings = call.argument<List<String>>("uris")
                if (uriStrings.isNullOrEmpty()) {
                    result.error("bad_args", "Missing uris", null)
                    return
                }
                try {
                    val uris = uriStrings.map { Uri.parse(it) }
                    val pendingIntent =
                        MediaStore.createWriteRequest(appContext.contentResolver, uris)
                    pendingWriteRequestResult = result
                    launchWriteRequest(pendingIntent.intentSender)
                } catch (e: Exception) {
                    Log.e(TAG, "requestWriteAccess failed", e)
                    result.error("write_request_failed", e.message, null)
                }
            }

            "videoThumbnail" -> {
                val path = call.argument<String>("path")
                val destPath = call.argument<String>("destPath")
                val width = call.argument<Number>("width")?.toInt() ?: 240
                val height = call.argument<Number>("height")?.toInt() ?: 240
                if (path == null || destPath == null) {
                    result.error("bad_args", "Missing path/destPath", null)
                    return
                }
                runAsync(result, "thumbnail_failed") {
                    videoThumbnail(path, destPath, width, height)
                }
            }

            else -> result.notImplemented()
        }
    }

    /**
     * Decodes a representative frame from the local video [path] and writes
     * it to [destPath] as a JPEG, scaled to fit within [width]x[height].
     * Used for archived-status grid tiles — those files are private to the
     * app, so they aren't MediaStore assets `photo_manager` could thumbnail.
     */
    private fun videoThumbnail(
        path: String,
        destPath: String,
        width: Int,
        height: Int,
    ): Boolean {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            val frame = retriever.getScaledFrameAtTime(
                -1,
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                width,
                height,
            ) ?: return false
            FileOutputStream(File(destPath)).use { out ->
                frame.compress(Bitmap.CompressFormat.JPEG, 85, out)
            }
            frame.recycle()
            return true
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }
    }

    /**
     * Deletes image/video rows in the gallery bucket [album] that were added
     * more than [olderThanMillis] ago. Uses a plain `contentResolver.delete`
     * (no `MediaStore.createDeleteRequest`, so no system confirmation
     * dialog) — valid because every row here was inserted by this app.
     */
    private fun pruneAlbum(album: String, olderThanMillis: Long): Int {
        val resolver = appContext.contentResolver
        val cutoffSeconds = (System.currentTimeMillis() - olderThanMillis) / 1000
        val collection = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)
        val selection =
            "${MediaStore.MediaColumns.BUCKET_DISPLAY_NAME} = ? AND " +
                "${MediaStore.MediaColumns.DATE_ADDED} < ? AND " +
                "${MediaStore.Files.FileColumns.MEDIA_TYPE} IN (" +
                "${MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE}," +
                "${MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO})"
        val args = arrayOf(album, cutoffSeconds.toString())

        var deleted = 0
        resolver.query(
            collection,
            arrayOf(MediaStore.MediaColumns._ID),
            selection,
            args,
            null,
        )?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            while (cursor.moveToNext()) {
                val uri = ContentUris.withAppendedId(collection, cursor.getLong(idCol))
                try {
                    deleted += resolver.delete(uri, null, null)
                } catch (e: RecoverableSecurityException) {
                    // Not owned by this app — leave it alone.
                } catch (e: Exception) {
                    // Skip this one, keep going.
                }
            }
        }
        return deleted
    }

    /**
     * Best-effort cleanup of a now-empty gallery album directory left behind
     * after deleting every MediaStore row that was in it — `ContentResolver`
     * has no notion of "directory", so `deleteWithIds`/`pruneAlbum` removing
     * the last file in a `RELATIVE_PATH` never removes the physical
     * (now-empty) folder itself, only the rows.
     *
     * Not guaranteed to work on every device/OS version: scoped storage
     * (API 29+) generally restricts direct `java.io.File` access to public
     * media directories this app doesn't hold broader storage permissions
     * for — this app deliberately doesn't request `MANAGE_EXTERNAL_STORAGE`
     * (see the Telegram investigation in the root `CLAUDE.md`). In practice
     * many devices *do* allow deleting an empty directory an app's own
     * MediaStore inserts created, since removing an empty directory touches
     * no tracked file — but that's unverified here, hence the plain
     * try/catch and a `Boolean` result the caller doesn't need to check
     * (deletion of the MediaStore rows already succeeded either way; this
     * is pure tidiness, not a correctness requirement).
     *
     * [albumRelativePath] may be multi-segment (e.g.
     * `AnyWhereDownloader/YouTube/Chill Mix` for a nested playlist folder,
     * see the "Playlist folders" section in `library/CLAUDE.md`) — this
     * walks upward deleting each now-empty directory in turn (so emptying
     * the last playlist under a service also cleans up the now-empty
     * service folder, and the shared `AnyWhereDownloader` root itself),
     * stopping at the first non-empty directory or at [base].
     *
     * [root] is the literal top-level directory this album actually lives
     * under (`Pictures`/`DCIM`/`Movies`/`Music`/`Podcasts` — matches
     * `Environment.DIRECTORY_*`'s own string value, see
     * `AppSettingsService.MediaSaveRoot`/`AudioSaveRoot` on the Dart side,
     * added 2026-09-13 for backlog #18's custom save-folder setting) — the
     * caller passes the item's *actual* root, not necessarily today's
     * setting, since a past download may have used a since-changed choice.
     */
    private fun cleanupEmptyAlbumDir(albumRelativePath: String, root: String): Boolean {
        @Suppress("DEPRECATION")
        val base = Environment.getExternalStoragePublicDirectory(root)
        var dir: File? = File(base, albumRelativePath)
        var removedAny = false
        try {
            while (dir != null && dir.path != base.path &&
                dir.isDirectory && dir.list()?.isEmpty() == true
            ) {
                if (dir.delete()) removedAny = true
                dir = dir.parentFile
            }
        } catch (e: Exception) {
            // Best-effort — see the doc above.
        }
        return removedAny
    }

    /**
     * Maps every gallery bucket under this app's shared `AnyWhereDownloader`
     * root (old flat `Pictures/AnyWhereDownloader - X` or new nested
     * `Pictures/AnyWhereDownloader/X[/Y]`, same under any of
     * [ALL_SAVE_ROOTS]) to its raw MediaStore `RELATIVE_PATH`, keyed by
     * `BUCKET_ID` — the same id `photo_manager`'s `AssetPathEntity.id` uses
     * (confirmed by reading its Android source, `AndroidQDBUtils.kt`,
     * directly: it builds `AssetPathEntity(id = BUCKET_ID, ...)`).
     * `photo_manager`'s own bucket listing only exposes
     * `BUCKET_DISPLAY_NAME` — the immediate parent folder's plain name,
     * with no hierarchy information at all — so identifying *which* bucket
     * is genuinely ours, and where in the tree it sits, needs this raw
     * column read directly.
     */
    private fun queryLibraryBucketPaths(): Map<String, String> {
        val resolver = appContext.contentResolver
        val collection = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)
        val rootClauses = ALL_SAVE_ROOTS.joinToString(" OR ") {
            "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE '$it/AnyWhereDownloader%'"
        }
        val selection =
            "($rootClauses) AND " +
                "${MediaStore.Files.FileColumns.MEDIA_TYPE} IN (" +
                "${MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE}," +
                "${MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO}," +
                "${MediaStore.Files.FileColumns.MEDIA_TYPE_AUDIO})"
        val result = HashMap<String, String>()
        resolver.query(
            collection,
            arrayOf(MediaStore.MediaColumns.BUCKET_ID, MediaStore.MediaColumns.RELATIVE_PATH),
            selection,
            null,
            null,
        )?.use { cursor ->
            val bucketCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.BUCKET_ID)
            val pathCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.RELATIVE_PATH)
            while (cursor.moveToNext()) {
                val bucketId = cursor.getString(bucketCol) ?: continue
                val relPath = cursor.getString(pathCol) ?: continue
                result[bucketId] = relPath
            }
        }
        Log.i(TAG, "queryLibraryBucketPaths found ${result.size} bucket(s): $result")
        return result
    }

    /**
     * Moves every file whose `RELATIVE_PATH` is exactly [oldRelativePath] to
     * [newRelativePath]. Returns how many rows moved.
     *
     * **On-device bug #2 (2026-09-12)**: bug #1's fix (matching on
     * `RELATIVE_PATH` instead of `BUCKET_ID`) still moved zero rows, now
     * failing loudly with `IllegalArgumentException: Movement of
     * content://media/external/file which isn't part of well-defined
     * collection not allowed`. Switching to type-specific collections
     * (`Images.Media`/`Video.Media`/`Audio.Media`) with the same bulk
     * `WHERE RELATIVE_PATH = ?` still failed identically against every one
     * of them, confirmed via logcat.
     *
     * **On-device bug #3 (2026-09-12)**: the real constraint behind bug #2's
     * error was row cardinality, not collection type — MediaProvider only
     * honors a `RELATIVE_PATH` change against a single identified row (a
     * URI with the row's `_ID` appended), never a bulk selection. Fixed by
     * querying every row's `_ID` under [oldRelativePath] first and updating
     * each individually via its own appended-ID URI — but still through the
     * *generic* `MediaStore.Files` collection.
     *
     * **On-device bug #4 (2026-09-12)**: bug #3's per-row fix still moved
     * zero rows, now failing with `SecurityException: <app> has no access
     * to content://media/external/file/<id>` for every row, even though
     * this app inserted every one of them. The generic `MediaStore.Files`
     * collection URI (`content://media/external/file/...`) does **not**
     * carry the "own row" write grant Android extends to an app for files
     * it inserted — that grant is only honored against the **type-specific**
     * collection URI (`Images.Media`/`Video.Media`/`Audio.Media`) matching
     * the row's actual media type, even for a single appended-`_ID` URI.
     * Bug #2 and bug #3 were each half the fix: this combines both — per
     * row (bug #3), through that row's own typed collection (bug #2's
     * collection, applied correctly this time: per-row, not bulk).
     *
     * **On-device bug #5 (2026-09-12)**: bug #4's fix moved zero rows
     * *again*, but this time with a materially different exception —
     * `RecoverableSecurityException`, not a plain `SecurityException` —
     * proving bug #4's fix was actually correct: MediaProvider now
     * recognizes these rows as ones this app is allowed to touch, but a
     * `RELATIVE_PATH` change (a real on-disk move, not just a metadata
     * edit) is scoped-storage-sensitive enough that it always requires
     * explicit interactive user consent, even for an app's own files —
     * `RecoverableSecurityException.getUserAction()` carries the consent
     * `PendingIntent` for exactly this. Rather than launch one system
     * dialog per failing row (which would mean dozens for a large
     * library), each such row's content URI is collected here and handed
     * back to the caller as [needsPermissionUris] — [requestWriteAccess]
     * (via [MediaStore.createWriteRequest]) then prompts **once** for the
     * whole batch, and the caller retries the move after consent is
     * granted.
     */
    private fun moveBucket(oldRelativePath: String, newRelativePath: String): Map<String, Any> {
        val resolver = appContext.contentResolver
        val filesCollection = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)
        data class Row(val id: Long, val mediaType: Int)
        val rows = mutableListOf<Row>()
        resolver.query(
            filesCollection,
            arrayOf(MediaStore.MediaColumns._ID, MediaStore.Files.FileColumns.MEDIA_TYPE),
            "${MediaStore.MediaColumns.RELATIVE_PATH} = ?",
            arrayOf(oldRelativePath),
            null,
        )?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val typeCol = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.MEDIA_TYPE)
            while (cursor.moveToNext()) {
                rows.add(Row(cursor.getLong(idCol), cursor.getInt(typeCol)))
            }
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.RELATIVE_PATH, newRelativePath)
        }
        var moved = 0
        val needsPermission = mutableListOf<String>()
        for (row in rows) {
            val typedCollection = when (row.mediaType) {
                MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE ->
                    MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
                MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO ->
                    MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
                MediaStore.Files.FileColumns.MEDIA_TYPE_AUDIO ->
                    MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
                else -> filesCollection
            }
            val uri = ContentUris.withAppendedId(typedCollection, row.id)
            try {
                moved += resolver.update(uri, values, null, null)
            } catch (e: RecoverableSecurityException) {
                needsPermission.add(uri.toString())
            } catch (e: Exception) {
                Log.e(TAG, "moveBucket '$oldRelativePath' failed to move row ${row.id}", e)
            }
        }
        Log.i(
            TAG,
            "moveBucket '$oldRelativePath' -> '$newRelativePath': $moved/${rows.size} row(s), " +
                "${needsPermission.size} need write-access consent",
        )
        return mapOf(
            "moved" to moved,
            "total" to rows.size,
            "needsPermissionUris" to needsPermission,
        )
    }

    private fun saveAudio(
        path: String,
        album: String,
        title: String,
        mimeType: String,
        root: String,
    ): String {
        val source = File(path)
        if (!source.exists() || source.length() == 0L) {
            throw IllegalStateException("The downloaded audio file is missing or empty")
        }

        val resolver = appContext.contentResolver
        val collection =
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val relativePath = "$root/$album"

        val values = ContentValues().apply {
            put(MediaStore.Audio.Media.DISPLAY_NAME, title)
            put(MediaStore.Audio.Media.MIME_TYPE, mimeType)
            put(MediaStore.Audio.Media.RELATIVE_PATH, relativePath)
            put(MediaStore.Audio.Media.IS_MUSIC, 1)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Audio.Media.IS_PENDING, 1)
            }
        }

        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("MediaStore rejected the audio insert")

        try {
            resolver.openOutputStream(uri)?.use { out ->
                source.inputStream().use { it.copyTo(out) }
            } ?: throw IllegalStateException("Could not open the MediaStore output stream")
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            values.clear()
            values.put(MediaStore.Audio.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        }

        return uri.toString()
    }
}
