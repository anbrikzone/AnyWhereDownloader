import '../yt_dlp_engine/yt_dlp_engine.dart';
import 'media_extractor.dart';

const _imageExts = {'jpg', 'jpeg', 'png', 'webp', 'heic'};

/// When a yt-dlp-based extractor found no usable video formats, this
/// returns a single image [MediaVariant] if the post looks like a photo:
/// yt-dlp's top-level `ext`/`url` are an image, or (last resort) its
/// `thumbnail` is the only media on offer. Carousels (multiple images in
/// one post) are out of scope — only the first/primary image is handled.
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
