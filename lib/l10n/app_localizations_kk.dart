// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Kazakh (`kk`).
class AppLocalizationsKk extends AppLocalizations {
  AppLocalizationsKk([String locale = 'kk']) : super(locale);

  @override
  String get navHome => 'Басты бет';

  @override
  String get navLibrary => 'Кітапхана';

  @override
  String get settingsTooltip => 'Параметрлер';

  @override
  String get clipboardLinkPasted => 'Сілтеме алмасу буферінен қойылды';

  @override
  String get clearTooltip => 'Тазалау';

  @override
  String get goButton => 'Өту';

  @override
  String get fetchingButton => 'Алынуда…';

  @override
  String get pauseButton => 'Кідірту';

  @override
  String get resumeButton => 'Жалғастыру';

  @override
  String get cancelButton => 'Бас тарту';

  @override
  String get retryButton => 'Қайталау';

  @override
  String get shareButton => 'Бөлісу';

  @override
  String get sharingButton => 'Бөлісілуде…';

  @override
  String get deleteButton => 'Жою';

  @override
  String get renameTooltip => 'Жүктеу алдында атын өзгерту';

  @override
  String get saveAsTitle => 'Былай сақтау';

  @override
  String get fileNameLabel => 'Файл атауы';

  @override
  String get downloadButton => 'Жүктеу';

  @override
  String get sizeUnknown => 'өлшемі белгісіз';

  @override
  String get imageLabel => 'Фото';

  @override
  String get homeUrlHint => 'Бейне сілтемесін қойыңыз';

  @override
  String get linkNotRecognized =>
      'Сілтеме танылмады немесе әлі қолдау көрсетілмейді';

  @override
  String get whatsappNotSupportedYet => 'Бұл қызмет әлі қолдау көрсетілмейді';

  @override
  String get serviceDisabledLabel => 'Өшірілген';

  @override
  String serviceDisabledSnack(String service) {
    return '$service өшірілген — оны параметрлерде қосыңыз';
  }

  @override
  String get youtubeUrlHint =>
      'YouTube бейнесінің немесе ойнату тізімінің сілтемесін қойыңыз.';

  @override
  String get youtubeUrlLabel => 'YouTube сілтемесі';

  @override
  String get playlistPickerTitle => 'Ойнату тізімі';

  @override
  String playlistVideosCount(int count) {
    return 'Бейне: $count';
  }

  @override
  String playlistSelectedCount(int selected, int total) {
    return '$total ішінен $selected таңдалды';
  }

  @override
  String get playlistSelectAll => 'Барлығы';

  @override
  String get playlistSelectNone => 'Алып тастау';

  @override
  String get playlistQualityHeading => 'Сапасы (барлық бейне үшін)';

  @override
  String playlistDownloadButton(int count) {
    return 'Жүктеу ($count)';
  }

  @override
  String playlistProgressLabel(int done, int total) {
    return 'Ойнату тізімі: $done / $total';
  }

  @override
  String playlistSavedResult(int saved, int failed) {
    return 'Ойнату тізімі: $saved сақталды, $failed қате';
  }

  @override
  String couldNotFetchPlaylist(String error) {
    return 'Ойнату тізімін жүктеу мүмкін болмады: $error';
  }

  @override
  String get playlistLinkDialogTitle => 'Бұл — ойнату тізімінің сілтемесі';

  @override
  String get playlistLinkDialogBody =>
      'Бүкіл ойнату тізімін жүктеу керек пе, әлде тек осы бейнені ме?';

  @override
  String get playlistLinkWhole => 'Бүкіл тізім';

  @override
  String get playlistLinkThisVideo => 'Тек бейне';

  @override
  String get tiktokUrlHint => 'TikTok бейнесінің сілтемесін қойыңыз.';

  @override
  String get tiktokUrlLabel => 'TikTok сілтемесі';

  @override
  String get xTwitterUrlHint => 'X/Twitter жазбасының сілтемесін қойыңыз.';

  @override
  String get xTwitterUrlLabel => 'X/Twitter сілтемесі';

  @override
  String get instagramUrlHint => 'Instagram рилс/жазба сілтемесін қойыңыз.';

  @override
  String get instagramUrlLabel => 'Instagram сілтемесі';

  @override
  String get linkedinUrlHint => 'LinkedIn жазбасының сілтемесін қойыңыз.';

  @override
  String get linkedinUrlLabel => 'LinkedIn сілтемесі';

  @override
  String downloadingPercent(String percent) {
    return 'Жүктелуде… $percent%';
  }

  @override
  String pausedPercent(String percent) {
    return 'Кідіртілді $percent%';
  }

