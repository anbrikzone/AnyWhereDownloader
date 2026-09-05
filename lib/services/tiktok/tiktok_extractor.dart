import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/extraction/media_extractor.dart';

/// The one extractor that does **not** use `yt_dlp_engine`: yt-dlp's TikTok
/// paths both proved unreliable on-device (need `curl_cffi` impersonation,
/// or return CDN URLs that 403 without a session cookie). Calls tikwm.com's
/// public API instead — a third-party service we don't control, accepted
/// knowingly as the price of TikTok working. See CLAUDE.md "TikTok".
class TikTokExtractor implements MediaExtractor {
  TikTokExtractor({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _apiBase = 'https://www.tikwm.com/api/';

  @override
  ServiceType get serviceType => ServiceType.tiktok;

  @override
  bool canHandle(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    return host == 'tiktok.com' || host.endsWith('.tiktok.com');
  }

  @override
  Future<MediaInfo> extract(String url) async {
    final requestUri = Uri.parse(
      _apiBase,
    ).replace(queryParameters: {'url': url.trim(), 'hd': '1'});

    final http.Response response;
    try {
      response = await _client
          .get(requestUri)
          .timeout(const Duration(seconds: 20));
    } catch (error) {
      throw ExtractionException('Could not reach the TikTok lookup service: $error');
    }

    if (response.statusCode != 200) {
      throw ExtractionException(
        'TikTok lookup service returned an error (HTTP ${response.statusCode}).',
      );
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw ExtractionException('TikTok lookup service returned an unexpected response.');
    }

    if (body['code'] != 0) {
      throw ExtractionException(
        (body['msg'] as String?) ?? 'This TikTok video could not be resolved.',
      );
    }

    final data = body['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw ExtractionException('This TikTok video could not be resolved.');
    }

    final play = data['play'] as String?;
    final hdplay = data['hdplay'] as String?;
    final size = data['size'] as int?;
    final hdSize = data['hd_size'] as int?;

    final variants = <MediaVariant>[];
    if (hdplay != null && hdplay.isNotEmpty && hdplay != play) {
      variants.add(
        MediaVariant(
          type: MediaVariantType.video,
          resolutionLabel: 'HD',
          container: 'mp4',
          approxSizeBytes: (hdSize != null && hdSize > 0) ? hdSize : null,
          sourceUrl: hdplay,
        ),
      );
    }
    if (play != null && play.isNotEmpty) {
      variants.add(
        MediaVariant(
          type: MediaVariantType.video,
          resolutionLabel: variants.isEmpty ? null : 'SD',
          container: 'mp4',
          approxSizeBytes: (size != null && size > 0) ? size : null,
          sourceUrl: play,
        ),
      );
    }

    if (variants.isEmpty) {
      throw ExtractionException(
        'No downloadable format found for this video in this version.',
      );
    }

    final title = data['title'] as String?;
    return MediaInfo(
      title: (title == null || title.isEmpty) ? 'TikTok video' : title,
      thumbnailUrl: data['cover'] as String?,
      variants: variants,
    );
  }
}
