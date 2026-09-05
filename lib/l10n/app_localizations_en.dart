// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get navHome => 'Home';

  @override
  String get navLibrary => 'Library';

  @override
  String get settingsTooltip => 'Settings';

  @override
  String get clipboardLinkPasted => 'Link pasted from clipboard';

  @override
  String get clearTooltip => 'Clear';

  @override
  String get goButton => 'Go';

  @override
  String get fetchingButton => 'Fetching…';

  @override
  String get pauseButton => 'Pause';

  @override
  String get resumeButton => 'Resume';

  @override
  String get cancelButton => 'Cancel';

  @override
  String get retryButton => 'Retry';

  @override
  String get shareButton => 'Share';

  @override
  String get sharingButton => 'Sharing…';

  @override
  String get deleteButton => 'Delete';

  @override
  String get renameTooltip => 'Rename before downloading';

  @override
  String get saveAsTitle => 'Save as';

  @override
  String get fileNameLabel => 'File name';

  @override
  String get downloadButton => 'Download';

  @override
  String get sizeUnknown => 'size unknown';

  @override
  String get imageLabel => 'Photo';

  @override
  String get homeUrlHint => 'Paste a video link';

  @override
  String get linkNotRecognized => 'Link not recognized or not supported yet';

  @override
  String get whatsappNotSupportedYet => 'This service isn\'t supported yet';

  @override
  String get serviceDisabledLabel => 'Disabled';

  @override
  String serviceDisabledSnack(String service) {
    return '$service is disabled — enable it in Settings';
  }

  @override
  String get youtubeUrlHint => 'Paste a YouTube video link.';

  @override
  String get youtubeUrlLabel => 'YouTube URL';

  @override
  String get tiktokUrlHint => 'Paste a TikTok video link.';

  @override
  String get tiktokUrlLabel => 'TikTok URL';

  @override
  String get xTwitterUrlHint => 'Paste an X/Twitter post link.';

  @override
  String get xTwitterUrlLabel => 'X/Twitter URL';

  @override
  String get instagramUrlHint => 'Paste an Instagram reel/post link.';

  @override
  String get instagramUrlLabel => 'Instagram URL';

  @override
  String get linkedinUrlHint => 'Paste a LinkedIn post link.';

  @override
  String get linkedinUrlLabel => 'LinkedIn URL';

  @override
  String downloadingPercent(String percent) {
    return 'Downloading… $percent%';
  }

  @override
  String pausedPercent(String percent) {
    return 'Paused $percent%';
  }

  @override
  String downloadingVideoPercent(String percent) {
    return 'Downloading video… $percent%';
  }

  @override
  String downloadingAudioPercent(String percent) {
    return 'Downloading audio… $percent%';
  }

  @override
  String mergingPercent(String percent) {
    return 'Merging video and audio… $percent%';
  }

  @override
  String get mergingIndeterminate => 'Merging video and audio…';

  @override
  String itemsSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get cancelSelectionTooltip => 'Cancel selection';

  @override
  String get selectTooltip => 'Select';

  @override
  String get refreshTooltip => 'Refresh';

  @override
  String get changeFolderTooltip => 'Change folder';

  @override
  String get whatsappPickFolderInstructions =>
      'To show statuses, pick your WhatsApp status folder. The picker will open already positioned there — just tap \"use this folder\".';

  @override
  String get whatsappPickFolderNote =>
      'Note: a status has to be opened/viewed in WhatsApp itself first, otherwise it isn\'t cached on the device yet.';

  @override
  String get whatsappNoStatuses =>
      'No statuses available right now.\nOpen a status in WhatsApp, then refresh.';

  @override
  String couldNotReadFolder(String error) {
    return 'Could not read the folder.\n$error';
  }

  @override
  String get pickFolderAgainButton => 'Pick folder again';

  @override
  String get savingButton => 'Saving…';

  @override
  String saveCountButton(int count) {
    return 'Save ($count)';
  }

  @override
  String get libraryTitle => 'Library';

  @override
  String get sortTooltip => 'Sort';

  @override
  String get newestFirst => 'Newest first';

  @override
  String get oldestFirst => 'Oldest first';

  @override
  String get nameAZ => 'Name (A–Z)';

  @override
  String get nameZA => 'Name (Z–A)';

  @override
  String couldNotLoadLibrary(String error) {
    return 'Could not load your library.\n$error';
  }

  @override
  String get filterAll => 'All';

  @override
  String get noFilesForFilter => 'No files for this filter.';

  @override
  String get libraryAccessDenied =>
      'Access was denied. If tapping below does nothing, Android has stopped showing the permission prompt — open Settings and allow access manually.';

  @override
  String get libraryAllowAccessPrompt =>
      'To show your downloaded files, allow access to your gallery.';

  @override
  String get tryAgainButton => 'Try again';

  @override
  String get allowAccessButton => 'Allow access';

  @override
  String get openSettingsButton => 'Open Settings';

  @override
  String get libraryNoDownloads =>
      'No downloads yet.\nFiles you save from YouTube or WhatsApp will show up here.';

  @override
  String shareCountButton(int count) {
    return 'Share ($count)';
  }

  @override
  String get downloadAlreadyInProgress => 'A download is already in progress';

  @override
  String get notYoutubeLink => 'That doesn\'t look like a YouTube link';

  @override
  String get notTiktokLink => 'That doesn\'t look like a TikTok link';

  @override
  String get notXTwitterLink => 'That doesn\'t look like an X/Twitter link';

  @override
  String get notInstagramLink => 'That doesn\'t look like an Instagram link';

  @override
  String get notLinkedinLink => 'That doesn\'t look like a LinkedIn link';

  @override
  String couldNotFetchVideo(String error) {
    return 'Could not fetch this video: $error';
  }

  @override
  String couldNotFetchPost(String error) {
    return 'Could not fetch this post: $error';
  }

  @override
  String get savedMessage => 'Saved';

  @override
  String get downloadCanceledMessage => 'Download canceled';

  @override
  String downloadFailedMessage(String error) {
    return 'Download failed: $error';
  }

  @override
  String get couldNotShareFiles => 'Could not share the selected files';

  @override
  String whatsappSavedCount(int succeeded) {
    return 'Saved: $succeeded';
  }

  @override
  String whatsappSavedFailedCount(int succeeded, int failed) {
    return 'Saved: $succeeded, failed: $failed';
  }

  @override
  String deletedCount(int count) {
    return 'Deleted: $count';
  }

  @override
  String deleteFailed(String error) {
    return 'Delete failed: $error';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get appearanceSection => 'Appearance';

  @override
  String get systemDefaultOption => 'System default';

  @override
  String get lightThemeOption => 'Light';

  @override
  String get darkThemeOption => 'Dark';

  @override
  String get servicesSection => 'Services';

  @override
  String servicesEnabledSubtitle(int enabled, int total) {
    return '$enabled of $total enabled';
  }

  @override
  String get clipboardSection => 'Clipboard';

  @override
  String get clipboardAutoPasteTitle => 'Auto-paste recognized links';

  @override
  String get clipboardAutoPasteSubtitle =>
      'Automatically fill in a supported link copied to the clipboard';

  @override
  String get languageSection => 'Language';

  @override
  String get aboutSection => 'About';

  @override
  String get whatsNewTitle => 'What\'s new';

  @override
  String get changelogAdded => 'Added';

  @override
  String get changelogChanged => 'Changed';

  @override
  String get changelogFixed => 'Fixed';

  @override
  String versionLabel(String version) {
    return 'Version $version';
  }

  @override
  String get checkForUpdatesTitle => 'Check for updates';

  @override
  String get updateChecking => 'Checking…';

  @override
  String get updateUpToDate => 'You\'re on the latest version';

  @override
  String updateAvailable(String version) {
    return 'Version $version available';
  }

  @override
  String get updateReleaseNotesTitle => 'What\'s new in this version';

  @override
  String updateDownloadButton(String size) {
    return 'Download ($size)';
  }

  @override
  String get updateDownloadButtonPlain => 'Download';

  @override
  String get updateInstallButton => 'Install now';

  @override
  String get updateRetryButton => 'Try again';

  @override
  String get updateDownloadingLabel => 'Downloading update…';

  @override
  String get updateFailed => 'Update failed — open the release page instead';

  @override
  String get updatePermissionNeeded =>
      'Allow installing apps from this source, then tap Install again';

  @override
  String get updateOpenReleasePage => 'Open release page';

  @override
  String get updateNoAsset => 'No compatible download for this device';
}
