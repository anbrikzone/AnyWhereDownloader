package com.anywheredownloader.anywhere_downloader

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import java.io.File
import java.util.Collections
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.atomic.AtomicInteger

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
 *
 * Saving the finished file into MediaStore and posting the "download
 * complete" notification also happen here, not in Dart: the Flutter UI can
 * die mid-download (app swiped from Recents, activity recreated) while this
 * service keeps running, and a save step living in Dart would then never
 * run — the file would sit in cacheDir, lost. Dart only mirrors the outcome
 * into its UI state when it's still around to hear it.
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
        // MediaStore `RELATIVE_PATH` to save into, e.g.
        // `Movies/AnyWhereDownloader/YouTube` (root already resolved by Dart
        // from Settings at start time).
        const val EXTRA_RELATIVE_PATH = "relativePath"
        // Bundle of localized notification strings from Dart
        // (`YtDlpEngine._notificationLabels`): phase names, "cancel",
        // "tapToOpen", channel names. English fallbacks below.
        const val EXTRA_LABELS = "labels"
        const val EXTRA_SUMMARY_TITLE = "summaryTitle" // playlist summary
        const val EXTRA_SUMMARY_TEXT = "summaryText" // template: {saved}, {total}
        const val ACTION_CANCEL = "com.anywheredownloader.anywhere_downloader.ACTION_CANCEL"

        private const val CHANNEL_ID = "yt_dlp_downloads"
        private const val NOTIFICATION_ID = 1001
        private const val TAG = "YtDlpDownloadService"
    }

    private val executor = Executors.newSingleThreadExecutor()

    // Playlist items are saved off the yt-dlp output callback thread so a
    // large file copy never stalls reading the subprocess's stdout.
    private val saveExecutor = Executors.newSingleThreadExecutor()

    private class SaveSpec(
        val relativePath: String,
        val summaryTitle: String,
        val summaryText: String,
    )

    // Strings of the download currently running (one at a time).
    private var labels = Bundle()

    private fun label(key: String, fallback: String) = labels.getString(key) ?: fallback

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
        val relativePath = intent?.getStringExtra(EXTRA_RELATIVE_PATH)
        if (url == null || processId == null || relativePath == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        labels = intent.getBundleExtra(EXTRA_LABELS) ?: Bundle()
        val save = SaveSpec(
            relativePath = relativePath,
            summaryTitle = intent.getStringExtra(EXTRA_SUMMARY_TITLE) ?: "YouTube",
            summaryText = intent.getStringExtra(EXTRA_SUMMARY_TEXT) ?: "Saved {saved} of {total}",
        )

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
                save,
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
            runAudioDownload(url, audioFormat, audioQuality, outputPath, processId, durationSeconds, save)
            return START_NOT_STICKY
        }

        val formatSelector = intent.getStringExtra(EXTRA_FORMAT_SELECTOR)
        if (formatSelector == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        startForeground(NOTIFICATION_ID, buildNotification(processId, progress = 0, phase = "video"))
        runDownload(url, formatSelector, outputPath, processId, durationSeconds, save)
        return START_NOT_STICKY
    }

    private fun runDownload(
        url: String,
        formatSelector: String,
        outputPath: String,
        processId: String,
        durationSeconds: Int,
        save: SaveSpec,
    ) {
        executor.execute {
            try {
                YtDlpCore.ensureInitialized(applicationContext)
                val request = YoutubeDLRequest(url)
                YtDlpOptions.applyYouTube(request, url)
                request.addOption("-f", formatSelector)
                request.addOption("--merge-output-format", "mp4")
                applyMergeSyncOptions(request)
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
                val contentUri = saveFinishedFile(
                    outputPath,
                    MediaStoreWriter.Kind.VIDEO,
                    "video/mp4",
                    save,
                )
                NativeToDartChannel.invoke(
                    "onDownloadStatus",
                    mapOf(
                        "processId" to processId,
                        "status" to "complete",
                        "path" to outputPath,
                        "contentUri" to contentUri,
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
                cleanupWorkDir(File(outputPath).parentFile)
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
        save: SaveSpec,
    ) {
        executor.execute {
            try {
                YtDlpCore.ensureInitialized(applicationContext)
                // yt-dlp replaces %(ext)s with the post-processed audio ext,
                // so name the output with the base only.
                val base = outputPath.substringBeforeLast('.', outputPath)
                val request = YoutubeDLRequest(url)
                YtDlpOptions.applyYouTube(request, url)
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
                val audioPath = finalPath ?: "$base.$audioFormat"
                val contentUri = saveFinishedFile(
                    audioPath,
                    MediaStoreWriter.Kind.AUDIO,
                    if (audioFormat == "mp3") "audio/mpeg" else "audio/mp4",
                    save,
                )
                NativeToDartChannel.invoke(
                    "onDownloadStatus",
                    mapOf(
                        "processId" to processId,
                        "status" to "complete",
                        "path" to audioPath,
                        "contentUri" to contentUri,
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
                cleanupWorkDir(File(outputPath).parentFile)
                stopSelf()
            }
        }
    }

    /**
     * Downloads a whole YouTube playlist (or a `--playlist-items` subset) in
     * one yt-dlp `execute()` — it iterates the entries itself. Each finished
     * file (announced by a `--print after_move:` line) is saved to
     * MediaStore right here, off the callback thread, and its temp copy
     * deleted as it goes, rather than holding a multi-GB playlist on disk
     * until the end; Dart hears the per-item outcome via `onPlaylistItem`.
     * Overall progress is item N of M.
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
        save: SaveSpec,
    ) {
        executor.execute {
            // Filled from yt-dlp's output-callback thread, drained here.
            val pendingSaves = Collections.synchronizedList(mutableListOf<Future<*>>())
            val savedCount = AtomicInteger(0)
            var completed = 0
            val status: Map<String, Any?> = try {
                YtDlpCore.ensureInitialized(applicationContext)
                val request = YoutubeDLRequest(url)
                YtDlpOptions.applyYouTube(request, url)
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
                    applyMergeSyncOptions(request)
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
                // The "N of M" counter and the entry-start/entry-done signals
                // come from `--print` marker lines (the one channel that
                // reliably reaches youtubedl-android's execute() callback for
                // a playlist run):
                //  - video:       once per entry, after extraction  (start)
                //  - post_process: around merge / audio-extract
                //  - after_move:  once the final file is in place   (done)
                // The video→audio stream switch and the fine-grained percent
                // come from the raw `[download] …` lines, which DO come
                // through once `--progress` is forced on (see below).
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
                request.addOption("--print", "post_process:@@AWD_PP@@")
                request.addOption(
                    "--print",
                    "after_move:@@AWD_ITEM@@\t%(playlist_count)s\t%(filepath)s",
                )

                // `completed` (declared above the try, so the summary can
                // read it after a cancel/error too) counts entries that have
                // fully finished. Drives the "N of M" counter directly (an
                // `@@AWD_ITEM@@` line = one done).
                // Prefer the caller's expected count (a `--playlist-items`
                // subset can be far smaller than yt-dlp's `playlist_count`).
                var total = if (expectedCount > 0) expectedCount else 0
                val isAudioMode = audioFormat != null
                // Which stream of the current entry we're on: 1 = video,
                // 2 = audio (video mode). Bumped by a `[download] Destination:`
                // line when we get one, and — since youtubedl-android's
                // callback often only surfaces `[download] N%` lines, not the
                // `Destination:` line — also inferred from the percent
                // dropping back near 0 (a fresh stream starting).
                var streamCount = 0
                var lastItemProgress = 0f
                var subPhase = if (isAudioMode) "audio" else "video"
                val startRegex = Regex("^@@AWD_START@@\t(\\d*)\t(\\d*)$")
                val doneRegex = Regex("^@@AWD_ITEM@@\t(\\d*)\t(.+)$")
                val dlDestRegex = Regex("^\\[download] Destination:")
                val mergerRegex = Regex("\\[Merger]|Merging formats into")
                val extractRegex = Regex("^\\[ExtractAudio]")

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
                        streamCount = 0
                        lastItemProgress = 0f
                        subPhase = if (isAudioMode) "audio" else "video"
                        m.groupValues[1].toIntOrNull()?.let { c ->
                            if (expectedCount <= 0 && c > 0) total = c
                        }
                        val itemPath = m.groupValues[2].trim()
                        val itemIndex = completed
                        val itemCount = total
                        pendingSaves.add(
                            saveExecutor.submit(Runnable {
                                savePlaylistItem(
                                    itemPath,
                                    itemIndex,
                                    itemCount,
                                    isAudioMode,
                                    audioFormat,
                                    processId,
                                    save,
                                    savedCount,
                                )
                            }),
                        )
                        emitProgress(0.0)
                        return@execute
                    }

                    startRegex.find(trimmed)?.let { m ->
                        if (expectedCount <= 0) {
                            m.groupValues[2].toIntOrNull()?.let { if (it > 0) total = it }
                        }
                        streamCount = 0
                        lastItemProgress = 0f
                        subPhase = if (isAudioMode) "audio" else "video"
                        emitProgress(0.0)
                        return@execute
                    }

                    if (trimmed == "@@AWD_PP@@" || mergerRegex.containsMatchIn(trimmed)) {
                        subPhase = if (isAudioMode) "converting" else "merging"
                        emitProgress(0.0)
                        return@execute
                    }

                    if (extractRegex.containsMatchIn(trimmed)) {
                        subPhase = "converting"
                        emitProgress(0.0)
                        return@execute
                    }

                    if (dlDestRegex.containsMatchIn(trimmed)) {
                        streamCount++
                        if (!isAudioMode) {
                            subPhase = if (streamCount >= 2) "audio" else "video"
                        }
                        lastItemProgress = 0f
                        emitProgress(0.0)
                        return@execute
                    }

                    // Fine-grained percent for the current entry. With
                    // `--progress --newline` youtubedl-android parses a real
                    // value into `progress` on every `[download] N%` line;
                    // it's 0/-1 on non-download lines, so gate on > 0.
                    if (progress > 0f && progress <= 100f) {
                        // A big drop back toward 0 while still in the same
                        // entry = a new stream started (the `Destination:`
                        // line for it didn't reach us). In video mode the 2nd
                        // stream is the audio track.
                        if (!isAudioMode &&
                            streamCount < 2 &&
                            progress < 12f &&
                            lastItemProgress > 45f
                        ) {
                            streamCount = 2
                            subPhase = "audio"
                        }
                        lastItemProgress = progress
                        emitProgress(progress.toDouble())
                    }
                }
                mapOf("processId" to processId, "status" to "complete")
            } catch (e: YoutubeDL.CanceledException) {
                mapOf("processId" to processId, "status" to "canceled")
            } catch (e: Exception) {
                mapOf("processId" to processId, "status" to "error", "error" to e.message)
            }
            try {
                // Entries that finished before a cancel/error are still
                // saved — wait for every queued save before reporting.
                for (pending in synchronized(pendingSaves) { pendingSaves.toList() }) {
                    runCatching { pending.get() }
                }
                val total = if (expectedCount > 0) expectedCount else completed
                DownloadNotifications.showDownloadComplete(
                    applicationContext,
                    save.summaryTitle,
                    save.summaryText
                        .replace("{saved}", savedCount.get().toString())
                        .replace("{total}", total.toString()),
                    null,
                    null,
                    label("channelComplete", "Downloads complete"),
                )
                NativeToDartChannel.invoke("onDownloadStatus", status)
            } finally {
                stopForeground(STOP_FOREGROUND_REMOVE)
                cleanupWorkDir(File(outputDir))
                stopSelf()
            }
        }
    }

    /**
     * Saves one finished single-file download into MediaStore, posts its
     * tap-to-open notification and returns the new `content://` URI. A save
     * failure is reported as the download's error (the caller's generic
     * `catch`) — the file itself is removed with the work dir either way.
     */
    private fun saveFinishedFile(
        path: String,
        kind: MediaStoreWriter.Kind,
        mimeType: String,
        save: SaveSpec,
    ): String {
        val fileName = File(path).name
        val contentUri = try {
            MediaStoreWriter.save(
                applicationContext,
                path,
                kind,
                save.relativePath,
                MediaStoreWriter.safeDisplayName(fileName, fallbackExtFor(kind)),
                mimeType,
            )
        } catch (e: Exception) {
            Log.e(TAG, "saving $path to ${save.relativePath} failed", e)
            throw IllegalStateException(
                "The file was downloaded but could not be saved: ${e.message}",
                e,
            )
        }
        DownloadNotifications.showDownloadComplete(
            applicationContext,
            fileName,
            label("tapToOpen", "Tap to open"),
            contentUri,
            if (kind == MediaStoreWriter.Kind.AUDIO) "audio/*" else "video/*",
            label("channelComplete", "Downloads complete"),
        )
        return contentUri
    }

    /** Runs on [saveExecutor]; never throws. */
    private fun savePlaylistItem(
        path: String,
        index: Int,
        count: Int,
        isAudioMode: Boolean,
        audioFormat: String?,
        processId: String,
        save: SaveSpec,
        savedCount: AtomicInteger,
    ) {
        val kind = if (isAudioMode) MediaStoreWriter.Kind.AUDIO else MediaStoreWriter.Kind.VIDEO
        val mimeType = when {
            !isAudioMode -> "video/mp4"
            audioFormat == "mp3" -> "audio/mpeg"
            else -> "audio/mp4"
        }
        var contentUri: String? = null
        var error: String? = null
        try {
            contentUri = MediaStoreWriter.save(
                applicationContext,
                path,
                kind,
                save.relativePath,
                MediaStoreWriter.safeDisplayName(File(path).name, fallbackExtFor(kind)),
                mimeType,
            )
            savedCount.incrementAndGet()
        } catch (e: Exception) {
            Log.e(TAG, "saving playlist item $path failed", e)
            error = e.message ?: e.toString()
        } finally {
            File(path).delete()
        }
        NativeToDartChannel.invoke(
            "onPlaylistItem",
            mapOf(
                "processId" to processId,
                "index" to index,
                "count" to count,
                "path" to path,
                "saved" to (contentUri != null),
                "contentUri" to contentUri,
                "error" to error,
            ),
        )
    }

    private fun fallbackExtFor(kind: MediaStoreWriter.Kind) =
        if (kind == MediaStoreWriter.Kind.AUDIO) "mp3" else "mp4"

    /**
     * Deletes a per-download work directory (`ytdlp_<id>` / `playlist_<id>`
     * directly under cacheDir) — including yt-dlp's `.part`/`.fNNN` leftovers
     * after a cancel or error. Anything else is left alone, deliberately.
     */
    private fun cleanupWorkDir(dir: File?) {
        if (dir == null) return
        try {
            val target = dir.canonicalFile
            if (target.parentFile != cacheDir.canonicalFile) return
            if (!target.name.startsWith("ytdlp_") && !target.name.startsWith("playlist_")) return
            target.deleteRecursively()
        } catch (e: Exception) {
            Log.w(TAG, "cleanupWorkDir($dir) failed", e)
        }
    }

    /**
     * A/V-sync hardening for every video merge (single video + playlist).
     *
     * `-avoid_negative_ts make_zero` + zeroed `-muxpreload`/`-muxdelay` make
     * the MP4 muxer start both streams at PTS 0 instead of recording the
     * audio's small start offset as an edit-list (`elst`) entry. Players that
     * honour the edit list (ExoPlayer) were fine either way; players that
     * ignore it (Google Photos, many Android system players) were showing a
     * constant audio offset for the whole clip — this removes the edit list
     * so there is nothing for them to ignore. Still a pure `-c copy` merge:
     * no re-encode, no quality loss.
     *
     * `--fragment-retries` + `--abort-on-unavailable-fragments` make a
     * dropped video fragment fail the download instead of silently yielding
     * a file whose audio drifts from that point on.
     */
    private fun applyMergeSyncOptions(request: YoutubeDLRequest) {
        request.addOption(
            "--postprocessor-args",
            "Merger+ffmpeg_o:-avoid_negative_ts make_zero -muxpreload 0 -muxdelay 0",
        )
        request.addOption("--fragment-retries", "10")
        request.addOption("--abort-on-unavailable-fragments")
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    label("channelProgress", "Downloads"),
                    NotificationManager.IMPORTANCE_LOW,
                )
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
            .addAction(0, label("cancel", "Cancel"), cancelPendingIntent)
            .build()
    }

    private fun phaseLabel(phase: String): String = when (phase) {
        "video" -> label("video", "Downloading video")
        "audio" -> label("audio", "Downloading audio")
        "merging" -> label("merging", "Merging video and audio")
        "converting" -> label("converting", "Converting audio")
        "playlist" -> label("playlist", "Downloading playlist")
        else -> label("downloading", "Downloading")
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
