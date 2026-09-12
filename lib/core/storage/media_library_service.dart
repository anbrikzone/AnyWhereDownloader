import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import 'media_save_service.dart';

const libraryAlbumPrefix = 'AnyWhereDownloader';
const _unknownSource = 'Unknown';

/// **Legacy** (superseded 2026-09-12 by [relativePathForSource] below, kept
/// only so the one-time migration in [MediaLibraryService] can recognize old
/// buckets). The gallery album name a service used to save into — one flat,
/// dash-joined bucket name — e.g. `albumNameForSource('YouTube')` ->
/// `AnyWhereDownloader - YouTube`.
///
/// [source] is sanitized of `/`/`\` — found on-device (`X/Twitter`) that a
/// literal slash here isn't cosmetic: the result becomes a MediaStore
/// `RELATIVE_PATH` (see `MediaSaveService`), where Android treats `/` as a
/// real folder separator, silently splitting one intended album into a
/// nested folder pair whose bucket name no longer matches
/// [parseLibraryAlbumName]'s prefix check at all.
String albumNameForSource(String source) =>
    '$libraryAlbumPrefix - ${source.replaceAll(RegExp(r'[\\/]'), '-')}';

/// **Legacy** (see [albumNameForSource]). The gallery album name a
/// playlist's items used to save into — a third dash-joined segment on the
/// same flat bucket name, e.g. `albumNameForPlaylist('YouTube', 'Chill
/// Mix')` -> `AnyWhereDownloader - YouTube - Chill Mix`.
String albumNameForPlaylist(String source, String playlistTitle) {
  var label = playlistTitle.replaceAll(RegExp(r'[\\/]'), '-').trim();
  if (label.length > 80) label = label.substring(0, 80);
  if (label.isEmpty) label = 'Playlist';
  return '${albumNameForSource(source)} - $label';
}

/// **Legacy** (see [albumNameForSource]). Parses one of the old flat album
/// names back into (source, playlistLabel) — the inverse of
/// [albumNameForSource]/[albumNameForPlaylist]. Returns null for a name that
/// doesn't carry the shared [libraryAlbumPrefix] at all.
({String source, String? playlistLabel})? parseLibraryAlbumName(String albumName) {
  if (albumName == libraryAlbumPrefix) {
    return (source: _unknownSource, playlistLabel: null);
  }
  final prefixDash = '$libraryAlbumPrefix - ';
  if (!albumName.startsWith(prefixDash)) return null;
  final tail = albumName.substring(prefixDash.length);
  // A playlist album has a third " - "-separated segment (see
  // `albumNameForPlaylist`); split on the *first* occurrence only — a plain
  // service name never contains " - " today, but a playlist title
  // legitimately might.
  final sep = tail.indexOf(' - ');
  if (sep == -1) return (source: tail, playlistLabel: null);
  return (source: tail.substring(0, sep), playlistLabel: tail.substring(sep + 3));
}

/// Shared root every download lands under, going forward — a real nested
/// directory (`Pictures/AnyWhereDownloader/<Service>[/<Playlist>]`, same
/// under `Music/`), not the flat dash-joined bucket name
/// [albumNameForSource] used to build. Real nesting was tried and initially
/// rejected (see `library/CLAUDE.md`'s "why not nested folders" note) for a
/// real reason — `photo_manager`'s own bucket listing only exposes
/// `BUCKET_DISPLAY_NAME` (a file's *immediate* parent folder name, with no
/// parent/child relationship at all in the MediaStore data model), so a
/// nested `AnyWhereDownloader/YouTube/Chill Mix/` bucket would report a name
/// of plain `"Chill Mix"` with nothing visibly tying it back to this app.
/// The fix, added 2026-09-12: `MediaSaveService.queryLibraryBucketPaths`
/// reads the raw `RELATIVE_PATH` column directly (bypassing that
/// name-only limitation) so [MediaLibraryService] can identify and parse
/// real nested buckets by their actual path instead.
const libraryRootDir = 'AnyWhereDownloader';

String _sanitizePathSegment(String segment) =>
    segment.replaceAll(RegExp(r'[\\/]'), '-').trim();

