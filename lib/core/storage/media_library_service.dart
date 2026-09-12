import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

// ignore: unused_import
import '../settings/app_settings_service.dart'; // for MediaSaveRoot/AudioSaveRoot doc links only
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

/// Every top-level Android directory a photo/video download might live
/// under — see [MediaSaveRoot] (Settings, backlog #18, 2026-09-13). Kept in
/// sync with [MediaSaveRoot]'s values by hand (this file doesn't import
/// `app_settings_service.dart`, to keep the pure path-parsing logic free of
/// a settings-persistence dependency) — [MediaLibraryService]'s own doc
/// notes this in case the two ever drift.
const _mediaRoots = {'Pictures', 'DCIM', 'Movies'};

/// Every top-level Android directory an audio download might live under —
/// see [AudioSaveRoot]. Same hand-sync note as [_mediaRoots].
const _audioRoots = {'Music', 'Podcasts'};

/// Parses one bucket's actual MediaStore `RELATIVE_PATH` (as returned by
/// [MediaSaveService.queryLibraryBucketPaths] — e.g.
/// `Pictures/AnyWhereDownloader/YouTube/Chill Mix/` for a new nested
/// playlist folder, or the legacy flat `Pictures/AnyWhereDownloader -
/// YouTube - Chill Mix/`) into (source, playlistLabel, isAudio,
/// isLegacyFlat, root). [root] is the literal top segment (e.g. `Pictures`)
/// — needed so a caller can clean up the item's *actual* on-disk directory
/// later even if the user has since changed their Settings save-location
/// choice (see `MediaSaveService.cleanupEmptyAlbumDir`). Returns null for a
/// path that isn't recognizably one of ours (shouldn't happen in practice —
/// callers only run this over paths [MediaSaveService.queryLibraryBucketPaths]
/// already filtered).
({String source, String? playlistLabel, bool isAudio, bool isLegacyFlat, String root})?
    parseLibraryRelativePath(String relativePath) {
  final slash = relativePath.indexOf('/');
  if (slash == -1) return null;
  final root = relativePath.substring(0, slash);
  final isAudio = _audioRoots.contains(root);
  if (!isAudio && !_mediaRoots.contains(root)) return null;
  final afterRoot = relativePath.substring(slash + 1);
  final trimmed =
      afterRoot.endsWith('/') ? afterRoot.substring(0, afterRoot.length - 1) : afterRoot;

  if (trimmed == libraryRootDir) {
    return (
      source: _unknownSource,
      playlistLabel: null,
      isAudio: isAudio,
      isLegacyFlat: false,
      root: root,
    );
  }
  final nestedPrefix = '$libraryRootDir/';
  if (trimmed.startsWith(nestedPrefix)) {
    final segments = trimmed.substring(nestedPrefix.length).split('/');
    return (
      source: segments.first,
      playlistLabel: segments.length > 1 ? segments.sublist(1).join('/') : null,
      isAudio: isAudio,
      isLegacyFlat: false,
      root: root,
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
    root: root,
  );
}

/// A batch of legacy-folder moves that got as far as they could without
/// interactive user consent (see [MediaLibraryService.attemptMigration] and
/// [MediaLibraryService.completeMigrationAfterConsent] — split into two
/// steps specifically so the caller can *explain why* before the system
/// consent dialog appears, rather than it popping up with no warning).
/// Opaque to callers beyond checking it's non-null and handing it back.
class PendingMigrationConsent {
  PendingMigrationConsent._(this._moves, this._uris);

  final List<({String oldPath, String newPath, bool isAudio})> _moves;
  final List<String> _uris;
}

/// One file in the Library, tagged with the source and (for a playlist
/// download) the sub-folder label derived from its containing album's
/// relative path — see [parseLibraryRelativePath].
class LibraryItem {
  LibraryItem({
    required this.asset,
    required this.source,
    required this.albumName,
    required this.root,
    this.playlistLabel,
  });

  final AssetEntity asset;
  final String source;

  /// Non-null for a playlist item — the folder label. Library groups items
  /// sharing a (source, playlistLabel) pair into one folder instead of
  /// listing them individually at the top level.
  final String? playlistLabel;

  /// This item's containing album, as a relativePath suffix under its
  /// [root] (e.g. `AnyWhereDownloader/YouTube/Chill Mix`, or the legacy flat
  /// `AnyWhereDownloader - YouTube - Chill Mix` for a not-yet-migrated
  /// bucket) — kept verbatim from [MediaSaveService.queryLibraryBucketPaths]
  /// rather than reconstructed from [source]/[playlistLabel], so a caller
  /// that needs the real on-disk location (e.g. to clean up a now-empty
  /// directory after deleting every item in it, see
  /// `MediaSaveService.cleanupEmptyAlbumDir`) can't drift from what's
  /// actually there.
  final String albumName;

  /// The literal top-level Android directory [albumName] lives under —
  /// `Pictures`/`DCIM`/`Movies` for photo/video, `Music`/`Podcasts` for
  /// audio (see [MediaSaveRoot]/[AudioSaveRoot], Settings, backlog #18).
  /// This is the item's *actual* root, independent of today's Settings
  /// choice — a past download may have used one since changed.
  final String root;
}

/// Thin wrapper over `photo_manager`, isolating the package the same way
/// `SafService` isolates `saf_util`. Downloads land under whichever root
/// Settings has chosen (default `Pictures`/`Music`, see [MediaSaveRoot]/
/// [AudioSaveRoot]) — `RequestType.common` plus filtering by the actual
/// `RELATIVE_PATH` (via [MediaSaveService.queryLibraryBucketPaths], not
/// `photo_manager`'s own name-only bucket listing) means this doesn't
/// depend on any one fixed root: it returns one `AssetPathEntity` per root
/// that has a matching bucket regardless of which root that is, and merges
/// them into one list so the rest of the app sees a single library either
/// way — including a mix of items saved under different roots if the
/// setting was ever changed.
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

  /// Returns the loaded [items] plus, non-null, a [PendingMigrationConsent]
  /// the caller should explain to the user before calling
  /// [completeMigrationAfterConsent] with it (see that method's doc for why
  /// this doesn't just prompt automatically). Items still list correctly
  /// either way — an unmigrated bucket is found via
  /// [parseLibraryRelativePath]'s legacy-flat branch regardless of whether
  /// consent has been granted yet.
  Future<({List<LibraryItem> items, PendingMigrationConsent? pendingConsent})>
      loadDownloadedAssets() async {
    // Must run — and finish — before the bucket-path lookup below: moving a
    // bucket's files changes their `BUCKET_ID` (it's computed from the
    // path), so a `bucketPaths` map fetched *before* migration would still
    // key a just-migrated bucket by its old id and silently drop those
    // items from this pass.
    final pendingConsent = await attemptMigration();

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
            root: parsed.root,
            playlistLabel: parsed.playlistLabel,
          ),
        ),
      );
    }

    items.sort(
      (a, b) => b.asset.createDateTime.compareTo(a.asset.createDateTime),
    );
    return (items: items, pendingConsent: pendingConsent);
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
  /// moving them.
  ///
  /// **On-device feedback (2026-09-13)**: the first version of this method
  /// called [MediaSaveService.requestWriteAccess] itself, so the system
  /// consent dialog could appear with zero warning the moment Library
  /// opened — confirmed working, but the user asked for an explanation
  /// *before* that dialog, and for a clear notice if it's ever declined
  /// (moving pre-existing downloads into the new layout isn't optional —
  /// the app now always organizes into folders, so an unmigrated bucket
  /// should keep getting asked about, not silently give up). Split into
  /// two steps so `LibraryController` can drive that UI: this method
  /// attempts every legacy bucket's move once (no prompt), batches every
  /// URI any of them reported needing consent into one
  /// [PendingMigrationConsent], and returns it for the caller to explain
  /// before calling [completeMigrationAfterConsent] — never null unless
  /// nothing legacy remains or everything moved cleanly on this first
  /// pass. If the caller never calls [completeMigrationAfterConsent] (or
  /// the user declines its system dialog), the affected buckets simply
  /// stay legacy-flat — [loadDownloadedAssets] still shows them correctly
  /// via [parseLibraryRelativePath]'s legacy-flat branch — and get a fresh
  /// [PendingMigrationConsent] (asked about again) the next time Library
  /// loads, since nothing here is gated by a persisted "gave up" flag.
  ///
  /// Regardless of whether an existing download ever gets migrated, every
  /// *new* download already lands directly in the nested layout —
  /// migration only concerns files saved before this rework, never a
  /// reason a fresh save would fall back to the old flat naming.
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
  Future<PendingMigrationConsent?> attemptMigration() async {
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
      if (pendingMoves.isEmpty) return null;

      final needsPermission = await _runMoves(pendingMoves);
      if (needsPermission.isEmpty) return null;
      return PendingMigrationConsent._(pendingMoves, needsPermission);
    } catch (_) {
      // Best-effort — never block Library from loading over this.
      return null;
    }
  }

  /// Shows the batched system write-access consent dialog for [pending] —
  /// one prompt covering every row [attemptMigration] found needing it,
  /// never one dialog per bucket — and, if granted, retries every affected
  /// bucket a single time. Returns whether every bucket in [pending] ended
  /// up fully migrated; `false` (never throws) if the user declined or
  /// anything else went wrong, in which case the caller should tell the
  /// user their files will be organized the next time Library opens rather
  /// than implying the migration is done for good.
  Future<bool> completeMigrationAfterConsent(PendingMigrationConsent pending) async {
    try {
      final granted = await _saveService.requestWriteAccess(pending._uris);
      if (!granted) return false;
      final stillNeeded = await _runMoves(pending._moves);
      return stillNeeded.isEmpty;
    } catch (_) {
      return false;
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
        // The legacy flat naming predates the Settings save-location
        // feature entirely — every legacy bucket always lived under
        // exactly `Pictures`/`Music`, never a user-chosen alternative.
        await _saveService.cleanupEmptyAlbumDir(
          _stripRoot(move.oldPath),
          root: move.isAudio ? 'Music' : 'Pictures',
        );
      }
    }
    return needsPermission;
  }

  /// Strips the leading top-level root (`Pictures`/`DCIM`/`Movies`/`Music`/
  /// `Podcasts`) and any trailing slash MediaStore always stores, leaving
  /// the part this app actually built (e.g.
  /// `AnyWhereDownloader/YouTube/Chill Mix`).
  String _stripRoot(String relativePath) {
    final afterRoot = relativePath.substring(relativePath.indexOf('/') + 1);
    return afterRoot.endsWith('/') ? afterRoot.substring(0, afterRoot.length - 1) : afterRoot;
  }
}
