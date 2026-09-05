import 'package:saf_util/saf_util.dart';
import 'package:saf_util/saf_util_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper around the `saf_util` plugin (Android Storage Access
/// Framework). Isolates every SAF call so the rest of the app never depends
/// directly on the plugin, mirroring the [MediaExtractor] isolation
/// principle used for the extraction services.
class SafService {
  SafService({SafUtil? safUtil}) : _safUtil = safUtil ?? SafUtil();

  final SafUtil _safUtil;

  static const _prefsKeyTreeUri = 'saf_tree_uri';

  /// Returns the previously picked folder URI for [prefsKey], or null if
  /// none was picked yet or the permission is no longer valid.
  Future<String?> getPersistedTreeUri(String prefsKey) async {
    final prefs = await SharedPreferences.getInstance();
    final uri = prefs.getString(_key(prefsKey));
    if (uri == null) return null;

    final stillValid = await _safUtil.hasPersistedPermission(uri);
    if (!stillValid) {
      await prefs.remove(_key(prefsKey));
      return null;
    }
    return uri;
  }

  /// Shows the system folder picker, persists read access to the chosen
  /// folder under [prefsKey], and returns its URI (or null if the user
  /// cancelled the picker). [initialUri], when provided, hints the picker to
  /// open already positioned at that folder (best-effort — some OEM file
  /// managers ignore it).
  Future<String?> pickAndPersistTreeUri(
    String prefsKey, {
    String? initialUri,
  }) async {
    final dir = await _safUtil.pickDirectory(
      initialUri: initialUri,
      writePermission: false,
      persistablePermission: true,
    );
    if (dir == null) return null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(prefsKey), dir.uri);
    return dir.uri;
  }

  /// Releases the persisted permission and forgets the folder for [prefsKey].
  /// Always clears the stored URI, even if releasing the OS-side permission
  /// fails (e.g. it was already invalidated) — otherwise a stale permission
  /// could leave the app stuck unable to forget a folder.
  Future<void> forgetTreeUri(String prefsKey) async {
    final prefs = await SharedPreferences.getInstance();
    final uri = prefs.getString(_key(prefsKey));
    if (uri != null) {
      try {
        await _safUtil.releasePersistedPermission(uri);
      } catch (_) {
        // Ignore — the URI is being forgotten regardless.
      }
    }
    await prefs.remove(_key(prefsKey));
  }

  Future<List<SafDocumentFile>> listFiles(String treeUri) {
    return _safUtil.list(treeUri);
  }

  /// Saves a thumbnail for [uri] (image or video) to [destPath]. Returns
  /// true if a thumbnail was generated.
  Future<bool> saveThumbnailToFile({
    required String uri,
    required int width,
    required int height,
    required String destPath,
  }) {
    return _safUtil.saveThumbnailToFile(
      uri: uri,
      width: width,
      height: height,
      destPath: destPath,
    );
  }

  String _key(String prefsKey) => '$_prefsKeyTreeUri:$prefsKey';
}
