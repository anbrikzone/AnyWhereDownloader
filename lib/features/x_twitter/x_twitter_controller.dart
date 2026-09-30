import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/download/download_engine.dart';
import '../../core/download/download_finalizer.dart';
import '../../core/extraction/media_extractor.dart';
import '../../core/l10n/status_message.dart';
import '../../core/notifications/notification_permission_service.dart';
import '../../core/storage/media_library_service.dart';
import '../../services/x_twitter/x_twitter_extractor.dart';

// Not 'X/Twitter' — that `/` isn't just cosmetic here. `relativePathForSource`'s
// result ends up as a MediaStore `RELATIVE_PATH` (see `MediaSaveService`),
// where Android treats any `/` as a real folder separator: an unsanitized
// literal slash inside the *source* name (as opposed to the deliberate
// structural slash `relativePathForSource` itself adds between the shared
// root and the service) created a literal nested "AnyWhereDownloader" /
// "X" / "Twitter" folder chain instead of one "X-Twitter" folder, so its
// bucket name was just "Twitter" — never matching `parseLibraryRelativePath`.
// Found on-device, not guessed.
final _galAlbum = relativePathForSource('X-Twitter');

class XTwitterState {
  const XTwitterState({
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

  /// Set while a download is running; used for pause/resume/cancel. Like
  /// TikTok (and unlike YouTube), X/Twitter's formats are always muxed (see
  /// `XTwitterExtractor`), so every download goes through this same
  /// `background_downloader` path — pause/resume always works.
  final DownloadTask? currentTask;

  bool get busy => fetching || downloading;

  XTwitterState copyWith({
    bool? fetching,
    bool? downloading,
    bool? paused,
    double? progress,
    StatusMessage? statusMessage,
    bool clearStatusMessage = false,
    DownloadTask? currentTask,
    bool clearCurrentTask = false,
  }) {
    return XTwitterState(
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

class XTwitterController extends StateNotifier<XTwitterState> {
  XTwitterController({
    XTwitterExtractor? extractor,
    DownloadEngine? downloadEngine,
    DownloadFinalizer? downloadFinalizer,
    NotificationPermissionService? notificationPermissionService,
  }) : _extractor = extractor ?? XTwitterExtractor(),
       _downloadEngine = downloadEngine ?? DownloadEngine(),
       _downloadFinalizer = downloadFinalizer ?? DownloadFinalizer.instance,
       _notificationPermissionService =
           notificationPermissionService ?? NotificationPermissionService(),
       super(const XTwitterState());

  final XTwitterExtractor _extractor;
  final DownloadEngine _downloadEngine;
  final DownloadFinalizer _downloadFinalizer;
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
        statusMessage: const StatusMessage(StatusMessageKey.notXTwitterLink),
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
                StatusMessageKey.couldNotFetchPost,
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
    return truncated.isEmpty ? 'x_twitter' : truncated;
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
      saveTo: GallerySaveSpec(
        kind: variant.type == MediaVariantType.image
            ? SavedMediaKind.image
            : SavedMediaKind.video,
        album: _galAlbum,
        notifyTitle: filename,
      ),
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
        await _downloadFinalizer.finalize(task);
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

final xTwitterControllerProvider =
    StateNotifierProvider<XTwitterController, XTwitterState>(
      (ref) => XTwitterController(),
    );
