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
        const val EXTRA_MODE = "mode" // "merge" (default) | "audio" | "playlist"
        const val EXTRA_URL = "url"
        const val EXTRA_FORMAT_SELECTOR = "formatSelector"
        const val EXTRA_AUDIO_FORMAT = "audioFormat" // "mp3" | "m4a"
        const val EXTRA_AUDIO_QUALITY = "audioQuality" // kbps; 0 = source bitrate
        const val EXTRA_OUTPUT_PATH = "outputPath"
        const val EXTRA_OUTPUT_DIR = "outputDir" // playlist mode: dir for all items
        const val EXTRA_PLAYLIST_ITEMS = "playlistItems" // yt-dlp --playlist-items spec; blank = all
        const val EXTRA_EXPECTED_COUNT = "expectedCount" // playlist mode: how many items will be downloaded
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

        val mode = intent?.getStringExtra(EXTRA_MODE) ?: "merge"
        val url = intent?.getStringExtra(EXTRA_URL)
        val processId = intent?.getStringExtra(EXTRA_PROCESS_ID)
        val durationSeconds = intent?.getIntExtra(EXTRA_DURATION_SECONDS, 0) ?: 0
        if (url == null || processId == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        ensureChannel()

        if (mode == "playlist") {
            val outputDir = intent.getStringExtra(EXTRA_OUTPUT_DIR)
            val playlistItems = intent.getStringExtra(EXTRA_PLAYLIST_ITEMS)
            val playlistFormat = intent.getStringExtra(EXTRA_FORMAT_SELECTOR)
            val playlistAudioFormat = intent.getStringExtra(EXTRA_AUDIO_FORMAT)
            val playlistAudioQuality = intent.getIntExtra(EXTRA_AUDIO_QUALITY, 0)
            val expectedCount = intent.getIntExtra(EXTRA_EXPECTED_COUNT, 0)
            if (outputDir == null || (playlistFormat == null && playlistAudioFormat == null)) {
                stopSelf()
                return START_NOT_STICKY
            }
            startForeground(NOTIFICATION_ID, buildNotification(processId, progress = 0, phase = "playlist"))
            runPlaylistDownload(
                url,
                playlistFormat,
                playlistAudioFormat,
                playlistAudioQuality,
                playlistItems,
                expectedCount,
                outputDir,
                processId,
            )
            return START_NOT_STICKY
        }

        val outputPath = intent.getStringExtra(EXTRA_OUTPUT_PATH)
        if (outputPath == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        if (mode == "audio") {
            val audioFormat = intent.getStringExtra(EXTRA_AUDIO_FORMAT)
            val audioQuality = intent.getIntExtra(EXTRA_AUDIO_QUALITY, 0)
            if (audioFormat == null) {
                stopSelf()
                return START_NOT_STICKY
            }
            startForeground(NOTIFICATION_ID, buildNotification(processId, progress = 0, phase = "audio"))
            runAudioDownload(url, audioFormat, audioQuality, outputPath, processId, durationSeconds)
            return START_NOT_STICKY
        }

        val formatSelector = intent.getStringExtra(EXTRA_FORMAT_SELECTOR)
        if (formatSelector == null) {
            stopSelf()
            return START_NOT_STICKY
        }
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

    private fun runAudioDownload(
        url: String,
        audioFormat: String,
        audioQuality: Int,
        outputPath: String,
        processId: String,
        durationSeconds: Int,
    ) {
        executor.execute {
            try {
                YtDlpCore.ensureInitialized(applicationContext)
                // yt-dlp replaces %(ext)s with the post-processed audio ext,
                // so name the output with the base only.
                val base = outputPath.substringBeforeLast('.', outputPath)
                val request = YoutubeDLRequest(url)
                request.addOption(
                    "-f",
                    if (audioFormat == "m4a") "ba[ext=m4a]/ba/b" else "ba/b",
                )
                request.addOption("-x")
                request.addOption("--audio-format", audioFormat)
                if (audioQuality > 0) {
                    request.addOption("--audio-quality", "${audioQuality}K")
                }
                request.addOption("-o", "$base.%(ext)s")

                var finalPath: String? = null
                var phase = "audio"
                val extractDestRegex = Regex("\\[ExtractAudio\\]\\s*Destination:\\s*(.+)$")
                val mergeTimeRegex = Regex("time=(\\d+):(\\d{2}):(\\d{2}\\.\\d+)")

                YoutubeDL.getInstance().execute(request, processId) { progress, _, line ->
                    if (line.contains("[ExtractAudio]")) phase = "converting"
                    extractDestRegex.find(line)?.groupValues?.get(1)?.trim()?.let {
                        finalPath = it
                    }
                    val combined = if (phase == "converting") {
                        val elapsed = mergeTimeRegex.find(line)?.let { m ->
                            val (h, min, s) = m.destructured
                            h.toDouble() * 3600 + min.toDouble() * 60 + s.toDouble()
                        }
                        if (elapsed != null && durationSeconds > 0) {
                            (96.0 + (elapsed / durationSeconds) * 3.0).coerceIn(96.0, 99.0)
                        } else {
                            97.0
                        }
                    } else {
                        (progress * 0.95).coerceIn(0.0, 95.0)
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
                    mapOf(
                        "processId" to processId,
                        "status" to "complete",
                        "path" to (finalPath ?: "$base.$audioFormat"),
                    ),
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

    /**
     * Downloads a whole YouTube playlist (or a `--playlist-items` subset) in
     * one yt-dlp `execute()` — it iterates the entries itself. Each finished
     * file's final path is emitted to Dart via `onPlaylistItem` (parsed from
     * a `--print after_move:` line) so Dart can save it to MediaStore and
     * delete the temp copy as it goes, rather than holding a multi-GB
     * playlist on disk until the end. Overall progress is item N of M.
     */
    private fun runPlaylistDownload(
        url: String,
        formatSelector: String?,
        audioFormat: String?,
        audioQuality: Int,
        playlistItems: String?,
        expectedCount: Int,
        outputDir: String,
        processId: String,
    ) {
        executor.execute {
            try {
                YtDlpCore.ensureInitialized(applicationContext)
                val request = YoutubeDLRequest(url)
                if (audioFormat != null) {
                    request.addOption(
                        "-f",
                        if (audioFormat == "m4a") "ba[ext=m4a]/ba/b" else "ba/b",
                    )
                    request.addOption("-x")
                    request.addOption("--audio-format", audioFormat)
                    if (audioQuality > 0) {
                        request.addOption("--audio-quality", "${audioQuality}K")
                    }
                } else {
                    request.addOption("-f", formatSelector!!)
                    request.addOption("--merge-output-format", "mp4")
                }
                request.addOption(
                    "-o",
                    "$outputDir/%(playlist_index)03d - %(title).150B.%(ext)s",
                )
                request.addOption("--yes-playlist")
                // Skip private/removed entries instead of aborting the batch.
                request.addOption("--ignore-errors")
                if (!playlistItems.isNullOrBlank()) {
                    request.addOption("--playlist-items", playlistItems)
                }
                // Progress/phase is driven entirely by `--print` marker lines,
                // NOT by parsing yt-dlp's normal stdout: youtubedl-android's
                // execute() callback only reliably surfaces `--print` output
                // for a playlist run (the raw `[download] N%` / `[Merger]`
                // lines don't come through), so anything not printed by us is
                // invisible here.
                //  - video:      fires once per entry, after extraction
                //  - before_dl:  fires before each stream download (video, then
                //                audio for a merge; the source for audio-only)
                //  - post_process: fires around merge / audio-extract
                //  - after_move: fires once the final file is in place
                request.addOption("--no-simulate")
                // `--print` implies `--quiet`, which kills the progress bar —
                // `--progress` forces it back on, `--newline` puts each
                // update on its own line so youtubedl-android parses a real
                // percent for the `progress` callback arg.
                request.addOption("--progress")
                request.addOption("--newline")
                request.addOption(
                    "--print",
                    "video:@@AWD_START@@\t%(playlist_index)s\t%(playlist_count)s",
                )
                request.addOption("--print", "before_dl:@@AWD_DL@@")
                request.addOption("--print", "post_process:@@AWD_PP@@")
                request.addOption(
                    "--print",
                    "after_move:@@AWD_ITEM@@\t%(playlist_count)s\t%(filepath)s",
                )

                // How many entries have fully finished. Drives the "N of M"
                // counter directly (an `@@AWD_ITEM@@` line = one done).
                var completed = 0
                // Prefer the caller's expected count (a `--playlist-items`
                // subset can be far smaller than yt-dlp's `playlist_count`).
                var total = if (expectedCount > 0) expectedCount else 0
                val isAudioMode = audioFormat != null
                var itemDlCount = 0
                var subPhase = if (isAudioMode) "audio" else "video"
                val startRegex = Regex("^@@AWD_START@@\t(\\d*)\t(\\d*)$")
                val doneRegex = Regex("^@@AWD_ITEM@@\t(\\d*)\t(.+)$")

                fun emitProgress(itemProgress: Double) {
                    val workingIndex =
                        if (total > 0) (completed + 1).coerceAtMost(total)
                        else completed + 1
                    val combined = if (total > 0) {
                        ((completed + itemProgress / 100.0) / total * 100.0)
                            .coerceIn(0.0, 99.0)
                    } else {
                        0.0
                    }
                    updateNotification(processId, combined.toInt(), "playlist", false)
                    NativeToDartChannel.invoke(
                        "onDownloadProgress",
                        mapOf(
                            "processId" to processId,
                            "progress" to combined,
                            "phase" to "playlist",
                            "subPhase" to subPhase,
                            "itemIndex" to workingIndex,
                            "itemProgress" to itemProgress,
                        ),
                    )
                }

                YoutubeDL.getInstance().execute(request, processId) { progress, _, line ->
                    val trimmed = line.trim()

                    doneRegex.find(trimmed)?.let { m ->
                        completed++
                        itemDlCount = 0
                        subPhase = if (isAudioMode) "audio" else "video"
                        m.groupValues[1].toIntOrNull()?.let { c ->
                            if (expectedCount <= 0 && c > 0) total = c
                        }
                        NativeToDartChannel.invoke(
                            "onPlaylistItem",
                            mapOf(
                                "processId" to processId,
                                "index" to completed,
                                "count" to total,
                                "path" to m.groupValues[2].trim(),
                            ),
                        )
                        emitProgress(0.0)
                        return@execute
                    }

                    startRegex.find(trimmed)?.let { m ->
                        if (expectedCount <= 0) {
                            m.groupValues[2].toIntOrNull()?.let { if (it > 0) total = it }
                        }
                        itemDlCount = 0
                        subPhase = if (isAudioMode) "audio" else "video"
                        emitProgress(0.0)
                        return@execute
                    }

                    if (trimmed == "@@AWD_DL@@") {
                        itemDlCount++
                        if (!isAudioMode) {
                            subPhase = if (itemDlCount >= 2) "audio" else "video"
                        }
                        emitProgress(0.0)
                        return@execute
                    }

                    if (trimmed == "@@AWD_PP@@") {
                        subPhase = if (isAudioMode) "converting" else "merging"
                        emitProgress(0.0)
                        return@execute
                    }

                    // Fine-grained percent for the current entry. With
                    // `--progress --newline` youtubedl-android parses a real
                    // value into `progress` on every `[download] N%` line;
                    // it's 0/-1 on non-download lines, so gate on > 0.
                    if (progress > 0f && progress <= 100f) {
                        emitProgress(progress.toDouble())
                    }
                }
                NativeToDartChannel.invoke(
                    "onDownloadStatus",
                    mapOf("processId" to processId, "status" to "complete"),
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
        val indeterminate = (phase == "merging" || phase == "converting") && !knownDuration
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
        "converting" -> "Converting audio"
        "playlist" -> "Downloading playlist"
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
