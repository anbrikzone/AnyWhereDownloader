package com.anywheredownloader.anywhere_downloader

import android.content.Context
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL

/**
 * Shared yt-dlp/ffmpeg initialization, used by both [YtDlpBridge] (getInfo)
 * and [YtDlpDownloadService] (merge downloads) so init happens exactly
 * once regardless of which entry point runs first.
 */
object YtDlpCore {
    @Volatile private var initialized = false

    @Synchronized
    fun ensureInitialized(appContext: Context) {
        if (initialized) return
        YoutubeDL.getInstance().init(appContext)
        FFmpeg.getInstance().init(appContext)
        // The bundled yt-dlp binary is only as fresh as this library's last
        // release. YouTube regularly changes extraction behavior (e.g. the
        // "SABR streaming" rollout that breaks older clients with HTTP 403),
        // and yt-dlp ships fixes for exactly this kind of breakage far more
        // often than we can update the app. This self-updates the bundled
        // yt-dlp script (not the Python/ffmpeg runtime) from its GitHub
        // releases on every cold start — best-effort, never blocks startup
        // on failure (e.g. no network).
        try {
            YoutubeDL.getInstance().updateYoutubeDL(appContext, YoutubeDL.UpdateChannel.STABLE)
        } catch (e: Exception) {
            // Keep working with whatever version is already bundled/cached.
        }
        initialized = true
    }
}