/// The relativePath (under `Pictures/` or `Music/`) a service's downloads
/// should live under — e.g. `relativePathForSource('YouTube')` ->
/// `AnyWhereDownloader/YouTube`. This is a real multi-segment directory
/// path (unlike the legacy [albumNameForSource]), safe to hand straight to
/// `MediaSaveService`/`photo_manager` as a `relativePath` — Android's
/// `RELATIVE_PATH` column is exactly this kind of path already.
String relativePathForSource(String source) =>
    '$libraryRootDir/${_sanitizePathSegment(source)}';

/// The relativePath for one playlist's downloads — e.g.
/// `relativePathForPlaylist('YouTube', 'Chill Mix')` ->
/// `AnyWhereDownloader/YouTube/Chill Mix`. [playlistTitle] is sanitized
/// (a literal `/`/`\` inside it would otherwise add an unintended extra
/// nesting level) and capped to 80 chars, matching the filename cap already
/// used for downloaded files (`YouTubeController.suggestedFileName`).
String relativePathForPlaylist(String source, String playlistTitle) {
  var label = _sanitizePathSegment(playlistTitle);
  if (label.length > 80) label = label.substring(0, 80);
  if (label.isEmpty) label = 'Playlist';
  return '${relativePathForSource(source)}/$label';
}

/// Parses one bucket's actual MediaStore `RELATIVE_PATH` (as returned by
/// [MediaSaveService.queryLibraryBucketPaths] — e.g.
/// `Pictures/AnyWhereDownloader/YouTube/Chill Mix/` for a new nested
/// playlist folder, or the legacy flat `Pictures/AnyWhereDownloader -
/// YouTube - Chill Mix/`) into (source, playlistLabel, isAudio,
/// isLegacyFlat). Returns null for a path that isn't recognizably one of
/// ours (shouldn't happen in practice — callers only run this over paths
/// [MediaSaveService.queryLibraryBucketPaths] already filtered).
({String source, String? playlistLabel, bool isAudio, bool isLegacyFlat})?
    parseLibraryRelativePath(String relativePath) {
  final isAudio = relativePath.startsWith('Music/');
  if (!isAudio && !relativePath.startsWith('Pictures/')) return null;
  final afterRoot = relativePath.substring(relativePath.indexOf('/') + 1);
  final trimmed =
      afterRoot.endsWith('/') ? afterRoot.substring(0, afterRoot.length - 1) : afterRoot;

  if (trimmed == libraryRootDir) {
    return (source: _unknownSource, playlistLabel: null, isAudio: isAudio, isLegacyFlat: false);
  }
  final nestedPrefix = '$libraryRootDir/';
  if (trimmed.startsWith(nestedPrefix)) {
    final segments = trimmed.substring(nestedPrefix.length).split('/');
    return (
      source: segments.first,
      playlistLabel: segments.length > 1 ? segments.sublist(1).join('/') : null,
      isAudio: isAudio,
      isLegacyFlat: false,
    );
  }
  // Not nested — either a not-yet-migrated legacy flat bucket, or (very
  // unlikely, given the caller's own LIKE-prefix filter) unrelated.
  final legacy = parseLibraryAlbumName(trimmed);
  if (legacy == null) return null;
  return (
    source: legacy.source,
    playlistLabel: legacy.playlistLabel,
    isAudio: isAudio,
    isLegacyFlat: true,
  );
}

/// One file in the Library, tagged with the source and (for a playlist
/// download) the sub-folder label derived from its containing album's
/// relative path — see [parseLibraryRelativePath].
class LibraryItem {
  LibraryItem({
    required this.asset,
    required this.source,
    required this.albumName,
    this.playlistLabel,
  });

  final AssetEntity asset;
  final String source;

  /// Non-null for a playlist item — the folder label. Library groups items
  /// sharing a (source, playlistLabel) pair into one folder instead of
  /// listing them individually at the top level.
  final String? playlistLabel;

  /// This item's containing album, as a relativePath suffix under
  /// `Pictures/`/`Music/` (e.g. `AnyWhereDownloader/YouTube/Chill Mix`, or
  /// the legacy flat `AnyWhereDownloader - YouTube - Chill Mix` for a
  /// not-yet-migrated bucket) — kept verbatim from
  /// [MediaSaveService.queryLibraryBucketPaths] rather than reconstructed
  /// from [source]/[playlistLabel], so a caller that needs the real on-disk
  /// location (e.g. to clean up a now-empty directory after deleting every
  /// item in it, see `MediaSaveService.cleanupEmptyAlbumDir`) can't drift
  /// from what's actually there.
  final String albumName;
}

