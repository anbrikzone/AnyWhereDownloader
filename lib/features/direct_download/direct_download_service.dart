import '../../core/extraction/media_extractor.dart';
import '../../core/l10n/status_message.dart';
import '../../l10n/app_localizations.dart';
import '../../services/instagram/instagram_extractor.dart';
import '../../services/linkedin/linkedin_extractor.dart';
import '../../services/pinterest/pinterest_extractor.dart';
import '../../services/tiktok/tiktok_extractor.dart';
import '../../services/x_twitter/x_twitter_extractor.dart';

/// Everything that differs between the "direct download" services — TikTok,
/// X/Twitter, Instagram, LinkedIn, Pinterest. Each resolves a link to muxed video (or a
/// single photo) and downloads it through the pausable `background_downloader`
/// path, so one [DirectDownloadController] + [DirectDownloadScreen] serve all
/// of them; only this data varies. YouTube (merge/audio/playlist paths) and
/// WhatsApp (SAF, no URL) have their own features.
class DirectDownloadService {
  const DirectDownloadService._({
    required this.type,
    required this.title,
    required this.librarySource,
    required this.createExtractor,
    required this.notHandledKey,
    required this.fetchFailedKey,
    required this.fallbackFileName,
    required this.urlHint,
    required this.urlLabel,
  });

  final ServiceType type;

  /// Brand name for the AppBar — deliberately not localized.
  final String title;

  /// Folder under `AnyWhereDownloader/` in the gallery (`relativePathForSource`).
  final String librarySource;

  final MediaExtractor Function() createExtractor;

  /// "This isn't a `<service>` link" status.
  final StatusMessageKey notHandledKey;

  /// "Could not fetch …: `<error>`" status for a non-`ExtractionException`.
  final StatusMessageKey fetchFailedKey;

  /// Base filename when the post title sanitizes to nothing.
  final String fallbackFileName;

  final String Function(AppLocalizations l10n) urlHint;
  final String Function(AppLocalizations l10n) urlLabel;

  static final tiktok = DirectDownloadService._(
    type: ServiceType.tiktok,
    title: 'TikTok',
    librarySource: 'TikTok',
    createExtractor: TikTokExtractor.new,
    notHandledKey: StatusMessageKey.notTiktokLink,
    fetchFailedKey: StatusMessageKey.couldNotFetchVideo,
    fallbackFileName: 'tiktok',
    urlHint: (l10n) => l10n.tiktokUrlHint,
    urlLabel: (l10n) => l10n.tiktokUrlLabel,
  );

  static final xTwitter = DirectDownloadService._(
    type: ServiceType.xTwitter,
    title: 'X / Twitter',
    // Not 'X/Twitter' — the result becomes a MediaStore `RELATIVE_PATH`,
    // where a literal `/` is a real folder separator: it once created a
    // nested "X" / "Twitter" folder chain whose bucket ("Twitter") never
    // matched `parseLibraryRelativePath`. Found on-device.
    librarySource: 'X-Twitter',
    createExtractor: XTwitterExtractor.new,
    notHandledKey: StatusMessageKey.notXTwitterLink,
    fetchFailedKey: StatusMessageKey.couldNotFetchPost,
    fallbackFileName: 'x_twitter',
    urlHint: (l10n) => l10n.xTwitterUrlHint,
    urlLabel: (l10n) => l10n.xTwitterUrlLabel,
  );

  static final instagram = DirectDownloadService._(
    type: ServiceType.instagram,
    title: 'Instagram',
    librarySource: 'Instagram',
    createExtractor: InstagramExtractor.new,
    notHandledKey: StatusMessageKey.notInstagramLink,
    fetchFailedKey: StatusMessageKey.couldNotFetchPost,
    fallbackFileName: 'instagram',
    urlHint: (l10n) => l10n.instagramUrlHint,
    urlLabel: (l10n) => l10n.instagramUrlLabel,
  );

  static final linkedin = DirectDownloadService._(
    type: ServiceType.linkedin,
    title: 'LinkedIn',
    librarySource: 'LinkedIn',
    createExtractor: LinkedInExtractor.new,
    notHandledKey: StatusMessageKey.notLinkedInLink,
    fetchFailedKey: StatusMessageKey.couldNotFetchPost,
    fallbackFileName: 'linkedin',
    urlHint: (l10n) => l10n.linkedinUrlHint,
    urlLabel: (l10n) => l10n.linkedinUrlLabel,
  );

  static final pinterest = DirectDownloadService._(
    type: ServiceType.pinterest,
    title: 'Pinterest',
    librarySource: 'Pinterest',
    createExtractor: PinterestExtractor.new,
    notHandledKey: StatusMessageKey.notPinterestLink,
    fetchFailedKey: StatusMessageKey.couldNotFetchPost,
    fallbackFileName: 'pinterest',
    urlHint: (l10n) => l10n.pinterestUrlHint,
    urlLabel: (l10n) => l10n.pinterestUrlLabel,
  );

  static final _byType = {
    for (final s in [tiktok, xTwitter, instagram, linkedin, pinterest])
      s.type: s,
  };

  /// Null for a service that isn't a direct-download one (YouTube, WhatsApp).
  static DirectDownloadService? of(ServiceType type) => _byType[type];
}
