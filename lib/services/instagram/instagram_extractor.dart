import '../../core/extraction/image_fallback.dart';
import '../../core/extraction/media_extractor.dart';
import '../../core/extraction/progressive_formats.dart';
import '../../core/yt_dlp_engine/yt_dlp_engine.dart';

/// Thin [YtDlpEngine] wrapper for Instagram reels/posts. Picks the
/// progressive (directly downloadable) format by name — `format_id` not
/// starting with `dash-` — because Instagram's progressive entries report
/// null codecs and `height=0`, so a `hasVideo && hasAudio` filter drops
/// exactly what we want. Indistinguishable entries collapse to one (see
/// [progressiveVideoVariants]) — they're one asset under different ids. See CLAUDE.md "Instagram" for
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
    final segments = [
      for (final s in uri.pathSegments)
        if (s.isNotEmpty) s.toLowerCase(),
    ];
    if (segments.length < 2) return false;
    if (segments.first == 'stories') return true;
    // `/p/<id>`, or the same with the account in front —
    // `/<username>/p/<id>` (what Instagram's web share gives).
    const postTypes = {'p', 'reel', 'reels', 'tv'};
    if (postTypes.contains(segments[0])) return true;
    return segments.length >= 3 && postTypes.contains(segments[1]);
  }

  @override
  Future<MediaInfo> extract(String url) async {
    // getPostItems, not getInfo: a carousel is a playlist whose entries the
    // getInfo mapper drops, and a photo item has no formats at all.
    final post = await _engine.getPostItems(url);
    final title = post.title ?? 'Instagram';

    if (post.items.length <= 1) {
      final info = post.items.isEmpty ? null : post.items.single;
      final variants = info == null ? <MediaVariant>[] : _variantsOf(info);
      if (variants.isEmpty) {
        throw ExtractionException(ExtractionErrorCode.noDownloadableMedia);
      }
      return MediaInfo(
        title: title,
        thumbnailUrl: info!.thumbnailUrl,
        variants: variants,
      );
    }

    // A carousel: each item downloads as its single best variant. An item
    // with nothing downloadable is skipped rather than failing the post.
    final requested = carouselIndexOf(url);
    final items = <MediaItem>[];
    int? current;
    for (final (index, info) in post.items.indexed) {
      final variants = _variantsOf(info);
      if (variants.isEmpty) continue;
      if (index == requested) current = items.length;
      items.add(
        MediaItem(thumbnailUrl: info.thumbnailUrl, variant: variants.first),
      );
    }
    if (items.isEmpty) {
      throw ExtractionException(ExtractionErrorCode.noDownloadableMedia);
    }
    final focused = items[current ?? 0];
    return MediaInfo(
      title: title,
      thumbnailUrl: focused.thumbnailUrl,
      variants: [focused.variant],
      items: items.length > 1 ? items : const [],
      currentItemIndex: items.length > 1 ? current : null,
    );
  }

  /// One item's choices: its progressive video qualities, else its photo.
  List<MediaVariant> _variantsOf(RawVideoInfo info) {
    // Progressive only: drop `dash-` (adaptive, needs muxing) and any
    // manifest URL. See the class doc for why not `hasVideo && hasAudio`.
    final progressive = info.formats
        .where((f) => f.url != null)
        .where((f) => !(f.formatId?.startsWith('dash-') ?? false))
        .where((f) => !f.url!.contains('.m3u8'))
        .where((f) => !f.url!.contains('.mpd'))
        .toList();

    final variants = progressiveVideoVariants(
      progressive,
      durationSeconds: info.durationSeconds,
    );
    if (variants.isNotEmpty) return variants;

    // No video — a photo. Instagram's photo item has no formats and no
    // image `ext`; its `thumbnail` is the full-size original (yt-dlp sorts
    // the uncropped, unscaled candidate last and picks it).
    final image = imageVariantFor(info);
    if (image != null) return [image];
    final thumb = info.thumbnailUrl;
    if (info.formats.isEmpty && thumb != null && thumb.isNotEmpty) {
      return [
        MediaVariant(
          type: MediaVariantType.image,
          resolutionLabel: null,
          container: imageContainerFor(thumb),
          approxSizeBytes: null,
          sourceUrl: thumb,
        ),
      ];
    }
    return const [];
  }
}

/// 0-based carousel position a post link points at — Instagram's share links
/// carry it as a 1-based `img_index` query parameter. Null when absent.
int? carouselIndexOf(String url) {
  final raw = Uri.tryParse(url.trim())?.queryParameters['img_index'];
  final n = raw == null ? null : int.tryParse(raw);
  return n == null || n < 1 ? null : n - 1;
}
