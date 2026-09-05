import '../../core/extraction/image_fallback.dart';
import '../../core/extraction/media_extractor.dart';
import '../../core/yt_dlp_engine/yt_dlp_engine.dart';

/// Thin [YtDlpEngine] wrapper for Instagram reels/posts. Picks the
/// progressive (directly downloadable) format by name — `format_id` not
/// starting with `dash-` — because Instagram's progressive entries report
/// null codecs and `height=0`, so a `hasVideo && hasAudio` filter drops
/// exactly what we want. Deduped by URL, not height, since those entries
/// are duplicate URLs under different ids. See CLAUDE.md "Instagram" for
/// the on-device investigation behind this.
class InstagramExtractor implements MediaExtractor {
  InstagramExtractor({YtDlpEngine? engine}) : _engine = engine ?? YtDlpEngine();

  final YtDlpEngine _engine;

  @override
  ServiceType get serviceType => ServiceType.instagram;

  @override
  bool canHandle(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    final isInstagramHost =
        host == 'instagram.com' ||
        host.endsWith('.instagram.com');
    if (!isInstagramHost) return false;
    final path = uri.path.toLowerCase();
    return path.startsWith('/p/') ||
        path.startsWith('/reel/') ||
        path.startsWith('/reels/') ||
        path.startsWith('/tv/') ||
        path.startsWith('/stories/');
  }

  @override
  Future<MediaInfo> extract(String url) async {
    final info = await _engine.getInfo(url);
    final duration = info.durationSeconds;

    // Progressive only: drop `dash-` (adaptive, needs muxing) and any
    // manifest URL. See the class doc for why not `hasVideo && hasAudio`.
    final progressive =
        info.formats
            .where((f) => f.url != null)
            .where((f) => !(f.formatId?.startsWith('dash-') ?? false))
            .where((f) => !f.url!.contains('.m3u8'))
            .where((f) => !f.url!.contains('.mpd'))
            .toList()
          ..sort((a, b) => b.height.compareTo(a.height));

    final seenUrls = <String>{};
    final variants = <MediaVariant>[];
    for (final format in progressive) {
      if (!seenUrls.add(format.url!)) continue;
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
      // No video — offer the image if this is a (single-image) photo post.
      final image = imageVariantFor(info);
      if (image != null) variants.add(image);
    }

    if (variants.isEmpty) {
      throw ExtractionException(
        'No downloadable format found for this post in this version.',
      );
    }

    return MediaInfo(
      title: info.title ?? 'Instagram',
      thumbnailUrl: info.thumbnailUrl,
      variants: variants,
    );
  }
}
