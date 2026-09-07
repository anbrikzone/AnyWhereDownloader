package com.anywheredownloader.anywhere_downloader

import android.content.Context
import android.util.Log
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicReference

/**
 * Shared yt-dlp/ffmpeg initialization, used by both [YtDlpBridge] (getInfo)
 * and [YtDlpDownloadService] (merge / audio / playlist downloads) so init
 * happens exactly once regardless of which entry point runs first.
 *
 * Also owns keeping the yt-dlp **script** fresh (not the Python/ffmpeg
 * runtime, not the library). The binary shipped inside `youtubedl-android`
 * is only as fresh as that library's last release, and YouTube breaks
 * older yt-dlp clients regularly (e.g. the "SABR streaming" rollout →
 * `HTTP Error 403: Forbidden`). Two layers: [preSeedBundledYtDlp] installs
 * the APK-bundled copy on first run, and [ownUpdate] fetches a newer one
 * from yt-dlp's GitHub releases when there is one.
 *
 * History:
 *  - v1 ran the update once inside init, swallowed every failure, and
 *    latched `initialized` regardless — one network-less cold start meant
 *    permanently stale, silently (OnePlus 15, stuck at 2025.11.12).
 *  - v2 added retry-after-failure, a time bound, and the APK bundle — but
 *    the pre-seed trusted youtubedl-android's version pref, which read
 *    ahead of the actual on-disk file, so it skipped.
 *  - v3 (this): pre-seed decides from its own [SEED_MARKER]; the update
 *    itself is [ownUpdate] — a plain timed HTTP check against yt-dlp's
 *    releases feed — because `YoutubeDL.updateYoutubeDL()`'s own check does
 *    a header-less, timeout-less full-JSON `readTree(URL)` that took a
 *    minute+ on the OnePlus 15 even when nothing needed updating.
 */
object YtDlpCore {
    private const val TAG = "YtDlpCore"

    /** How long [ensureInitialized] will block an extraction waiting for an
     *  update before letting it proceed on the current binary (the update
     *  keeps running in the background if it hasn't finished). */
    private const val INLINE_UPDATE_TIMEOUT_MS = 15_000L

    /** Budget for the user-triggered Settings button. Our own updater is a
     *  ~8 s API check plus, only when a newer release exists, a ~3 MB
     *  download — so this is a safety net, not the normal wait. */
    private const val FORCED_UPDATE_TIMEOUT_MS = 60_000L

    /** After a failed attempt, don't hammer GitHub on every extraction. */
    private const val RETRY_COOLDOWN_MS = 60_000L

    /** yt-dlp's own releases feed. We query this ourselves — with a
     *  User-Agent, an `Accept` header, an `If-None-Match` conditional and
     *  real timeouts — instead of `YoutubeDL.updateYoutubeDL()`, whose
     *  check does a header-less, timeout-less `ObjectMapper.readTree(URL)`
     *  of the whole (large) release JSON and routinely takes a minute+ even
     *  when nothing needs updating (confirmed on a OnePlus 15: two `already
     *  up to date` results, no download, minute-long spinner). */
    private const val YTDLP_RELEASES_API =
        "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest"
    private const val YTDLP_DOWNLOAD_URL =
        "https://github.com/yt-dlp/yt-dlp/releases/download/%s/yt-dlp"
    private const val API_TIMEOUT_MS = 8_000
    private const val DOWNLOAD_TIMEOUT_MS = 30_000

    /** A manual "Check for updates" tap re-uses the last result rather than
     *  hitting the network again if a check already succeeded this recently
     *  (the startup warm-up usually already ran one). */
    private const val FORCE_RECHECK_THROTTLE_MS = 5 * 60_000L

    /** Our own prefs (not youtubedl-android's) — caches the releases-feed
     *  ETag + last-seen tag so repeat checks are a 304, not a full re-read
     *  of the multi-KB release JSON. */
    private const val AWD_PREFS = "awd_ytdlp"
    private const val KEY_ETAG = "releases_etag"
    private const val KEY_LATEST_TAG = "releases_latest_tag"

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
            val sinceLast = System.currentTimeMillis() - lastUpdate.timestampMs
            if ((lastUpdate.status == "upToDate" || lastUpdate.status == "done") &&
                sinceLast < FORCE_RECHECK_THROTTLE_MS
            ) {
                Log.i(TAG, "yt-dlp check re-used (${lastUpdate.status}, ${sinceLast}ms ago)")
                return lastUpdate
            }
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
            val outcome = ownUpdate(appContext)
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

