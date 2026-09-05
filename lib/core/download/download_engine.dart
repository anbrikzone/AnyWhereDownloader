import 'package:background_downloader/background_downloader.dart';

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

  DownloadTask buildTask({
    required String url,
    required String filename,
    Map<String, String>? headers,
  }) {
    return DownloadTask(
      url: url,
      filename: filename,
      headers: headers ?? const {},
      baseDirectory: BaseDirectory.temporary,
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
