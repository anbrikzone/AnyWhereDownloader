import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:saf_stream/saf_stream.dart';

import '../../services/whatsapp/whatsapp_status_reader.dart';
import '../settings/app_settings_service.dart';
import 'media_library_service.dart';
import 'media_save_service.dart';

/// Auto-archives viewed WhatsApp statuses into a dedicated gallery album so
/// they survive WhatsApp's own cache eviction, and prunes archived copies
/// older than the user's chosen retention window. Runs opportunistically
/// from `WhatsAppStatusController.refresh()` — there is no background job.
class StatusArchiveService {
  StatusArchiveService({
    SafStream? safStream,
    MediaSaveService? mediaSaveService,
    AppSettingsService? settings,
  })  : _safStream = safStream ?? SafStream(),
        _mediaSaveService = mediaSaveService ?? MediaSaveService(),
        _settings = settings ?? AppSettingsService();

  final SafStream _safStream;
  final MediaSaveService _mediaSaveService;
  final AppSettingsService _settings;

  static final _album = albumNameForSource('WhatsApp Archive');

  /// Copies any [statuses] not already archived into the archive album.
  /// Returns how many were newly archived. Never throws.
  Future<int> archiveNew(List<StatusItem> statuses) async {
    if (statuses.isEmpty) return 0;
    final ledger = await _settings.getArchivedStatusLedger();
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempDir = await getTemporaryDirectory();

    var archived = 0;
    for (final status in statuses) {
      if (ledger.containsKey(status.name)) continue;
      final tempPath =
          '${tempDir.path}/wa_archive_${now}_${archived}_${status.name}';
      try {
        await _safStream.copyToLocalFile(status.uri, tempPath);
        if (status.mediaType == StatusMediaType.image) {
          await _mediaSaveService.saveImage(tempPath, album: _album);
        } else {
          await _mediaSaveService.saveVideo(tempPath, album: _album);
        }
        ledger[status.name] = now;
        archived++;
      } catch (_) {
        // Skip this one; try the rest.
      } finally {
        final f = File(tempPath);
        if (await f.exists()) await f.delete();
      }
    }

    // Drop ledger entries well past the retention window — the files are
    // gone from the gallery and the source status is long gone from
    // WhatsApp, so re-archiving can't happen anyway. Keeps the ledger small.
    final retention = await _settings.getStatusArchiveRetention();
    final keepAfter = now -
        (retention.duration + const Duration(days: 3)).inMilliseconds;
    ledger.removeWhere((_, ts) => ts < keepAfter);

    await _settings.setArchivedStatusLedger(ledger);
    return archived;
  }

  /// Deletes archived statuses older than [retention]. No-op for
  /// [Duration.zero]. Never throws.
  Future<int> pruneExpired(Duration retention) {
    if (retention == Duration.zero) return Future.value(0);
    return _mediaSaveService.pruneAlbum(_album, retention);
  }
}
