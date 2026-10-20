import 'dart:async';
import 'dart:io';

import 'package:anywhere_downloader/core/download/download_engine.dart';
import 'package:anywhere_downloader/core/download/download_finalizer.dart';
import 'package:anywhere_downloader/core/download/download_registry.dart';
import 'package:anywhere_downloader/core/download/ytdlp_service_download.dart';
import 'package:anywhere_downloader/core/extraction/media_extractor.dart';
import 'package:anywhere_downloader/core/l10n/status_message.dart';
import 'package:anywhere_downloader/core/notifications/notification_permission_service.dart';
import 'package:anywhere_downloader/core/storage/media_save_service.dart';
import 'package:anywhere_downloader/core/yt_dlp_engine/yt_dlp_engine.dart';
import 'package:anywhere_downloader/features/direct_download/direct_download_controller.dart';
import 'package:anywhere_downloader/features/direct_download/direct_download_service.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeExtractor implements MediaExtractor {
  _FakeExtractor({this.handles = true, this.error});

  final bool handles;
  final Object? error;

  @override
  ServiceType get serviceType => ServiceType.tiktok;

  @override
  bool canHandle(String url) => handles;

  @override
  Future<MediaInfo> extract(String url) async {
    if (error != null) throw error!;
    return MediaInfo(title: 't', thumbnailUrl: null, variants: const []);
  }
}

class _FakeYtDlpEngine implements YtDlpEngine {
  final merges = <Map<String, Object?>>[];
  final canceled = <String>[];
  final finish = Completer<MergeDownloadResult>();
  final started = Completer<void>();

  @override
  Future<MergeDownloadResult> downloadMerge({
    required String url,
    required String formatSelector,
    required String outputPath,
    required String processId,
    required String relativePath,
    int? durationSeconds,
    void Function(MergeProgress progress)? onProgress,
  }) {
    merges.add({
      'url': url,
      'formatSelector': formatSelector,
      'outputPath': outputPath,
      'processId': processId,
      'relativePath': relativePath,
    });
    started.complete();
    return finish.future;
  }

