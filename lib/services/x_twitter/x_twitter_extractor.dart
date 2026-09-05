import '../../core/extraction/image_fallback.dart';
import '../../core/extraction/media_extractor.dart';
import '../../core/yt_dlp_engine/yt_dlp_engine.dart';

/// Thin [YtDlpEngine] wrapper for X/Twitter post video. Selects the plain
/// progressive MP4 by `format_id` starting `http-` rather than
/// `hasVideo && hasAudio`, because those entries carry no codec info at all
/// (only `hls-*` entries do, and those need segment fetching we don't do).
/// Protected/login-required accounts are out of scope (no cookie auth). See
/// CLAUDE.md "X/Twitter" for the on-device investigation.
class XTwitterExtractor implements MediaExtractor {
  XTwitterExtractor({YtDlpEngine? engine}) : _engine = engine ?? YtDlpEngine();

  final YtDlpEngine _engine;

  @override
  ServiceType get serviceType => ServiceType.xTwitter;

  @override
  bool canHandle(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    return host == 'twitter.com' ||
        host.endsWith('.twitter.com') ||
        host == 'x.com' ||
        host.endsWith('.x.com');
  }

  @override
  Future<MediaInfo> extract(String url) async {
    final info = await _engine.getInfo(url);
    final duration = info.durationSeconds;

    // Progressive MP4 only (`http-*`); exclude HLS. See the class doc.
    final muxed =
        info.formats
            .where((f) => f.formatId?.startsWith('http-') ?? false)
            .where((f) => !(f.url?.contains('.m3u8') ?? false))
            .toList()
          ..sort((a, b) => b.height.compareTo(a.height));

    final seenHeights = <int>{};
    final variants = <MediaVariant>[];
    for (final format in muxed) {
      if (format.url == null) continue;
      if (!seenHeights.add(format.height)) continue;
      variants.add(
        MediaVariant(
          type: MediaVariantType.video,
          resolutionLabel: format.height > 0 ? '${format.height}p' : null,
          container: format.ext ?? 'mp4',
          approxSizeBytes: format.estimatedSizeBytes(duration),
          sourceUrl: format.url!,
          requestHeaders: format.httpHeaders,
        ),
      );
    }

    if (variants.isEmpty) {
      // No video — offer the image if this is a (single-image) photo tweet.
      // Note: a photo-only tweet often makes `getInfo` itself throw
      // "No video could be found" before reaching here — that case can't
      // be recovered without a separate image API.
      final image = imageVariantFor(info);
      if (image != null) variants.add(image);
    }

    if (variants.isEmpty) {
      throw ExtractionException(
        'No downloadable format found for this post in this version.',
      );
    }

    return MediaInfo(
      title: info.title ?? 'X/Twitter',
      thumbnailUrl: info.thumbnailUrl,
      variants: variants,
    );
  }
}
