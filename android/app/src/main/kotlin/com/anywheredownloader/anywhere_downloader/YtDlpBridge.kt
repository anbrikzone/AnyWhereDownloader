package com.anywheredownloader.anywhere_downloader

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLException
import com.yausername.youtubedl_android.YoutubeDLRequest
import com.yausername.youtubedl_android.mapper.VideoFormat
import com.yausername.youtubedl_android.mapper.VideoInfo
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Bridges Dart (`core/yt_dlp_engine`) to the youtubedl-android library.
 * Kept as a plain class rather than a full Flutter plugin package — the
 * surface area doesn't justify the ceremony.
 *
 * `getInfo` runs and returns here directly. `startMergeDownload` only
 * starts [YtDlpDownloadService] and returns immediately — actual progress
 * and completion are reported later by the service calling back into Dart
 * on the same channel (see [NativeToDartChannel]).
 */
class YtDlpBridge(private val appContext: Context) {
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getInfo" -> {
                val url = call.argument<String>("url")
                if (url == null) {
                    result.error("bad_args", "Missing 'url' argument", null)
                    return
                }
                getInfo(url, result)
            }

            "startMergeDownload" -> {
                val url = call.argument<String>("url")
                val formatSelector = call.argument<String>("formatSelector")
                val outputPath = call.argument<String>("outputPath")
                val processId = call.argument<String>("processId")
                val durationSeconds = call.argument<Int>("durationSeconds") ?: 0
                if (url == null || formatSelector == null || outputPath == null || processId == null) {
                    result.error("bad_args", "Missing arguments", null)
                    return
                }
                val intent = Intent(appContext, YtDlpDownloadService::class.java).apply {
                    putExtra(YtDlpDownloadService.EXTRA_URL, url)
                    putExtra(YtDlpDownloadService.EXTRA_FORMAT_SELECTOR, formatSelector)
                    putExtra(YtDlpDownloadService.EXTRA_OUTPUT_PATH, outputPath)
                    putExtra(YtDlpDownloadService.EXTRA_PROCESS_ID, processId)
                    putExtra(YtDlpDownloadService.EXTRA_DURATION_SECONDS, durationSeconds)
                }
                ContextCompat.startForegroundService(appContext, intent)
                result.success(null)
            }

            "cancelDownload" -> {
                val processId = call.argument<String>("processId")
                if (processId == null) {
                    result.error("bad_args", "Missing 'processId' argument", null)
                    return
                }
                result.success(YoutubeDL.getInstance().destroyProcessById(processId))
            }

            else -> result.notImplemented()
        }
    }

    private fun getInfo(url: String, result: MethodChannel.Result) {
        executor.execute {
            try {
                YtDlpCore.ensureInitialized(appContext)
                val info = try {
                    YoutubeDL.getInstance().getInfo(url)
                } catch (e: YoutubeDLException) {
                    if (isTwitterUrl(url) && e.message?.contains("No video could be found") == true) {
                        // X/Twitter's default GraphQL extraction path doesn't
                        // surface "Amplify" (promoted/ad) videos — confirmed
                        // by calling Twitter's public syndication endpoint
                        // directly (cdn.syndication.twimg.com/tweet-result)
                        // for a real tweet that hit exactly this error: it
                        // returned complete video_info/variants data GraphQL
                        // didn't. `--extractor-args "twitter:api=syndication"`
                        // is a real, intended yt-dlp option (confirmed by
                        // reading twitter.py directly, not guessed) that
                        // steers extraction to that same endpoint. Only
                        // retried as a fallback after the default path
                        // reports no video, rather than always forcing it,
                        // since syndication is yt-dlp's own known-reduced-
                        // fidelity path (its `_call_syndication_api` warns
                        // "Not all metadata or media is available") — no
                        // reason to downgrade the common case that already
                        // works via GraphQL.
                        val request = YoutubeDLRequest(url)
                        request.addOption("--extractor-args", "twitter:api=syndication")
                        YoutubeDL.getInstance().getInfo(request)
                    } else {
                        throw e
                    }
                }
                val map = videoInfoToMap(info)
                mainHandler.post { result.success(map) }
            } catch (e: YoutubeDLException) {
                mainHandler.post { result.error("yt_dlp_error", e.message, null) }
            } catch (e: Exception) {
                mainHandler.post { result.error("unknown_error", e.message, null) }
            }
        }
    }

    private fun isTwitterUrl(url: String): Boolean {
        val host = try {
            java.net.URI(url).host?.lowercase()
        } catch (e: Exception) {
            null
        } ?: return false
        return host == "twitter.com" || host.endsWith(".twitter.com") ||
            host == "x.com" || host.endsWith(".x.com")
    }

    private fun videoInfoToMap(info: VideoInfo): Map<String, Any?> {
        return mapOf(
            "title" to info.title,
            "thumbnail" to info.thumbnail,
            "duration" to info.duration,
            // Top-level ext/url identify a photo post (image ext, direct
            // image URL) so an extractor can offer it as an image variant
            // when there are no video formats.
            "ext" to info.ext,
            "url" to info.url,
            "formats" to (info.formats ?: arrayListOf()).map { formatToMap(it) },
        )
    }

    private fun formatToMap(format: VideoFormat): Map<String, Any?> {
        return mapOf(
            "formatId" to format.formatId,
            "ext" to format.ext,
            "vcodec" to format.vcodec,
            "acodec" to format.acodec,
            "height" to format.height,
            "tbr" to format.tbr,
            "url" to format.url,
            "fileSize" to format.fileSize,
            "fileSizeApproximate" to format.fileSizeApproximate,
            "httpHeaders" to format.httpHeaders,
        )
    }
}
