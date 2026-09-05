import 'dart:async';

import 'package:flutter/services.dart';

/// A single format entry as reported by yt-dlp, close to its own shape —
/// no YouTube/Instagram/X-specific interpretation happens here. That's the
/// job of each service's extractor (e.g. `services/youtube/youtube_extractor.dart`).
class RawFormat {
  RawFormat({
    required this.formatId,
    required this.ext,
    required this.vcodec,
    required this.acodec,
    required this.height,
    required this.url,
    required this.fileSizeBytes,
    required this.httpHeaders,
    required this.tbrKbps,
  });

  factory RawFormat.fromMap(Map<Object?, Object?> map) {
    final headersRaw = map['httpHeaders'];
    Map<String, String>? headers;
    if (headersRaw is Map) {
      headers = headersRaw.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    }
    final fileSize = map['fileSize'] as int? ?? 0;
    final fileSizeApprox = map['fileSizeApproximate'] as int? ?? 0;
    return RawFormat(
      formatId: map['formatId'] as String?,
      ext: map['ext'] as String?,
      vcodec: map['vcodec'] as String?,
      acodec: map['acodec'] as String?,
      height: map['height'] as int? ?? 0,
      url: map['url'] as String?,
      fileSizeBytes: fileSize > 0 ? fileSize : fileSizeApprox,
      httpHeaders: headers,
      tbrKbps: (map['tbr'] as num?)?.toDouble() ?? 0,
    );
  }

  final String? formatId;
  final String? ext;
  final String? vcodec;
  final String? acodec;
  final int height;
  final String? url;
  final int fileSizeBytes;
  final Map<String, String>? httpHeaders;

  /// Total bitrate in kbps, as reported by yt-dlp. Used to estimate a size
  /// when yt-dlp doesn't report `filesize`/`filesize_approx` for this
  /// format (common for adaptive/DASH formats).
  final double tbrKbps;

  bool get hasVideo => vcodec != null && vcodec != 'none';
  bool get hasAudio => acodec != null && acodec != 'none';

  /// [fileSizeBytes] if yt-dlp reported one, otherwise a rough estimate
  /// from bitrate × [durationSeconds] — still better than showing nothing.
  int? estimatedSizeBytes(int durationSeconds) {
    if (fileSizeBytes > 0) return fileSizeBytes;
    if (tbrKbps > 0 && durationSeconds > 0) {
      return ((tbrKbps * 1000) / 8 * durationSeconds).round();
    }
    return null;
  }
}

class RawVideoInfo {
  RawVideoInfo({
    required this.title,
    required this.thumbnailUrl,
    required this.durationSeconds,
    required this.formats,
    required this.ext,
    required this.directUrl,
  });

  factory RawVideoInfo.fromMap(Map<Object?, Object?> map) {
    final formatsRaw = map['formats'];
    final formats = <RawFormat>[];
    if (formatsRaw is List) {
      for (final entry in formatsRaw) {
        if (entry is Map) {
          formats.add(RawFormat.fromMap(entry.cast<Object?, Object?>()));
        }
      }
    }
    return RawVideoInfo(
      title: map['title'] as String?,
      thumbnailUrl: map['thumbnail'] as String?,
      durationSeconds: map['duration'] as int? ?? 0,
      formats: formats,
      ext: map['ext'] as String?,
      directUrl: map['url'] as String?,
    );
  }

  final String? title;
  final String? thumbnailUrl;
  final int durationSeconds;
  final List<RawFormat> formats;

  /// yt-dlp's top-level `ext` — an image extension (`jpg`/`webp`/…) marks a
  /// photo post rather than a video.
  final String? ext;

  /// yt-dlp's top-level `url` — for a photo post this is the direct image
  /// URL. For a video post it's usually null (the URLs live in [formats]).
  final String? directUrl;
}

/// Outcome of a foreground-service yt-dlp `execute()` download — the merge
/// path ([YtDlpEngine.downloadMerge]) and the audio-extract path
/// ([YtDlpEngine.downloadAudio]) share this shape.
class MergeDownloadResult {
  MergeDownloadResult({required this.status, this.path, this.error});

  factory MergeDownloadResult.fromMap(Map<Object?, Object?> map) {
    return MergeDownloadResult(
      status: map['status'] as String? ?? 'error',
      path: map['path'] as String?,
      error: map['error'] as String?,
    );
  }

  /// One of `complete`, `canceled`, `error`.
  final String status;
  final String? path;
  final String? error;
}

