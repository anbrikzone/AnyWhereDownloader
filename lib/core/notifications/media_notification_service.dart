import 'package:flutter/services.dart';

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
    return _channel.invokeMethod('showDownloadComplete', {
      'title': title,
      'text': 'Tap to open',
      'uri': contentUri,
      'mimeType': mimeType,
    });
  }

  /// Shows a plain summary notification with no tap-to-open action — used
  /// when a batch save (e.g. multiple WhatsApp statuses at once) has no
  /// single file to point at.
  Future<void> notifySummary({required String title, required String text}) {
    return _channel.invokeMethod('showDownloadComplete', {
      'title': title,
      'text': text,
    });
  }
}
