import 'package:anywhere_downloader/core/download/download_registry.dart';
import 'package:anywhere_downloader/core/l10n/status_message.dart';
import 'package:anywhere_downloader/features/downloads/downloads_screen.dart';
import 'package:anywhere_downloader/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements DownloadHistoryStore {
  @override
  Future<List<DownloadEntry>> load() async => const [];

  @override
  Future<void> save(List<DownloadEntry> history) async {}
}

Widget _app(DownloadRegistry registry) => ProviderScope(
      overrides: [downloadRegistryProvider.overrideWith((ref) => registry)],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DownloadsScreen(),
      ),
    );

void main() {
  testWidgets('shows an empty state when nothing was downloaded',
      (tester) async {
    final registry = DownloadRegistry(store: _MemoryStore());
    await tester.pumpWidget(_app(registry));
    await tester.pump();
    expect(find.textContaining('No downloads yet'), findsOneWidget);
  });

  testWidgets('active row: cancel-only download routes Cancel to its owner',
      (tester) async {
    final registry = DownloadRegistry(store: _MemoryStore());
    var canceled = 0;
    registry.begin(
      id: '1',
      source: 'Pinterest',
      title: 'pin.mp4',
      kind: DownloadKind.video,
      controls: DownloadControls(cancel: () async => canceled++),
    );
    await tester.pumpWidget(_app(registry));
    await tester.pump();

    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('pin.mp4'), findsOneWidget);
    expect(find.text('Pinterest · Starting download…'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsNothing);

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pump();
    expect(canceled, 1);
  });

  testWidgets('finished downloads are listed under Recent with their outcome',
      (tester) async {
    final registry = DownloadRegistry(store: _MemoryStore());
    registry.begin(
      id: '2',
      source: 'YouTube',
      title: 'song.mp3',
      kind: DownloadKind.audio,
      controls: DownloadControls(cancel: () async {}),
    );
    registry.finish(
      '2',
      const StatusMessage(StatusMessageKey.downloadFailed, error: 'HTTP 403'),
    );
    await tester.pumpWidget(_app(registry));
    await tester.pump();

    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('YouTube · Failed: HTTP 403'), findsOneWidget);
    expect(find.byTooltip('Clear history'), findsOneWidget);
  });
}
