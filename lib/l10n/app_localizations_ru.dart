// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get navHome => 'Главная';

  @override
  String get navLibrary => 'Библиотека';

  @override
  String get settingsTooltip => 'Настройки';

  @override
  String get clipboardLinkPasted => 'Ссылка вставлена из буфера обмена';

  @override
  String get clearTooltip => 'Очистить';

  @override
  String get goButton => 'Перейти';

  @override
  String get fetchingButton => 'Получение…';

  @override
  String get pauseButton => 'Пауза';

  @override
  String get resumeButton => 'Продолжить';

  @override
  String get cancelButton => 'Отмена';

  @override
  String get retryButton => 'Повторить';

  @override
  String get shareButton => 'Поделиться';

  @override
  String get sharingButton => 'Отправка…';

  @override
  String get deleteButton => 'Удалить';

  @override
  String get renameTooltip => 'Переименовать перед загрузкой';

  @override
  String get saveAsTitle => 'Сохранить как';

  @override
  String get fileNameLabel => 'Имя файла';

  @override
  String get downloadButton => 'Скачать';

  @override
  String get sizeUnknown => 'размер неизвестен';

  @override
  String get imageLabel => 'Фото';

  @override
  String get homeUrlHint => 'Вставьте ссылку на видео';

  @override
  String get linkNotRecognized =>
      'Ссылка не распознана или пока не поддерживается';

  @override
  String get whatsappNotSupportedYet => 'Этот сервис пока не поддерживается';

  @override
  String get serviceDisabledLabel => 'Отключено';

  @override
  String serviceDisabledSnack(String service) {
    return '$service отключён — включите его в настройках';
  }

  @override
  String get youtubeUrlHint => 'Вставьте ссылку на видео YouTube.';

  @override
  String get youtubeUrlLabel => 'Ссылка YouTube';

  @override
  String get tiktokUrlHint => 'Вставьте ссылку на видео TikTok.';

  @override
  String get tiktokUrlLabel => 'Ссылка TikTok';

  @override
  String get xTwitterUrlHint => 'Вставьте ссылку на пост X/Twitter.';

  @override
  String get xTwitterUrlLabel => 'Ссылка X/Twitter';

  @override
  String get instagramUrlHint => 'Вставьте ссылку на рилс/пост Instagram.';

  @override
  String get instagramUrlLabel => 'Ссылка Instagram';

  @override
  String get linkedinUrlHint => 'Вставьте ссылку на пост LinkedIn.';

  @override
  String get linkedinUrlLabel => 'Ссылка LinkedIn';

  @override
  String downloadingPercent(String percent) {
    return 'Загрузка… $percent%';
  }

  @override
  String pausedPercent(String percent) {
    return 'Пауза $percent%';
  }

  @override
  String downloadingVideoPercent(String percent) {
    return 'Загрузка видео… $percent%';
  }

  @override
  String downloadingAudioPercent(String percent) {
    return 'Загрузка аудио… $percent%';
  }

  @override
  String mergingPercent(String percent) {
    return 'Объединение видео и аудио… $percent%';
  }

  @override
  String get mergingIndeterminate => 'Объединение видео и аудио…';

  @override
  String convertingAudioPercent(String percent) {
    return 'Конвертация аудио… $percent%';
  }

  @override
  String get convertingAudioIndeterminate => 'Конвертация аудио…';

  @override
  String get audioOriginalLabel => 'Оригинал (M4A)';

  @override
  String get formatSectionVideo => 'Видео';

  @override
  String get formatSectionAudio => 'Аудио';

  @override
  String itemsSelectedCount(int count) {
    return 'Выбрано: $count';
  }

  @override
  String get cancelSelectionTooltip => 'Отменить выбор';

  @override
  String get selectTooltip => 'Выбрать';

  @override
  String get refreshTooltip => 'Обновить';

  @override
  String get changeFolderTooltip => 'Сменить папку';

  @override
  String get whatsappPickFolderInstructions =>
      'Чтобы показать статусы, выберите папку статусов WhatsApp. Средство выбора откроется уже в нужном месте — просто нажмите «использовать эту папку».';

  @override
  String get whatsappPickFolderNote =>
      'Примечание: статус нужно сначала открыть/просмотреть в самом WhatsApp, иначе он ещё не сохранён на устройстве.';

  @override
  String get whatsappNoStatuses =>
      'Сейчас статусов нет.\nОткройте статус в WhatsApp, затем обновите.';

  @override
  String couldNotReadFolder(String error) {
    return 'Не удалось прочитать папку.\n$error';
  }

  @override
  String get pickFolderAgainButton => 'Выбрать папку заново';

  @override
  String get savingButton => 'Сохранение…';

  @override
  String saveCountButton(int count) {
    return 'Сохранить ($count)';
  }

  @override
  String get libraryTitle => 'Библиотека';

  @override
  String get sortTooltip => 'Сортировка';

  @override
  String get newestFirst => 'Сначала новые';

  @override
  String get oldestFirst => 'Сначала старые';

  @override
  String get nameAZ => 'По имени (А–Я)';

  @override
  String get nameZA => 'По имени (Я–А)';

  @override
  String couldNotLoadLibrary(String error) {
    return 'Не удалось загрузить библиотеку.\n$error';
  }

  @override
  String get filterAll => 'Все';

  @override
  String get noFilesForFilter => 'Нет файлов по этому фильтру.';

  @override
  String get libraryAccessDenied =>
      'В доступе отказано. Если нажатие ниже ничего не делает, значит Android перестал показывать системный запрос — откройте настройки и разрешите доступ вручную.';

  @override
  String get libraryAllowAccessPrompt =>
      'Чтобы показать скачанные файлы, разрешите доступ к галерее.';

  @override
  String get tryAgainButton => 'Повторить попытку';

  @override
  String get allowAccessButton => 'Разрешить доступ';

  @override
  String get openSettingsButton => 'Открыть настройки';

  @override
  String get libraryNoDownloads =>
      'Пока нет загрузок.\nФайлы, сохранённые из YouTube или WhatsApp, появятся здесь.';

  @override
  String shareCountButton(int count) {
    return 'Поделиться ($count)';
  }

  @override
  String get downloadAlreadyInProgress => 'Загрузка уже выполняется';

  @override
  String get notYoutubeLink => 'Это не похоже на ссылку YouTube';

  @override
  String get notTiktokLink => 'Это не похоже на ссылку TikTok';

  @override
  String get notXTwitterLink => 'Это не похоже на ссылку X/Twitter';

  @override
  String get notInstagramLink => 'Это не похоже на ссылку Instagram';

  @override
  String get notLinkedinLink => 'Это не похоже на ссылку LinkedIn';

  @override
  String couldNotFetchVideo(String error) {
    return 'Не удалось получить видео: $error';
  }

  @override
  String couldNotFetchPost(String error) {
    return 'Не удалось получить пост: $error';
  }

  @override
  String get savedMessage => 'Сохранено';

  @override
  String get downloadCanceledMessage => 'Загрузка отменена';

  @override
  String downloadFailedMessage(String error) {
    return 'Загрузка не удалась: $error';
  }

  @override
  String get couldNotShareFiles => 'Не удалось поделиться выбранными файлами';

  @override
  String whatsappSavedCount(int succeeded) {
    return 'Сохранено: $succeeded';
  }

  @override
  String whatsappSavedFailedCount(int succeeded, int failed) {
    return 'Сохранено: $succeeded, не удалось: $failed';
  }

  @override
  String deletedCount(int count) {
    return 'Удалено: $count';
  }

  @override
  String deleteFailed(String error) {
    return 'Не удалось удалить: $error';
  }

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get appearanceSection => 'Оформление';

  @override
  String get systemDefaultOption => 'Как в системе';

  @override
  String get lightThemeOption => 'Светлая';

  @override
  String get darkThemeOption => 'Тёмная';

  @override
  String get servicesSection => 'Сервисы';

  @override
  String servicesEnabledSubtitle(int enabled, int total) {
    return 'Включено: $enabled из $total';
  }

  @override
  String get clipboardSection => 'Буфер обмена';

  @override
  String get clipboardAutoPasteTitle => 'Автовставка распознанных ссылок';

  @override
  String get clipboardAutoPasteSubtitle =>
      'Автоматически подставлять поддерживаемую ссылку, скопированную в буфер обмена';

  @override
  String get languageSection => 'Язык';

  @override
  String get aboutSection => 'О приложении';

  @override
  String get whatsNewTitle => 'Что нового';

  @override
  String get changelogAdded => 'Добавлено';

  @override
  String get changelogChanged => 'Изменено';

  @override
  String get changelogFixed => 'Исправлено';

  @override
  String versionLabel(String version) {
    return 'Версия $version';
  }

  @override
  String get checkForUpdatesTitle => 'Проверить обновления';

  @override
  String get updateChecking => 'Проверка…';

  @override
  String get updateUpToDate => 'Установлена последняя версия';

  @override
  String updateAvailable(String version) {
    return 'Доступна версия $version';
  }

  @override
  String get updateReleaseNotesTitle => 'Что нового в этой версии';

  @override
  String updateDownloadButton(String size) {
    return 'Скачать ($size)';
  }

  @override
  String get updateDownloadButtonPlain => 'Скачать';

  @override
  String get updateInstallButton => 'Установить';

  @override
  String get updateRetryButton => 'Повторить';

  @override
  String get updateDownloadingLabel => 'Загрузка обновления…';

  @override
  String get updateFailed => 'Не удалось обновить — откройте страницу релиза';

  @override
  String get updatePermissionNeeded =>
      'Разрешите установку приложений из этого источника и нажмите «Установить» снова';

  @override
  String get updateOpenReleasePage => 'Открыть страницу релиза';

  @override
  String get updateNoAsset => 'Нет совместимой загрузки для этого устройства';
}