  @override
  String downloadingVideoPercent(String percent) {
    return 'Бейне жүктелуде… $percent%';
  }

  @override
  String downloadingAudioPercent(String percent) {
    return 'Аудио жүктелуде… $percent%';
  }

  @override
  String mergingPercent(String percent) {
    return 'Бейне мен аудио біріктірілуде… $percent%';
  }

  @override
  String get mergingIndeterminate => 'Бейне мен аудио біріктірілуде…';

  @override
  String convertingAudioPercent(String percent) {
    return 'Аудио түрлендірілуде… $percent%';
  }

  @override
  String get convertingAudioIndeterminate => 'Аудио түрлендірілуде…';

  @override
  String get audioOriginalLabel => 'Түпнұсқа (M4A)';

  @override
  String get formatSectionVideo => 'Бейне';

  @override
  String get formatSectionAudio => 'Аудио';

  @override
  String itemsSelectedCount(int count) {
    return 'Таңдалды: $count';
  }

  @override
  String get cancelSelectionTooltip => 'Таңдауды болдырмау';

  @override
  String get selectTooltip => 'Таңдау';

  @override
  String get refreshTooltip => 'Жаңарту';

  @override
  String get changeFolderTooltip => 'Қапшықты өзгерту';

  @override
  String get whatsappPickFolderInstructions =>
      'Статустарды көрсету үшін WhatsApp статус қапшығын таңдаңыз. Таңдау терезесі бірден керек жерде ашылады — тек «осы қапшықты пайдалану» түймесін басыңыз.';

  @override
  String get whatsappPickFolderNote =>
      'Ескерту: статус алдымен WhatsApp қолданбасының өзінде ашылған/қаралған болуы керек, әйтпесе ол құрылғыда әлі сақталмаған.';

  @override
  String get whatsappNoStatuses =>
      'Қазір статустар жоқ.\nWhatsApp-та статусты ашып, содан кейін жаңартыңыз.';

  @override
  String get statusTabRecent => 'Соңғылар';

  @override
  String get statusTabArchived => 'Мұрағат';

  @override
  String get whatsappArchiveEmpty =>
      'Мұрағат әзірге бос.\nМұрағат қосулы тұрғанда көрілген статустар осында автоматты түрде сақталады.';

  @override
  String couldNotReadFolder(String error) {
    return 'Қапшықты оқу мүмкін болмады.\n$error';
  }

  @override
  String get pickFolderAgainButton => 'Қапшықты қайта таңдау';

  @override
  String get savingButton => 'Сақталуда…';

  @override
  String saveCountButton(int count) {
    return 'Сақтау ($count)';
  }

  @override
  String get libraryTitle => 'Кітапхана';

  @override
  String get sortTooltip => 'Сұрыптау';

  @override
  String get newestFirst => 'Алдымен жаңалары';

  @override
  String get oldestFirst => 'Алдымен ескілері';

  @override
  String get nameAZ => 'Атауы бойынша (А–Я)';

  @override
  String get nameZA => 'Атауы бойынша (Я–А)';

  @override
  String couldNotLoadLibrary(String error) {
    return 'Кітапхананы жүктеу мүмкін болмады.\n$error';
  }

  @override
  String get filterAll => 'Барлығы';

  @override
  String get noFilesForFilter => 'Бұл сүзгі бойынша файлдар жоқ.';

  @override
  String get libraryAccessDenied =>
      'Рұқсат берілмеді. Төмендегі түймені басу ешнәрсе істемесе, Android жүйелік сұрауды көрсетуді тоқтатқан — параметрлерді ашып, рұқсатты қолмен беріңіз.';

  @override
  String get libraryAllowAccessPrompt =>
      'Жүктелген файлдарды көрсету үшін галереяға рұқсат беріңіз.';

  @override
  String get tryAgainButton => 'Қайта көру';

  @override
  String get allowAccessButton => 'Рұқсат беру';

  @override
  String get openSettingsButton => 'Параметрлерді ашу';

  @override
  String get libraryNoDownloads =>
      'Әзірге жүктеулер жоқ.\nYouTube немесе WhatsApp-тан сақталған файлдар осында пайда болады.';

  @override
  String shareCountButton(int count) {
    return 'Бөлісу ($count)';
  }

  @override
  String get downloadAlreadyInProgress => 'Жүктеу әлдеқашан орындалуда';

  @override
  String get notYoutubeLink => 'Бұл YouTube сілтемесіне ұқсамайды';

  @override
  String get notTiktokLink => 'Бұл TikTok сілтемесіне ұқсамайды';

  @override
  String get notXTwitterLink => 'Бұл X/Twitter сілтемесіне ұқсамайды';

