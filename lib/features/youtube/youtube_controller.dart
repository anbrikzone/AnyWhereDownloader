import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/download/download_engine.dart';
import '../../core/extraction/media_extractor.dart';
import '../../core/l10n/status_message.dart';
import '../../core/notifications/media_notification_service.dart';
import '../../core/notifications/notification_permission_service.dart';
import '../../core/storage/media_library_service.dart';
import '../../core/storage/media_save_service.dart';
import '../../core/yt_dlp_engine/yt_dlp_engine.dart';
import '../../services/youtube/youtube_extractor.dart';
import '../../services/youtube/youtube_playlist.dart';

final _galAlbum = albumNameForSource('YouTube');

class YouTubeState {
  const YouTubeState({
    this.fetching = false,
    this.downloading = false,
    this.paused = false,
    this.canPause = false,
    this.progress = 0,
    this.statusMessage,
    this.currentTask,
    this.mergeProcessId,
    this.downloadPhase,
    this.mergeDurationKnown = false,
    this.playlistTotal,
    this.playlistSaved = 0,
    this.playlistFailed = 0,
    this.playlistCurrentIndex = 0,
    this.playlistItemPhase,
    this.playlistItemProgress = 0,
  });

  final bool fetching;
  final bool downloading;
  final bool paused;

  /// Whether the current download supports pause/resume — only true for
  /// the direct/progressive (`background_downloader`) path, not the merge
  /// (adaptive, yt-dlp `execute()`) path.
  final bool canPause;

  /// 0..1, only meaningful while [downloading].
  final double progress;
  final StatusMessage? statusMessage;

  /// Set while a direct/progressive download is running; used for
  /// pause/resume/cancel.
  final DownloadTask? currentTask;

  /// Set while a merge download is running; used for cancel.
  final String? mergeProcessId;

  /// Only meaningful for a merge download: `video`, `audio`, or `merging`
  /// — tells the UI which of the two sub-downloads (or the final mux) is
  /// currently running, since [progress] alone would otherwise look like
  /// it resets partway through.
  final String? downloadPhase;

  /// Whether the source video's duration was known when the current merge
  /// download started — only then does the "merging" phase have a real 0-99%
  /// progress value (from ffmpeg's own mux output) instead of needing an
  /// indeterminate spinner.
  final bool mergeDurationKnown;

  /// Playlist download (`downloadPhase == 'playlist'`): how many items were
  /// selected, how many have been saved / failed so far, which entry is
  /// being processed now (1-based) and what's happening to it
  /// (`video` / `audio` / `merging` / `converting`).
  final int? playlistTotal;
  final int playlistSaved;
  final int playlistFailed;
  final int playlistCurrentIndex;
  final String? playlistItemPhase;

  /// 0..1 progress of the current playlist entry's sub-download.
  final double playlistItemProgress;

  bool get busy => fetching || downloading;

