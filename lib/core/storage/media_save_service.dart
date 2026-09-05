import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

/// Thrown when the file handed to [MediaSaveService] isn't actually the
/// media it's supposed to be — most often an HTML error/login page a CDN
/// returned instead of the video, which MediaStore otherwise rejects with
/// an opaque `IllegalArgumentException: MIME type text/html ...`.
class MediaSaveException implements Exception {
  MediaSaveException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Saves a downloaded file to the gallery via `photo_manager`'s editor API
/// (returns the resulting `AssetEntity`, whose `getMediaUrl()` gives the
/// real `content://` URI for a "download complete" notification to open —
/// `gal` couldn't provide that).
///
/// Both media types save under `Pictures/<album>`, matching the on-device
/// behavior confirmed via `adb shell` (an album name is enough to force
/// `DIRECTORY_PICTURES` regardless of type); splitting videos into
/// `Movies/` would fragment existing libraries for no gain.
class MediaSaveService {
  static const _audioChannel = MethodChannel('anywhere_downloader/media_save');

  Future<String> saveVideo(String filePath, {required String album}) {
    return _save(filePath, album: album, expected: 'video', isImage: false);
  }

  Future<String> saveImage(String filePath, {required String album}) {
    return _save(filePath, album: album, expected: 'image', isImage: true);
  }

  /// Saves an audio file into `Music/<album>/` via the native
  /// `MediaSaveBridge` (`photo_manager` has no audio save API). Returns the
  /// resulting `content://` URI (for the "tap to open" notification).
  Future<String> saveAudio(
    String filePath, {
    required String album,
    required bool isMp3,
  }) async {
    await _assertNotHtml(filePath, expected: 'audio');
    // The temp file already carries the right `.mp3`/`.m4a` extension.
    final title = _safeTitle(filePath, isImage: false);
    try {
      final uri = await _audioChannel.invokeMethod<String>('saveAudio', {
        'path': filePath,
        'album': album,
        'title': title,
        'mimeType': isMp3 ? 'audio/mpeg' : 'audio/mp4',
      });
      if (uri == null) {
        throw MediaSaveException('The audio file could not be saved.');
      }
      return uri;
    } on PlatformException catch (e) {
      throw MediaSaveException(
        'The audio file could not be saved${e.message != null ? ': ${e.message}' : ''}.',
      );
    }
  }

  Future<String> _save(
    String filePath, {
    required String album,
    required String expected,
    required bool isImage,
  }) async {
    await _assertNotHtml(filePath, expected: expected);
    // `photo_manager` derives the MediaStore MIME type from this title via
    // `URLConnection.guessContentTypeFromName`, which treats `#` as a URL
    // fragment separator and drops everything after it — including the
    // `.mp4`/`.jpg` extension — when the title is a post caption full of
    // hashtags (`#foo #bar video.mp4`). Losing the extension makes it
    // guess `text/html`, and MediaStore then rejects the insert. Sanitise
    // the title so the extension always survives.
    final title = _safeTitle(filePath, isImage: isImage);
    final AssetEntity asset;
    try {
      asset = isImage
          ? await PhotoManager.editor.saveImageWithPath(
              filePath,
              title: title,
              relativePath: 'Pictures/$album',
            )
          : await PhotoManager.editor.saveVideo(
              File(filePath),
              title: title,
              relativePath: 'Pictures/$album',
            );
    } catch (error) {
      // MediaStore rejects a non-media file (e.g. `MIME type text/html
      // cannot be inserted`). That's definitive proof the download wasn't
      // the $expected — turn the raw platform crash into a clean message.
      final text = error.toString();
      if (text.contains('MIME type') || text.contains('IllegalArgument')) {
        throw MediaSaveException(
          'The download was not a valid $expected (the source likely served '
          'a web page — the post may require signing in, or has no '
          'downloadable $expected).',
        );
      }
      rethrow;
    }
    return _requireMediaUrl(asset);
  }

  /// A plain HTTP GET can "succeed" while actually fetching a web page
  /// (login wall, error/consent page) instead of the media file. Sniff the
  /// first bytes and fail early with a readable message; the try/catch in
  /// [_save] is the definitive backstop if this misses.
  Future<void> _assertNotHtml(String filePath, {required String expected}) async {
    final file = File(filePath);
    final length = await file.length();
    if (length == 0) {
      throw MediaSaveException('The download produced an empty file.');
    }
    final head = <int>[];
    await for (final chunk in file.openRead(0, length < 1024 ? length : 1024)) {
      head.addAll(chunk);
    }
    // Strip a UTF-8 BOM, then leading whitespace.
    var text = String.fromCharCodes(head);
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) text = text.substring(1);
    final start = text.trimLeft().toLowerCase();
    if (kDebugMode) {
      debugPrint(
        '[MediaSave] $expected file ${length}B head: '
        '${start.substring(0, start.length < 160 ? start.length : 160)}',
      );
    }
    final looksLikeHtml = start.startsWith('<!doctype') ||
        start.startsWith('<html') ||
        start.startsWith('<head') ||
        start.startsWith('<?xml') ||
        start.contains('<html') ||
        start.contains('<meta ') ||
        start.contains('<!-- ');
    if (looksLikeHtml) {
      throw MediaSaveException(
        'The download did not return a $expected — the source served a web '
        'page instead (the post may require signing in, or has no '
        'downloadable $expected).',
      );
    }
  }

  Future<String> _requireMediaUrl(AssetEntity asset) async {
    final url = await asset.getMediaUrl();
    if (url == null) {
      throw StateError('Could not resolve a media URL for the saved asset');
    }
    return url;
  }

  String _basename(String path) => path.split(Platform.pathSeparator).last;

  /// A gallery title that keeps its extension when `photo_manager` runs it
  /// through `URLConnection.guessContentTypeFromName`: no `#` (fragment
  /// separator), no other URL-significant / filesystem-hostile chars, no
  /// double spaces, and a guaranteed trailing `.<ext>`.
  String _safeTitle(String filePath, {required bool isImage}) {
    final raw = _basename(filePath);
    final dot = raw.lastIndexOf('.');
    final rawExt = dot > 0 ? raw.substring(dot + 1).toLowerCase() : '';
    final ext = RegExp(r'^[a-z0-9]{1,5}$').hasMatch(rawExt)
        ? rawExt
        : (isImage ? 'jpg' : 'mp4');
    var base = dot > 0 ? raw.substring(0, dot) : raw;
    base = base
        .replaceAll(RegExp(r'''[#?&%:*"<>|\\/\x00-\x1F]'''), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (base.isEmpty) base = isImage ? 'image' : 'video';
    return '$base.$ext';
  }
}
