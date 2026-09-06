import 'package:flutter/foundation.dart';

/// The app's current version, shown in Settings and used as the newest
/// changelog entry's version. Keep this in sync with `pubspec.yaml`'s
/// `version:` field and the top entry of both [kChangelog] and the
/// project-root `CHANGELOG.md`.
const String kAppVersion = '0.3.6';

/// The kind of change a changelog line describes. Rendered as a small
/// section header ("Added" / "Changed" / "Fixed"); a kind with no lines is
/// omitted. ("Removed" isn't used — nothing has been removed so far; add a
/// value here if that changes.)
enum ChangeKind { added, changed, fixed }

/// One released version's worth of user-facing notes, grouped by [ChangeKind]
/// and localized. Plain feature descriptions — what changed and why a user
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

  /// `localeCode` → (`ChangeKind` → lines). `en` is required and is the
  /// fallback for any locale not present.
  final Map<String, Map<ChangeKind, List<String>>> notes;

  Map<ChangeKind, List<String>> notesFor(String localeCode) =>
      notes[localeCode] ?? notes['en']!;
}

/// Full changelog, newest first. This is the source the in-app "What's
/// new" screen renders; the project-root `CHANGELOG.md` mirrors it for
/// people reading the repo. Update both together on every release.
const List<ChangelogEntry> kChangelog = [
  ChangelogEntry(
    version: '0.3.6',
    date: '2026-09-06',
    notes: {
      'en': {
        ChangeKind.changed: [
          'Rebuilt the full-screen video player (Library and WhatsApp status viewers): tap anywhere to show or hide the controls — only the centre button plays/pauses; double-tap the left or right side to skip 10 seconds; a chunkier progress bar with a round grab handle that highlights while dragged; and a 1× / 1.5× / 2× speed button.',
        ],
      },
      'ru': {
        ChangeKind.changed: [
          'Переработан полноэкранный видеоплеер (просмотр в Библиотеке и статусов WhatsApp): тап в любом месте показывает/скрывает управление — воспроизведение переключает только центральная кнопка; двойной тап слева или справа — перемотка на 10 секунд; более толстая полоса прогресса с круглым бегунком, который подсвечивается при перетаскивании; кнопка скорости 1× / 1.5× / 2×.',
        ],
      },
      'kk': {
        ChangeKind.changed: [
          'Толық экранды бейне ойнатқыш қайта жасалды (Кітапхана мен WhatsApp статустарын қарауда): кез келген жерді түрту басқаруды көрсетеді/жасырады — ойнатуды тек ортаңғы түйме ауыстырады; сол не оң жақты қос түрту — 10 секундқа айналдыру; дөңгелек, сүйрегенде ерекшеленетін тұтқасы бар қалыңдау прогресс жолағы; 1× / 1.5× / 2× жылдамдық түймесі.',
        ],
      },
    },
  ),
  ChangelogEntry(
    version: '0.3.5',
    date: '2026-09-06',
    notes: {
      'en': {
        ChangeKind.added: [
          'Download a whole YouTube playlist, or tick just the videos you want, at one shared quality (best / up to 1080p / 720p / 360p / MP3 320).',
        ],
        ChangeKind.changed: [
          'The WhatsApp status archive is now a private in-app copy under a new "Archived" tab on the WhatsApp screen — archived statuses no longer go to your gallery or the Library unless you save them yourself.',
        ],
        ChangeKind.fixed: [
          'Double-tapping a zoomed-in photo now zooms it back out, in both the WhatsApp status viewer and the Library viewer.',
        ],
      },
      'ru': {
        ChangeKind.added: [
          'Скачивание плейлиста YouTube целиком или только отмеченных роликов, в одном общем качестве (лучшее / до 1080p / 720p / 360p / MP3 320).',
        ],
        ChangeKind.changed: [
          'Архив статусов WhatsApp теперь локальная копия внутри приложения во вкладке «Архив» на экране WhatsApp — архивные статусы больше не попадают в галерею и Библиотеку, пока вы не сохраните их сами.',
        ],
        ChangeKind.fixed: [
          'Двойное касание по приближённому фото теперь возвращает масштаб обратно — и в просмотре статусов WhatsApp, и в просмотрщике Библиотеки.',
        ],
      },
      'kk': {
        ChangeKind.added: [
          'YouTube ойнату тізімін толығымен немесе тек белгіленген бейнелерді бір ортақ сапада жүктеу (ең жоғары / 1080p / 720p / 360p / MP3 320 дейін).',
        ],
        ChangeKind.changed: [
          'WhatsApp статустарының мұрағаты енді WhatsApp экранындағы «Мұрағат» қойындысындағы қолданба ішіндегі жеке көшірме — мұрағатталған статустар өзіңіз сақтамайынша галереяға да, Кітапханаға да түспейді.',
        ],
        ChangeKind.fixed: [
          'Үлкейтілген фотоны қос түрту енді масштабты қайтарады — WhatsApp статустары мен Кітапхана қараушысында да.',
        ],
      },
    },
  ),
  ChangelogEntry(
    version: '0.3.4',
    date: '2026-09-05',
    notes: {
      'en': {
        ChangeKind.added: [
          'Pinch and double-tap to zoom photos in the WhatsApp status viewer, and swipe between statuses — same as the Library viewer.',
          'Optional WhatsApp status archive (Settings → WhatsApp): keep viewed statuses for 1 week or 1 month so they survive WhatsApp clearing its cache.',
        ],
      },
      'ru': {
        ChangeKind.added: [
          'Масштабирование фото щипком и двойным касанием в просмотре статусов WhatsApp, а также перелистывание между статусами — как в просмотрщике Библиотеки.',
          'Необязательный архив статусов WhatsApp (Настройки → WhatsApp): хранить просмотренные статусы неделю или месяц, чтобы они не пропали после очистки кэша WhatsApp.',
        ],
      },
      'kk': {
        ChangeKind.added: [
          'WhatsApp статустарын қараушыда фотоны шымшу және қос түртумен масштабтау, сондай-ақ статустар арасында сырғыту — Кітапхана қараушысындағыдай.',
          'WhatsApp статустарының қосымша мұрағаты (Параметрлер → WhatsApp): WhatsApp кэшін тазалағаннан кейін жоғалмауы үшін көрілген статустарды бір апта немесе бір ай сақтау.',
        ],
      },
    },
  ),
  ChangelogEntry(
    version: '0.3.3',
    date: '2026-09-05',
    notes: {
      'en': {
        ChangeKind.changed: [
          'The quality chooser is now a compact, scrollable sheet with separate Video and Audio sections.',
        ],
        ChangeKind.fixed: [
          'Photos and videos opened tiny in the full-screen viewer.',
          'Downloaded audio: tapping the Library tile now opens the player, the seek bar is within thumb reach, and the broken cover image is gone.',
        ],
      },
      'ru': {
        ChangeKind.changed: [
          'Выбор качества теперь компактный прокручиваемый список с отдельными разделами «Видео» и «Аудио».',
        ],
        ChangeKind.fixed: [
          'Фото и видео открывались крохотными в полноэкранном просмотре.',
          'Скачанное аудио: тап по плитке в Библиотеке открывает плеер, ползунок перемотки в зоне досягаемости пальца, битая обложка убрана.',
        ],
      },
      'kk': {
        ChangeKind.changed: [
          'Сапаны таңдау енді бөлек «Бейне» және «Аудио» бөлімдері бар ықшам, айналдырылатын тізім.',
        ],
        ChangeKind.fixed: [
          'Фото мен бейне толық экранды қараушыда өте кішкентай ашылатын.',
          'Жүктелген аудио: Кітапханадағы тақтайшаны түрткенде плеер ашылады, айналдыру жолағы саусақ жететін жерде, бұзылған мұқаба суреті жойылды.',
        ],
      },
    },
  ),
  ChangelogEntry(
    version: '0.3.2',
    date: '2026-09-05',
    notes: {
      'en': {
        ChangeKind.added: [
          'Download just the audio from a YouTube video — MP3 at 320, 192 or 128 kbps, or keep the original M4A. Saved to your Music folder and listed in the Library.',
        ],
        ChangeKind.fixed: [
          'Pinch-to-zoom on a photo in the full-screen viewer no longer flicks to the next item.',
        ],
      },
      'ru': {
        ChangeKind.added: [
          'Скачивание только звука из видео YouTube — MP3 320, 192 или 128 kbps либо оригинал M4A. Сохраняется в папку Music и показывается в Библиотеке.',
        ],
        ChangeKind.fixed: [
          'Масштабирование фото щипком в полноэкранном просмотре больше не перелистывает на следующий файл.',
        ],
      },
      'kk': {
        ChangeKind.added: [
          'YouTube бейнесінен тек дыбысты жүктеу — MP3 320, 192 немесе 128 kbps не түпнұсқа M4A. Music қалтасына сақталып, Кітапханада көрсетіледі.',
        ],
        ChangeKind.fixed: [
          'Толық экранды қараушыда фотоны шымшып масштабтау енді келесі файлға өтіп кетпейді.',
        ],
      },
    },
  ),
  ChangelogEntry(
    version: '0.3.1',
    date: '2026-09-05',
    notes: {
      'en': {
        ChangeKind.added: [
          'Pinch and double-tap to zoom photos in the full-screen viewer.',
        ],
        ChangeKind.changed: [
          'Saving a single photo no longer shows a one-item chooser — it downloads right away.',
          'The per-service on/off switches moved to their own screen, opened from a single Settings row.',
        ],
      },
      'ru': {
        ChangeKind.added: [
          'Масштабирование фото щипком и двойным касанием в полноэкранном просмотре.',
        ],
        ChangeKind.changed: [
          'Сохранение одиночного фото больше не показывает выбор из одного пункта — загрузка начинается сразу.',
          'Переключатели сервисов вынесены на отдельный экран, который открывается одной строкой в настройках.',
        ],
      },
      'kk': {
        ChangeKind.added: [
          'Толық экранды қараушыда фотоны шымшу және қос түртумен масштабтау.',
        ],
        ChangeKind.changed: [
          'Жалғыз фотоны сақтау енді бір тармақты таңдауды көрсетпейді — жүктеу бірден басталады.',
          'Қызметтердің қосу/өшіру ауыстырғыштары бөлек экранға шығарылды, ол параметрлердегі бір жолмен ашылады.',
        ],
      },
    },
  ),
  ChangelogEntry(
    version: '0.3.0',
    date: '2026-09-05',
    notes: {
      'en': {
        ChangeKind.added: [
          'The app can now update itself: Settings → About → Check for updates downloads and installs the newest version for you.',
          'It also checks quietly in the background once a day and shows a dot on the settings icon when an update is ready.',
        ],
      },
      'ru': {
        ChangeKind.added: [
          'Приложение теперь умеет обновляться само: «Настройки → О приложении → Проверить обновления» скачает и установит новую версию за вас.',
          'Раз в день оно также тихо проверяет обновления в фоне и показывает точку на значке настроек, когда обновление готово.',
        ],
      },
      'kk': {
        ChangeKind.added: [
          'Қолданба енді өзін-өзі жаңарта алады: «Параметрлер → Қолданба туралы → Жаңартуларды тексеру» жаңа нұсқаны жүктеп, орнатады.',
          'Сондай-ақ ол күніне бір рет фонда үнсіз тексеріп, жаңарту дайын болғанда параметрлер белгішесінде нүкте көрсетеді.',
        ],
      },
    },
  ),
  ChangelogEntry(
    version: '0.2.0',
    date: '2026-09-05',
    notes: {
      'en': {
        ChangeKind.added: [
          'LinkedIn is now supported: paste a link to a public post or feed video to download it.',
          'Photos as well as videos: single-image posts from Instagram, X (Twitter) and LinkedIn can now be downloaded.',
          'The Library tab refreshes on its own when you switch back to it, so files you just downloaded show up without a manual refresh.',
        ],
        ChangeKind.fixed: [
          'Some downloads whose title contained a "#" failed to save to the gallery.',
        ],
      },
      'ru': {
        ChangeKind.added: [
          'Добавлена поддержка LinkedIn: вставьте ссылку на публичный пост или видео из ленты, чтобы скачать его.',
          'Не только видео, но и фото: теперь можно скачивать одиночные изображения из постов Instagram, X (Twitter) и LinkedIn.',
          'Вкладка «Библиотека» обновляется сама при возврате на неё — только что скачанные файлы появляются без ручного обновления.',
        ],
        ChangeKind.fixed: [
          'Некоторые загрузки с символом «#» в названии не сохранялись в галерею.',
        ],
      },
      'kk': {
        ChangeKind.added: [
          'LinkedIn қолдауы қосылды: жүктеу үшін ашық жазбаға немесе таспадағы бейнеге сілтемені қойыңыз.',
          'Тек бейне ғана емес, фото да: енді Instagram, X (Twitter) және LinkedIn жазбаларынан жеке суреттерді жүктеуге болады.',
          '«Кітапхана» қойындысы оған қайта ауысқанда өзі жаңарады — жаңа ғана жүктелген файлдар қолмен жаңартусыз көрінеді.',
        ],
        ChangeKind.fixed: [
          'Атауында «#» таңбасы бар кейбір жүктеулер галереяға сақталмайтын.',
        ],
      },
    },
  ),
  ChangelogEntry(
    version: '0.1.0',
    date: '2026-09-03',
    notes: {
      'en': {
        ChangeKind.added: [
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
      },
      'ru': {
        ChangeKind.added: [
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
      },
      'kk': {
        ChangeKind.added: [
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
    },
  ),
];