  YouTubeState copyWith({
    bool? fetching,
    bool? downloading,
    bool? paused,
    bool? canPause,
    double? progress,
    StatusMessage? statusMessage,
    bool clearStatusMessage = false,
    DownloadTask? currentTask,
    bool clearCurrentTask = false,
    String? mergeProcessId,
    bool clearMergeProcessId = false,
    String? downloadPhase,
    bool clearDownloadPhase = false,
    bool? mergeDurationKnown,
    int? playlistTotal,
    bool clearPlaylist = false,
    int? playlistSaved,
    int? playlistFailed,
    int? playlistCurrentIndex,
    String? playlistItemPhase,
    double? playlistItemProgress,
  }) {
    return YouTubeState(
      fetching: fetching ?? this.fetching,
      downloading: downloading ?? this.downloading,
      paused: paused ?? this.paused,
      canPause: canPause ?? this.canPause,
      progress: progress ?? this.progress,
      statusMessage: clearStatusMessage
          ? null
          : (statusMessage ?? this.statusMessage),
      currentTask: clearCurrentTask ? null : (currentTask ?? this.currentTask),
      mergeProcessId: clearMergeProcessId
          ? null
          : (mergeProcessId ?? this.mergeProcessId),
      downloadPhase: clearDownloadPhase
          ? null
          : (downloadPhase ?? this.downloadPhase),
      mergeDurationKnown: mergeDurationKnown ?? this.mergeDurationKnown,
      playlistTotal: clearPlaylist
          ? null
          : (playlistTotal ?? this.playlistTotal),
      playlistSaved: clearPlaylist ? 0 : (playlistSaved ?? this.playlistSaved),
      playlistFailed: clearPlaylist
          ? 0
          : (playlistFailed ?? this.playlistFailed),
      playlistCurrentIndex: clearPlaylist
          ? 0
          : (playlistCurrentIndex ?? this.playlistCurrentIndex),
      playlistItemPhase: clearPlaylist
          ? null
          : (playlistItemPhase ?? this.playlistItemPhase),
      playlistItemProgress: clearPlaylist
          ? 0
          : (playlistItemProgress ?? this.playlistItemProgress),
    );
  }
}

class YouTubeController extends StateNotifier<YouTubeState> {
  YouTubeController({
    YouTubeExtractor? extractor,
    DownloadEngine? downloadEngine,
    YtDlpEngine? ytDlpEngine,
    MediaSaveService? mediaSaveService,
    MediaNotificationService? mediaNotificationService,
    NotificationPermissionService? notificationPermissionService,
  }) : _extractor = extractor ?? YouTubeExtractor(),
       _downloadEngine = downloadEngine ?? DownloadEngine(),
       _ytDlpEngine = ytDlpEngine ?? YtDlpEngine(),
       _mediaSaveService = mediaSaveService ?? MediaSaveService(),
       _mediaNotificationService =
           mediaNotificationService ?? MediaNotificationService(),
       _notificationPermissionService =
           notificationPermissionService ?? NotificationPermissionService(),
       super(const YouTubeState());

  final YouTubeExtractor _extractor;
  final DownloadEngine _downloadEngine;
  final YtDlpEngine _ytDlpEngine;
  final MediaSaveService _mediaSaveService;
  final MediaNotificationService _mediaNotificationService;
  final NotificationPermissionService _notificationPermissionService;

  /// Fetches format info for [url]. Returns null (and sets an error status
  /// message) on failure. Guards against running while a download from
  /// another `YouTubeScreen` instance (this provider is a singleton) is
  /// already in progress, so the flow stops here rather than silently
  /// no-opping at the download step.
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
        statusMessage: const StatusMessage(StatusMessageKey.notYoutubeLink),
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

  /// Enumerates a playlist's entries for the picker screen. Returns null
  /// (and sets an error status) on failure or an empty playlist.
  Future<PlaylistInfoResult?> fetchPlaylist(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    if (state.busy) {
      state = state.copyWith(
        statusMessage: const StatusMessage(
          StatusMessageKey.downloadAlreadyInProgress,
        ),
      );
      return null;
    }

    state = state.copyWith(fetching: true, clearStatusMessage: true);
    try {
      final info = await _ytDlpEngine.getPlaylistInfo(trimmed);
      state = state.copyWith(fetching: false);
      if (info.entries.isEmpty) {
        state = state.copyWith(
          statusMessage: const StatusMessage(
            StatusMessageKey.couldNotFetchPlaylist,
            error: 'empty',
          ),
        );
        return null;
      }
      return info;
    } catch (error) {
      state = state.copyWith(
        fetching: false,
        statusMessage: StatusMessage(
          StatusMessageKey.couldNotFetchPlaylist,
          error: error.toString(),
        ),
      );
      return null;
    }
  }

