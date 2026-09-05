package com.anywheredownloader.anywhere_downloader

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
 * (`Music/<album>/`). `photo_manager` (used for image/video via
 * [com.anywheredownloader...MediaSaveService] on the Dart side) has no
 * audio save API, so this is a small dedicated bridge. Same defensive
 * try/catch → channel-error style as [MediaNotificationBridge].
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

            else -> result.notImplemented()
        }
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
