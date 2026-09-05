package com.anywheredownloader.anywhere_downloader

import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Saves an audio file into the MediaStore audio collection
 * (`Music/<album>/`) — `photo_manager` has no audio save API — and
 * silently prunes old files from an app-owned gallery album (WhatsApp
 * status auto-archive retention). Same defensive try/catch →
 * channel-error style as [MediaNotificationBridge].
 */
class MediaSaveBridge(private val appContext: Context) {

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
                try {
                    result.success(saveAudio(path, album, title, mimeType))
                } catch (e: Exception) {
                    result.error("save_failed", e.message, null)
                }
            }

            "pruneAlbum" -> {
                val album = call.argument<String>("album")
                val olderThanMillis = (call.argument<Number>("olderThanMillis"))?.toLong()
                if (album == null || olderThanMillis == null) {
                    result.error("bad_args", "Missing album/olderThanMillis", null)
                    return
                }
                try {
                    result.success(pruneAlbum(album, olderThanMillis))
                } catch (e: Exception) {
                    result.error("prune_failed", e.message, null)
                }
            }

            else -> result.notImplemented()
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
