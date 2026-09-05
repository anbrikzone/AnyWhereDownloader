import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';

import '../changelog/changelog.dart';

/// The public GitHub repository whose Releases feed is checked for a newer
/// APK. Format `owner/repo`. See `RELEASE.md` for how releases are cut and
/// which assets they must carry.
///
/// While this is left as the placeholder the check is inert — [checkForUpdate]
/// treats a 404 the same as "no newer version" and returns null.
const String kUpdateRepoSlug = 'anbrikzone/AnyWhereDownloader';

/// One downloadable file attached to a GitHub release.
class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.downloadUrl,
    required this.sizeBytes,
  });

  final String name;
  final String downloadUrl;
  final int sizeBytes;
}

/// A release newer than the running app, as resolved from GitHub.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.tagName,
    required this.htmlUrl,
    required this.releaseNotes,
    required this.assets,
  });

  /// Parsed, `v`-stripped version (e.g. `0.3.0`).
  final String version;
  final String tagName;

  /// The release's page on GitHub — the fallback if in-app install fails.
  final String htmlUrl;

  /// The release body as authored on GitHub. English-only Markdown; shown
  /// as plain text (same accepted caveat as the native notification
  /// strings — see CLAUDE.md "Multi-language support").
  final String releaseNotes;

  final List<UpdateAsset> assets;

  /// The asset matching the device's ABIs, preferring the order the
  /// platform lists them (so `arm64-v8a` wins on a 64-bit device). Null if
  /// the release carries no APK for any supported ABI.
  UpdateAsset? assetForAbis(List<String> supportedAbis) {
    for (final abi in supportedAbis) {
      for (final asset in assets) {
        if (asset.name.contains(abi) &&
            asset.name.toLowerCase().endsWith('.apk')) {
          return asset;
        }
      }
    }
    return null;
  }
}

/// Checks the configured GitHub repo's latest release against [kAppVersion].
///
/// Every failure mode — no network, non-200, malformed JSON, placeholder
/// repo slug — resolves to `null` ("nothing to update to"), never an
/// exception: the caller runs this best-effort on cold start.
class UpdateService {
  UpdateService({http.Client? client, this.repoSlug = kUpdateRepoSlug})
      : _client = client ?? http.Client();

  /// `owner/repo` to check. Defaults to [kUpdateRepoSlug]; overridable for
  /// tests.
  final String repoSlug;

  final http.Client _client;

  Future<UpdateInfo?> checkForUpdate() async {
    if (repoSlug == 'OWNER/REPO' || !repoSlug.contains('/')) return null;
    try {
      final res = await _client.get(
        Uri.parse('https://api.github.com/repos/$repoSlug/releases/latest'),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'AnyWhereDownloader',
        },
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final tagName = (body['tag_name'] as String?)?.trim();
      if (tagName == null || tagName.isEmpty) return null;

      final latest = _tryParse(tagName);
      final current = _tryParse(kAppVersion);
      if (latest == null || current == null) return null;
      if (latest <= current) return null;

      final assets = <UpdateAsset>[];
      for (final raw in (body['assets'] as List<dynamic>? ?? const [])) {
        final map = raw as Map<String, dynamic>;
        final name = map['name'] as String?;
        final url = map['browser_download_url'] as String?;
        if (name == null || url == null) continue;
        assets.add(UpdateAsset(
          name: name,
          downloadUrl: url,
          sizeBytes: (map['size'] as num?)?.toInt() ?? 0,
        ));
      }

      return UpdateInfo(
        version: latest.toString(),
        tagName: tagName,
        htmlUrl: (body['html_url'] as String?) ??
            'https://github.com/$repoSlug/releases',
        releaseNotes: (body['body'] as String?)?.trim() ?? '',
        assets: assets,
      );
    } catch (_) {
      return null;
    }
  }

  static Version? _tryParse(String raw) {
    var s = raw.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    try {
      return Version.parse(s);
    } catch (_) {
      return null;
    }
  }
}