/// Thin wrapper over `photo_manager`, isolating the package the same way
/// `SafService` isolates `saf_util`. All downloads (video and image alike)
/// currently land under `Pictures/<relativePath>` — confirmed via `adb
/// shell`, see `MediaSaveService` — but `RequestType.common` plus filtering
/// by the actual `RELATIVE_PATH` (via [MediaSaveService.queryLibraryBucketPaths],
/// not `photo_manager`'s own name-only bucket listing) means this doesn't
/// depend on that: it returns one `AssetPathEntity` per root that has a
/// matching bucket regardless of which root that is, and merges them into
/// one list so the rest of the app sees a single library either way.
class MediaLibraryService {
  MediaLibraryService({MediaSaveService? saveService})
    : _saveService = saveService ?? MediaSaveService();

  final MediaSaveService _saveService;

  /// Checks the current permission without prompting.
  Future<PermissionState> currentPermission() {
    return PhotoManager.getPermissionState(
      requestOption: const PermissionRequestOption(),
    );
  }

  /// Actually requests permission — shows the system dialog, at least the
  /// first time (Android may silently stop showing it after a denial).
  Future<PermissionState> ensurePermission() {
    return PhotoManager.requestPermissionExtend();
  }

  /// Opens the app's system settings page, for when a re-request silently
  /// no-ops after a prior denial.
  Future<void> openSettings() => PhotoManager.openSetting();

  Future<List<LibraryItem>> loadDownloadedAssets() async {
    // Must run — and finish — before the bucket-path lookup below: moving a
    // bucket's files changes their `BUCKET_ID` (it's computed from the
    // path), so a `bucketPaths` map fetched *before* migration would still
    // key a just-migrated bucket by its old id and silently drop those
    // items from this pass.
    await migrateLegacyFolders();

    final paths = await PhotoManager.getAssetPathList(
      hasAll: false,
      // common (image + video) plus audio — YouTube audio-only downloads
      // land under `Music/`, which `photo_manager` groups by bucket name
      // the same as image/video.
      type: RequestType.common + RequestType.audio,
    );
    final bucketPaths = await _saveService.queryLibraryBucketPaths();

    final items = <LibraryItem>[];
    for (final path in paths) {
      final relativePath = bucketPaths[path.id];
      if (relativePath == null) continue;
      final parsed = parseLibraryRelativePath(relativePath);
      if (parsed == null) continue;
      final count = await path.assetCountAsync;
      if (count == 0) continue;
      final assets = await path.getAssetListRange(start: 0, end: count);
      final albumName = _stripRoot(relativePath);
      items.addAll(
        assets.map(
          (a) => LibraryItem(
            asset: a,
            source: parsed.source,
            albumName: albumName,
            playlistLabel: parsed.playlistLabel,
          ),
        ),
      );
    }

    items.sort(
      (a, b) => b.asset.createDateTime.compareTo(a.asset.createDateTime),
    );
    return items;
  }

  Future<List<String>> delete(List<String> ids) {
    return PhotoManager.editor.deleteWithIds(ids);
  }