  @override
  String get notInstagramLink => 'Бұл Instagram сілтемесіне ұқсамайды';

  @override
  String get notLinkedinLink => 'Бұл LinkedIn сілтемесіне ұқсамайды';

  @override
  String couldNotFetchVideo(String error) {
    return 'Бейнені алу мүмкін болмады: $error';
  }

  @override
  String couldNotFetchPost(String error) {
    return 'Жазбаны алу мүмкін болмады: $error';
  }

  @override
  String get savedMessage => 'Сақталды';

  @override
  String get downloadCanceledMessage => 'Жүктеу тоқтатылды';

  @override
  String downloadFailedMessage(String error) {
    return 'Жүктеу сәтсіз аяқталды: $error';
  }

  @override
  String get couldNotShareFiles => 'Таңдалған файлдармен бөлісу мүмкін болмады';

  @override
  String whatsappSavedCount(int succeeded) {
    return 'Сақталды: $succeeded';
  }

  @override
  String whatsappSavedFailedCount(int succeeded, int failed) {
    return 'Сақталды: $succeeded, сәтсіз: $failed';
  }

  @override
  String deletedCount(int count) {
    return 'Жойылды: $count';
  }

  @override
  String deleteFailed(String error) {
    return 'Жою сәтсіз аяқталды: $error';
  }

  @override
  String statusesArchivedCount(int count) {
    return 'Кітапханаға қосылды: $count';
  }

  @override
  String get settingsTitle => 'Параметрлер';

  @override
  String get appearanceSection => 'Сыртқы түрі';

  @override
  String get systemDefaultOption => 'Жүйе бойынша әдепкі';

  @override
  String get lightThemeOption => 'Ашық';

  @override
  String get darkThemeOption => 'Қараңғы';

  @override
  String get servicesSection => 'Қызметтер';

  @override
  String servicesEnabledSubtitle(int enabled, int total) {
    return '$total ішінен $enabled қосулы';
  }

  @override
  String get clipboardSection => 'Алмасу буфері';

  @override
  String get clipboardAutoPasteTitle => 'Танылған сілтемелерді автоматты қою';

  @override
  String get clipboardAutoPasteSubtitle =>
      'Алмасу буферіне көшірілген қолдау көрсетілетін сілтемені автоматты түрде қою';

  @override
  String get whatsappSection => 'WhatsApp';

  @override
  String get statusArchiveTitle => 'Статустарды мұрағаттау';

  @override
  String get statusArchiveSubtitle =>
      'WhatsApp жойғаннан кейін көрілген статустардың жеке көшірмесін WhatsApp қойындысында сақтау. Оларды сақтағанша Кітапханаға түспейді.';

  @override
  String get statusArchiveOff => 'Өшірулі';

  @override
  String get statusArchiveWeek => 'Бір апта сақтау';

  @override
  String get statusArchiveMonth => 'Бір ай сақтау';

  @override
  String get languageSection => 'Тіл';

  @override
  String get aboutSection => 'Қолданба туралы';

  @override
  String get whatsNewTitle => 'Не жаңалық';

  @override
  String get changelogAdded => 'Қосылды';

  @override
  String get changelogChanged => 'Өзгертілді';

  @override
  String get changelogFixed => 'Түзетілді';

  @override
  String versionLabel(String version) {
    return '$version нұсқасы';
  }

  @override
  String get checkForUpdatesTitle => 'Жаңартуларды тексеру';

  @override
  String get updateChecking => 'Тексерілуде…';

  @override
  String get updateUpToDate => 'Соңғы нұсқа орнатылған';

  @override
  String updateAvailable(String version) {
    return '$version нұсқасы қолжетімді';
  }

  @override
  String get updateReleaseNotesTitle => 'Осы нұсқадағы жаңалықтар';

  @override
  String updateDownloadButton(String size) {
    return 'Жүктеу ($size)';
  }

  @override
  String get updateDownloadButtonPlain => 'Жүктеу';

  @override
  String get updateInstallButton => 'Орнату';

  @override
  String get updateRetryButton => 'Қайталау';

  @override
  String get updateDownloadingLabel => 'Жаңарту жүктелуде…';

  @override
  String get updateFailed => 'Жаңарту сәтсіз аяқталды — шығарылым бетін ашыңыз';

  @override
  String get updatePermissionNeeded =>
      'Осы көзден қолданба орнатуға рұқсат етіп, «Орнату» түймесін қайта басыңыз';

  @override
  String get updateOpenReleasePage => 'Шығарылым бетін ашу';

  @override
  String get updateNoAsset => 'Бұл құрылғыға үйлесімді жүктеме жоқ';
}
