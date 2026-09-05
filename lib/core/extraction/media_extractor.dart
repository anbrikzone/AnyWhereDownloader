enum ServiceType { youtube, whatsapp, instagram, xTwitter, tiktok, linkedin }

enum MediaVariantType { video, audio, image }

/// How to produce an audio-only download. Present on a [MediaVariant] whose
/// [MediaVariant.type] is [MediaVariantType.audio] — it can only be
/// downloaded by yt-dlp's own `execute()` (`-x --audio-format …`), which
/// extracts/transcodes the audio track inside a foreground service (same
/// path as [MediaVariant.mergeFormatSelector]); no pause/resume, only cancel.
class AudioSpec {
  const AudioSpec({required this.format, this.qualityKbps});

  /// yt-dlp `--audio-format` value: `mp3` (re-encoded) or `m4a` (extracted
  /// as-is, no re-encode).
  final String format;

  /// Target bitrate for an mp3 preset (320/192/128); null means "keep the
  /// source stream's bitrate" (the `m4a` extract-as-is case).
  final int? qualityKbps;
}

class MediaVariant {
  MediaVariant({
    required this.type,
    required this.resolutionLabel,
    required this.container,
    required this.approxSizeBytes,
    required this.sourceUrl,
    this.requestHeaders,
    this.mergeFormatSelector,
    this.durationSeconds,
    this.audioSpec,
  });

  final MediaVariantType type;

  /// e.g. "720p"; null for audio.
  final String? resolutionLabel;

  /// e.g. mp4, m3u8, mp3, m4a.
  final String container;
  final int? approxSizeBytes;

  /// A direct, single-file stream URL when [mergeFormatSelector] is null.
  /// When [mergeFormatSelector] is set, this instead holds the *original*
  /// page URL (e.g. the YouTube watch URL) — there's no single direct URL
  /// for an unmerged video+audio pair, so it's re-resolved by yt-dlp's own
  /// `execute()` using the selector.
  final String sourceUrl;

  /// HTTP headers required to actually fetch [sourceUrl] (some CDNs, e.g.
  /// YouTube's, reject the URL without the headers yt-dlp resolved it with).
  /// Not used when [mergeFormatSelector] is set.
  final Map<String, String>? requestHeaders;

  /// When set (e.g. `"137+bestaudio/best"`), this variant is an adaptive
  /// video-only stream with no matching muxed format — it can only be
  /// downloaded by yt-dlp's own `execute()`, which downloads both streams
  /// and merges them with ffmpeg in one call. That path has no pause/resume
  /// (only cancel), unlike the direct/progressive path.
  final String? mergeFormatSelector;

  /// The source video's total duration, when known — used by the merge path
  /// to turn ffmpeg's own mux progress into a real percentage instead of an
  /// indeterminate spinner (see `YtDlpDownloadService.kt`).
  final int? durationSeconds;

  /// Set when [type] is [MediaVariantType.audio] — how to extract/transcode
  /// the audio. When set, [sourceUrl] holds the original watch URL (there's
  /// no single direct URL for a to-be-transcoded track).
  final AudioSpec? audioSpec;
}

class MediaInfo {
  MediaInfo({
    required this.title,
    required this.thumbnailUrl,
    required this.variants,
  });

  final String title;
  final String? thumbnailUrl;
  final List<MediaVariant> variants;
}

/// Common contract every URL-based service implements (TZ §4.1). WhatsApp
/// does not implement this — it isn't URL-based, see
/// `services/whatsapp/whatsapp_status_reader.dart` instead.
abstract class MediaExtractor {
  ServiceType get serviceType;

  bool canHandle(String url);

  Future<MediaInfo> extract(String url);
}

class ExtractionException implements Exception {
  ExtractionException(this.message);

  final String message;

  @override
  String toString() => message;
}
