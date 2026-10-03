import 'package:flutter/services.dart';

import '../l10n/current_l10n.dart';

/// Posts the "download complete" system notification via a small native
/// bridge (`MediaNotificationBridge.kt`) rather than a Flutter notification
/// plugin — the tap action needs to launch an arbitrary external viewer app
/// for the saved file via a plain Android `ACTION_VIEW` `PendingIntent`,
/// which is set directly on the native notification so it still works if
/// the app process has been killed. No Flutter package builds that.
class MediaNotificationService {
  static const _channel = MethodChannel(
    'anywhere_downloader/media_notifications',
  );

  /// Shows a notification for one saved file. Tapping it opens [contentUri]
  /// (a `content://` MediaStore URI) with the system's default viewer for
  /// [mimeType].
  Future<void> notifyFileSaved({
    required String title,
    required String contentUri,
    required String mimeType,
  }) {
    final l10n = CurrentL10n.value;
    return _channel.invokeMethod('showDownloadComplete', {
      'title': title,
      'text': l10n.notificationTapToOpen,
      'uri': contentUri,
      'mimeType': mimeType,
      'channelName': l10n.notificationChannelComplete,
    });
  }

  /// Opens a saved file ([contentUri]) in the system's default viewer — the
  /// same action the completion notification's tap fires. The MIME type is
  /// looked up from MediaStore. Returns false when nothing could open it
  /// (e.g. the file was deleted since).
  Future<bool> openFile(String contentUri) async {
    try {
      return await _channel.invokeMethod<bool>('openFile', {
            'uri': contentUri,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// Shows a plain summary notification with no tap-to-open action — used
  /// when a batch save (e.g. multiple WhatsApp statuses at once) has no
  /// single file to point at.
  Future<void> notifySummary({required String title, required String text}) {
    return _channel.invokeMethod('showDownloadComplete', {
      'title': title,
      'text': text,
      'channelName': CurrentL10n.value.notificationChannelComplete,
    });
  }
}
