import 'package:background_downloader/background_downloader.dart';

import 'download_finalizer.dart';

/// Thin wrapper over `background_downloader`, isolating the package the
/// same way `SafService` isolates `saf_util`. Chosen over a plain HTTP
/// client (the original prototype used `dio`) because large downloads need
/// to survive the screen turning off and Android's ~9-minute background
/// execution limit — both handled by this package's native WorkManager
/// (Android) / URLSession (iOS) backed tasks with `allowPause`, not by
/// anything we could reasonably reimplement ourselves.
class DownloadEngine {
  DownloadEngine() {
    FileDownloader().configureNotification(
      running: const TaskNotification('Downloading', '{filename}'),
      paused: const TaskNotification('Paused', '{filename}'),
      complete: const TaskNotification('Download complete', '{filename}'),
      error: const TaskNotification('Download failed', '{filename}'),
      progressBar: true,
    );
  }

  /// [saveTo] marks a download destined for the gallery: it joins
  /// [kGallerySaveGroup] (tracked in the plugin's database, see
  /// [DownloadFinalizer]), carries its save spec in `metaData`, and lands in
  /// app-support storage instead of the cache the OS may purge before a
  /// download that finished without the UI gets saved. Without it (the
  /// self-update APK), behaviour is unchanged.
  DownloadTask buildTask({
    required String url,
    required String filename,
    Map<String, String>? headers,
    GallerySaveSpec? saveTo,
  }) {
    if (saveTo == null) {
      return DownloadTask(
        url: url,
        filename: filename,
        headers: headers ?? const {},
        baseDirectory: BaseDirectory.temporary,
        updates: Updates.statusAndProgress,
        allowPause: true,
      );
    }
    return DownloadTask(
      url: url,
      filename: filename,
      headers: headers ?? const {},
      baseDirectory: BaseDirectory.applicationSupport,
      directory: 'downloads',
      group: kGallerySaveGroup,
      metaData: saveTo.toMetaData(),
      updates: Updates.statusAndProgress,
      allowPause: true,
    );
  }

  Future<TaskStatusUpdate> run(
    DownloadTask task, {
    void Function(TaskStatus status)? onStatus,
    void Function(double progress)? onProgress,
  }) {
    return FileDownloader().download(
      task,
      onStatus: onStatus,
      onProgress: onProgress,
    );
  }

  Future<String> filePath(DownloadTask task) => task.filePath();

  Future<bool> pause(DownloadTask task) => FileDownloader().pause(task);

  Future<bool> resume(DownloadTask task) => FileDownloader().resume(task);

  Future<bool> cancel(DownloadTask task) => FileDownloader().cancel(task);
}
