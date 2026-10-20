import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/download/download_engine.dart';
import '../../core/download/download_finalizer.dart';
import '../../core/download/download_registry.dart';
import '../../core/download/ytdlp_service_download.dart';
import '../../core/extraction/media_extractor.dart';
import '../../core/l10n/status_message.dart';
import '../../core/notifications/notification_permission_service.dart';
import '../../core/storage/media_library_service.dart';
import '../../core/yt_dlp_engine/yt_dlp_engine.dart';
import 'direct_download_service.dart';

class DirectDownloadState {
  const DirectDownloadState({
    this.fetching = false,
    this.downloading = false,
    this.paused = false,
    this.progress = 0,
    this.statusMessage,
    this.currentTask,
    this.mergeProcessId,
  });

  final bool fetching;
  final bool downloading;
  final bool paused;

  /// 0..1, only meaningful while [downloading].
  final double progress;
  final StatusMessage? statusMessage;

  /// Set while a direct (`background_downloader`) download runs — used for
  /// pause/resume/cancel.
  final DownloadTask? currentTask;

  /// Set instead while a yt-dlp *merge* download runs (a variant with
  /// `mergeFormatSelector`, e.g. an HLS-only Pinterest video) — cancel only.
  final String? mergeProcessId;

  bool get busy => fetching || downloading;

  /// Only the direct path can pause; the yt-dlp merge path can only cancel.
  bool get canPause => currentTask != null;

  DirectDownloadState copyWith({
    bool? fetching,
    bool? downloading,
    bool? paused,
    double? progress,
    StatusMessage? statusMessage,
    bool clearStatusMessage = false,
    DownloadTask? currentTask,
    bool clearCurrentTask = false,
    String? mergeProcessId,
    bool clearMergeProcessId = false,
  }) {
    return DirectDownloadState(
      fetching: fetching ?? this.fetching,
      downloading: downloading ?? this.downloading,
      paused: paused ?? this.paused,
      progress: progress ?? this.progress,
      statusMessage: clearStatusMessage
          ? null
          : (statusMessage ?? this.statusMessage),
      currentTask: clearCurrentTask ? null : (currentTask ?? this.currentTask),
      mergeProcessId: clearMergeProcessId
          ? null
          : (mergeProcessId ?? this.mergeProcessId),
    );
  }
}

/// Fetch → pick a variant → download → save, for one [DirectDownloadService].
class DirectDownloadController extends StateNotifier<DirectDownloadState> {
  DirectDownloadController(
    this.service, {
    MediaExtractor? extractor,
    DownloadEngine? downloadEngine,
    DownloadFinalizer? downloadFinalizer,
    NotificationPermissionService? notificationPermissionService,
    YtDlpServiceDownload? serviceDownload,
    DownloadRegistry? registry,
  }) : _extractor = extractor ?? service.createExtractor(),
       _downloadEngine = downloadEngine ?? DownloadEngine(),
       _downloadFinalizer = downloadFinalizer ?? DownloadFinalizer.instance,
       _serviceDownload = serviceDownload ?? YtDlpServiceDownload(),
       _notificationPermissionService =
           notificationPermissionService ?? NotificationPermissionService(),
       _downloads = registry,
       _galAlbum = relativePathForSource(service.librarySource),
       super(const DirectDownloadState());

  final DirectDownloadService service;
  final MediaExtractor _extractor;
  final DownloadEngine _downloadEngine;
  final DownloadFinalizer _downloadFinalizer;
  final YtDlpServiceDownload _serviceDownload;
  final NotificationPermissionService _notificationPermissionService;
  final String _galAlbum;

  /// Where downloads are reported for the Downloads screen; null in tests
  /// that don't care.
  final DownloadRegistry? _downloads;

  /// The registry id of the download in flight, if any.
  String? _trackedId;

  /// Set by [cancelDownload] to stop [downloadItems] before its next item.
  bool _batchCanceled = false;

