package com.anywheredownloader.anywhere_downloader

import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
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
 * Saves an audio file into the MediaStore audio collection
 * (`Music/<album>/`) — `photo_manager` has no audio save API — silently
 * prunes old files from an app-owned gallery album, decodes a thumbnail
 * frame from a local (private) video file, and (backlog #7) reads/rewrites
 * raw MediaStore `RELATIVE_PATH`s so Library's nested playlist-folder model
 * can identify and migrate buckets `photo_manager`'s own bucket-name-only
 * API can't see the hierarchy of. Same defensive try/catch → channel-error
 * style as [MediaNotificationBridge].
 */
class MediaSaveBridge(private val appContext: Context) {

    companion object {
        private const val TAG = "MediaSaveBridge"
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
                if (path == null || album == null || title == null) {
                    result.error("bad_args", "Missing path/album/title", null)
                    return
                }
                runAsync(result, "save_failed") {
                    saveAudio(path, album, title, mimeType)
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
                val isAudio = call.argument<Boolean>("isAudio") ?: false
                if (album == null) {
                    result.error("bad_args", "Missing album", null)
                    return
                }
                runAsync(result, "cleanup_failed") { cleanupEmptyAlbumDir(album, isAudio) }
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
     */
    private fun cleanupEmptyAlbumDir(albumRelativePath: String, isAudio: Boolean): Boolean {
        @Suppress("DEPRECATION")
        val base = Environment.getExternalStoragePublicDirectory(
            if (isAudio) Environment.DIRECTORY_MUSIC else Environment.DIRECTORY_PICTURES,
        )
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
     * `Pictures/AnyWhereDownloader/X[/Y]`, same under `Music/`) to its raw
     * MediaStore `RELATIVE_PATH`, keyed by `BUCKET_ID` — the same id
     * `photo_manager`'s `AssetPathEntity.id` uses (confirmed by reading its
     * Android source, `AndroidQDBUtils.kt`, directly: it builds
     * `AssetPathEntity(id = BUCKET_ID, ...)`). `photo_manager`'s own bucket
     * listing only exposes `BUCKET_DISPLAY_NAME` — the immediate parent
     * folder's plain name, with no hierarchy information at all — so
     * identifying *which* bucket is genuinely ours, and where in the tree
     * it sits, needs this raw column read directly.
     */
    private fun queryLibraryBucketPaths(): Map<String, String> {
        val resolver = appContext.contentResolver
        val collection = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)
        val selection =
            "(${MediaStore.MediaColumns.RELATIVE_PATH} LIKE 'Pictures/AnyWhereDownloader%' OR " +
                "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE 'Music/AnyWhereDownloader%') AND " +
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
     * [newRelativePath] in one bulk `ContentResolver.update()` — Android's
     * documented way for an app to move/rename media files it owns by
     * rewriting `RELATIVE_PATH` (confirmed by reading `photo_manager`'s own
     * Android source: its `AndroidQDBUtils.moveToGallery` does the identical
     * single-row form of this same update, selecting on `_ID`). One
     * bucket-wide selection here instead of a loop of per-row calls.
     *
     * Matches on `RELATIVE_PATH` itself rather than `BUCKET_ID` — the
     * latter is a value MediaProvider *computes* from the path at query
     * time, not a genuine underlying column, and while it's confirmed to
     * work in a `SELECT`'s `WHERE` (see `pruneAlbum`'s `BUCKET_DISPLAY_NAME`
     * use, exercised on-device), an earlier version of this method used it
     * for `UPDATE` too and that was never actually verified to match any
     * rows there — `photo_manager`'s own precedent only uses a real column.
     * `RELATIVE_PATH` is a real column, so this is the safer bet.
     *
     * Returns how many rows moved.
     */
    private fun moveBucket(oldRelativePath: String, newRelativePath: String): Int {
        val resolver = appContext.contentResolver
        val collection = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.RELATIVE_PATH, newRelativePath)
        }
        val moved = resolver.update(
            collection,
            values,
            "${MediaStore.MediaColumns.RELATIVE_PATH} = ?",
            arrayOf(oldRelativePath),
        )
        Log.i(TAG, "moveBucket '$oldRelativePath' -> '$newRelativePath': $moved row(s)")
        return moved
    }

    private fun saveAudio(
        path: String,
        album: String,
        title: String,
        mimeType: String,
    ): String {
        val source = File(path)
        if (!source.exists() || source.length() == 0L) {
            throw IllegalStateException("The downloaded audio file is missing or empty")
        }

        val resolver = appContext.contentResolver
        val collection =
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val relativePath = Environment.DIRECTORY_MUSIC + "/" + album

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
