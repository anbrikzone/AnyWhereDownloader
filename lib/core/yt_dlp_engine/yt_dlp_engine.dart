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
/// - playlist path: `playlist` (with [subPhase] / [itemIndex] filled in for
///   the current entry)
class MergeProgress {
  MergeProgress({
    required this.progress,
    required this.phase,
    this.subPhase,
    this.itemIndex,
    this.itemProgress,
  });

  final double progress;
  final String phase;

  /// Playlist path only: what's happening to the current entry —
  /// `video` / `audio` / `merging` / `converting`.
  final String? subPhase;

  /// Playlist path only: 1-based index of the entry being processed.
  final int? itemIndex;

  /// Playlist path only: 0..1 progress of the current entry's sub-download.
  final double? itemProgress;
}

/// One lightweight playlist entry from `getPlaylistInfo` (a `--flat-playlist`
/// enumeration — no formats/sizes, just enough to list and pick).
class PlaylistEntryInfo {
  PlaylistEntryInfo({
    required this.position,
    required this.id,
    required this.title,
    required this.url,
    this.durationSeconds,
  });

  factory PlaylistEntryInfo.fromMap(Map<Object?, Object?> map) {
    return PlaylistEntryInfo(
      position: (map['position'] as num?)?.toInt() ?? 0,
      id: map['id'] as String? ?? '',
      title: (map['title'] as String? ?? '').trim(),
      url: map['url'] as String? ?? '',
      durationSeconds: (map['duration'] as num?)?.toInt(),
    );
  }

  final int position;
  final String id;
  final String title;
  final String url;
  final int? durationSeconds;
}

class PlaylistInfoResult {
  PlaylistInfoResult({required this.title, required this.entries});

  factory PlaylistInfoResult.fromMap(Map<Object?, Object?> map) {
    final raw = map['entries'];
    final entries = <PlaylistEntryInfo>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          entries.add(PlaylistEntryInfo.fromMap(e.cast<Object?, Object?>()));
        }
      }
    }
    return PlaylistInfoResult(
      title: (map['title'] as String? ?? '').trim(),
      entries: entries,
    );
  }

  final String title;
  final List<PlaylistEntryInfo> entries;
}

/// Fired once per playlist item that finished downloading — [path] is the
/// final on-disk file, ready to be saved to MediaStore and then deleted.
class PlaylistItemDone {
  PlaylistItemDone({
    required this.index,
    required this.count,
    required this.path,
  });

  final int index;
  final int count;
  final String path;
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
  final _playlistItemCallbacks = <String, void Function(PlaylistItemDone)>{};

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

  /// Enumerates a playlist's entries (`--flat-playlist`, no per-video
  /// extraction — fast). Throws on failure.
  Future<PlaylistInfoResult> getPlaylistInfo(String url) async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'getPlaylistInfo',
      {'url': url},
    );
    if (result == null) {
      throw StateError('yt-dlp returned no playlist data for $url');
    }
    return PlaylistInfoResult.fromMap(result);
  }

  /// Downloads a playlist (or the [playlistItems] subset — a yt-dlp
  /// `--playlist-items` spec like `"1,3,5-7"`, or null for all) in one
  /// foreground-service `execute()`. [onItem] fires as each entry's file
  /// lands so the caller can save it and free the temp copy; [onProgress]
  /// carries the overall item N-of-M progress. No pause — only
  /// [cancelDownload]. Pass exactly one of [formatSelector] (video) or
  /// [audioFormat] (`mp3`/`m4a`, audio-only).
  Future<MergeDownloadResult> downloadPlaylist({
    required String url,
    required String outputDir,
    required String processId,
    String? formatSelector,
    String? audioFormat,
    int audioQualityKbps = 0,
    String? playlistItems,
    int expectedCount = 0,
    void Function(MergeProgress progress)? onProgress,
    void Function(PlaylistItemDone item)? onItem,
  }) async {
    final completer = Completer<MergeDownloadResult>();
    _completers[processId] = completer;
    if (onProgress != null) _progressCallbacks[processId] = onProgress;
    if (onItem != null) _playlistItemCallbacks[processId] = onItem;
    await _channel.invokeMethod('startPlaylistDownload', {
      'url': url,
      'outputDir': outputDir,
      'processId': processId,
      'formatSelector': formatSelector,
      'audioFormat': audioFormat,
      'audioQuality': audioQualityKbps,
      'playlistItems': playlistItems,
      'expectedCount': expectedCount,
    });
    return completer.future;
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
          MergeProgress(
            progress: progress / 100.0,
            phase: phase,
            subPhase: args['subPhase'] as String?,
            itemIndex: (args['itemIndex'] as num?)?.toInt(),
            itemProgress: (args['itemProgress'] as num?) == null
                ? null
                : (args['itemProgress'] as num).toDouble() / 100.0,
          ),
        );
      case 'onPlaylistItem':
        final path = args!['path'] as String? ?? '';
        if (path.isNotEmpty) {
          _playlistItemCallbacks[processId]?.call(
            PlaylistItemDone(
              index: (args['index'] as num?)?.toInt() ?? 0,
              count: (args['count'] as num?)?.toInt() ?? 0,
              path: path,
            ),
          );
        }
      case 'onDownloadStatus':
        final completer = _completers.remove(processId);
        _progressCallbacks.remove(processId);
        _playlistItemCallbacks.remove(processId);
        completer?.complete(MergeDownloadResult.fromMap(args!));
    }
  }
}
