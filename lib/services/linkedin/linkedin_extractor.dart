import 'package:flutter/foundation.dart';

import '../../core/extraction/image_fallback.dart';
import '../../core/extraction/media_extractor.dart';
import '../../core/yt_dlp_engine/yt_dlp_engine.dart';
import 'linkedin_og_fallback.dart';

const _videoExts = {'mp4', 'm4v', 'mov', 'webm', 'mkv'};

/// Thin [YtDlpEngine] wrapper for LinkedIn post/feed video, plus an
/// OpenGraph-`<meta>` fallback ([linkedInInfoViaOpenGraph]) for photo /
/// non-video posts, which yt-dlp's video-only `linkedin` extractor can't
/// handle at all ("Unable to extract video").
///
/// Video format filtering is still being tuned against real on-device
/// output (see the LinkedIn note in CLAUDE.md). Current rule: the entry
/// must look like a real progressive video file — a video container ext, a
/// known height, or a real video codec — and not be a manifest or an HTML
/// page (yt-dlp can otherwise hand back the webpage URL as a "format").
class LinkedInExtractor implements MediaExtractor {
  LinkedInExtractor({YtDlpEngine? engine}) : _engine = engine ?? YtDlpEngine();

  final YtDlpEngine _engine;

  @override
  ServiceType get serviceType => ServiceType.linkedin;

  @override
  bool canHandle(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    if (host == 'lnkd.in' || host.endsWith('.lnkd.in')) return true;
    final isLinkedInHost =
        host == 'linkedin.com' || host.endsWith('.linkedin.com');
    if (!isLinkedInHost) return false;
    final path = uri.path.toLowerCase();
    return path.startsWith('/posts/') ||
        path.startsWith('/feed/') ||
        path.startsWith('/video/');
  }

  @override
  Future<MediaInfo> extract(String url) async {
    final RawVideoInfo info;
    try {
      info = await _engine.getInfo(url);
    } catch (error) {
      // yt-dlp's LinkedIn extractor is video-only — a photo/text post
      // throws "Unable to extract video" here. Try the OpenGraph fallback
      // before giving up.
      final og = await linkedInInfoViaOpenGraph(url);
      if (og != null) return og;
      rethrow;
    }
    final duration = info.durationSeconds;

    if (kDebugMode) {
      for (final f in info.formats) {
        debugPrint(
          '[LinkedIn] format id=${f.formatId} ext=${f.ext} height=${f.height} '
          'vcodec=${f.vcodec} acodec=${f.acodec} url=${f.url}',
        );
      }
    }

    bool looksLikeVideo(RawFormat f) {
      final url = f.url;
      if (url == null) return false;
      if (url.contains('.m3u8') || url.contains('.mpd')) return false;
      final ext = f.ext?.toLowerCase();
      if (ext != null && _videoExts.contains(ext)) return true;
      if (f.height > 0) return true;
      final vcodec = f.vcodec?.toLowerCase();
      return vcodec != null && vcodec.isNotEmpty && vcodec != 'none';
    }

    final downloadable = info.formats.where(looksLikeVideo).toList()
      ..sort((a, b) => b.height.compareTo(a.height));

    final seen = <String>{};
    final variants = <MediaVariant>[];
    for (final format in downloadable) {
      final key = format.height > 0 ? '${format.height}p' : format.url!;
      if (!seen.add(key)) continue;
      variants.add(
        MediaVariant(
          type: MediaVariantType.video,
          resolutionLabel: format.height > 0 ? '${format.height}p' : null,
          container: _videoExts.contains(format.ext?.toLowerCase())
              ? format.ext!
              : 'mp4',
          approxSizeBytes: format.estimatedSizeBytes(duration),
          sourceUrl: format.url!,
          requestHeaders: format.httpHeaders,
        ),
      );
    }

    if (variants.isEmpty) {
      // No video — try yt-dlp's own image fields, then the OpenGraph page.
      final image = imageVariantFor(info);
      if (image != null) {
        variants.add(image);
      } else {
        final og = await linkedInInfoViaOpenGraph(url);
        if (og != null) return og;
      }
    }

    if (variants.isEmpty) {
      throw ExtractionException(
        'No downloadable video or image found for this LinkedIn post.',
      );
    }

    if (kDebugMode) {
      for (final v in variants) {
        debugPrint('[LinkedIn] picked ${v.type.name} ${v.resolutionLabel} '
            'headers=${v.requestHeaders?.keys.toList()} url=${v.sourceUrl}');
      }
    }

    return MediaInfo(
      title: info.title ?? 'LinkedIn',
      thumbnailUrl: info.thumbnailUrl,
      variants: variants,
    );
  }
}
