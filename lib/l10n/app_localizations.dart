import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_kk.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('kk'),
    Locale('ru'),
  ];

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get navLibrary;

  /// No description provided for @settingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTooltip;

  /// No description provided for @clipboardLinkPasted.
  ///
  /// In en, this message translates to:
  /// **'Link pasted from clipboard'**
  String get clipboardLinkPasted;

  /// No description provided for @clearTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearTooltip;

  /// No description provided for @goButton.
  ///
  /// In en, this message translates to:
  /// **'Go'**
  String get goButton;

  /// No description provided for @fetchingButton.
  ///
  /// In en, this message translates to:
  /// **'Fetching…'**
  String get fetchingButton;

  /// No description provided for @pauseButton.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pauseButton;

  /// No description provided for @resumeButton.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resumeButton;

  /// No description provided for @cancelButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelButton;

  /// No description provided for @retryButton.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryButton;

  /// No description provided for @shareButton.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareButton;

  /// No description provided for @sharingButton.
  ///
  /// In en, this message translates to:
  /// **'Sharing…'**
  String get sharingButton;

  /// No description provided for @deleteButton.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteButton;

  /// No description provided for @renameTooltip.
  ///
  /// In en, this message translates to:
  /// **'Rename before downloading'**
  String get renameTooltip;

  /// No description provided for @saveAsTitle.
  ///
  /// In en, this message translates to:
  /// **'Save as'**
  String get saveAsTitle;

  /// No description provided for @fileNameLabel.
  ///
  /// In en, this message translates to:
  /// **'File name'**
  String get fileNameLabel;

  /// No description provided for @downloadButton.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get downloadButton;

  /// No description provided for @sizeUnknown.
  ///
  /// In en, this message translates to:
  /// **'size unknown'**
  String get sizeUnknown;

  /// No description provided for @imageLabel.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get imageLabel;

  /// No description provided for @homeUrlHint.
  ///
  /// In en, this message translates to:
  /// **'Paste a video link'**
  String get homeUrlHint;

  /// No description provided for @linkNotRecognized.
  ///
  /// In en, this message translates to:
  /// **'Link not recognized or not supported yet'**
  String get linkNotRecognized;

  /// No description provided for @whatsappNotSupportedYet.
  ///
  /// In en, this message translates to:
  /// **'This service isn\'t supported yet'**
  String get whatsappNotSupportedYet;

  /// No description provided for @serviceDisabledLabel.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get serviceDisabledLabel;

  /// No description provided for @serviceDisabledSnack.
  ///
  /// In en, this message translates to:
  /// **'{service} is disabled — enable it in Settings'**
  String serviceDisabledSnack(String service);

  /// No description provided for @youtubeUrlHint.
  ///
  /// In en, this message translates to:
  /// **'Paste a YouTube video link.'**
  String get youtubeUrlHint;

  /// No description provided for @youtubeUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'YouTube URL'**
  String get youtubeUrlLabel;

  /// No description provided for @tiktokUrlHint.
  ///
  /// In en, this message translates to:
  /// **'Paste a TikTok video link.'**
  String get tiktokUrlHint;

  /// No description provided for @tiktokUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'TikTok URL'**
  String get tiktokUrlLabel;

  /// No description provided for @xTwitterUrlHint.
  ///
  /// In en, this message translates to:
  /// **'Paste an X/Twitter post link.'**
  String get xTwitterUrlHint;

  /// No description provided for @xTwitterUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'X/Twitter URL'**
  String get xTwitterUrlLabel;

  /// No description provided for @instagramUrlHint.
  ///
  /// In en, this message translates to:
  /// **'Paste an Instagram reel/post link.'**
  String get instagramUrlHint;

  /// No description provided for @instagramUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Instagram URL'**
  String get instagramUrlLabel;

  /// No description provided for @linkedinUrlHint.
  ///
  /// In en, this message translates to:
  /// **'Paste a LinkedIn post link.'**
  String get linkedinUrlHint;

  /// No description provided for @linkedinUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'LinkedIn URL'**
  String get linkedinUrlLabel;

  /// No description provided for @downloadingPercent.
  ///
  /// In en, this message translates to:
  /// **'Downloading… {percent}%'**
  String downloadingPercent(String percent);

  /// No description provided for @pausedPercent.
  ///
  /// In en, this message translates to:
  /// **'Paused {percent}%'**
  String pausedPercent(String percent);

  /// No description provided for @downloadingVideoPercent.
  ///
  /// In en, this message translates to:
  /// **'Downloading video… {percent}%'**
  String downloadingVideoPercent(String percent);

  /// No description provided for @downloadingAudioPercent.
  ///
  /// In en, this message translates to:
  /// **'Downloading audio… {percent}%'**
  String downloadingAudioPercent(String percent);

  /// No description provided for @mergingPercent.
  ///
  /// In en, this message translates to:
  /// **'Merging video and audio… {percent}%'**
  String mergingPercent(String percent);

  /// No description provided for @mergingIndeterminate.
  ///
  /// In en, this message translates to:
  /// **'Merging video and audio…'**
  String get mergingIndeterminate;

  /// No description provided for @convertingAudioPercent.
  ///
  /// In en, this message translates to:
  /// **'Converting audio… {percent}%'**
  String convertingAudioPercent(String percent);

  /// No description provided for @convertingAudioIndeterminate.
  ///
  /// In en, this message translates to:
  /// **'Converting audio…'**
  String get convertingAudioIndeterminate;

  /// No description provided for @audioOriginalLabel.
  ///
  /// In en, this message translates to:
  /// **'Original (M4A)'**
  String get audioOriginalLabel;

  /// No description provided for @formatSectionVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get formatSectionVideo;

  /// No description provided for @formatSectionAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get formatSectionAudio;

  /// No description provided for @itemsSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String itemsSelectedCount(int count);

  /// No description provided for @cancelSelectionTooltip.
  ///
  /// In en, this message translates to:
  /// **'Cancel selection'**
  String get cancelSelectionTooltip;

  /// No description provided for @selectTooltip.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get selectTooltip;

  /// No description provided for @refreshTooltip.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refreshTooltip;

  /// No description provided for @changeFolderTooltip.
  ///
  /// In en, this message translates to:
  /// **'Change folder'**
  String get changeFolderTooltip;

  /// No description provided for @whatsappPickFolderInstructions.
  ///
  /// In en, this message translates to:
  /// **'To show statuses, pick your WhatsApp status folder. The picker will open already positioned there — just tap \"use this folder\".'**
  String get whatsappPickFolderInstructions;

  /// No description provided for @whatsappPickFolderNote.
  ///
  /// In en, this message translates to:
  /// **'Note: a status has to be opened/viewed in WhatsApp itself first, otherwise it isn\'t cached on the device yet.'**
  String get whatsappPickFolderNote;

  /// No description provided for @whatsappNoStatuses.
  ///
  /// In en, this message translates to:
  /// **'No statuses available right now.\nOpen a status in WhatsApp, then refresh.'**
  String get whatsappNoStatuses;

  /// No description provided for @couldNotReadFolder.
  ///
  /// In en, this message translates to:
  /// **'Could not read the folder.\n{error}'**
  String couldNotReadFolder(String error);

  /// No description provided for @pickFolderAgainButton.
  ///
  /// In en, this message translates to:
  /// **'Pick folder again'**
  String get pickFolderAgainButton;

  /// No description provided for @savingButton.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get savingButton;

  /// No description provided for @saveCountButton.
  ///
  /// In en, this message translates to:
  /// **'Save ({count})'**
  String saveCountButton(int count);

  /// No description provided for @libraryTitle.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get libraryTitle;

  /// No description provided for @sortTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sortTooltip;

  /// No description provided for @newestFirst.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get newestFirst;

  /// No description provided for @oldestFirst.
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get oldestFirst;

  /// No description provided for @nameAZ.
  ///
  /// In en, this message translates to:
  /// **'Name (A–Z)'**
  String get nameAZ;

  /// No description provided for @nameZA.
  ///
  /// In en, this message translates to:
  /// **'Name (Z–A)'**
  String get nameZA;

  /// No description provided for @couldNotLoadLibrary.
  ///
  /// In en, this message translates to:
  /// **'Could not load your library.\n{error}'**
  String couldNotLoadLibrary(String error);

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @noFilesForFilter.
  ///
  /// In en, this message translates to:
  /// **'No files for this filter.'**
  String get noFilesForFilter;

  /// No description provided for @libraryAccessDenied.
  ///
  /// In en, this message translates to:
  /// **'Access was denied. If tapping below does nothing, Android has stopped showing the permission prompt — open Settings and allow access manually.'**
  String get libraryAccessDenied;

  /// No description provided for @libraryAllowAccessPrompt.
  ///
  /// In en, this message translates to:
  /// **'To show your downloaded files, allow access to your gallery.'**
  String get libraryAllowAccessPrompt;

  /// No description provided for @tryAgainButton.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgainButton;

  /// No description provided for @allowAccessButton.
  ///
  /// In en, this message translates to:
  /// **'Allow access'**
  String get allowAccessButton;

  /// No description provided for @openSettingsButton.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get openSettingsButton;

  /// No description provided for @libraryNoDownloads.
  ///
  /// In en, this message translates to:
  /// **'No downloads yet.\nFiles you save from YouTube or WhatsApp will show up here.'**
  String get libraryNoDownloads;

  /// No description provided for @shareCountButton.
  ///
  /// In en, this message translates to:
  /// **'Share ({count})'**
  String shareCountButton(int count);

  /// No description provided for @downloadAlreadyInProgress.
  ///
  /// In en, this message translates to:
  /// **'A download is already in progress'**
  String get downloadAlreadyInProgress;

  /// No description provided for @notYoutubeLink.
  ///
  /// In en, this message translates to:
  /// **'That doesn\'t look like a YouTube link'**
  String get notYoutubeLink;

  /// No description provided for @notTiktokLink.
  ///
  /// In en, this message translates to:
  /// **'That doesn\'t look like a TikTok link'**
  String get notTiktokLink;

  /// No description provided for @notXTwitterLink.
  ///
  /// In en, this message translates to:
  /// **'That doesn\'t look like an X/Twitter link'**
  String get notXTwitterLink;

  /// No description provided for @notInstagramLink.
  ///
  /// In en, this message translates to:
  /// **'That doesn\'t look like an Instagram link'**
  String get notInstagramLink;

  /// No description provided for @notLinkedinLink.
  ///
  /// In en, this message translates to:
  /// **'That doesn\'t look like a LinkedIn link'**
  String get notLinkedinLink;

  /// No description provided for @couldNotFetchVideo.
  ///
  /// In en, this message translates to:
  /// **'Could not fetch this video: {error}'**
  String couldNotFetchVideo(String error);

  /// No description provided for @couldNotFetchPost.
  ///
  /// In en, this message translates to:
  /// **'Could not fetch this post: {error}'**
  String couldNotFetchPost(String error);

  /// No description provided for @savedMessage.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get savedMessage;

  /// No description provided for @downloadCanceledMessage.
  ///
  /// In en, this message translates to:
  /// **'Download canceled'**
  String get downloadCanceledMessage;

  /// No description provided for @downloadFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Download failed: {error}'**
  String downloadFailedMessage(String error);

  /// No description provided for @couldNotShareFiles.
  ///
  /// In en, this message translates to:
  /// **'Could not share the selected files'**
  String get couldNotShareFiles;

  /// No description provided for @whatsappSavedCount.
  ///
  /// In en, this message translates to:
  /// **'Saved: {succeeded}'**
  String whatsappSavedCount(int succeeded);

  /// No description provided for @whatsappSavedFailedCount.
  ///
  /// In en, this message translates to:
  /// **'Saved: {succeeded}, failed: {failed}'**
  String whatsappSavedFailedCount(int succeeded, int failed);

  /// No description provided for @deletedCount.
  ///
  /// In en, this message translates to:
  /// **'Deleted: {count}'**
  String deletedCount(int count);

  /// No description provided for @deleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String deleteFailed(String error);

  /// No description provided for @statusesArchivedCount.
  ///
  /// In en, this message translates to:
  /// **'Archived {count} to the Library'**
  String statusesArchivedCount(int count);

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @appearanceSection.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearanceSection;

  /// No description provided for @systemDefaultOption.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get systemDefaultOption;

  /// No description provided for @lightThemeOption.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get lightThemeOption;

  /// No description provided for @darkThemeOption.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get darkThemeOption;

  /// No description provided for @servicesSection.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get servicesSection;

  /// No description provided for @servicesEnabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{enabled} of {total} enabled'**
  String servicesEnabledSubtitle(int enabled, int total);

  /// No description provided for @clipboardSection.
  ///
  /// In en, this message translates to:
  /// **'Clipboard'**
  String get clipboardSection;

  /// No description provided for @clipboardAutoPasteTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-paste recognized links'**
  String get clipboardAutoPasteTitle;

  /// No description provided for @clipboardAutoPasteSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatically fill in a supported link copied to the clipboard'**
  String get clipboardAutoPasteSubtitle;

  /// No description provided for @whatsappSection.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get whatsappSection;

  /// No description provided for @statusArchiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Archive statuses'**
  String get statusArchiveTitle;

  /// No description provided for @statusArchiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Keep viewed statuses in the Library after WhatsApp deletes them'**
  String get statusArchiveSubtitle;

  /// No description provided for @statusArchiveOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get statusArchiveOff;

  /// No description provided for @statusArchiveWeek.
  ///
  /// In en, this message translates to:
  /// **'Keep for 1 week'**
  String get statusArchiveWeek;

  /// No description provided for @statusArchiveMonth.
  ///
  /// In en, this message translates to:
  /// **'Keep for 1 month'**
  String get statusArchiveMonth;

  /// No description provided for @languageSection.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageSection;

  /// No description provided for @aboutSection.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutSection;

  /// No description provided for @whatsNewTitle.
  ///
  /// In en, this message translates to:
  /// **'What\'s new'**
  String get whatsNewTitle;

  /// No description provided for @changelogAdded.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get changelogAdded;

  /// No description provided for @changelogChanged.
  ///
  /// In en, this message translates to:
  /// **'Changed'**
  String get changelogChanged;

  /// No description provided for @changelogFixed.
  ///
  /// In en, this message translates to:
  /// **'Fixed'**
  String get changelogFixed;

  /// No description provided for @versionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String versionLabel(String version);

  /// No description provided for @checkForUpdatesTitle.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get checkForUpdatesTitle;

  /// No description provided for @updateChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get updateChecking;

  /// No description provided for @updateUpToDate.
  ///
  /// In en, this message translates to:
  /// **'You\'re on the latest version'**
  String get updateUpToDate;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Version {version} available'**
  String updateAvailable(String version);

  /// No description provided for @updateReleaseNotesTitle.
  ///
  /// In en, this message translates to:
  /// **'What\'s new in this version'**
  String get updateReleaseNotesTitle;

  /// No description provided for @updateDownloadButton.
  ///
  /// In en, this message translates to:
  /// **'Download ({size})'**
  String updateDownloadButton(String size);

  /// No description provided for @updateDownloadButtonPlain.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get updateDownloadButtonPlain;

  /// No description provided for @updateInstallButton.
  ///
  /// In en, this message translates to:
  /// **'Install now'**
  String get updateInstallButton;

  /// No description provided for @updateRetryButton.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get updateRetryButton;

  /// No description provided for @updateDownloadingLabel.
  ///
  /// In en, this message translates to:
  /// **'Downloading update…'**
  String get updateDownloadingLabel;

  /// No description provided for @updateFailed.
  ///
  /// In en, this message translates to:
  /// **'Update failed — open the release page instead'**
  String get updateFailed;

  /// No description provided for @updatePermissionNeeded.
  ///
  /// In en, this message translates to:
  /// **'Allow installing apps from this source, then tap Install again'**
  String get updatePermissionNeeded;

  /// No description provided for @updateOpenReleasePage.
  ///
  /// In en, this message translates to:
  /// **'Open release page'**
  String get updateOpenReleasePage;

  /// No description provided for @updateNoAsset.
  ///
  /// In en, this message translates to:
  /// **'No compatible download for this device'**
  String get updateNoAsset;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'kk', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'kk':
      return AppLocalizationsKk();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
