import 'package:flutter/foundation.dart';

/// The app's current version, shown in Settings and used as the newest
/// changelog entry's version. Keep this in sync with `pubspec.yaml`'s
/// `version:` field and the top entry of both [kChangelog] and the
/// project-root `CHANGELOG.md`.
const String kAppVersion = '0.3.0';

/// One released version's worth of user-facing notes, in every supported
/// language. Plain feature descriptions — what changed and why a user
/// would care — not developer/task phrasing.
@immutable
class ChangelogEntry {
  const ChangelogEntry({
    required this.version,
    required this.date,
    required this.notes,
  });

  final String version;

  /// ISO date (`YYYY-MM-DD`), shown as-is.
  final String date;

  /// Bullet lines keyed by locale code (`en`, `ru`, `kk`). `en` is
  /// required and is the fallback for any locale not present.
  final Map<String, List<String>> notes;

  List<String> notesFor(String localeCode) => notes[localeCode] ?? notes['en']!;
}

/// Full changelog, newest first. This is the source the in-app "What's
/// new" screen renders; the project-root `CHANGELOG.md` mirrors it for
/// people reading the repo. Update both together on every release.
const List<ChangelogEntry> kChangelog = [
  ChangelogEntry(
    version: '0.3.0',
    date: '2026-09-05',
    notes: {
      'en': [
        'The app can now update itself: Settings → About → Check for updates downloads and installs the newest version for you.',
        'It also checks quietly in the background once a day and shows a dot on the settings icon when an update is ready.',
      ],
      'ru': [
        'Приложение теперь умеет обновляться само: «Настройки → О приложении → Проверить обновления» скачает и установит новую версию за вас.',
        'Раз в день оно также тихо проверяет обновления в фоне и показывает точку на значке настроек, когда обновление готово.',
      ],
      'kk': [
        'Қолданба енді өзін-өзі жаңарта алады: «Параметрлер → Қолданба туралы → Жаңартуларды тексеру» жаңа нұсқаны жүктеп, орнатады.',
        'Сондай-ақ ол күніне бір рет фонда үнсіз тексеріп, жаңарту дайын болғанда параметрлер белгішесінде нүкте көрсетеді.',
      ],
    },
  ),
  ChangelogEntry(
    version: '0.2.0',
    date: '2026-09-05',
    notes: {
      'en': [
        'LinkedIn is now supported: paste a link to a public post or feed video to download it.',
        'Photos as well as videos: single-image posts from Instagram, X (Twitter) and LinkedIn can now be downloaded.',
        'The Library tab refreshes on its own when you switch back to it, so files you just downloaded show up without a manual refresh.',
        'Fixed a problem where some downloads whose title contained a "#" failed to save to the gallery.',
      ],
      'ru': [
        'Добавлена поддержка LinkedIn: вставьте ссылку на публичный пост или видео из ленты, чтобы скачать его.',
        'Не только видео, но и фото: теперь можно скачивать одиночные изображения из постов Instagram, X (Twitter) и LinkedIn.',
        'Вкладка «Библиотека» обновляется сама при возврате на неё — только что скачанные файлы появляются без ручного обновления.',
        'Исправлена ошибка, из-за которой некоторые загрузки с символом «#» в названии не сохранялись в галерею.',
      ],
      'kk': [
        'LinkedIn қолдауы қосылды: жүктеу үшін ашық жазбаға немесе таспадағы бейнеге сілтемені қойыңыз.',
        'Тек бейне ғана емес, фото да: енді Instagram, X (Twitter) және LinkedIn жазбаларынан жеке суреттерді жүктеуге болады.',
        '«Кітапхана» қойындысы оған қайта ауысқанда өзі жаңарады — жаңа ғана жүктелген файлдар қолмен жаңартусыз көрінеді.',
        'Атауында «#» таңбасы бар кейбір жүктеулердің галереяға сақталмауына әкелген қате түзетілді.',
      ],
    },
  ),
  ChangelogEntry(
    version: '0.1.0',
    date: '2026-09-03',
    notes: {
      'en': [
        'Paste a link — or let the app pick it up from your clipboard — to download videos from YouTube, TikTok, X (Twitter) and Instagram.',
        'Choose the quality before downloading, and rename the file first if you want.',
        'YouTube downloads can go above 360p and can be paused and resumed. A notification shows progress while a download runs.',
        'Save WhatsApp statuses to your gallery, with a preview and quick sharing. Works with both regular WhatsApp and WhatsApp Business.',
        'The Library tab gathers everything you have downloaded, grouped by where it came from, with sorting, multi-select, sharing and delete.',
        'Full-screen viewer: swipe between items, scrub the timeline, and skip forward or back.',
        'Settings: light or dark theme, turn individual services on or off, toggle clipboard auto-paste, and pick the app language.',
        'The app is now available in English, Russian and Kazakh.',
        'This "What\'s new" screen, so you can see what changed in each version.',
      ],
      'ru': [
        'Вставьте ссылку — или дайте приложению взять её из буфера обмена — чтобы скачивать видео с YouTube, TikTok, X (Twitter) и Instagram.',
        'Выбор качества перед загрузкой и переименование файла по желанию.',
        'Загрузки с YouTube поддерживают качество выше 360p, паузу и продолжение. Во время загрузки прогресс виден в уведомлении.',
        'Сохранение статусов WhatsApp в галерею с предпросмотром и быстрой отправкой. Работает и с обычным WhatsApp, и с WhatsApp Business.',
        'Вкладка «Библиотека» собирает всё скачанное с разбивкой по источнику: сортировка, множественный выбор, отправка и удаление.',
        'Полноэкранный просмотр: перелистывание между файлами, перемотка по шкале, переход вперёд и назад.',
        'Настройки: светлая или тёмная тема, включение и отключение отдельных сервисов, автовставка ссылок из буфера обмена, выбор языка приложения.',
        'Приложение теперь доступно на английском, русском и казахском языках.',
        'Экран «Что нового» (этот) — чтобы видеть изменения в каждой версии.',
      ],
      'kk': [
        'Сілтемені қойыңыз — немесе қолданбаға оны алмасу буферінен алуға рұқсат етіңіз — YouTube, TikTok, X (Twitter) және Instagram бейнелерін жүктеу үшін.',
        'Жүктеу алдында сапаны таңдау және қаласаңыз файл атауын алдын ала өзгерту.',
        'YouTube жүктеулері 360p-дан жоғары сапаны, кідірту мен жалғастыруды қолдайды. Жүктеу кезінде орындалу барысы хабарландыруда көрінеді.',
        'WhatsApp статустарын алдын ала қарау және жылдам бөлісумен галереяға сақтау. Кәдімгі WhatsApp-та да, WhatsApp Business-те де жұмыс істейді.',
        '«Кітапхана» қойындысы жүктелген барлық нәрсені дереккөзі бойынша топтап жинайды: сұрыптау, бірнеше файлды таңдау, бөлісу және жою.',
        'Толық экранды қараушы: файлдар арасында сырғыту, уақыт жолағын айналдыру, алға және артқа өту.',
        'Параметрлер: ашық немесе қараңғы тақырып, жекелеген қызметтерді қосу/өшіру, алмасу буферінен автоқою, қолданба тілін таңдау.',
        'Қолданба енді ағылшын, орыс және қазақ тілдерінде қолжетімді.',
        'Әр нұсқадағы өзгерістерді көру үшін осы «Не жаңалық» экраны.',
      ],
    },
  ),
];