  /// Migrates every old flat, dash-joined bucket still found (see
  /// [albumNameForSource]/[albumNameForPlaylist]) into the new nested
  /// layout (see [relativePathForSource]/[relativePathForPlaylist]) — added
  /// 2026-09-12 after the user pointed out the flat buckets sat mixed in
  /// directly
  /// under `Pictures/` alongside every other app's albums, with no shared
  /// parent folder of their own to sort them apart from the rest.
  ///
  /// Deliberately **not** gated by a persisted "already ran" flag — an
  /// earlier version was, and a real bug in [MediaSaveService.moveBucket]
  /// (matching on a MediaProvider-*computed* `BUCKET_ID` in an `UPDATE`,
  /// never actually verified to work there — `photo_manager`'s own
  /// precedent only ever does this against a genuine column) meant the
  /// first on-device attempt silently moved nothing, and the flag then
  /// permanently skipped every later attempt too. Re-scanning on every
  /// [loadDownloadedAssets] call instead is self-healing: it's a cheap
  /// no-op once nothing legacy remains, and a failed attempt simply retries
  /// next time Library loads rather than getting stuck forever.
  ///
  /// Moves each legacy bucket's files one row at a time through that row's
  /// own type-specific MediaStore collection, matched by the bucket's
  /// actual `RELATIVE_PATH` value (a real column) rather than its
  /// `BUCKET_ID` — see `MediaSaveBridge.moveBucket`'s bug #1–#4 history.
  /// Then best-effort cleans up the now-empty old flat directory.
  ///
  /// **Bug #5 (2026-09-12)**: even for rows this app owns, Android refuses
  /// a `RELATIVE_PATH` move without explicit interactive consent
  /// (`RecoverableSecurityException`) — [MediaSaveService.moveBucket]
  /// surfaces the affected content URIs as `needsPermissionUris` instead of
  /// moving them. Rather than prompt once per bucket (which would mean one
  /// system dialog after another for a library with several legacy
  /// buckets), every bucket's move is attempted first, all the URIs needing
  /// consent are batched across the whole migration, and
  /// [MediaSaveService.requestWriteAccess] is asked **once** for the lot —
  /// then every bucket is retried a single time. If the user declines,
  /// buckets stay legacy-flat and simply get asked again next time Library
  /// loads (this method's self-healing re-scan, not a retry loop here).
  ///
  /// Best-effort throughout — a failure here must never block Library from
  /// loading; an unmigrated bucket is still found and shown correctly via
  /// [parseLibraryRelativePath]'s legacy-flat branch, just not yet moved.
  ///
  /// Not underscore-private so `media_library_service_test.dart` can drive
  /// it directly (via [MediaLibraryService]'s `saveService` injection point)
  /// without going through [loadDownloadedAssets]'s `photo_manager` calls,
  /// which aren't mockable from a plain unit test — [@visibleForTesting]
  /// marks it as not otherwise part of the public API.
  @visibleForTesting
  Future<void> migrateLegacyFolders() async {
    try {
      final bucketPaths = await _saveService.queryLibraryBucketPaths();
      final pendingMoves = <({String oldPath, String newPath, bool isAudio})>[];
      for (final entry in bucketPaths.entries) {
        final oldRelativePath = entry.value;
        final parsed = parseLibraryRelativePath(oldRelativePath);
        if (parsed == null || !parsed.isLegacyFlat) continue;
        final newSuffix = parsed.playlistLabel == null
            ? relativePathForSource(parsed.source)
            : relativePathForPlaylist(parsed.source, parsed.playlistLabel!);
        final root = parsed.isAudio ? 'Music' : 'Pictures';
        pendingMoves.add((
          oldPath: oldRelativePath,
          newPath: '$root/$newSuffix',
          isAudio: parsed.isAudio,
        ));
      }
      if (pendingMoves.isEmpty) return;

      final needsPermission = await _runMoves(pendingMoves);
      if (needsPermission.isNotEmpty) {
        final granted = await _saveService.requestWriteAccess(needsPermission);
        if (granted) await _runMoves(pendingMoves);
      }
    } catch (_) {
      // Best-effort — never block Library from loading over this.
    }
  }

  /// Runs [moves] once, cleaning up any bucket that fully emptied out, and
  /// returns the combined `needsPermissionUris` any of them reported.
  Future<List<String>> _runMoves(
    List<({String oldPath, String newPath, bool isAudio})> moves,
  ) async {
    final needsPermission = <String>[];
    for (final move in moves) {
      final outcome = await _saveService.moveBucket(move.oldPath, move.newPath);
      needsPermission.addAll(outcome.needsPermissionUris);
      if (outcome.total > 0 && outcome.moved == outcome.total) {
        await _saveService.cleanupEmptyAlbumDir(
          _stripRoot(move.oldPath),
          isAudio: move.isAudio,
        );
      }
    }
    return needsPermission;
  }

  /// Strips the leading `Pictures/`/`Music/` root and any trailing slash
  /// MediaStore always stores, leaving the part this app actually built
  /// (e.g. `AnyWhereDownloader/YouTube/Chill Mix`).
  String _stripRoot(String relativePath) {
    final afterRoot = relativePath.substring(relativePath.indexOf('/') + 1);
    return afterRoot.endsWith('/') ? afterRoot.substring(0, afterRoot.length - 1) : afterRoot;
  }
}
