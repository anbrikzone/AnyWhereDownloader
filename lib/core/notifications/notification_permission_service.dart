import 'package:background_downloader/background_downloader.dart';

/// Requests Android 13+ `POST_NOTIFICATIONS` lazily, right before a
/// download or WhatsApp save (without it every notification this app shows
/// is silently suppressed). Uses `background_downloader`'s `Permissions`
/// API to avoid pulling in `permission_handler` for one check.
class NotificationPermissionService {
  /// No-ops if already granted. Otherwise triggers the system dialog;
  /// Android only shows it once, so calling this before every save is fine.
  Future<void> ensureRequested() async {
    final status = await FileDownloader().permissions.status(
      PermissionType.notifications,
    );
    if (status != PermissionStatus.granted) {
      await FileDownloader().permissions.request(PermissionType.notifications);
    }
  }
}
