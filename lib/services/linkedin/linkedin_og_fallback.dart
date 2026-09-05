import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../../core/extraction/media_extractor.dart';

const _browserUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

/// Last-resort extraction for a LinkedIn post yt-dlp can't handle — its
/// `linkedin` extractor is video-only and throws "Unable to extract video"
/// for a photo or text post. GETs the post page directly (LinkedIn, not a
/// third party) and reads the OpenGraph `<meta>` tags LinkedIn serves
/// publicly for link previews.
///
/// **Photo only.** LinkedIn's `og:video` points at an HTML embed *player*
/// page, never a raw stream, so it's useless to us — and if `og:video` is
/// present at all, the post is a video we genuinely can't download, so we
/// return null (→ the real "can't extract video" error) rather than
/// offering the poster image as if it were the content. `og:image` is used
/// only when there's no `og:video` (a true photo post), where it's a
/// direct `media.licdn.com` image URL.
Future<MediaInfo?> linkedInInfoViaOpenGraph(
  String url, {
  http.Client? client,
}) async {
  final httpClient = client ?? http.Client();
  final http.Response response;
  try {
    response = await httpClient
        .get(Uri.parse(url.trim()), headers: const {'User-Agent': _browserUa})
        .timeout(const Duration(seconds: 20));
  } catch (_) {
    return null;
  }
  if (response.statusCode != 200) return null;

  final doc = html_parser.parse(response.body);
  String? meta(String property) {
    for (final el in doc.querySelectorAll('meta')) {
      final key = el.attributes['property'] ?? el.attributes['name'];
      if (key == property) {
        final content = el.attributes['content']?.trim();
        if (content != null && content.isNotEmpty) return content;
      }
    }
    return null;
  }

  final title = meta('og:title') ?? 'LinkedIn';
  final image = meta('og:image');
  final hasVideo = meta('og:video:secure_url') != null ||
      meta('og:video:url') != null ||
      meta('og:video') != null;

  if (kDebugMode) {
    debugPrint(
      '[LinkedIn OG] hasVideo=$hasVideo image=$image title=$title',
    );
  }

  // A video post yt-dlp couldn't extract — OG can't help (og:video is an
  // embed page, not a stream). Let the caller surface the real error.
  if (hasVideo) return null;
  if (image == null) return null;

  final lower = image.toLowerCase();
  final ext = lower.contains('.png')
      ? 'png'
      : lower.contains('.webp')
          ? 'webp'
          : 'jpg';

  return MediaInfo(
    title: title,
    thumbnailUrl: image,
    variants: [
      MediaVariant(
        type: MediaVariantType.image,
        resolutionLabel: null,
        container: ext,
        approxSizeBytes: null,
        sourceUrl: image,
      ),
    ],
  );
}
