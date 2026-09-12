import 'package:photo_manager/photo_manager.dart';

const libraryAlbumPrefix = 'AnyWhereDownloader';
const _unknownSource = 'Unknown';

/// The gallery album name a service should save into to have its files
/// show up in Library tagged with [source] — e.g. `albumNameForSource('YouTube')`.
/// The source is derived purely from the album name (no DB): Library reads
/// it back by stripping the shared prefix, per an explicit decision to keep
/// no download-history database (confirmed with the user).
///
/// [source] is sanitized of `/`/`\` — found on-device (`X/Twitter`) that a
/// literal slash here isn't cosmetic: the result becomes a MediaStore
/// `RELATIVE_PATH` (see `MediaSaveService`), where Android treats `/` as a
/// real folder separator, silently splitting one intended album into a
/// nested folder pair whose bucket name no longer matches
/// [loadDownloadedAssets]'s prefix check at all.
String albumNameForSource(String source) =>
    '$libraryAlbumPrefix - ${source.replaceAll(RegExp(r'[\\/]'), '-')}';

/// The gallery album name for one item of a downloaded playlist — adds a
/// third segment to [albumNameForSource] so Library can group these into a
/// drill-in folder instead of mixing them into the flat per-service list —
/// e.g. `albumNameForPlaylist('YouTube', 'Chill Mix')` ->
/// `AnyWhereDownloader - YouTube - Chill Mix`.
///
/// [playlistTitle] gets the same `/`/`\` sanitizing as [albumNameForSource]'s
/// [source] (see its doc — a literal separator here would nest the album
/// under a different bucket instead of naming it) and is capped to 80 chars,
/// matching the filename cap already used for downloaded files
/// (`YouTubeController.suggestedFileName`), so an unusually long playlist
/// title can't overflow a MediaStore path component.
String albumNameForPlaylist(String source, String playlistTitle) {
  var label = playlistTitle.replaceAll(RegExp(r'[\\/]'), '-').trim();
  if (label.length > 80) label = label.substring(0, 80);
  if (label.isEmpty) label = 'Playlist';
  return '${albumNameForSource(source)} - $label';
}

/// Parses a gallery album name back into (source, playlistLabel) — the
/// inverse of [albumNameForSource]/[albumNameForPlaylist]. Returns null for
/// an album that doesn't carry the shared [libraryAlbumPrefix] at all (not
/// expected in practice — callers only ever run this over an already
/// prefix-filtered album list).
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

/// One file in the Library, tagged with the source and (for a playlist
/// download) the sub-folder label derived from its containing album name —
/// see [albumNameForPlaylist].
class LibraryItem {
  LibraryItem({
    required this.asset,
    required this.source,
    required this.albumName,
    this.playlistLabel,
  });

  final AssetEntity asset;
  final String source;

  /// Non-null for a playlist item — the third album-name segment. Library
  /// groups items sharing a (source, playlistLabel) pair into one folder
  /// instead of listing them individually at the top level.
  final String? playlistLabel;

  /// The raw gallery album (bucket) name this item was read from — kept
  /// verbatim (not reconstructed from [source]/[playlistLabel]) so a caller
  /// that needs the real on-disk album, e.g. to clean up a now-empty
  /// directory after deleting every item in it (see
  /// `MediaSaveService.cleanupEmptyAlbumDir`), can't drift from what
  /// `albumNameForSource`/`albumNameForPlaylist` actually produced.
  final String albumName;
}

/// Thin wrapper over `photo_manager`, isolating the package the same way
/// `SafService` isolates `saf_util`. All downloads (video and image alike)
/// currently land under `Pictures/<album>` — confirmed via `adb shell`, see
/// `MediaSaveService` — but `RequestType.common` plus filtering by album
/// name means this doesn't depend on that: it returns one `AssetPathEntity`
/// per root that has a matching bucket regardless of which root that is,
/// and merges them into one list so the rest of the app sees a single
/// library either way.
class MediaLibraryService {
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
    final paths = await PhotoManager.getAssetPathList(
      hasAll: false,
      // common (image + video) plus audio — YouTube audio-only downloads
      // land in `Music/AnyWhereDownloader - YouTube/`, which `photo_manager`
      // groups by bucket name the same as image/video, so the album-name
      // filter below picks them up with no other change.
      type: RequestType.common + RequestType.audio,
    );
    final matching = paths.where(
      (p) =>
          p.name == libraryAlbumPrefix ||
          p.name.startsWith('$libraryAlbumPrefix - '),
    );

    final items = <LibraryItem>[];
    for (final path in matching) {
      final parsed = parseLibraryAlbumName(path.name);
      if (parsed == null) continue;
      final count = await path.assetCountAsync;
      if (count == 0) continue;
      final assets = await path.getAssetListRange(start: 0, end: count);
      items.addAll(
        assets.map(
          (a) => LibraryItem(
            asset: a,
            source: parsed.source,
            albumName: path.name,
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
}
