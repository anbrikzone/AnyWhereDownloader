import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/services.dart';

import '../download/download_engine.dart';
import 'update_service.dart';

/// Result of [UpdateInstaller.downloadApk].
class ApkDownloadResult {
  const ApkDownloadResult({required this.ok, this.path, this.error});

  final bool ok;
  final String? path;
  final String? error;
}

/// Downloads a release APK (via the shared [DownloadEngine]) and hands it to
/// the native package installer.
///
/// Native side: `android/.../UpdateInstallBridge.kt` on the
/// `anywhere_downloader/update_install` channel.
class UpdateInstaller {
  UpdateInstaller({DownloadEngine? engine})
      : _engine = engine ?? DownloadEngine();

  static const _channel = MethodChannel('anywhere_downloader/update_install');

  final DownloadEngine _engine;
  DownloadTask? _task;

  /// ABIs this device supports, most-preferred first (`Build.SUPPORTED_ABIS`).
  Future<List<String>> supportedAbis() async {
    final list = await _channel.invokeMethod<List<Object?>>('getSupportedAbis');
    return (list ?? const []).map((e) => e.toString()).toList();
  }

  /// Whether the app already holds the per-source "install unknown apps"
  /// grant (`PackageManager.canRequestPackageInstalls`).
  Future<bool> canInstallPackages() async {
    return await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
  }

  /// Opens the system screen where the user grants this app permission to
  /// install packages.
  Future<void> openInstallPermissionSettings() {
    return _channel.invokeMethod('openInstallPermissionSettings');
  }

  Future<ApkDownloadResult> downloadApk(
    UpdateAsset asset, {
    void Function(double progress)? onProgress,
  }) async {
    final task = _engine.buildTask(url: asset.downloadUrl, filename: asset.name);
    _task = task;
    try {
      final status = await _engine.run(task, onProgress: onProgress);
      if (status.status != TaskStatus.complete) {
        return ApkDownloadResult(ok: false, error: status.status.name);
      }
      final path = await _engine.filePath(task);
      return ApkDownloadResult(ok: true, path: path);
    } catch (e) {
      return ApkDownloadResult(ok: false, error: e.toString());
    }
  }

  /// Fires the system package-installer intent for a downloaded APK.
  Future<void> installApk(String path) {
    return _channel.invokeMethod('installApk', {'path': path});
  }

  /// Opens a URL in the browser (the release page, as a manual fallback).
  Future<void> openUrl(String url) {
    return _channel.invokeMethod('openUrl', {'url': url});
  }

  Future<void> cancel() async {
    final task = _task;
    if (task != null) await _engine.cancel(task);
  }
}
