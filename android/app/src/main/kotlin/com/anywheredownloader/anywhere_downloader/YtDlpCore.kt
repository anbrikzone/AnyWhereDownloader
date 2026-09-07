package com.anywheredownloader.anywhere_downloader

import android.content.Context
import android.util.Log
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import java.io.File
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

    /** APK-bundled yt-dlp (refreshed per release by
     *  `tool/refresh_bundled_ytdlp.sh`) — installed on first run when it
     *  beats what youtubedl-android unpacked, so a fresh install isn't
     *  stuck on the AAR's months-old binary until the self-update lands. */
    private const val BUNDLED_DIR = "ytdlp"

    /** youtubedl-android's own SharedPreferences file + version keys — the
     *  stable contract its updater reads/writes (`SharedPrefsHelper`,
     *  `YoutubeDLUpdater`). Written directly here rather than via that
     *  internal class so a library refactor can't break the pre-seed. */
    private const val YTDL_PREFS = "youtubedl-android"
    private const val DLP_VERSION_KEY = "dlpVersion"
    private const val DLP_VERSION_NAME_KEY = "dlpVersionName"

    /** Our own record, written next to the yt-dlp binary, of which bundled
     *  version we last installed there. The decision to (re)seed is made
     *  from this file, NOT youtubedl-android's `dlpVersion` pref: on some
     *  devices that library's updater reports success and bumps the pref
     *  without actually replacing the binary (real OnePlus 15 report —
     *  About showed 2026.08.19 while the running yt-dlp was still
     *  2025.11.12), which then made the old pref-trusting pre-seed skip. */
    private const val SEED_MARKER = ".awd_bundled_version"

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
        preSeedBundledYtDlp(appContext)
        YoutubeDL.getInstance().init(appContext)
        FFmpeg.getInstance().init(appContext)
        initialized = true
    }

    /** Reads our [SEED_MARKER] next to the on-disk yt-dlp binary. */
    private fun seededVersion(appContext: Context): String? = try {
        val marker = File(ytdlpDir(appContext), SEED_MARKER)
        if (marker.exists()) marker.readText().trim().ifEmpty { null } else null
    } catch (e: Throwable) {
        null
    }

    private fun ytdlpDir(appContext: Context) = File(
        appContext.noBackupFilesDir,
        "${YoutubeDL.baseName}/${YoutubeDL.ytdlpDirName}",
    )

    /**
     * Install the APK-bundled yt-dlp as the on-disk binary *before*
     * [YoutubeDL.init] runs (`init_ytdlp` only unpacks its own `R.raw.ytdlp`
     * when the target file is absent, so writing ours first makes it win).
     *
     * The "is the right binary already there?" question is answered from
     * our own [SEED_MARKER] file, deliberately NOT from youtubedl-android's
     * `dlpVersion` pref — that pref can be ahead of the file that's really
     * on disk (its updater reporting success without swapping the binary),
     * which is exactly what made the first version of this skip and leave a
     * months-old yt-dlp running. Best-effort: any failure falls through to
     * youtubedl-android's vendored copy.
     */
    private fun preSeedBundledYtDlp(appContext: Context) {
        try {
            val assetVersion = appContext.assets.open("$BUNDLED_DIR/version")
                .use { it.readBytes().toString(Charsets.UTF_8).trim() }
            if (assetVersion.isEmpty()) return

            val dir = ytdlpDir(appContext)
            val target = File(dir, YoutubeDL.ytdlpBin)
            val marker = File(dir, SEED_MARKER)
            val seeded = seededVersion(appContext)

            // Our bundled binary is already the one we put on disk — done.
            if (target.exists() && seeded == assetVersion) return

            // We seeded before AND something recorded a version strictly
            // newer than we ship — assume a genuine self-update fetched it
            // and leave that alone.
            val recorded = appContext
                .getSharedPreferences(YTDL_PREFS, Context.MODE_PRIVATE)
                .getString(DLP_VERSION_KEY, null)
            if (seeded != null && recorded != null && target.exists() &&
                recorded > assetVersion
            ) {
                return
            }

            val targetExisted = target.exists()
            dir.mkdirs()
            val tmp = File(dir, "yt-dlp.awdtmp")
            appContext.assets.open("$BUNDLED_DIR/yt-dlp").use { input ->
                tmp.outputStream().use { input.copyTo(it) }
            }
            if (!tmp.renameTo(target)) {
                tmp.copyTo(target, overwrite = true)
                tmp.delete()
            }
            marker.writeText(assetVersion)
            appContext.getSharedPreferences(YTDL_PREFS, Context.MODE_PRIVATE).edit()
                .putString(DLP_VERSION_KEY, assetVersion)
                .putString(DLP_VERSION_NAME_KEY, "yt-dlp $assetVersion")
                .apply()
            Log.i(
                TAG,
                "pre-seeded bundled yt-dlp $assetVersion " +
                    "(marker was ${seeded ?: "none"}, pref was ${recorded ?: "none"}, " +
                    "target existed=$targetExisted)",
            )
        } catch (e: Throwable) {
            Log.w(TAG, "bundled yt-dlp pre-seed FAILED", e)
        }
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

    /**
     * Best guess at the yt-dlp version actually on disk. youtubedl-android's
     * own `version()` pref can read ahead of the real file (see
     * [preSeedBundledYtDlp]), so when we have a [SEED_MARKER] we trust that
     * instead — unless the pref is strictly newer, which only a genuine
     * self-update produces.
     */
    fun currentVersion(appContext: Context): String? = try {
        val pref = YoutubeDL.getInstance().version(appContext)
        val seeded = seededVersion(appContext)
        when {
            seeded == null -> pref
            pref == null -> seeded
            pref > seeded -> pref
            else -> seeded
        }
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