  @override
  Future<void> cancelDownload(String processId) async => canceled.add(processId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMediaSaveService implements MediaSaveService {
  @override
  Future<String> resolveRelativePath(String album, {required bool isAudio}) async =>
      'Pictures/$album';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryHistoryStore implements DownloadHistoryStore {
  @override
  Future<List<DownloadEntry>> load() async => const [];

  @override
  Future<void> save(List<DownloadEntry> history) async {}
}

class _NoopNotificationPermission implements NotificationPermissionService {
  @override
  Future<void> ensureRequested() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Real [DownloadEngine.buildTask]; [run] answers from [outcomes] in turn.
class _ScriptedDownloadEngine extends DownloadEngine {
  _ScriptedDownloadEngine(this.outcomes);

  final List<TaskStatus> outcomes;
  final tasks = <DownloadTask>[];

  @override
  Future<TaskStatusUpdate> run(
    DownloadTask task, {
    void Function(TaskStatus status)? onStatus,
    void Function(double progress)? onProgress,
  }) async {
    tasks.add(task);
    onProgress?.call(1);
    return TaskStatusUpdate(task, outcomes[tasks.length - 1]);
  }
}

class _FakeFinalizer implements DownloadFinalizer {
  @override
  Future<String?> finalize(Task task) async => 'content://media/${task.filename}';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _photoItem(String name) => MediaItem(
  thumbnailUrl: null,
  variant: MediaVariant(
    type: MediaVariantType.image,
    resolutionLabel: null,
    container: 'jpg',
    approxSizeBytes: null,
    sourceUrl: 'https://cdn.example/$name.jpg',
  ),
);

const _directTypes = [
  ServiceType.tiktok,
  ServiceType.xTwitter,
  ServiceType.instagram,
  ServiceType.linkedin,
  ServiceType.pinterest,
];

void main() {
  test('exactly the direct-download services are configured', () {
    for (final type in ServiceType.values) {
      final service = DirectDownloadService.of(type);
      if (_directTypes.contains(type)) {
        expect(service?.type, type);
      } else {
        expect(service, isNull, reason: '$type has its own feature');
      }
    }
  });

  test('X/Twitter saves into a slash-free folder', () {
    expect(DirectDownloadService.xTwitter.librarySource, isNot(contains('/')));
  });

  for (final type in _directTypes) {
    final service = DirectDownloadService.of(type)!;

    test('${service.title}: empty title falls back to its own file name', () {
      final controller = DirectDownloadController(
        service,
        extractor: _FakeExtractor(),
      );
      expect(controller.suggestedFileName('  '), service.fallbackFileName);
      expect(controller.suggestedFileName('a/b:c'), 'a_b_c');
    });

    test('${service.title}: a foreign link gets its "not a … link" status', () async {
      final controller = DirectDownloadController(
        service,
        extractor: _FakeExtractor(handles: false),
      );
      expect(await controller.fetchInfo('https://example.com/x'), isNull);
      expect(controller.state.statusMessage?.key, service.notHandledKey);
    });

    test('${service.title}: a generic fetch failure uses its fetch-failed key', () async {
      final controller = DirectDownloadController(
        service,
        extractor: _FakeExtractor(error: StateError('boom')),
      );
      expect(await controller.fetchInfo('https://example.com/x'), isNull);
      expect(controller.state.statusMessage?.key, service.fetchFailedKey);
      expect(controller.state.fetching, isFalse);
    });
  }

  test('an ExtractionException keeps its code and detail for localizing',
      () async {
    final controller = DirectDownloadController(
      DirectDownloadService.tiktok,
      extractor: _FakeExtractor(
        error: ExtractionException(
          ExtractionErrorCode.lookupHttpError,
          detail: 'HTTP 503',
        ),
      ),
    );
    await controller.fetchInfo('https://www.tiktok.com/@a/video/1');
    final message = controller.state.statusMessage;
    expect(message?.key, StatusMessageKey.extractionFailed);
    expect(message?.extractionCode, ExtractionErrorCode.lookupHttpError);
    expect(message?.error, 'HTTP 503');
  });

  test('a merge variant goes through yt-dlp: no pause, cancel reaches yt-dlp',
      () async {
    final engine = _FakeYtDlpEngine();
    final registry = DownloadRegistry(store: _MemoryHistoryStore());
    final tmp = await Directory.systemTemp.createTemp('awd_test');
    addTearDown(() => tmp.delete(recursive: true));
    final controller = DirectDownloadController(
      DirectDownloadService.pinterest,
      extractor: _FakeExtractor(),
      serviceDownload: YtDlpServiceDownload(
        engine: engine,
        mediaSaveService: _FakeMediaSaveService(),
        tempDirectory: () async => tmp,
      ),
      notificationPermissionService: _NoopNotificationPermission(),
      registry: registry,
    );
    final variant = MediaVariant(
      type: MediaVariantType.video,
      resolutionLabel: '720p',
      container: 'mp4',
      approxSizeBytes: null,
      sourceUrl: 'https://www.pinterest.com/pin/1/',
      mergeFormatSelector: 'v+a/bv*+ba/b',
    );

    final done = controller.downloadVariant(variant, 'clip');
    await engine.started.future;

    expect(engine.merges.single['url'], 'https://www.pinterest.com/pin/1/');
    expect(engine.merges.single['formatSelector'], 'v+a/bv*+ba/b');
    expect(engine.merges.single['relativePath'], 'Pictures/AnyWhereDownloader/Pinterest');
    expect((engine.merges.single['outputPath']! as String), endsWith('/clip.mp4'));
    expect(controller.state.downloading, isTrue);
    expect(controller.state.canPause, isFalse);
    // Reported to the Downloads screen, cancel-only.
    final active = registry.state.active.single;
    expect(active.id, engine.merges.single['processId']);
    expect(active.source, 'Pinterest');
    expect(active.title, 'clip.mp4');
    expect(active.canPause, isFalse);

    await controller.cancelDownload();
    expect(engine.canceled.single, engine.merges.single['processId']);

    engine.finish.complete(MergeDownloadResult(status: 'canceled'));
    await done;
    expect(controller.state.downloading, isFalse);
    expect(controller.state.mergeProcessId, isNull);
    expect(controller.state.statusMessage?.key, StatusMessageKey.downloadCanceled);
    expect(registry.state.active, isEmpty);
    expect(registry.state.history.single.status, DownloadStatus.canceled);
  });

  test('a carousel downloads item by item; only the last one notifies',
      () async {
    final engine = _ScriptedDownloadEngine([
      TaskStatus.complete,
      TaskStatus.failed,
      TaskStatus.complete,
    ]);
    final registry = DownloadRegistry(store: _MemoryHistoryStore());
    final controller = DirectDownloadController(
      DirectDownloadService.instagram,
      extractor: _FakeExtractor(),
      downloadEngine: engine,
      downloadFinalizer: _FakeFinalizer(),
      notificationPermissionService: _NoopNotificationPermission(),
      registry: registry,
    );

    await controller.downloadItems(
      [_photoItem('a'), _photoItem('b'), _photoItem('c')],
      'Post',
    );

    expect(engine.tasks.map((t) => t.filename), [
      'Post_01.jpg',
      'Post_02.jpg',
      'Post_03.jpg',
    ]);
    expect(engine.tasks.map((t) => t.url), [
      'https://cdn.example/a.jpg',
      'https://cdn.example/b.jpg',
      'https://cdn.example/c.jpg',
    ]);
    final specs = engine.tasks
        .map((t) => GallerySaveSpec.fromMetaData(t.metaData)!)
        .toList();
    expect(specs.map((s) => s.notify), [false, false, true]);
    expect(specs.every((s) => s.kind == SavedMediaKind.image), isTrue);
    expect(specs.first.album, 'AnyWhereDownloader/Instagram');

    // A failed item doesn't stop the batch; the summary counts both.
    expect(controller.state.downloading, isFalse);
    expect(controller.state.statusMessage?.key, StatusMessageKey.postItemsSaved);
    expect(controller.state.statusMessage?.count, 2);
    expect(controller.state.statusMessage?.failedCount, 1);
    expect(registry.state.active, isEmpty);
    expect(registry.state.history, hasLength(3));
  });

  test('canceling one carousel item stops the rest of the batch', () async {
    final engine = _ScriptedDownloadEngine([
      TaskStatus.complete,
      TaskStatus.canceled,
      TaskStatus.complete,
    ]);
    final controller = DirectDownloadController(
      DirectDownloadService.instagram,
      extractor: _FakeExtractor(),
      downloadEngine: engine,
      downloadFinalizer: _FakeFinalizer(),
      notificationPermissionService: _NoopNotificationPermission(),
    );

    await controller.downloadItems(
      [_photoItem('a'), _photoItem('b'), _photoItem('c')],
      'Post',
    );

    expect(engine.tasks, hasLength(2));
    expect(controller.state.statusMessage?.key, StatusMessageKey.postItemsSaved);
    expect(controller.state.statusMessage?.count, 1);
    expect(controller.state.statusMessage?.failedCount, 0);
  });
}
