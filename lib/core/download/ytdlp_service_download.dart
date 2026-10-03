import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../extraction/media_extractor.dart';
import '../l10n/status_message.dart';
import '../storage/media_save_service.dart';
import '../yt_dlp_engine/yt_dlp_engine.dart';

/// What a service download ended with: the message the controller shows,
/// plus the saved MediaStore item when it completed.
class ServiceDownloadOutcome {
  const ServiceDownloadOutcome(this.message, {this.contentUri});

  final StatusMessage message;
  final String? contentUri;
}

/// Plumbing shared by every *single* download that runs inside the native
/// `YtDlpDownloadService` (yt-dlp `execute()` in a foreground service) —
/// a merge (adaptive video + audio, muxed by ffmpeg: YouTube high-res,
/// HLS-only Pinterest) or an audio extract (YouTube MP3/M4A). The service
/// saves the result to MediaStore and posts the tap-to-open notification
/// itself, so the caller only tracks progress and shows the outcome.
/// These downloads can be canceled, never paused.
///
/// Controllers keep their own state shape; this owns the per-download work
/// dir, the MediaStore relative path, the engine call and the
/// result → [StatusMessage] mapping. Playlists (multi-item progress, their
/// own summary) stay in `YouTubeController`.
class YtDlpServiceDownload {
  YtDlpServiceDownload({
    YtDlpEngine? engine,
    MediaSaveService? mediaSaveService,
    Future<Directory> Function()? tempDirectory,
  }) : _injectedEngine = engine,
       _mediaSaveService = mediaSaveService ?? MediaSaveService(),
       _tempDirectory = tempDirectory ?? getTemporaryDirectory;

  final YtDlpEngine? _injectedEngine;
  final MediaSaveService _mediaSaveService;
  final Future<Directory> Function() _tempDirectory;

  /// Lazy: constructing the real engine binds its platform channel, which
  /// tests that never start a service download don't need.
  YtDlpEngine get _engine => _injectedEngine ?? YtDlpEngine();

  /// A fresh id for one service download — pass it to [merge]/[audio] and,
  /// to stop it, [cancel].
  static String newProcessId() =>
      DateTime.now().microsecondsSinceEpoch.toString();

  /// Downloads [variant] (which has a `mergeFormatSelector`) into
  /// `<root>/<album>`. Never throws — a failure comes back as a
  /// `downloadFailed` outcome.
  Future<ServiceDownloadOutcome> merge({
    required MediaVariant variant,
    required String filename,
    required String album,
    required String processId,
    void Function(MergeProgress progress)? onProgress,
  }) {
    return _run(() async {
      final outputPath = await _workFilePath(processId, filename);
      final relativePath = await _mediaSaveService.resolveRelativePath(
        album,
        isAudio: false,
      );
      return _engine.downloadMerge(
        url: variant.sourceUrl,
        formatSelector: variant.mergeFormatSelector!,
        outputPath: outputPath,
        processId: processId,
        relativePath: relativePath,
        durationSeconds: variant.durationSeconds,
        onProgress: onProgress,
      );
    });
  }

  /// Extracts [variant]'s audio (which has an `audioSpec`) into the audio
  /// root (`Music/<album>` by default). Never throws, like [merge].
  Future<ServiceDownloadOutcome> audio({
    required MediaVariant variant,
    required String filename,
    required String album,
    required String processId,
    void Function(MergeProgress progress)? onProgress,
  }) {
    final spec = variant.audioSpec!;
    return _run(() async {
      final outputPath = await _workFilePath(processId, filename);
      final relativePath = await _mediaSaveService.resolveRelativePath(
        album,
        isAudio: true,
      );
      return _engine.downloadAudio(
        url: variant.sourceUrl,
        audioFormat: spec.format,
        audioQualityKbps: spec.qualityKbps ?? 0,
        outputPath: outputPath,
        processId: processId,
        relativePath: relativePath,
        durationSeconds: variant.durationSeconds,
        onProgress: onProgress,
      );
    });
  }

  Future<void> cancel(String processId) => _engine.cancelDownload(processId);

  Future<ServiceDownloadOutcome> _run(
    Future<MergeDownloadResult> Function() start,
  ) async {
    try {
      final result = await start();
      return switch (result.status) {
        // Already saved + notified by the native service.
        'complete' => ServiceDownloadOutcome(
          const StatusMessage(StatusMessageKey.saved),
          contentUri: result.contentUri,
        ),
        'canceled' => const ServiceDownloadOutcome(
          StatusMessage(StatusMessageKey.downloadCanceled),
        ),
        _ => ServiceDownloadOutcome(
          StatusMessage(
            StatusMessageKey.downloadFailed,
            error: result.error ?? result.status,
          ),
        ),
      };
    } catch (error) {
      return ServiceDownloadOutcome(
        StatusMessage(StatusMessageKey.downloadFailed, error: error.toString()),
      );
    }
  }

  /// `<tmp>/ytdlp_<processId>/<filename>` — a per-download work dir the
  /// native service deletes wholesale when it finishes (including yt-dlp's
  /// `.part`/`.fNNN` leftovers after a cancel or error).
  Future<String> _workFilePath(String processId, String filename) async {
    final tempDir = await _tempDirectory();
    final dir = Directory('${tempDir.path}/ytdlp_$processId');
    await dir.create(recursive: true);
    return '${dir.path}/$filename';
  }
}
