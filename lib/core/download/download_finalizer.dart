import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/widgets.dart';

import '../notifications/media_notification_service.dart';
import '../storage/media_save_service.dart';

/// `background_downloader` group for every download that ends up in the
/// gallery. Only this group is tracked/reconciled — the self-update APK
/// download (`UpdateInstaller`) stays in the default group, untouched.
const kGallerySaveGroup = 'awd_gallery_save';

enum SavedMediaKind { video, image }

/// Where a finished download goes — carried inside the task's `metaData`,
/// so the save can still run long after the controller that started the
/// download is gone.
class GallerySaveSpec {
  const GallerySaveSpec({
    required this.kind,
    required this.album,
    required this.notifyTitle,
  });

  final SavedMediaKind kind;

  /// `relativePathForSource`/`relativePathForPlaylist` result; the Settings
  /// root is prepended by [MediaSaveService] at save time.
  final String album;

  /// Title of the "download complete" notification (the file name).
  final String notifyTitle;

  String toMetaData() => jsonEncode({
    'v': 1,
    'kind': kind.name,
    'album': album,
    'title': notifyTitle,
  });

  /// Null for anything that isn't a spec this app wrote.
  static GallerySaveSpec? fromMetaData(String metaData) {
    try {
      final map = jsonDecode(metaData) as Map<String, dynamic>;
      if (map['v'] != 1) return null;
      final kind = SavedMediaKind.values.byName(map['kind'] as String);
      final album = map['album'] as String;
      if (album.isEmpty) return null;
      return GallerySaveSpec(
        kind: kind,
        album: album,
        notifyTitle: map['title'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

/// A download known to `background_downloader`'s task database.
class TrackedDownload {
  const TrackedDownload({
    required this.taskId,
    required this.status,
    required this.metaData,
    this.task,
  });

  final String taskId;
  final TaskStatus status;
  final String metaData;
  final Task? task;
}

/// Seam over `background_downloader`'s database + file paths, so
/// [DownloadFinalizer] is unit-testable without the plugin.
abstract class TrackedDownloadStore {
  Future<List<TrackedDownload>> all();
  Future<String> filePath(TrackedDownload download);
  Future<void> delete(String taskId);
}

class _PluginTrackedDownloadStore implements TrackedDownloadStore {
  @override
  Future<List<TrackedDownload>> all() async {
    final records = await FileDownloader().database.allRecords(
      group: kGallerySaveGroup,
    );
    return [
      for (final r in records)
        TrackedDownload(
          taskId: r.taskId,
          status: r.status,
          metaData: r.task.metaData,
          task: r.task,
        ),
    ];
  }

  @override
  Future<String> filePath(TrackedDownload download) => download.task!.filePath();

  @override
  Future<void> delete(String taskId) =>
      FileDownloader().database.deleteRecordWithId(taskId);
}

/// The single "save a finished direct download to the gallery" step for every
/// `background_downloader` download (direct YouTube, TikTok, X, Instagram,
/// LinkedIn).
///
/// Why it exists: that save used to be awaited inside each controller, so a
/// download finishing after the Flutter UI died (app swiped from Recents,
/// activity recreated) completed into app storage and was never saved.
/// Tasks are now tracked in the plugin's own database with the save spec in
/// their `metaData`, and anything complete-but-unsaved is saved here on
/// start, on resume, or as soon as an orphaned task reports completion.
/// Idempotent: concurrent callers for the same task share one save.
class DownloadFinalizer {
  DownloadFinalizer({
    MediaSaveService? mediaSaveService,
    MediaNotificationService? mediaNotificationService,
    TrackedDownloadStore? store,
  }) : _mediaSaveService = mediaSaveService ?? MediaSaveService(),
       _mediaNotificationService =
           mediaNotificationService ?? MediaNotificationService(),
       _store = store ?? _PluginTrackedDownloadStore();

  static final instance = DownloadFinalizer();

  final MediaSaveService _mediaSaveService;
  final MediaNotificationService _mediaNotificationService;
  final TrackedDownloadStore _store;

  final _inFlight = <String, Future<String?>>{};
  bool _started = false;

  /// Call once at app start, before any download is enqueued.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      // Completion of a task nobody awaits any more (its controller died
      // with the previous Flutter engine) lands here; awaited tasks are
      // routed to their `download()` future first and never reach it.
      FileDownloader().registerCallbacks(
        group: kGallerySaveGroup,
        taskStatusCallback: _onOrphanStatus,
      );
      await FileDownloader().trackTasksInGroup(kGallerySaveGroup);
      // Replays status updates the plugin stored while no Dart side was
      // alive to receive them — they update the tracking database.
      await FileDownloader().resumeFromBackground();
      AppLifecycleListener(onResume: () => unawaited(reconcile()));
      await reconcile();
    } catch (error, stack) {
      debugPrint('[DownloadFinalizer] start failed: $error\n$stack');
    }
  }

  void _onOrphanStatus(TaskStatusUpdate update) {
    if (update.status == TaskStatus.complete) {
      unawaited(_finalizeQuietly(_fromTask(update.task, update.status)));
    } else if (update.status.isFinalState) {
      unawaited(_store.delete(update.task.taskId).catchError((_) {}));
    }
  }

  /// Saves every tracked download that finished but was never saved, and
  /// drops records of downloads that ended any other way. Never throws.
  Future<void> reconcile() async {
    final List<TrackedDownload> records;
    try {
      records = await _store.all();
    } catch (error) {
      debugPrint('[DownloadFinalizer] reading records failed: $error');
      return;
    }
    for (final record in records) {
      if (record.status == TaskStatus.complete) {
        await _finalizeQuietly(record);
      } else if (record.status.isFinalState) {
        try {
          await _store.delete(record.taskId);
        } catch (_) {}
      }
    }
  }

  /// Saves the finished [task] (built with a [GallerySaveSpec]) and returns
  /// its `content://` URI — or null if another caller already saved it.
  /// Throws the save error (after cleaning up) so the caller can show it.
  Future<String?> finalize(Task task) =>
      _finalize(_fromTask(task, TaskStatus.complete));

  TrackedDownload _fromTask(Task task, TaskStatus status) => TrackedDownload(
    taskId: task.taskId,
    status: status,
    metaData: task.metaData,
    task: task,
  );

  Future<void> _finalizeQuietly(TrackedDownload download) async {
    try {
      await _finalize(download);
    } catch (error) {
      debugPrint(
        '[DownloadFinalizer] background save of ${download.taskId} failed: $error',
      );
    }
  }

  Future<String?> _finalize(TrackedDownload download) {
    final existing = _inFlight[download.taskId];
    if (existing != null) return existing;
    final future = _save(download);
    _inFlight[download.taskId] = future;
    // Dropped from the map once settled — a finished task's record and file
    // are gone by then, so a later call is a harmless no-op.
    // Block bodies on purpose: `remove` returns the removed future itself,
    // and returning that from `onError` would re-raise its error unhandled.
    future.then<void>(
      (_) {
        _inFlight.remove(download.taskId);
      },
      onError: (Object _) {
        _inFlight.remove(download.taskId);
      },
    );
    return future;
  }

  Future<String?> _save(TrackedDownload download) async {
    final spec = GallerySaveSpec.fromMetaData(download.metaData);
    if (spec == null) {
      await _store.delete(download.taskId);
      return null;
    }
    final path = await _store.filePath(download);
    final file = File(path);
    if (!await file.exists()) {
      // Already saved (and deleted) by an earlier call.
      await _store.delete(download.taskId);
      return null;
    }
    try {
      final isImage = spec.kind == SavedMediaKind.image;
      final contentUri = isImage
          ? await _mediaSaveService.saveImage(path, album: spec.album)
          : await _mediaSaveService.saveVideo(path, album: spec.album);
      try {
        await _mediaNotificationService.notifyFileSaved(
          title: spec.notifyTitle,
          contentUri: contentUri,
          mimeType: isImage ? 'image/*' : 'video/*',
        );
      } catch (_) {
        // A notification failure must never turn a successful save into a
        // reported download failure.
      }
      return contentUri;
    } finally {
      // Also on a failed save: a download MediaStore rejects (e.g. an HTML
      // page) would fail identically on every retry, so it's not kept for
      // the next reconcile.
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      try {
        await _store.delete(download.taskId);
      } catch (_) {}
    }
  }
}
