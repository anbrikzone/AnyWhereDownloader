import 'package:anywhere_downloader/core/download/download_registry.dart';
import 'package:anywhere_downloader/core/l10n/status_message.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements DownloadHistoryStore {
  List<DownloadEntry> stored = const [];
  int saves = 0;

  @override
  Future<List<DownloadEntry>> load() async => stored;

  @override
  Future<void> save(List<DownloadEntry> history) async {
    saves++;
    stored = history;
  }
}

DownloadControls _controls({
  void Function()? onCancel,
  void Function()? onToggle,
}) =>
    DownloadControls(
      cancel: () async => onCancel?.call(),
      togglePause: onToggle == null ? null : () async => onToggle(),
    );

void main() {
  test('begin → progress → pause → finish moves the entry into history',
      () async {
    final store = _MemoryStore();
    final registry = DownloadRegistry(store: store);
    await registry.ready;

    registry.begin(
      id: 'a',
      source: 'YouTube',
      title: 'clip.mp4',
      kind: DownloadKind.video,
      controls: _controls(onToggle: () {}),
    );
    expect(registry.state.active.single.status, DownloadStatus.running);
    expect(registry.state.active.single.canPause, isTrue);

    registry.progress('a', 0.4);
    registry.setPaused('a', true);
    expect(registry.state.active.single.progress, 0.4);
    expect(registry.state.active.single.status, DownloadStatus.paused);

    registry.finish(
      'a',
      const StatusMessage(StatusMessageKey.saved),
      contentUri: 'content://media/9',
    );
    expect(registry.state.active, isEmpty);
    final done = registry.state.history.single;
    expect(done.status, DownloadStatus.completed);
    expect(done.contentUri, 'content://media/9');
    expect(done.finishedAt, isNotNull);
    await pumpEventQueue();
    expect(store.stored.single.id, 'a');
  });

  test('outcome mapping: canceled, failed with error, playlist counts',
      () async {
    final registry = DownloadRegistry(store: _MemoryStore());
    await registry.ready;
    for (final id in ['c', 'f', 'p']) {
      registry.begin(
        id: id,
        source: 'YouTube',
        title: id,
        kind: id == 'p' ? DownloadKind.playlist : DownloadKind.video,
        controls: _controls(),
      );
    }
    registry.finish('c', const StatusMessage(StatusMessageKey.downloadCanceled));
    registry.finish(
      'f',
      const StatusMessage(StatusMessageKey.downloadFailed, error: 'HTTP 403'),
    );
    registry.finish(
      'p',
      const StatusMessage(
        StatusMessageKey.playlistSaved,
        count: 5,
        failedCount: 1,
      ),
    );
    final byId = {for (final e in registry.state.history) e.id: e};
    expect(byId['c']!.status, DownloadStatus.canceled);
    expect(byId['f']!.status, DownloadStatus.failed);
    expect(byId['f']!.error, 'HTTP 403');
    expect(byId['p']!.status, DownloadStatus.completed);
    expect(byId['p']!.savedCount, 5);
    expect(byId['p']!.failedCount, 1);
    // Newest first.
    expect(registry.state.history.first.id, 'p');
  });

  test('controls route to the owning controller; finished ids are inert',
      () async {
    final registry = DownloadRegistry(store: _MemoryStore());
    await registry.ready;
    var canceled = 0;
    var toggled = 0;
    registry.begin(
      id: 'x',
      source: 'Pinterest',
      title: 'pin.mp4',
      kind: DownloadKind.video,
      controls: _controls(onCancel: () => canceled++, onToggle: () => toggled++),
    );
    await registry.togglePause('x');
    await registry.cancel('x');
    expect((toggled, canceled), (1, 1));

    registry.finish('x', const StatusMessage(StatusMessageKey.downloadCanceled));
    await registry.cancel('x');
    expect(canceled, 1);
  });

  test('history is capped, persisted, reloaded, and clearable', () async {
    final store = _MemoryStore();
    final registry = DownloadRegistry(store: store);
    await registry.ready;
    for (var i = 0; i < DownloadRegistry.historyLimit + 5; i++) {
      registry.begin(
        id: '$i',
        source: 'TikTok',
        title: '$i.mp4',
        kind: DownloadKind.video,
        controls: _controls(),
      );
      registry.finish('$i', const StatusMessage(StatusMessageKey.saved));
    }
    expect(registry.state.history, hasLength(DownloadRegistry.historyLimit));
    expect(registry.state.history.first.id, '${DownloadRegistry.historyLimit + 4}');

    // Round-trip through JSON, as the prefs store does.
    store.stored = store.stored
        .map((e) => DownloadEntry.fromJson(e.toJson())!)
        .toList();
    final reloaded = DownloadRegistry(store: store);
    await reloaded.ready;
    expect(reloaded.state.history, hasLength(DownloadRegistry.historyLimit));
    expect(reloaded.state.history.first.title, '${DownloadRegistry.historyLimit + 4}.mp4');

    reloaded.clearHistory();
    expect(reloaded.state.history, isEmpty);
    await pumpEventQueue();
    expect(store.stored, isEmpty);
  });

  test('a malformed stored row is dropped, not fatal', () {
    expect(DownloadEntry.fromJson({'id': 'x', 'kind': 'nope'}), isNull);
    expect(DownloadEntry.fromJson('garbage'), isNull);
  });
}