/// One progress update for a foreground-service yt-dlp download. [progress]
/// (0..1) is already combined into one continuous value on the native side.
/// [phase] tells the UI which part is running:
/// - merge path: `video`, `audio`, `merging`
/// - audio-extract path: `audio`, `converting`
class MergeProgress {
  MergeProgress({required this.progress, required this.phase});

  final double progress;
  final String phase;
}

/// Thin wrapper over the native yt-dlp bridge (see
/// `android/app/src/main/kotlin/.../YtDlpBridge.kt`). Shared by every
/// URL-based extractor (YouTube now, Instagram/X later) — nothing
/// service-specific belongs here.
///
/// A singleton: it registers a `setMethodCallHandler` to receive
/// native→Dart progress/completion calls for merge downloads (see
/// `YtDlpDownloadService.kt`), and only one handler can be active on a
/// channel at a time — multiple instances would clobber each other's.
class YtDlpEngine {
  factory YtDlpEngine() => _instance;

  YtDlpEngine._internal() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static final YtDlpEngine _instance = YtDlpEngine._internal();

  static const _channel = MethodChannel('anywhere_downloader/yt_dlp');

  final _progressCallbacks = <String, void Function(MergeProgress)>{};
  final _completers = <String, Completer<MergeDownloadResult>>{};

  Future<RawVideoInfo> getInfo(String url) async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'getInfo',
      {'url': url},
    );
    if (result == null) {
      throw StateError('yt-dlp returned no data for $url');
    }
    return RawVideoInfo.fromMap(result);
  }

  /// Starts a merge download (video-only + audio-only, combined by yt-dlp's
  /// own `execute()` inside an Android foreground service — see
  /// `YtDlpDownloadService.kt`) and returns once it truly finishes
  /// (complete/canceled/error). [onProgress] receives combined progress
  /// updates while it runs. Unlike the `background_downloader` path, this
  /// cannot be paused — only canceled (via [cancelDownload]).
  Future<MergeDownloadResult> downloadMerge({
    required String url,
    required String formatSelector,
    required String outputPath,
    required String processId,
    int? durationSeconds,
    void Function(MergeProgress progress)? onProgress,
  }) async {
    final completer = Completer<MergeDownloadResult>();
    _completers[processId] = completer;
    if (onProgress != null) {
      _progressCallbacks[processId] = onProgress;
    }
    await _channel.invokeMethod('startMergeDownload', {
      'url': url,
      'formatSelector': formatSelector,
      'outputPath': outputPath,
      'processId': processId,
      'durationSeconds': durationSeconds ?? 0,
    });
    return completer.future;
  }

  /// Starts an audio-only download (yt-dlp `-x --audio-format …` inside the
  /// same Android foreground service as [downloadMerge]) and returns once it
  /// finishes. [audioFormat] is `mp3` or `m4a`; [audioQualityKbps] is the
  /// target bitrate for an mp3 preset, or 0 to keep the source bitrate.
  /// No pause/resume — only [cancelDownload].
  Future<MergeDownloadResult> downloadAudio({
    required String url,
    required String audioFormat,
    required int audioQualityKbps,
    required String outputPath,
    required String processId,
    int? durationSeconds,
    void Function(MergeProgress progress)? onProgress,
  }) async {
    final completer = Completer<MergeDownloadResult>();
    _completers[processId] = completer;
    if (onProgress != null) {
      _progressCallbacks[processId] = onProgress;
    }
    await _channel.invokeMethod('startAudioDownload', {
      'url': url,
      'audioFormat': audioFormat,
      'audioQuality': audioQualityKbps,
      'outputPath': outputPath,
      'processId': processId,
      'durationSeconds': durationSeconds ?? 0,
    });
    return completer.future;
  }

  Future<void> cancelDownload(String processId) {
    return _channel.invokeMethod('cancelDownload', {'processId': processId});
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, Object?>();
    final processId = args?['processId'] as String?;
    if (processId == null) return;

    switch (call.method) {
      case 'onDownloadProgress':
        final progress = (args!['progress'] as num?)?.toDouble() ?? 0;
        final phase = args['phase'] as String? ?? 'video';
        _progressCallbacks[processId]?.call(
          MergeProgress(progress: progress / 100.0, phase: phase),
        );
      case 'onDownloadStatus':
        final completer = _completers.remove(processId);
        _progressCallbacks.remove(processId);
        completer?.complete(MergeDownloadResult.fromMap(args!));
    }
  }
}