  bool canHandle(String url) => _extractor.canHandle(url);

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
      state = state.copyWith(statusMessage: StatusMessage(service.notHandledKey));
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
            ? StatusMessage.extraction(error)
            : StatusMessage(
                service.fetchFailedKey,
                error: error.toString(),
                suggestYtDlpUpdate: looksLikeOutdatedYtDlp(error),
              ),
      );
      return null;
    }
  }

  /// Suggests a safe default base filename (no extension) from a post title
  /// — same sanitizer as `YouTubeController.suggestedFileName`, only strips
  /// characters actually illegal in a filename.
  String suggestedFileName(String title) {
    final safeTitle = title
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
        .trim();
    final truncated = safeTitle.length > 80
        ? safeTitle.substring(0, 80)
        : safeTitle;
    return truncated.isEmpty ? service.fallbackFileName : truncated;
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
    if (variant.mergeFormatSelector != null) {
      return _downloadViaMerge(variant, filename);
    }
    state = state.copyWith(
      downloading: true,
      paused: false,
      progress: 0,
      clearStatusMessage: true,
    );
    final outcome = await _runDirect(
      variant,
      filename,
      onProgress: (p) => state = state.copyWith(progress: p),
    );
    _finishDownload(outcome.message, contentUri: outcome.contentUri);
  }

  /// Downloads several items of one post (an Instagram carousel) one after
  /// another, as `<base>_01.jpg`, `<base>_02.jpg`, … — each its own entry on
  /// the Downloads screen, but only the last one posts a "saved"
  /// notification. Cancel stops the whole batch; a failed item doesn't.
  Future<void> downloadItems(List<MediaItem> items, String baseFileName) async {
    if (items.length == 1) {
      return downloadVariant(items.single.variant, baseFileName);
    }
    if (state.busy) {
      state = state.copyWith(
        statusMessage: const StatusMessage(StatusMessageKey.downloadAlreadyInProgress),
      );
      return;
    }
    if (items.isEmpty) return;
    unawaited(_notificationPermissionService.ensureRequested());

    _batchCanceled = false;
    state = state.copyWith(
      downloading: true,
      paused: false,
      progress: 0,
      clearStatusMessage: true,
    );
    final width = items.length.toString().length.clamp(2, 9);
    var saved = 0;
    var failed = 0;
    for (final (i, item) in items.indexed) {
      if (_batchCanceled) break;
      final variant = item.variant;
      final number = (i + 1).toString().padLeft(width, '0');
      final outcome = await _runDirect(
        variant,
        '${baseFileName}_$number.${variant.container}',
        notify: i == items.length - 1,
        onProgress: (p) =>
            state = state.copyWith(progress: (i + p) / items.length),
      );
      if (outcome.message.key == StatusMessageKey.saved) {
        saved++;
      } else if (outcome.message.key == StatusMessageKey.downloadCanceled) {
        _batchCanceled = true;
      } else {
        failed++;
      }
    }

    final StatusMessage message;
    if (_batchCanceled && saved == 0) {
      message = const StatusMessage(StatusMessageKey.downloadCanceled);
    } else {
      message = StatusMessage(
        StatusMessageKey.postItemsSaved,
        count: saved,
        failedCount: failed,
      );
    }
    _batchCanceled = false;
    state = state.copyWith(
      downloading: false,
      paused: false,
      clearCurrentTask: true,
      statusMessage: message,
    );
  }

  /// One direct (`background_downloader`) download → gallery save, tracked
  /// on the Downloads screen. Leaves `downloading` to the caller.
  Future<({StatusMessage message, String? contentUri})> _runDirect(
    MediaVariant variant,
    String filename, {
    bool notify = true,
    required void Function(double progress) onProgress,
  }) async {
    final isImage = variant.type == MediaVariantType.image;
    final task = _downloadEngine.buildTask(
      url: variant.sourceUrl,
      filename: filename,
      headers: variant.requestHeaders,
      saveTo: GallerySaveSpec(
        kind: isImage ? SavedMediaKind.image : SavedMediaKind.video,
        album: _galAlbum,
        notifyTitle: filename,
        notify: notify,
      ),
    );

    state = state.copyWith(paused: false, currentTask: task);
    _track(
      task.taskId,
      filename,
      isImage ? DownloadKind.image : DownloadKind.video,
      canPause: true,
    );

    StatusMessage message;
    String? contentUri;
    try {
      final result = await _downloadEngine.run(
        task,
        onStatus: (status) {
          state = state.copyWith(paused: status == TaskStatus.paused);
          _downloads?.setPaused(task.taskId, status == TaskStatus.paused);
        },
        onProgress: (progress) {
          if (progress >= 0) {
            onProgress(progress);
            _downloads?.progress(task.taskId, progress);
          }
        },
      );

      if (result.status == TaskStatus.complete) {
        contentUri = await _downloadFinalizer.finalize(task);
        message = const StatusMessage(StatusMessageKey.saved);
      } else if (result.status == TaskStatus.canceled) {
        message = const StatusMessage(StatusMessageKey.downloadCanceled);
      } else {
        message = StatusMessage(
          StatusMessageKey.downloadFailed,
          error: '${result.exception ?? result.status}',
        );
      }
    } catch (error) {
      message = StatusMessage(
        StatusMessageKey.downloadFailed,
        error: error.toString(),
      );
    }
    state = state.copyWith(paused: false, clearCurrentTask: true);
    _untrack(message, contentUri: contentUri);
    return (message: message, contentUri: contentUri);
  }

  /// yt-dlp downloads + muxes the streams itself inside the foreground
  /// service — same path as YouTube's high-res downloads (see
  /// [YtDlpServiceDownload]). No pause, only cancel.
  Future<void> _downloadViaMerge(MediaVariant variant, String filename) async {
    final processId = YtDlpServiceDownload.newProcessId();
    state = state.copyWith(
      downloading: true,
      paused: false,
      progress: 0,
      clearStatusMessage: true,
      clearCurrentTask: true,
      mergeProcessId: processId,
    );
    _track(processId, filename, DownloadKind.video, canPause: false);
    final outcome = await _serviceDownload.merge(
      variant: variant,
      filename: filename,
      album: _galAlbum,
      processId: processId,
      onProgress: (update) {
        state = state.copyWith(progress: update.progress);
        _downloads?.progress(processId, update.progress);
      },
    );
    _finishDownload(outcome.message, contentUri: outcome.contentUri);
  }

  void _track(
    String id,
    String title,
    DownloadKind kind, {
    required bool canPause,
  }) {
    _trackedId = id;
    _downloads?.begin(
      id: id,
      source: service.title,
      title: title,
      kind: kind,
      controls: DownloadControls(
        cancel: cancelDownload,
        togglePause: canPause ? togglePause : null,
      ),
    );
  }

  void _finishDownload(StatusMessage message, {String? contentUri}) {
    state = state.copyWith(
      downloading: false,
      paused: false,
      clearCurrentTask: true,
      clearMergeProcessId: true,
      statusMessage: message,
    );
    _untrack(message, contentUri: contentUri);
  }

  /// Reports the tracked download's outcome to the Downloads screen.
  void _untrack(StatusMessage message, {String? contentUri}) {
    final id = _trackedId;
    _trackedId = null;
    if (id != null) _downloads?.finish(id, message, contentUri: contentUri);
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
    if (state.downloading) _batchCanceled = true;
    final task = state.currentTask;
    if (task != null) {
      await _downloadEngine.cancel(task);
      return;
    }
    final processId = state.mergeProcessId;
    if (processId != null) {
      await _serviceDownload.cancel(processId);
    }
  }
}

/// One long-lived controller per service (not auto-disposed, so a download
/// keeps its state while the screen is closed), keyed by [ServiceType].
/// Only the types [DirectDownloadService.of] knows are valid keys.
final directDownloadControllerProvider =
    StateNotifierProvider.family<
      DirectDownloadController,
      DirectDownloadState,
      ServiceType
    >(
      (ref, type) => DirectDownloadController(
        DirectDownloadService.of(type)!,
        registry: ref.read(downloadRegistryProvider.notifier),
      ),
    );