    /**
     * Our replacement for `YoutubeDL.updateYoutubeDL()`: query yt-dlp's
     * `releases/latest` ourselves (User-Agent + `Accept` + timeouts), and
     * only when the tag is newer than what's on disk, download the `yt-dlp`
     * asset (with timeouts) and swap it in — writing our [SEED_MARKER] and
     * youtubedl-android's `dlpVersion` pref so everything stays consistent.
     * The common "already current" path is a single fast API call, no
     * download, no giant-JSON parse.
     */
    private fun ownUpdate(appContext: Context): UpdateOutcome {
        val now = System.currentTimeMillis()
        return try {
            val latestTag = fetchLatestYtDlpTag(appContext)
            val installed = seededVersion(appContext) ?: appContext
                .getSharedPreferences(YTDL_PREFS, Context.MODE_PRIVATE)
                .getString(DLP_VERSION_KEY, null)

            // yt-dlp tags are zero-padded YYYY.MM.DD — a string compare orders them.
            if (installed != null && installed >= latestTag) {
                Log.i(TAG, "yt-dlp current ($installed, latest $latestTag)")
                return UpdateOutcome("upToDate", currentVersion(appContext), null, now)
            }

            val dir = ytdlpDir(appContext).apply { mkdirs() }
            val tmp = File(dir, "yt-dlp.dltmp")
            downloadFile(YTDLP_DOWNLOAD_URL.format(latestTag), tmp)
            if (tmp.length() < 500_000L) {
                tmp.delete()
                throw IOException("downloaded yt-dlp is implausibly small (${tmp.length()} B)")
            }
            val target = File(dir, YoutubeDL.ytdlpBin)
            if (!tmp.renameTo(target)) {
                tmp.copyTo(target, overwrite = true)
                tmp.delete()
            }
            File(dir, SEED_MARKER).writeText(latestTag)
            appContext.getSharedPreferences(YTDL_PREFS, Context.MODE_PRIVATE).edit()
                .putString(DLP_VERSION_KEY, latestTag)
                .putString(DLP_VERSION_NAME_KEY, "yt-dlp $latestTag")
                .apply()
            Log.i(TAG, "yt-dlp updated ${installed ?: "none"} -> $latestTag")
            UpdateOutcome("done", latestTag, null, now)
        } catch (e: Throwable) {
            Log.w(TAG, "yt-dlp update failed", e)
            UpdateOutcome(
                "failed",
                currentVersion(appContext),
                e.message ?: e.javaClass.simpleName,
                now,
            )
        }
    }

    /**
     * The latest yt-dlp tag, via a conditional GET of the releases feed: an
     * `If-None-Match` ETag means a repeat check is a tiny `304`, not a
     * re-read of the whole multi-KB release JSON. Cached tag + ETag live in
     * our own prefs.
     */
    private fun fetchLatestYtDlpTag(appContext: Context): String {
        val prefs = appContext.getSharedPreferences(AWD_PREFS, Context.MODE_PRIVATE)
        val etag = prefs.getString(KEY_ETAG, null)
        val cachedTag = prefs.getString(KEY_LATEST_TAG, null)

        val conn = (URL(YTDLP_RELEASES_API).openConnection() as HttpURLConnection).apply {
            connectTimeout = API_TIMEOUT_MS
            readTimeout = API_TIMEOUT_MS
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", "AnyWhereDownloader")
            setRequestProperty("Accept", "application/vnd.github+json")
            if (etag != null) setRequestProperty("If-None-Match", etag)
        }
        try {
            val code = conn.responseCode
            if (code == HttpURLConnection.HTTP_NOT_MODIFIED && cachedTag != null) {
                return cachedTag
            }
            if (code !in 200..299) throw IOException("HTTP $code from releases feed")
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            val tag = org.json.JSONObject(body).getString("tag_name")
            prefs.edit().apply {
                putString(KEY_LATEST_TAG, tag)
                val newEtag = conn.getHeaderField("ETag")
                if (newEtag != null) putString(KEY_ETAG, newEtag) else remove(KEY_ETAG)
            }.apply()
            return tag
        } finally {
            conn.disconnect()
        }
    }

    private fun downloadFile(urlStr: String, dest: File) {
        val conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
            connectTimeout = API_TIMEOUT_MS
            readTimeout = DOWNLOAD_TIMEOUT_MS
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", "AnyWhereDownloader")
        }
        try {
            if (conn.responseCode !in 200..299) {
                throw IOException("HTTP ${conn.responseCode} downloading $urlStr")
            }
            conn.inputStream.use { input ->
                dest.outputStream().use { output -> input.copyTo(output) }
            }
        } finally {
            conn.disconnect()
        }
    }
}
