import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/download/download_engine.dart';
import '../../core/extraction/media_extractor.dart';
import '../../core/l10n/status_message.dart';
import '../../core/notifications/media_notification_service.dart';
import '../../core/notifications/notification_permission_service.dart';
import '../../core/storage/media_library_service.dart';
import '../../core/storage/media_save_service.dart';
import '../../services/tiktok/tiktok_extractor.dart';

final _galAlbum = albumNameForSource('TikTok');

class TikTokState {
  const TikTokState({
    this.fetching = false,
    this.downloading = false,
    this.paused = false,
    this.progress = 0,
    this.statusMessage,
    this.currentTask,
  });

  final bool fetching;
  final bool downloading;
  final bool paused;

  /// 0..1, only meaningful while [downloading].
  final double progress;
  final StatusMessage? statusMessage;

  /// Set while a download is running; used for pause/resume/cancel. Unlike
  /// YouTube, TikTok's formats are always muxed (see `TikTokExtractor`), so
  /// every download goes through this same `background_downloader` path —
  /// pause/resume always works, no separate merge-path state needed.
  final DownloadTask? currentTask;

  bool get busy => fetching || downloading;

  TikTokState copyWith({
    bool? fetching,
    bool? downloading,
    bool? paused,
    double? progress,
    StatusMessage? statusMessage,
    bool clearStatusMessage = false,
    DownloadTask? currentTask,
    bool clearCurrentTask = false,
  }) {
    return TikTokState(
      fetching: fetching ?? this.fetching,
      downloading: downloading ?? this.downloading,
      paused: paused ?? this.paused,
      progress: progress ?? this.progress,
      statusMessage: clearStatusMessage
          ? null
          : (statusMessage ?? this.statusMessage),
      currentTask: clearCurrentTask ? null : (currentTask ?? this.currentTask),
    );
  }
}

class TikTokController extends StateNotifier<TikTokState> {
  TikTokController({
    TikTokExtractor? extractor,
    DownloadEngine? downloadEngine,
    MediaSaveService? mediaSaveService,
    MediaNotificationService? mediaNotificationService,
    NotificationPermissionService? notificationPermissionService,
  }) : _extractor = extractor ?? TikTokExtractor(),
       _downloadEngine = downloadEngine ?? DownloadEngine(),
       _mediaSaveService = mediaSaveService ?? MediaSaveService(),
       _mediaNotificationService =
           mediaNotificationService ?? MediaNotificationService(),
       _notificationPermissionService =
           notificationPermissionService ?? NotificationPermissionService(),
       super(const TikTokState());

  final TikTokExtractor _extractor;
  final DownloadEngine _downloadEngine;
  final MediaSaveService _mediaSaveService;
  final MediaNotificationService _mediaNotificationService;
  final NotificationPermissionService _notificationPermissionService;

  /// Fetches format info for [url]. Returns null (and sets an error status
  /// message) on failure so the screen can decide whether to open the
  /// format sheet.
  Future<MediaInfo?> fetchInfo(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    if (state.busy) {
      state = state.copyWith(
        statusMessage: const StatusMessage(StatusMessageKey.downloadAlreadyInProgress),
      );
      return null;
    }
    if (!_extractor.canHandle(trimmed)) {
      state = state.copyWith(
        statusMessage: const StatusMessage(StatusMessageKey.notTiktokLink),
      );
      return null;
    }

    state = state.copyWith(fetching: true, clearStatusMessage: true);
    try {
      final info = await _extractor.extract(trimmed);
      state = state.copyWith(fetching: false);
      return info;
    } catch (error) {
      state = state.copyWith(
        fetching: false,
        statusMessage: error is ExtractionException
            ? StatusMessage.raw(error.message)
            : StatusMessage(
                StatusMessageKey.couldNotFetchVideo,
                error: error.toString(),
              ),
      );
      return null;
    }
  }

  /// Suggests a safe default base filename (no extension) from a video
  /// title — same sanitizer as `YouTubeController.suggestedFileName`, only
  /// strips characters actually illegal in a filename.
  static String suggestedFileName(String title) {
    final safeTitle = title
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
        .trim();
    final truncated = safeTitle.length > 80
        ? safeTitle.substring(0, 80)
        : safeTitle;
    return truncated.isEmpty ? 'tiktok' : truncated;
  }

  Future<void> downloadVariant(MediaVariant variant, String baseFileName) async {
    if (state.busy) {
      state = state.copyWith(
        statusMessage: const StatusMessage(StatusMessageKey.downloadAlreadyInProgress),
      );
      return;
    }
    // Best-effort: the download proceeds regardless of the outcome — denied
    // just means its notifications stay invisible.
    unawaited(_notificationPermissionService.ensureRequested());

    final filename = '$baseFileName.${variant.container}';
    final task = _downloadEngine.buildTask(
      url: variant.sourceUrl,
      filename: filename,
      headers: variant.requestHeaders,
    );

    state = state.copyWith(
      downloading: true,
      paused: false,
      progress: 0,
      clearStatusMessage: true,
      currentTask: task,
    );

    try {
      final result = await _downloadEngine.run(
        task,
        onStatus: (status) {
          state = state.copyWith(paused: status == TaskStatus.paused);
        },
        onProgress: (progress) {
          if (progress >= 0) {
            state = state.copyWith(progress: progress);
          }
        },
      );

      if (result.status == TaskStatus.complete) {
        final path = await _downloadEngine.filePath(task);
        await _saveAndNotify(path, filename);
        state = state.copyWith(
          downloading: false,
          paused: false,
          clearCurrentTask: true,
          statusMessage: const StatusMessage(StatusMessageKey.saved),
        );
      } else if (result.status == TaskStatus.canceled) {
        state = state.copyWith(
          downloading: false,
          paused: false,
          clearCurrentTask: true,
          statusMessage: const StatusMessage(StatusMessageKey.downloadCanceled),
        );
      } else {
        state = state.copyWith(
          downloading: false,
          paused: false,
          clearCurrentTask: true,
          statusMessage: StatusMessage(
            StatusMessageKey.downloadFailed,
            error: '${result.exception ?? result.status}',
          ),
        );
      }
    } catch (error) {
      state = state.copyWith(
        downloading: false,
        paused: false,
        clearCurrentTask: true,
        statusMessage: StatusMessage(
          StatusMessageKey.downloadFailed,
          error: error.toString(),
        ),
      );
    }
  }

  /// Saves the downloaded temp file to the gallery and posts a "download
  /// complete, tap to open" notification pointing at the saved item. A
  /// notification failure must never turn a successful save into a
  /// reported download failure, so it's isolated in its own try/catch —
  /// same pattern as `YouTubeController._saveAndNotify`.
  Future<void> _saveAndNotify(String path, String filename) async {
    final contentUri = await _mediaSaveService.saveVideo(
      path,
      album: _galAlbum,
    );
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    try {
      await _mediaNotificationService.notifyFileSaved(
        title: filename,
        contentUri: contentUri,
        mimeType: 'video/*',
      );
    } catch (_) {}
  }

  Future<void> togglePause() async {
    final task = state.currentTask;
    if (task == null) return;
    if (state.paused) {
      await _downloadEngine.resume(task);
    } else {
      await _downloadEngine.pause(task);
    }
  }

  Future<void> cancelDownload() async {
    final task = state.currentTask;
    if (task == null) return;
    await _downloadEngine.cancel(task);
  }
}

final tikTokControllerProvider =
    StateNotifierProvider<TikTokController, TikTokState>(
      (ref) => TikTokController(),
    );
