import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/app_settings_service.dart';
import 'update_installer.dart';
import 'update_service.dart';

/// How often the silent cold-start check is allowed to hit the network.
const _checkThrottle = Duration(hours: 24);

sealed class UpdateState {
  const UpdateState();
}

class UpdateIdle extends UpdateState {
  const UpdateIdle();
}

class UpdateChecking extends UpdateState {
  const UpdateChecking();
}

class UpdateUpToDate extends UpdateState {
  const UpdateUpToDate();
}

class UpdateAvailable extends UpdateState {
  const UpdateAvailable(this.info);
  final UpdateInfo info;
}

class UpdateDownloading extends UpdateState {
  const UpdateDownloading(this.info, this.progress);
  final UpdateInfo info;

  /// 0.0–1.0, or negative while indeterminate (background_downloader emits
  /// -1 / -2 / -3 for waiting-to-retry etc.).
  final double progress;
}

class UpdateReadyToInstall extends UpdateState {
  const UpdateReadyToInstall(this.info, this.apkPath);
  final UpdateInfo info;
  final String apkPath;
}

class UpdateError extends UpdateState {
  const UpdateError(this.message, {this.info});
  final String message;

  /// Present when the failure happened after an update was already found,
  /// so the UI can still offer "open the release page".
  final UpdateInfo? info;
}

class UpdateController extends StateNotifier<UpdateState> {
  UpdateController({
    UpdateService? service,
    UpdateInstaller? installer,
    AppSettingsService? settings,
  })  : _service = service ?? UpdateService(),
        _installer = installer ?? UpdateInstaller(),
        _settings = settings ?? AppSettingsService(),
        super(const UpdateIdle());

  final UpdateService _service;
  final UpdateInstaller _installer;
  final AppSettingsService _settings;

  /// Silent, best-effort — only actually checks if the last check was more
  /// than [_checkThrottle] ago. Never surfaces an error state (this runs on
  /// cold start, where a failed check must be invisible).
  Future<void> maybeCheckOnStartup() async {
    if (state is! UpdateIdle) return;
    final last = await _settings.getLastUpdateCheck();
    if (last != null && DateTime.now().difference(last) < _checkThrottle) return;
    await _check(surfaceErrors: false);
  }

  /// User tapped "Check for updates" — always hits the network, surfaces
  /// "up to date" and errors.
  Future<void> checkNow() => _check(surfaceErrors: true);

  Future<void> _check({required bool surfaceErrors}) async {
    state = const UpdateChecking();
    final info = await _service.checkForUpdate();
    await _settings.setLastUpdateCheck(DateTime.now());
    if (info != null) {
      state = UpdateAvailable(info);
    } else {
      state = surfaceErrors ? const UpdateUpToDate() : const UpdateIdle();
    }
  }

  Future<void> startDownload() async {
    final current = state;
    final info = switch (current) {
      UpdateAvailable(:final info) => info,
      UpdateError(:final info?) => info,
      _ => null,
    };
    if (info == null) return;

    final abis = await _installer.supportedAbis();
    final asset = info.assetForAbis(abis);
    if (asset == null) {
      state = UpdateError('no_matching_asset', info: info);
      return;
    }

    state = UpdateDownloading(info, 0);
    final result = await _installer.downloadApk(
      asset,
      onProgress: (p) {
        if (state is UpdateDownloading) state = UpdateDownloading(info, p);
      },
    );
    if (result.ok && result.path != null) {
      state = UpdateReadyToInstall(info, result.path!);
    } else {
      state = UpdateError(result.error ?? 'download_failed', info: info);
    }
  }

  /// Fires the system installer for the downloaded APK, first routing the
  /// user to grant "install unknown apps" if they haven't.
  Future<void> install() async {
    final current = state;
    if (current is! UpdateReadyToInstall) return;
    if (!await _installer.canInstallPackages()) {
      await _installer.openInstallPermissionSettings();
      return;
    }
    await _installer.installApk(current.apkPath);
  }

  Future<void> cancelDownload() async {
    await _installer.cancel();
    final current = state;
    if (current is UpdateDownloading) state = UpdateAvailable(current.info);
  }

  /// Opens the release's GitHub page — the manual fallback when the in-app
  /// download or install path fails.
  Future<void> openReleasePage() async {
    final info = switch (state) {
      UpdateAvailable(:final info) => info,
      UpdateDownloading(:final info) => info,
      UpdateReadyToInstall(:final info) => info,
      UpdateError(:final info?) => info,
      _ => null,
    };
    if (info != null) await _installer.openUrl(info.htmlUrl);
  }
}

final updateControllerProvider =
    StateNotifierProvider<UpdateController, UpdateState>(
  (ref) => UpdateController(),
);