  /// Downloads [selectedPositions] (1-based) of a playlist at one shared
  /// [quality], via a single foreground-service yt-dlp run. Each finished
  /// item is saved to the standard YouTube album as it lands; a summary
  /// notification is posted at the end.
  Future<void> downloadPlaylist({
    required String playlistUrl,
    required List<int> selectedPositions,
    required int totalInPlaylist,
    required PlaylistQuality quality,
    required String playlistTitle,
  }) async {
    if (state.busy) {
      state = state.copyWith(
        statusMessage: const StatusMessage(
          StatusMessageKey.downloadAlreadyInProgress,
        ),
      );
      return;
    }
    if (selectedPositions.isEmpty) return;
    unawaited(_notificationPermissionService.ensureRequested());

    final processId = DateTime.now().microsecondsSinceEpoch.toString();
    final tempDir = await getTemporaryDirectory();
    final outputDir = Directory('${tempDir.path}/playlist_$processId');
    await outputDir.create(recursive: true);
    final targetCount = selectedPositions.length;

    state = state.copyWith(
      downloading: true,
      paused: false,
      canPause: false,
      progress: 0,
      clearStatusMessage: true,
      mergeProcessId: processId,
      downloadPhase: 'playlist',
      mergeDurationKnown: false,
      playlistTotal: targetCount,
      playlistSaved: 0,
      playlistFailed: 0,
    );

    final pendingSaves = <Future<void>>[];
    var saved = 0;
    var failed = 0;

    Future<void> saveItem(PlaylistItemDone item) async {
      try {
        if (quality.isAudio) {
          await _mediaSaveService.saveAudio(
            item.path,
            album: _galAlbum,
            isMp3: true,
          );
        } else {
          await _mediaSaveService.saveVideo(item.path, album: _galAlbum);
        }
        saved++;
      } catch (_) {
        failed++;
      } finally {
        final f = File(item.path);
        if (await f.exists()) await f.delete();
        state = state.copyWith(playlistSaved: saved, playlistFailed: failed);
      }
    }

    try {
      final result = await _ytDlpEngine.downloadPlaylist(
        url: playlistUrl,
        outputDir: outputDir.path,
        processId: processId,
        formatSelector: quality.formatSelector,
        audioFormat: quality.audioFormat,
        audioQualityKbps: quality.audioQualityKbps,
        playlistItems: YouTubePlaylistUrl.itemsSpec(
          selectedPositions,
          totalInPlaylist,
        ),
        expectedCount: targetCount,
        onProgress: (update) => state = state.copyWith(
          progress: update.progress,
          playlistItemPhase: update.subPhase,
          playlistCurrentIndex: update.itemIndex ?? state.playlistCurrentIndex,
          playlistItemProgress:
              update.itemProgress ?? state.playlistItemProgress,
        ),
        onItem: (item) => pendingSaves.add(saveItem(item)),
      );

      await Future.wait(pendingSaves);
      try {
        await outputDir.delete(recursive: true);
      } catch (_) {}

      try {
        await _mediaNotificationService.notifySummary(
          title: 'YouTube',
          text: 'Playlist "$playlistTitle": saved $saved of $targetCount',
        );
      } catch (_) {}

      if (result.status == 'canceled') {
        state = state.copyWith(
          downloading: false,
          clearMergeProcessId: true,
          clearDownloadPhase: true,
          clearPlaylist: true,
          statusMessage: saved > 0
              ? StatusMessage(
                  StatusMessageKey.playlistSaved,
                  count: saved,
                  failedCount: failed,
                )
              : const StatusMessage(StatusMessageKey.downloadCanceled),
        );
      } else if (result.status == 'complete' || saved > 0) {
        state = state.copyWith(
          downloading: false,
          clearMergeProcessId: true,
          clearDownloadPhase: true,
          clearPlaylist: true,
          statusMessage: StatusMessage(
            StatusMessageKey.playlistSaved,
            count: saved,
            failedCount: failed,
          ),
        );
      } else {
        state = state.copyWith(
          downloading: false,
          clearMergeProcessId: true,
          clearDownloadPhase: true,
          clearPlaylist: true,
          statusMessage: StatusMessage(
            StatusMessageKey.downloadFailed,
            error: result.error ?? result.status,
          ),
        );
      }
    } catch (error) {
      await Future.wait(pendingSaves);
      try {
        await outputDir.delete(recursive: true);
      } catch (_) {}
      state = state.copyWith(
        downloading: false,
        clearMergeProcessId: true,
        clearDownloadPhase: true,
        clearPlaylist: true,
        statusMessage: StatusMessage(
          StatusMessageKey.downloadFailed,
          error: error.toString(),
        ),
      );
    }
  }

