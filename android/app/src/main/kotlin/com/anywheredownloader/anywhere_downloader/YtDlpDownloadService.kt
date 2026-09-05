package com.anywheredownloader.anywhere_downloader

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import java.util.concurrent.Executors

/**
 * Runs a merge download (adaptive video-only + audio-only, muxed via
 * yt-dlp's own `execute()`) as a real Android foreground service, so it
 * survives the screen turning off the same way the `background_downloader`
 * path does for muxed/progressive formats — `execute()` itself has no such
 * protection on its own, running it as a plain background thread in the
 * app process would silently reintroduce the screen-sleep failure that
 * `background_downloader` was adopted to fix for the other path.
 *
 * Reports progress/completion back to Dart via [NativeToDartChannel]
 * (`onDownloadProgress` / `onDownloadStatus`) rather than a single
 * MethodChannel result, since the call that starts this service returns
 * immediately — the whole point is surviving beyond that call's lifetime.
 */
class YtDlpDownloadService : Service() {
    companion object {
        const val EXTRA_URL = "url"
        const val EXTRA_FORMAT_SELECTOR = "formatSelector"
        const val EXTRA_OUTPUT_PATH = "outputPath"
        const val EXTRA_PROCESS_ID = "processId"
        const val EXTRA_DURATION_SECONDS = "durationSeconds"
        const val ACTION_CANCEL = "com.anywheredownloader.anywhere_downloader.ACTION_CANCEL"

        private const val CHANNEL_ID = "yt_dlp_downloads"
        private const val NOTIFICATION_ID = 1001
    }

    private val executor = Executors.newSingleThreadExecutor()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_CANCEL) {
            intent.getStringExtra(EXTRA_PROCESS_ID)?.let {
                YoutubeDL.getInstance().destroyProcessById(it)
            }
            return START_NOT_STICKY
        }

        val url = intent?.getStringExtra(EXTRA_URL)
        val formatSelector = intent?.getStringExtra(EXTRA_FORMAT_SELECTOR)
        val outputPath = intent?.getStringExtra(EXTRA_OUTPUT_PATH)
        val processId = intent?.getStringExtra(EXTRA_PROCESS_ID)
        val durationSeconds = intent?.getIntExtra(EXTRA_DURATION_SECONDS, 0) ?: 0
        if (url == null || formatSelector == null || outputPath == null || processId == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        ensureChannel()
        startForeground(NOTIFICATION_ID, buildNotification(processId, progress = 0, phase = "video"))
        runDownload(url, formatSelector, outputPath, processId, durationSeconds)
        return START_NOT_STICKY
    }

    private fun runDownload(
        url: String,
        formatSelector: String,
        outputPath: String,
        processId: String,
        durationSeconds: Int,
    ) {
        executor.execute {
            try {
                YtDlpCore.ensureInitialized(applicationContext)
                val request = YoutubeDLRequest(url)
                request.addOption("-f", formatSelector)
                request.addOption("--merge-output-format", "mp4")
                request.addOption("-o", outputPath)

                // A merge download is really 2 sub-downloads (video, then
                // audio) plus a final mux — yt-dlp reports 0-100% progress
                // separately for each, which looks like two separate bars
                // to the user. Detect the "Destination:" line yt-dlp prints
                // at the start of each sub-download to tell them apart, and
                // report one continuous combined progress + a phase label
                // instead.
                val seenDestinations = mutableSetOf<String>()
                var currentPart = 0
                val destinationRegex = Regex("Destination:\\s*(.+)$")
                val mergingRegex = Regex("\\[Merger\\]|Merging formats")
                // ffmpeg's own encode/remux progress line, e.g.
                // "frame=  123 fps=45 ... time=00:01:23.45 bitrate=...". Only
                // printed once the actual mux (not the two downloads) is
                // running, so it doubles as a way to compute real 0-99%
                // progress for the "merging" phase instead of a flat/
                // indeterminate value — that phase can take a while for a
                // large, high-resolution file and previously just showed a
                // stalled-looking running stripe.
                val mergeTimeRegex = Regex("time=(\\d+):(\\d{2}):(\\d{2}\\.\\d+)")
                val totalParts = 2.0

                YoutubeDL.getInstance().execute(request, processId) { progress, _, line ->
                    destinationRegex.find(line)?.groupValues?.get(1)?.trim()?.let { dest ->
                        if (seenDestinations.add(dest)) {
                            currentPart = seenDestinations.size - 1
                        }
                    }
                    val merging = mergingRegex.containsMatchIn(line)
                    val phase = when {
                        merging -> "merging"
                        currentPart <= 0 -> "video"
                        else -> "audio"
                    }
                    val combined = if (phase == "merging") {
                        val elapsed = mergeTimeRegex.find(line)?.let { m ->
                            val (h, min, s) = m.destructured
                            h.toDouble() * 3600 + min.toDouble() * 60 + s.toDouble()
                        }
                        if (elapsed != null && durationSeconds > 0) {
                            ((elapsed / durationSeconds) * 100.0).coerceIn(0.0, 99.0)
                        } else {
                            99.0
                        }
                    } else {
                        (((currentPart + (progress / 100.0)) / totalParts) * 100.0)
                            .coerceIn(0.0, 99.0)
                    }
                    updateNotification(processId, combined.toInt(), phase, durationSeconds > 0)
                    NativeToDartChannel.invoke(
                        "onDownloadProgress",
                        mapOf(
                            "processId" to processId,
                            "progress" to combined,
                            "phase" to phase,
                        ),
                    )
                }
                NativeToDartChannel.invoke(
                    "onDownloadStatus",
                    mapOf("processId" to processId, "status" to "complete", "path" to outputPath),
                )
            } catch (e: YoutubeDL.CanceledException) {
                NativeToDartChannel.invoke(
                    "onDownloadStatus",
                    mapOf("processId" to processId, "status" to "canceled"),
                )
            } catch (e: Exception) {
                NativeToDartChannel.invoke(
                    "onDownloadStatus",
                    mapOf("processId" to processId, "status" to "error", "error" to e.message),
                )
            } finally {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Downloads", NotificationManager.IMPORTANCE_LOW)
            )
        }
    }

    private fun buildNotification(
        processId: String,
        progress: Int,
        phase: String,
        knownDuration: Boolean = false,
    ): Notification {
        val cancelIntent = Intent(this, YtDlpDownloadService::class.java).apply {
            action = ACTION_CANCEL
            putExtra(EXTRA_PROCESS_ID, processId)
        }
        val cancelPendingIntent = PendingIntent.getService(
            this,
            0,
            cancelIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        // Only shown as an indeterminate spinner when we truly have no way
        // to compute a real percentage (duration unknown) — otherwise the
        // merge phase now gets real progress from ffmpeg's own "time=" line.
        val indeterminate = phase == "merging" && !knownDuration
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(phaseLabel(phase))
            .setContentText(if (indeterminate) "" else "$progress%")
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setProgress(100, progress, indeterminate)
            .setOngoing(true)
            .addAction(0, "Cancel", cancelPendingIntent)
            .build()
    }

    private fun phaseLabel(phase: String): String = when (phase) {
        "video" -> "Downloading video"
        "audio" -> "Downloading audio"
        "merging" -> "Merging video and audio"
        else -> "Downloading"
    }

    private fun updateNotification(
        processId: String,
        progress: Int,
        phase: String,
        knownDuration: Boolean,
    ) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification(processId, progress, phase, knownDuration))
    }
}
