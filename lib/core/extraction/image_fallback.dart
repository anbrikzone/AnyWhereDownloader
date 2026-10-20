import '../yt_dlp_engine/yt_dlp_engine.dart';
import 'media_extractor.dart';

const _imageExts = {'jpg', 'jpeg', 'png', 'webp', 'heic'};

/// File extension for a CDN image URL (TikTok, Instagram) — its path
/// usually ends in `.jpeg`/`.webp` before the query string; `jpg` when it
/// can't tell.
String imageContainerFor(String url) {
  final path = (Uri.tryParse(url)?.path ?? '').toLowerCase();
  for (final ext in const ['jpeg', 'jpg', 'webp', 'png', 'heic']) {
    if (path.endsWith('.$ext')) return ext;
  }
  return 'jpg';
}

/// When a yt-dlp-based extractor found no usable video formats, this
/// returns a single image [MediaVariant] if the post looks like a photo:
/// yt-dlp's top-level `ext`/`url` are an image, or (last resort) its
/// `thumbnail` is the only media on offer. Single-image only — Instagram's
/// carousels go through `YtDlpEngine.getPostItems` instead.
MediaVariant? imageVariantFor(RawVideoInfo info) {
  final ext = info.ext?.toLowerCase();
  final direct = info.directUrl;
  final extIsImage = ext != null && _imageExts.contains(ext);
  final urlIsImage = direct != null &&
      _imageExts.any((e) => direct.toLowerCase().contains('.$e'));
  if (!extIsImage && !urlIsImage) return null;

  final url = direct ?? info.thumbnailUrl;
  if (url == null || url.isEmpty) return null;

  return MediaVariant(
    type: MediaVariantType.image,
    resolutionLabel: null,
    container: extIsImage ? ext : 'jpg',
    approxSizeBytes: null,
    sourceUrl: url,
  );
}
