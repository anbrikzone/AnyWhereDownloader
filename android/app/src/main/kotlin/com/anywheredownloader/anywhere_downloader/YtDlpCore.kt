package com.anywheredownloader.anywhere_downloader

import android.content.Context
import android.util.Log
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import java.util.concurrent.atomic.AtomicReference

/**
 * Shared yt-dlp/ffmpeg initialization, used by both [YtDlpBridge] (getInfo)
 * and [YtDlpDownloadService] (merge / audio / playlist downloads) so init
 * happens exactly once regardless of which entry point runs first.
 *
 * Also owns the **bundled-yt-dlp self-update**. The binary shipped inside
 * `youtubedl-android` is only as fresh as that library's last release, and
 * YouTube breaks older yt-dlp clients regularly (e.g. the "SABR streaming"
 * rollout → `HTTP Error 403: Forbidden`). yt-dlp ships fixes for that far
 * more often than the app can. [ensureInitialized] pulls the latest yt-dlp
 * script (not the Python/ffmpeg runtime, not the library) from yt-dlp's
 * own GitHub releases.
 *
 * History: the first version of this ran the update once, inside the
 * synchronized init, swallowed every failure with a bare `catch`, and
 * latched an `initialized` flag whether or not the update actually
 * succeeded — so a device that had no network on its first cold-start
 * extraction never retried and silently stayed months stale (real
 * OnePlus 15 report, yt-dlp stuck at 2025.11.12). This version: retries on
 * later calls after a failure (with a short cooldown), bounds how long it
 * blocks an extraction, records the last outcome for Settings → About, and
 * exposes a forced update for the manual button there.
 */
object YtDlpCore {
    private const val TAG = "YtDlpCore"

    /** How long [ensureInitialized] will block an extraction waiting for an
     *  update before letting it proceed on the current binary (the update
     *  keeps running in the background if it hasn't finished). */
    private const val INLINE_UPDATE_TIMEOUT_MS = 15_000L

    /** Longer budget for the user-triggered Settings button — they asked
     *  for it and are watching a spinner. */
    private const val FORCED_UPDATE_TIMEOUT_MS = 120_000L

    /** After a failed attempt, don't hammer GitHub on every extraction. */
    private const val RETRY_COOLDOWN_MS = 60_000L

    @Volatile private var initialized = false
    @Volatile private var updateSucceededThisProcess = false

    private val updateLock = Any()

    /** Outcome of the most recent self-update attempt in this process. */
    data class UpdateOutcome(
        /** `done` | `upToDate` | `failed` | `never`. */
        val status: String,
        /** yt-dlp version string observed after the attempt, if readable. */
        val version: String?,
        val error: String?,
        val timestampMs: Long,
    )

    @Volatile
    var lastUpdate: UpdateOutcome = UpdateOutcome("never", null, null, 0L)
        private set

    @Synchronized
    private fun ensureInitOnly(appContext: Context) {
        if (initialized) return
        YoutubeDL.getInstance().init(appContext)
        FFmpeg.getInstance().init(appContext)
        initialized = true
    }

    /**
     * Blocking init for an extraction call. Runs the fast native init once,
     * then a best-effort, time-bounded self-update (skipped once one has
     * succeeded this process, rate-limited after a failure).
     */
    fun ensureInitialized(appContext: Context) {
        ensureInitOnly(appContext)
        synchronized(updateLock) {
            if (updateSucceededThisProcess) return
            val sinceLast = System.currentTimeMillis() - lastUpdate.timestampMs
            if (lastUpdate.status == "failed" && sinceLast < RETRY_COOLDOWN_MS) return
            runUpdateLocked(appContext, INLINE_UPDATE_TIMEOUT_MS)
        }
    }

    /**
     * Fire-and-forget init + update on a background thread. Called at app
     * startup so the update is off the first extraction's critical path.
     */
    fun warmUp(appContext: Context) {
        Thread {
            try {
                ensureInitialized(appContext)
            } catch (e: Throwable) {
                Log.w(TAG, "yt-dlp warm-up failed", e)
            }
        }.apply {
            isDaemon = true
            name = "ytdlp-warmup"
        }.start()
    }

    /**
     * User-triggered forced update (Settings → About). Always attempts,
     * ignoring the per-process "already succeeded" short-circuit and the
     * failure cooldown. Returns the outcome for display.
     */
    fun forceUpdate(appContext: Context): UpdateOutcome {
        ensureInitOnly(appContext)
        synchronized(updateLock) {
            return runUpdateLocked(appContext, FORCED_UPDATE_TIMEOUT_MS)
        }
    }

    fun currentVersion(appContext: Context): String? = try {
        YoutubeDL.getInstance().version(appContext)
    } catch (e: Throwable) {
        Log.w(TAG, "reading yt-dlp version failed", e)
        null
    }

    /** Must be called holding [updateLock]. */
    private fun runUpdateLocked(appContext: Context, timeoutMs: Long): UpdateOutcome {
        val holder = AtomicReference<UpdateOutcome?>()
        val worker = Thread {
            val outcome = try {
                val status = YoutubeDL.getInstance()
                    .updateYoutubeDL(appContext, YoutubeDL.UpdateChannel.STABLE)
                val version = currentVersion(appContext)
                if (status == YoutubeDL.UpdateStatus.DONE) {
                    Log.i(TAG, "yt-dlp updated to ${version ?: "?"}")
                    UpdateOutcome("done", version, null, System.currentTimeMillis())
                } else {
                    Log.i(TAG, "yt-dlp already up to date (${version ?: "?"})")
                    UpdateOutcome("upToDate", version, null, System.currentTimeMillis())
                }
            } catch (e: Throwable) {
                Log.w(TAG, "yt-dlp self-update failed", e)
                UpdateOutcome(
                    "failed",
                    currentVersion(appContext),
                    e.message ?: e.javaClass.simpleName,
                    System.currentTimeMillis(),
                )
            }
            holder.set(outcome)
            synchronized(updateLock) {
                lastUpdate = outcome
                if (outcome.status == "done" || outcome.status == "upToDate") {
                    updateSucceededThisProcess = true
                }
            }
        }.apply {
            isDaemon = true
            name = "ytdlp-update"
        }
        worker.start()
        worker.join(timeoutMs)

        holder.get()?.let { return it }
        // Timed out — the worker is still running (daemon) and will record
        // its real result whenever it finishes; report a soft failure now
        // so the caller doesn't stall the extraction further.
        val soft = UpdateOutcome(
            "failed",
            currentVersion(appContext),
            "timed out after ${timeoutMs}ms (still running in the background)",
            System.currentTimeMillis(),
        )
        if (lastUpdate.status != "done" && lastUpdate.status != "upToDate") {
            lastUpdate = soft
        }
        return soft
    }
}
