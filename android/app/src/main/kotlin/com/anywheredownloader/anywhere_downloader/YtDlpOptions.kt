package com.anywheredownloader.anywhere_downloader

import com.yausername.youtubedl_android.YoutubeDLRequest

/**
 * YouTube-specific yt-dlp workarounds, applied to every request that
 * targets a youtube.com / youtu.be URL (metadata *and* download).
 *
 * YouTube's "SABR streaming" rollout (yt-dlp issue #12482) makes the
 * default `web` player client hand back adaptive formats with no usable
 * `url`, so the actual media fetch then fails with `HTTP Error 403:
 * Forbidden` — exactly the on-device report this was added for. Steering
 * the player-client selection sidesteps it without a PO token / JS runtime
 * (neither is available in youtubedl-android's minimal bundled Python).
 *
 * This is a band-aid and a **tuning point**, not a real fix: the durable
 * fix is keeping the bundled yt-dlp fresh (see [YtDlpCore]). If a future
 * yt-dlp makes this unnecessary — or harmful — set [PLAYER_CLIENT] to an
 * empty string to disable it entirely.
 */
object YtDlpOptions {
    /**
     * Value for `--extractor-args "youtube:player_client=…"`. `default`
     * keeps whatever the current yt-dlp picks (so nothing that already
     * works regresses); the extra clients are tried when the default set
     * only yields URL-less SABR formats. Empty string ⇒ option not added.
     */
    const val PLAYER_CLIENT = "default,tv"

    private val YOUTUBE_HOST = Regex(
        """^(https?://)?([\w-]+\.)*(youtube\.com|youtu\.be|youtube-nocookie\.com)/""",
        RegexOption.IGNORE_CASE,
    )

    fun isYouTube(url: String): Boolean = YOUTUBE_HOST.containsMatchIn(url.trim())

    /** Adds the YouTube workaround options to [request] when [url] is a
     *  YouTube link and [PLAYER_CLIENT] is non-empty. No-op otherwise. */
    fun applyYouTube(request: YoutubeDLRequest, url: String) {
        if (PLAYER_CLIENT.isBlank() || !isYouTube(url)) return
        request.addOption("--extractor-args", "youtube:player_client=$PLAYER_CLIENT")
    }
}
