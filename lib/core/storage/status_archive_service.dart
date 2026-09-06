import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:saf_stream/saf_stream.dart';

import '../../services/whatsapp/whatsapp_status_reader.dart';
import 'media_library_service.dart';
import 'media_save_service.dart';

/// One archived file's decoded name: the epoch-millis it was archived plus
/// the original WhatsApp status filename.
class ArchivedName {
  const ArchivedName(this.archivedAtMillis, this.originalName);

  final int archivedAtMillis;
  final String originalName;
}

/// Keeps a **private in-app copy** of viewed WhatsApp statuses so they
/// survive WhatsApp's own cache eviction, and prunes copies older than the
/// user's chosen retention window. Runs opportunistically from
/// `WhatsAppStatusController.refresh()` — there is no background job.
///
/// The copies live under the app's private support directory, **not** the
/// gallery/MediaStore — an archived status shows up only in the app's
/// WhatsApp tab ("Archived"), and reaches the Library exclusively when the
/// user explicitly saves it. (Up to 0.3.4 this wrote straight into a
/// gallery album, which leaked every viewed status into the Library and the
/// system gallery — see [purgeLegacyGalleryAlbum].)
class StatusArchiveService {
  StatusArchiveService({
    SafStream? safStream,
    MediaSaveService? mediaSaveService,
  })  : _safStream = safStream ?? SafStream(),
        _mediaSaveService = mediaSaveService ?? MediaSaveService();

  final SafStream _safStream;
  final MediaSaveService _mediaSaveService;

  static const _dirName = 'whatsapp_archive';

  /// The gallery album the 0.3.4 archiver used to write into — no longer
  /// written, purged once on upgrade.
  static final _legacyAlbum = albumNameForSource('WhatsApp Archive');

  /// `<millis>__<originalName>` — millis prefix so a plain directory listing
  /// gives us the archived-at time and dedup key with no side ledger.
  static String encodeName(int archivedAtMillis, String originalName) =>
      '${archivedAtMillis}__$originalName';

  /// Inverse of [encodeName]. Null for anything that doesn't match (a stray
  /// file, a leftover from an older layout).
  static ArchivedName? decodeName(String fileName) {
    final sep = fileName.indexOf('__');
    if (sep <= 0) return null;
    final millis = int.tryParse(fileName.substring(0, sep));
    if (millis == null) return null;
    final name = fileName.substring(sep + 2);
    if (name.isEmpty) return null;
    return ArchivedName(millis, name);
  }

  Future<Directory> _archiveDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$_dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Copies any of [freshStatuses] not already archived into the private
  /// archive dir. Returns how many were newly archived. Never throws.
  Future<int> archiveNew(List<StatusItem> freshStatuses) async {
    if (freshStatuses.isEmpty) return 0;
    final dir = await _archiveDir();
    final existing = await _existingOriginalNames(dir);
    final now = DateTime.now().millisecondsSinceEpoch;

    var archived = 0;
    for (final status in freshStatuses) {
      if (status.isArchived) continue;
      if (existing.contains(status.name)) continue;
      // `+ archived` disambiguates two files copied in the same millisecond.
      final dest =
          '${dir.path}/${encodeName(now + archived, status.name)}';
      try {
        await _safStream.copyToLocalFile(status.uri, dest);
        existing.add(status.name);
        archived++;
      } catch (_) {
        final f = File(dest);
        if (await f.exists()) await f.delete();
      }
    }
    return archived;
  }

  /// The archived statuses as [StatusItem]s (`origin` = archived),
  /// newest-archived first. Never throws.
  Future<List<StatusItem>> loadArchived() async {
    try {
      final dir = await _archiveDir();
      if (!await dir.exists()) return const [];
      final items = <StatusItem>[];
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final decoded = decodeName(_basename(entity.path));
        if (decoded == null) continue;
        final mediaType =
            WhatsAppStatusReader.mediaTypeForName(decoded.originalName);
        if (mediaType == null) continue;
        final stat = await entity.stat();
        items.add(
          StatusItem(
            uri: entity.path,
            name: decoded.originalName,
            sizeBytes: stat.size,
            lastModified:
                DateTime.fromMillisecondsSinceEpoch(decoded.archivedAtMillis),
            mediaType: mediaType,
            origin: StatusOrigin.archived,
            localPath: entity.path,
          ),
        );
      }
      items.sort((a, b) => b.lastModified.compareTo(a.lastModified));
      return items;
    } catch (_) {
      return const [];
    }
  }

  /// Deletes archived copies older than [retention]. No-op for
  /// [Duration.zero]. Returns how many were removed. Never throws.
  Future<int> pruneExpired(Duration retention) async {
    if (retention == Duration.zero) return 0;
    try {
      final dir = await _archiveDir();
      if (!await dir.exists()) return 0;
      final cutoff =
          DateTime.now().millisecondsSinceEpoch - retention.inMilliseconds;
      var removed = 0;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final decoded = decodeName(_basename(entity.path));
        final archivedAt = decoded?.archivedAtMillis ??
            (await entity.stat()).modified.millisecondsSinceEpoch;
        if (archivedAt < cutoff) {
          try {
            await entity.delete();
            removed++;
          } catch (_) {}
        }
      }
      return removed;
    } catch (_) {
      return 0;
    }
  }

  /// Deletes every archived copy — used when the user turns the archive off
  /// entirely. Never throws.
  Future<void> purgeAll() async {
    try {
      final dir = await _archiveDir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  /// One-time cleanup of the gallery album the 0.3.4 archiver wrote into.
  /// Silent — every row there was inserted by this app. Harmless to call
  /// again; the controller gates it on a "done once" flag anyway.
  Future<void> purgeLegacyGalleryAlbum() async {
    try {
      // `Duration.zero` => "older than now" => the whole album.
      await _mediaSaveService.pruneAlbum(_legacyAlbum, Duration.zero);
    } catch (_) {}
  }

  Future<Set<String>> _existingOriginalNames(Directory dir) async {
    final names = <String>{};
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final decoded = decodeName(_basename(entity.path));
      if (decoded != null) names.add(decoded.originalName);
    }
    return names;
  }

  String _basename(String path) => path.split(Platform.pathSeparator).last;
}
