import 'package:http/http.dart' as http;

import '../../core/extraction/media_extractor.dart';
import '../../core/extraction/progressive_formats.dart';
import '../../core/logging/app_log.dart';
import '../../core/yt_dlp_engine/yt_dlp_engine.dart';

/// `pinterest.com`, a country domain (`pinterest.ru`, `pinterest.co.uk`),
/// with or without a subdomain (`www.`, `ru.`).
final _pinterestHost = RegExp(
  r'^(?:[\w-]+\.)?pinterest\.(?:[a-z]{2,4}|co\.[a-z]{2}|com\.[a-z]{2})$',
);

const _imageExts = {'jpg', 'jpeg', 'png', 'webp', 'gif'};

/// Pinterest pins via yt-dlp's `pinterest` extractor:
/// - **video pin with progressive MP4s** (older pins, `V_720P`-style ids) →
///   direct, pausable downloads;
/// - **video pin with only HLS** (most current pins, `V_HLSV3_MOBILE-*`:
///   video-only renditions + a separate audio stream — seen on every pin the
///   user tried, 2026-10-03) → one *merge* variant per rendition: yt-dlp
///   itself fetches the HLS video + audio and muxes them with the bundled
///   ffmpeg (the same foreground-service path as YouTube's high-res
///   downloads; cancel only, no pause). An earlier attempt guessed muxed
///   `expMp4` URLs instead — they exist for some pins and not others;
/// - **image pin** → no formats at all. yt-dlp would fail with "No video
///   formats found", so `YtDlpBridge` passes `--ignore-no-formats-error` for
///   Pinterest and the image comes from yt-dlp's best `thumbnail` (the
///   pin's `images`, largest — normally `orig`);
/// - **`pin.it` short link** → not matched by yt-dlp's URL pattern, so it's
///   expanded here by following redirects to `pinterest.com/pin/<id>`.
class PinterestExtractor implements MediaExtractor {
  PinterestExtractor({YtDlpEngine? engine, http.Client? client})
    : _engine = engine ?? YtDlpEngine(),
      _client = client ?? http.Client();

  final YtDlpEngine _engine;
  final http.Client _client;

  @override
  ServiceType get serviceType => ServiceType.pinterest;

  @override
  bool canHandle(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    if (host == 'pin.it') return uri.pathSegments.isNotEmpty;
    return _isPinUri(uri);
  }

  static bool _isPinUri(Uri uri) =>
      _pinterestHost.hasMatch(uri.host.toLowerCase()) &&
      uri.path.toLowerCase().startsWith('/pin/');

  @override
  Future<MediaInfo> extract(String url) async {
    final pinUrl = await _expandShortLink(url.trim());
    final info = await _engine.getInfo(pinUrl);

    bool isHls(RawFormat f) =>
        (f.formatId?.toLowerCase().contains('hls') ?? false) ||
        (f.url?.contains('.m3u8') ?? false);

    final variants = progressiveVideoVariants(
      info.formats.where((f) => f.url != null && !isHls(f)).toList(),
      durationSeconds: info.durationSeconds,
    );
    if (variants.isEmpty) {
      variants.addAll(_hlsMergeVariants(info, pinUrl, isHls));
    }
    if (variants.isEmpty) {
      final image = _imageVariant(info);
      if (image != null) variants.add(image);
    }
    if (variants.isEmpty) {
      throw ExtractionException(ExtractionErrorCode.noDownloadableMedia);
    }

    final title = info.title?.trim();
    return MediaInfo(
      title: title == null || title.isEmpty ? 'Pinterest' : title,
      thumbnailUrl: info.thumbnailUrl,
      variants: variants,
    );
  }

  /// One merge variant per HLS video rendition, best first. The selector
  /// names the exact video + audio format ids from this extraction, with a
  /// height-capped generic fallback in case the ids differ when the
  /// download re-extracts.
  List<MediaVariant> _hlsMergeVariants(
    RawVideoInfo info,
    String pinUrl,
    bool Function(RawFormat) isHls,
  ) {
    final hls = info.formats.where(isHls).where((f) => f.formatId != null);
    // Pinterest's audio rendition reports vcodec "none" and no acodec at
    // all, so "the HLS stream without video" is the audio.
    final audio = hls.where((f) => !f.hasVideo).firstOrNull;
    final videos = hls.where((f) => f.hasVideo).toList()
      ..sort((a, b) => b.height.compareTo(a.height));

    final seen = <String>{};
    final variants = <MediaVariant>[];
    for (final video in videos) {
      final label = qualityLabelOf(video);
      if (!seen.add(label ?? video.formatId!)) continue;
      final exact = audio == null
          ? video.formatId!
          : '${video.formatId}+${audio.formatId}';
      final capped = video.height > 0 ? '[height<=${video.height}]' : '';
      variants.add(
        MediaVariant(
          type: MediaVariantType.video,
          resolutionLabel: label,
          container: 'mp4',
          approxSizeBytes: null,
          sourceUrl: pinUrl,
          mergeFormatSelector: '$exact/bv*$capped+ba/b$capped/b',
          durationSeconds: info.durationSeconds > 0
              ? info.durationSeconds
              : null,
        ),
      );
    }
    return variants;
  }

  /// An image pin's picture: yt-dlp's top-level `url` if it's an image,
  /// otherwise its best thumbnail — for a format-less pin that *is* the
  /// pin image.
  MediaVariant? _imageVariant(RawVideoInfo info) {
    final url = info.directUrl ?? info.thumbnailUrl;
    if (url == null || url.isEmpty) return null;
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    final dot = path.lastIndexOf('.');
    final ext = dot >= 0 ? path.substring(dot + 1) : '';
    return MediaVariant(
      type: MediaVariantType.image,
      resolutionLabel: null,
      container: _imageExts.contains(ext) ? ext : 'jpg',
      approxSizeBytes: null,
      sourceUrl: url,
    );
  }

  /// Follows a `pin.it/<code>` short link's redirects (it hops through
  /// `api.pinterest.com/url_shortener/…`) until it reaches a pin URL. On any
  /// failure the original link is returned, and yt-dlp's generic extractor
  /// gets a try.
  Future<String> _expandShortLink(String url) async {
    var current = Uri.parse(url);
    if (current.host.toLowerCase() != 'pin.it') return url;
    try {
      for (var hop = 0; hop < 6; hop++) {
        final request = http.Request('GET', current)
          ..followRedirects = false
          ..headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 14)';
        final response = await _client
            .send(request)
            .timeout(const Duration(seconds: 15));
        await response.stream.drain<void>();
        final location = response.headers['location'];
        if (response.statusCode < 300 ||
            response.statusCode >= 400 ||
            location == null) {
          break;
        }
        current = current.resolve(location);
        if (_isPinUri(current)) {
          // Drop the tracking query (`?invite_code=…&sender=…`).
          return Uri(
            scheme: current.scheme,
            host: current.host,
            path: current.path,
          ).toString();
        }
      }
    } catch (e, st) {
      logError('PinterestExtractor.expandShortLink', e, st);
    }
    return url;
  }
}
