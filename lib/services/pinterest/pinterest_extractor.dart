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

/// `ORIGIN/videos/iht/hls/[vN/]aa/bb/cc/HASH[_vN]_WIDTHw.m3u8` → groups
/// (ORIGIN, `aa/bb/cc/HASH`, `_vN` or null, `WIDTHw`).
final _hlsRendition = RegExp(
  r'^(https?://[^/]+)/videos/iht/hls/(?:v\d+/)?([0-9a-f]{2}/[0-9a-f]{2}/[0-9a-f]{2}/[0-9a-f]+)(_v\d+)?_(\d+w)\.m3u8$',
);

/// Pinterest pins via yt-dlp's `pinterest` extractor (read from the bundled
/// source, 2026-10-03):
/// - **video pin** → progressive MP4s from the pin's `video_list` (with
///   width/height) plus `V_HLS*` m3u8 entries, which are skipped;
///   **Current pins usually have *only* HLS** (`V_HLSV3_MOBILE-*`, video-only
///   streams plus a separate audio stream — found on-device 2026-10-03), so
///   [_mp4TwinsOfHls] maps each HLS rendition to the muxed MP4 Pinterest
///   also serves for it;
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

    final progressive = info.formats
        .where((f) => f.url != null)
        .where((f) => !(f.formatId?.toLowerCase().contains('hls') ?? false))
        .where((f) => !f.url!.contains('.m3u8'))
        .toList();
    if (progressive.isEmpty) progressive.addAll(await _mp4TwinsOfHls(info));
    final variants = progressiveVideoVariants(
      progressive,
      durationSeconds: info.durationSeconds,
    );

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

  /// Pinterest serves every HLS rendition `…/videos/iht/hls/…/HASH_Ww.m3u8`
  /// as a muxed (video + audio) MP4 at `…/videos/iht/expMp4/aa/bb/cc/HASH_Ww.mp4`
  /// too — not part of yt-dlp's output, found by probing (2026-10-03, two
  /// pins, 240w–720w, each MP4 with an `mp4a` track). Newer pins put a `v2/`
  /// directory and a `_v2` suffix into the HLS name; the MP4 has neither
  /// (`…_v2_720w.mp4` is 403, `…_720w.mp4` is 200), so that form is tried
  /// first and the literal one only as a fallback. It's an undocumented
  /// scheme, so every candidate is HEAD-checked and only ones that really
  /// exist are offered (with their exact size).
  Future<List<RawFormat>> _mp4TwinsOfHls(RawVideoInfo info) async {
    final candidates = <List<RawFormat>>[];
    for (final f in info.formats) {
      final url = f.url;
      if (url == null || !f.hasVideo) continue;
      final match = _hlsRendition.firstMatch(url);
      if (match == null) continue;
      final base = '${match.group(1)}/videos/iht/expMp4/${match.group(2)}';
      final width = match.group(4);
      final suffix = match.group(3);
      candidates.add(
        ['${base}_$width.mp4', if (suffix != null) '$base${suffix}_$width.mp4']
            .map(
              (mp4) => RawFormat(
                formatId: f.formatId,
                ext: 'mp4',
                vcodec: f.vcodec,
                acodec: null,
                height: f.height,
                width: f.width,
                formatNote: f.formatNote,
                url: mp4,
                fileSizeBytes: 0,
                httpHeaders: null,
                tbrKbps: 0,
              ),
            )
            .toList(),
      );
    }
    final checked = await Future.wait(candidates.map(_firstExisting));
    return checked.whereType<RawFormat>().toList();
  }

  /// The first of [options] (alternative URLs for one rendition) that exists.
  Future<RawFormat?> _firstExisting(List<RawFormat> options) async {
    for (final option in options) {
      final found = await _withSizeIfExists(option);
      if (found != null) return found;
    }
    return null;
  }

  Future<RawFormat?> _withSizeIfExists(RawFormat f) async {
    try {
      final response = await _client
          .head(Uri.parse(f.url!))
          .timeout(const Duration(seconds: 10));
      final type = response.headers['content-type'] ?? '';
      if (response.statusCode != 200 || !type.startsWith('video/')) {
        return null;
      }
      return RawFormat(
        formatId: f.formatId,
        ext: f.ext,
        vcodec: f.vcodec,
        acodec: f.acodec,
        height: f.height,
        width: f.width,
        formatNote: f.formatNote,
        url: f.url,
        fileSizeBytes:
            int.tryParse(response.headers['content-length'] ?? '') ?? 0,
        httpHeaders: null,
        tbrKbps: 0,
      );
    } catch (e, st) {
      logError('PinterestExtractor.probeMp4', e, st);
      return null;
    }
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
