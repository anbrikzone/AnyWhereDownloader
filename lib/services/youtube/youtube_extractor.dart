import 'package:flutter/foundation.dart';

import '../../core/extraction/media_extractor.dart';
import '../../core/yt_dlp_engine/yt_dlp_engine.dart';

/// Thin wrapper over [YtDlpEngine] for YouTube specifically. Offers two
/// kinds of variants:
/// - Muxed (video+audio combined) formats — downloaded directly, one URL,
///   via `background_downloader` (supports pause/resume).
/// - Adaptive video-only formats at heights no muxed format covers — these
///   need a separate audio stream muxed in with ffmpeg, which only yt-dlp's
///   own `execute()` can do (see `MediaVariant.mergeFormatSelector`); no
///   pause/resume on that path, only cancel.
class YouTubeExtractor implements MediaExtractor {
  YouTubeExtractor({YtDlpEngine? engine}) : _engine = engine ?? YtDlpEngine();

  final YtDlpEngine _engine;

  @override
  ServiceType get serviceType => ServiceType.youtube;

  @override
  bool canHandle(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    return host == 'youtu.be' ||
        host == 'youtube.com' ||
        host == 'www.youtube.com' ||
        host == 'm.youtube.com' ||
        host == 'music.youtube.com';
  }

  @override
  Future<MediaInfo> extract(String url) async {
    final info = await _engine.getInfo(url);
    final duration = info.durationSeconds;

    final muxed = info.formats.where((f) => f.hasVideo && f.hasAudio).toList()
      ..sort((a, b) => b.height.compareTo(a.height));

    final seenHeights = <int>{};
    final entries = <(int, MediaVariant)>[];
    for (final format in muxed) {
      if (format.url == null) continue;
      if (!seenHeights.add(format.height)) continue;
      entries.add((
        format.height,
        MediaVariant(
          type: MediaVariantType.video,
          resolutionLabel: format.height > 0 ? '${format.height}p' : null,
          container: format.ext ?? 'mp4',
          approxSizeBytes: format.estimatedSizeBytes(duration),
          sourceUrl: format.url!,
          requestHeaders: format.httpHeaders,
        ),
      ));
    }

    // Adaptive video-only formats at heights no muxed format covers. These
    // need yt-dlp's own execute() to merge in a separate audio track.
    final audioOnly = info.formats.where((f) => f.hasAudio && !f.hasVideo).toList()
      ..sort((a, b) => b.tbrKbps.compareTo(a.tbrKbps));
    final bestAudioSize = audioOnly.isNotEmpty
        ? audioOnly.first.estimatedSizeBytes(duration)
        : null;

    final videoOnly = info.formats.where((f) => f.hasVideo && !f.hasAudio).toList()
      ..sort((a, b) => b.height.compareTo(a.height));
    for (final format in videoOnly) {
      if (format.formatId == null) continue;
      if (!seenHeights.add(format.height)) continue;
      final videoSize = format.estimatedSizeBytes(duration);
      final size = videoSize != null
          ? videoSize + (bestAudioSize ?? 0)
          : null;
      entries.add((
        format.height,
        MediaVariant(
          type: MediaVariantType.video,
          resolutionLabel: format.height > 0 ? '${format.height}p' : null,
          container: 'mp4',
          approxSizeBytes: size,
          sourceUrl: url,
          mergeFormatSelector: '${format.formatId}+bestaudio/best',
          durationSeconds: duration > 0 ? duration : null,
        ),
      ));
    }

    if (entries.isEmpty) {
      throw ExtractionException(
        'No downloadable format found for this video in this version.',
      );
    }

    entries.sort((a, b) => b.$1.compareTo(a.$1));
    final variants = entries.map((e) => e.$2).toList();

    // Audio-only options, appended after the video rows. Downloaded via
    // yt-dlp's own execute() (`-x --audio-format …`) in a foreground
    // service — the same path the adaptive-video merge uses.
    final hasAnyAudio = info.formats.any((f) => f.hasAudio);
    if (hasAnyAudio) {
      for (final kbps in const [320, 192, 128]) {
        variants.add(
          MediaVariant(
            type: MediaVariantType.audio,
            resolutionLabel: null,
            container: 'mp3',
            approxSizeBytes: duration > 0
                ? (kbps * 1000 ~/ 8) * duration
                : null,
            sourceUrl: url,
            durationSeconds: duration > 0 ? duration : null,
            audioSpec: AudioSpec(format: 'mp3', qualityKbps: kbps),
          ),
        );
      }
      variants.add(
        MediaVariant(
          type: MediaVariantType.audio,
          resolutionLabel: null,
          container: 'm4a',
          approxSizeBytes: bestAudioSize,
          sourceUrl: url,
          durationSeconds: duration > 0 ? duration : null,
          audioSpec: const AudioSpec(format: 'm4a'),
        ),
      );
    }

    // TEMP diagnostic — remove once the "320 kbps → video" bug is fixed.
    debugPrint(
      '[AWD] extract: hasAnyAudio=$hasAnyAudio variants='
      '${variants.map((v) => '${v.type.name}:${v.resolutionLabel ?? v.audioSpec?.qualityKbps ?? v.audioSpec?.format}').toList()}',
    );

    return MediaInfo(
      title: info.title ?? 'YouTube video',
      thumbnailUrl: info.thumbnailUrl,
      variants: variants,
    );
  }
}