  /// Suggests a safe default base filename (no extension) from a video
  /// title. Only strips characters that are actually illegal in a
  /// filename — everything else (Cyrillic, other scripts, punctuation)
  /// is kept as-is.
  static String suggestedFileName(String title) {
    final safeTitle = title
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
        .trim();
    final truncated = safeTitle.length > 80
        ? safeTitle.substring(0, 80)
        : safeTitle;
    return truncated.isEmpty ? 'video' : truncated;
  }

  Future<void> downloadVariant(MediaVariant variant, String baseFileName) {
    if (state.busy) {
      state = state.copyWith(
        statusMessage: const StatusMessage(StatusMessageKey.downloadAlreadyInProgress),
      );
      return Future.value();
    }
    // Best-effort: a download proceeds regardless of the outcome (denied
    // just means its notifications stay invisible, which isn't worth
    // blocking the download itself over).
    unawaited(_notificationPermissionService.ensureRequested());
    final filename = '$baseFileName.${variant.container}';
    if (variant.audioSpec != null) {
      return _downloadViaAudio(variant, filename);
    }
    if (variant.mergeFormatSelector != null) {
      return _downloadViaMerge(variant, filename);
    }
    return _downloadDirect(variant, filename);
  }

  Future<void> _downloadDirect(MediaVariant variant, String filename) async {
    final task = _downloadEngine.buildTask(
      url: variant.sourceUrl,
      filename: filename,
      headers: variant.requestHeaders,
    );

    state = state.copyWith(
      downloading: true,
      paused: false,
      canPause: true,
      progress: 0,
      clearStatusMessage: true,
      currentTask: task,
      clearDownloadPhase: true,
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

  /// Downloads an adaptive video-only format merged with the best audio
  /// track, via yt-dlp's own `execute()` running inside an Android
  /// foreground service (`YtDlpDownloadService.kt`) — no pause/resume, only
  /// cancel.
  Future<void> _downloadViaMerge(MediaVariant variant, String filename) async {
    final processId = DateTime.now().microsecondsSinceEpoch.toString();
    final tempDir = await getTemporaryDirectory();
    final outputPath = '${tempDir.path}/$filename';

    state = state.copyWith(
      downloading: true,
      paused: false,
      canPause: false,
      progress: 0,
      clearStatusMessage: true,
      mergeProcessId: processId,
      mergeDurationKnown: (variant.durationSeconds ?? 0) > 0,
    );

    try {
      final result = await _ytDlpEngine.downloadMerge(
        url: variant.sourceUrl,
        formatSelector: variant.mergeFormatSelector!,
        outputPath: outputPath,
        processId: processId,
        durationSeconds: variant.durationSeconds,
        onProgress: (update) => state = state.copyWith(
          progress: update.progress,
          downloadPhase: update.phase,
        ),
      );

      switch (result.status) {
        case 'complete':
          final path = result.path ?? outputPath;
          await _saveAndNotify(path, filename);
          state = state.copyWith(
            downloading: false,
            clearMergeProcessId: true,
            clearDownloadPhase: true,
            statusMessage: const StatusMessage(StatusMessageKey.saved),
          );
        case 'canceled':
          state = state.copyWith(
            downloading: false,
            clearMergeProcessId: true,
            clearDownloadPhase: true,
            statusMessage: const StatusMessage(StatusMessageKey.downloadCanceled),
          );
        default:
          state = state.copyWith(
            downloading: false,
            clearMergeProcessId: true,
            clearDownloadPhase: true,
            statusMessage: StatusMessage(
              StatusMessageKey.downloadFailed,
              error: result.error ?? result.status,
            ),
          );
      }
    } catch (error) {
      state = state.copyWith(
        downloading: false,
        clearMergeProcessId: true,
        clearDownloadPhase: true,
        statusMessage: StatusMessage(
          StatusMessageKey.downloadFailed,
          error: error.toString(),
        ),
      );
    }
  }

  /// Downloads an audio-only track (yt-dlp `-x --audio-format …`) via the
  /// same Android foreground service as the merge path — no pause/resume,
  /// only cancel. Saves the result into `Music/<album>/` (not the gallery).
  Future<void> _downloadViaAudio(MediaVariant variant, String filename) async {
    final spec = variant.audioSpec!;
    final processId = DateTime.now().microsecondsSinceEpoch.toString();
    final tempDir = await getTemporaryDirectory();
    final outputPath = '${tempDir.path}/$filename';

    state = state.copyWith(
      downloading: true,
      paused: false,
      canPause: false,
      progress: 0,
      clearStatusMessage: true,
      mergeProcessId: processId,
      downloadPhase: 'audio',
      mergeDurationKnown: (variant.durationSeconds ?? 0) > 0,
    );

    try {
      final result = await _ytDlpEngine.downloadAudio(
        url: variant.sourceUrl,
        audioFormat: spec.format,
        audioQualityKbps: spec.qualityKbps ?? 0,
        outputPath: outputPath,
        processId: processId,
        durationSeconds: variant.durationSeconds,
        onProgress: (update) => state = state.copyWith(
          progress: update.progress,
          downloadPhase: update.phase,
        ),
      );

      switch (result.status) {
        case 'complete':
          final path = result.path ?? outputPath;
          await _saveAudioAndNotify(path, filename, isMp3: spec.format == 'mp3');
          state = state.copyWith(
            downloading: false,
            clearMergeProcessId: true,
            clearDownloadPhase: true,
            statusMessage: const StatusMessage(StatusMessageKey.saved),
          );
        case 'canceled':
          state = state.copyWith(
            downloading: false,
            clearMergeProcessId: true,
            clearDownloadPhase: true,
            statusMessage: const StatusMessage(StatusMessageKey.downloadCanceled),
          );
        default:
          state = state.copyWith(
            downloading: false,
            clearMergeProcessId: true,
            clearDownloadPhase: true,
            statusMessage: StatusMessage(
              StatusMessageKey.downloadFailed,
              error: result.error ?? result.status,
            ),
          );
      }
    } catch (error) {
      state = state.copyWith(
        downloading: false,
        clearMergeProcessId: true,
        clearDownloadPhase: true,
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
  /// reported download failure, so it's isolated in its own try/catch.
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

  /// Audio counterpart of [_saveAndNotify] — saves into `Music/<album>/` via
  /// the native bridge (which returns the `content://` URI directly) instead
  /// of `photo_manager`.
  Future<void> _saveAudioAndNotify(
    String path,
    String filename, {
    required bool isMp3,
  }) async {
    final contentUri = await _mediaSaveService.saveAudio(
      path,
      album: _galAlbum,
      isMp3: isMp3,
    );
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    try {
      await _mediaNotificationService.notifyFileSaved(
        title: filename,
        contentUri: contentUri,
        mimeType: 'audio/*',
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
    if (task != null) {
      await _downloadEngine.cancel(task);
      return;
    }
    final processId = state.mergeProcessId;
    if (processId != null) {
      await _ytDlpEngine.cancelDownload(processId);
    }
  }
}

final youTubeControllerProvider =
    StateNotifierProvider<YouTubeController, YouTubeState>(
      (ref) => YouTubeController(),
    );
