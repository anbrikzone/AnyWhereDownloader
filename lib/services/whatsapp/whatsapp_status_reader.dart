import 'package:saf_util/saf_util_platform_interface.dart';

enum StatusMediaType { image, video }

class StatusItem {
  StatusItem({
    required this.uri,
    required this.name,
    required this.sizeBytes,
    required this.lastModified,
    required this.mediaType,
  });

  final String uri;
  final String name;
  final int sizeBytes;
  final DateTime lastModified;
  final StatusMediaType mediaType;
}

/// Domain logic for the WhatsApp status feature: knows which files inside a
/// user-picked folder actually look like WhatsApp status media, and where to
/// point the user when asking them to pick that folder.
class WhatsAppStatusReader {
  WhatsAppStatusReader._();

  /// Shown to the user as guidance in the folder picker prompt.
  static const folderHints = [
    'Android/media/com.whatsapp/WhatsApp/Media/.Statuses',
    'Android/media/com.whatsapp.w4b/WhatsApp Business/Media/.Statuses',
  ];

  /// Content URI used to pre-seed the SAF folder picker (Android's
  /// `EXTRA_INITIAL_URI`) so it opens already positioned at the regular
  /// WhatsApp status folder instead of forcing the user to navigate there
  /// manually. Best-effort: some OEM file managers ignore this hint, in
  /// which case the picker just falls back to its default starting point.
  static String get initialUriForWhatsApp =>
      _seedUri('Android/media/com.whatsapp/WhatsApp/Media/.Statuses');

  /// Same as [initialUriForWhatsApp] but for WhatsApp Business.
  static String get initialUriForWhatsAppBusiness => _seedUri(
    'Android/media/com.whatsapp.w4b/WhatsApp Business/Media/.Statuses',
  );

  static String _seedUri(String relativePath) {
    final documentId = 'primary:$relativePath';
    return 'content://com.android.externalstorage.documents/document/'
        '${Uri.encodeComponent(documentId)}';
  }

  static const _imageExtensions = {'.jpg', '.jpeg', '.png', '.webp'};
  static const _videoExtensions = {'.mp4', '.3gp', '.mkv'};

  static List<StatusItem> filterStatusFiles(List<SafDocumentFile> files) {
    final items = <StatusItem>[];
    for (final file in files) {
      if (file.isDir) continue;
      final mediaType = _mediaTypeFor(file.name);
      if (mediaType == null) continue;
      items.add(
        StatusItem(
          uri: file.uri,
          name: file.name,
          sizeBytes: file.length,
          lastModified: DateTime.fromMillisecondsSinceEpoch(
            file.lastModified,
          ),
          mediaType: mediaType,
        ),
      );
    }
    items.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return items;
  }

  static StatusMediaType? _mediaTypeFor(String name) {
    final lower = name.toLowerCase();
    final dot = lower.lastIndexOf('.');
    if (dot < 0) return null;
    final ext = lower.substring(dot);
    if (_imageExtensions.contains(ext)) return StatusMediaType.image;
    if (_videoExtensions.contains(ext)) return StatusMediaType.video;
    return null;
  }
}
