package com.anywheredownloader.anywhere_downloader

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.provider.MediaStore
import java.io.File

/**
 * Inserts a local file into the right MediaStore collection under
 * `<relativePath>/` — shared by [MediaSaveBridge] (audio saves requested from
 * Dart) and [YtDlpDownloadService], which saves its own finished files
 * natively so a download that completes after the Flutter UI died (app
 * swiped from Recents, activity recreated) still lands in the gallery
 * instead of being stranded in cacheDir with nobody left to save it.
 */
object MediaStoreWriter {
    enum class Kind { VIDEO, IMAGE, AUDIO }

    /** Returns the new item's `content://` URI as a string. */
    fun save(
        context: Context,
        path: String,
        kind: Kind,
        relativePath: String,
        displayName: String,
        mimeType: String,
    ): String {
        val source = File(path)
        if (!source.exists() || source.length() == 0L) {
            throw IllegalStateException("The downloaded file is missing or empty")
        }

        val resolver = context.contentResolver
        val collection = when (kind) {
            Kind.VIDEO -> MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            Kind.IMAGE -> MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            Kind.AUDIO -> MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        }
        val now = System.currentTimeMillis()
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
            // Same as photo_manager's own save — keeps Library's newest-first
            // ordering consistent with items saved through that path.
            if (kind == Kind.AUDIO) {
                put(MediaStore.Audio.Media.IS_MUSIC, 1)
            } else {
                put(MediaStore.MediaColumns.DATE_TAKEN, now)
            }
        }

        val uri: Uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("MediaStore rejected the insert")

        try {
            resolver.openOutputStream(uri)?.use { out ->
                source.inputStream().use { it.copyTo(out) }
            } ?: throw IllegalStateException("Could not open the MediaStore output stream")
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }

        values.clear()
        values.put(MediaStore.MediaColumns.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return uri.toString()
    }

    /**
     * Kotlin twin of `MediaSaveService._safeTitle` (Dart) — keep the two in
     * sync. Strips characters MediaStore's MIME guessing chokes on (`#` is
     * read as a URL fragment and eats the extension) and guarantees a sane
     * extension survives.
     */
    fun safeDisplayName(fileName: String, fallbackExt: String): String {
        val dot = fileName.lastIndexOf('.')
        val rawExt = if (dot > 0) fileName.substring(dot + 1).lowercase() else ""
        val ext = if (Regex("^[a-z0-9]{1,5}$").matches(rawExt)) rawExt else fallbackExt
        var base = if (dot > 0) fileName.substring(0, dot) else fileName
        base = base
            .replace(Regex("[#?&%:*\"<>|\\\\/\\x00-\\x1F]"), "")
            .replace(Regex("\\s+"), " ")
            .trim()
        if (base.isEmpty()) base = "video"
        return "$base.$ext"
    }
}
