import 'package:anywhere_downloader/core/l10n/current_l10n.dart';
import 'package:anywhere_downloader/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    final l10n = lookupAppLocalizations(locale);

    test('${locale.languageCode}: playlist summary keeps the native placeholders', () {
      // YtDlpDownloadService substitutes these literally after the run.
      final text = l10n.notificationPlaylistSummary('Mix', '{saved}', '{total}');
      expect(text, contains('{saved}'));
      expect(text, contains('{total}'));
      expect(text, contains('Mix'));
    });

    test('${locale.languageCode}: every notification string is non-empty', () {
      for (final s in [
        l10n.notificationDownloading,
        l10n.notificationPaused,
        l10n.notificationDownloadComplete,
        l10n.notificationDownloadFailed,
        l10n.notificationTapToOpen,
        l10n.notificationPhaseVideo,
        l10n.notificationPhaseAudio,
        l10n.notificationPhaseMerging,
        l10n.notificationPhaseConverting,
        l10n.notificationPhasePlaylist,
        l10n.notificationChannelDownloads,
        l10n.notificationChannelComplete,
        l10n.notificationSavedToGallery(3),
        l10n.notificationSavedWithFailures(2, 1),
      ]) {
        expect(s.trim(), isNotEmpty);
      }
    });
  }

  test('CurrentL10n falls back to English and reports real changes only', () {
    expect(CurrentL10n.value.localeName, isNotEmpty);
    final ru = lookupAppLocalizations(const Locale('ru'));
    CurrentL10n.update(ru);
    expect(CurrentL10n.update(ru), isFalse);
    expect(CurrentL10n.value.notificationTapToOpen, ru.notificationTapToOpen);
    expect(CurrentL10n.update(lookupAppLocalizations(const Locale('kk'))), isTrue);
  });
}
