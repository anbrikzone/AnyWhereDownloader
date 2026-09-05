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

/// One file in the Library, tagged with the source derived from its
/// containing album name.
class LibraryItem {
  LibraryItem({required this.asset, required this.source});

  final AssetEntity asset;
  final String source;
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
      final source = path.name == libraryAlbumPrefix
          ? _unknownSource
          : path.name.substring('$libraryAlbumPrefix - '.length);
      final count = await path.assetCountAsync;
      if (count == 0) continue;
      final assets = await path.getAssetListRange(start: 0, end: count);
      items.addAll(assets.map((a) => LibraryItem(asset: a, source: source)));
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
