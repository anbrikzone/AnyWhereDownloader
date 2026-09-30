import 'dart:async';
import 'dart:io';

import 'package:anywhere_downloader/core/download/download_finalizer.dart';
import 'package:anywhere_downloader/core/notifications/media_notification_service.dart';
import 'package:anywhere_downloader/core/storage/media_save_service.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeMediaSaveService extends MediaSaveService {
  final saved = <({String path, String album, bool isImage})>[];
  Object? failWith;

  /// When set, a save blocks until it completes — to drive concurrent calls.
  Completer<void>? gate;

  Future<String> _record(String path, String album, bool isImage) async {
    if (gate != null) await gate!.future;
    if (failWith != null) throw failWith!;
    saved.add((path: path, album: album, isImage: isImage));
    return 'content://media/external/${saved.length}';
  }

  @override
  Future<String> saveVideo(String filePath, {required String album}) =>
      _record(filePath, album, false);

  @override
  Future<String> saveImage(String filePath, {required String album}) =>
      _record(filePath, album, true);
}

class _FakeNotifications extends MediaNotificationService {
  final notified = <String>[];

  @override
  Future<void> notifyFileSaved({
    required String title,
    required String contentUri,
    required String mimeType,
  }) async {
    notified.add('$title|$mimeType');
  }
}

class _FakeStore implements TrackedDownloadStore {
  _FakeStore(this.dir);

  final Directory dir;
  final records = <String, TrackedDownload>{};

  @override
  Future<List<TrackedDownload>> all() async => records.values.toList();

  @override
  Future<String> filePath(TrackedDownload download) async =>
      '${dir.path}/${download.taskId}.mp4';

  @override
  Future<void> delete(String taskId) async => records.remove(taskId);
}

void main() {
  late Directory dir;
  late _FakeMediaSaveService saver;
  late _FakeNotifications notifications;
  late _FakeStore store;
  late DownloadFinalizer finalizer;

  const videoSpec = GallerySaveSpec(
    kind: SavedMediaKind.video,
    album: 'AnyWhereDownloader/TikTok',
    notifyTitle: 'clip.mp4',
  );

  File addRecord(
    String id,
    TaskStatus status, {
    String? metaData,
    bool withFile = true,
  }) {
    store.records[id] = TrackedDownload(
      taskId: id,
      status: status,
      metaData: metaData ?? videoSpec.toMetaData(),
    );
    final file = File('${dir.path}/$id.mp4');
    if (withFile) file.writeAsBytesSync([1, 2, 3]);
    return file;
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('finalizer_test');
    saver = _FakeMediaSaveService();
    notifications = _FakeNotifications();
    store = _FakeStore(dir);
    finalizer = DownloadFinalizer(
      mediaSaveService: saver,
      mediaNotificationService: notifications,
      store: store,
    );
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('GallerySaveSpec round-trips through metaData', () {
    const spec = GallerySaveSpec(
      kind: SavedMediaKind.image,
      album: 'AnyWhereDownloader/X-Twitter',
      notifyTitle: 'photo.jpg',
    );
    final back = GallerySaveSpec.fromMetaData(spec.toMetaData())!;
    expect(back.kind, SavedMediaKind.image);
    expect(back.album, spec.album);
    expect(back.notifyTitle, spec.notifyTitle);
  });

  test('GallerySaveSpec ignores metaData this app did not write', () {
    expect(GallerySaveSpec.fromMetaData(''), isNull);
    expect(GallerySaveSpec.fromMetaData('not json'), isNull);
    expect(GallerySaveSpec.fromMetaData('{"v":2,"kind":"video","album":"a"}'), isNull);
    expect(GallerySaveSpec.fromMetaData('{"v":1,"kind":"gif","album":"a"}'), isNull);
  });

  test('reconcile saves a complete-but-unsaved download, then cleans up', () async {
    final file = addRecord('t1', TaskStatus.complete);

    await finalizer.reconcile();

    expect(saver.saved.single.album, 'AnyWhereDownloader/TikTok');
    expect(saver.saved.single.isImage, isFalse);
    expect(notifications.notified.single, 'clip.mp4|video/*');
    expect(file.existsSync(), isFalse);
    expect(store.records, isEmpty);
  });

  test('reconcile saves images via saveImage', () async {
    addRecord(
      't1',
      TaskStatus.complete,
      metaData: const GallerySaveSpec(
        kind: SavedMediaKind.image,
        album: 'AnyWhereDownloader/Instagram',
        notifyTitle: 'p.jpg',
      ).toMetaData(),
    );

    await finalizer.reconcile();

    expect(saver.saved.single.isImage, isTrue);
    expect(notifications.notified.single, 'p.jpg|image/*');
  });

  test('reconcile drops failed/canceled records and leaves running ones', () async {
    addRecord('failed', TaskStatus.failed, withFile: false);
    addRecord('canceled', TaskStatus.canceled, withFile: false);
    addRecord('running', TaskStatus.running, withFile: false);

    await finalizer.reconcile();

    expect(saver.saved, isEmpty);
    expect(store.records.keys, ['running']);
  });

  test('a complete record whose file is already gone is dropped, not saved', () async {
    addRecord('t1', TaskStatus.complete, withFile: false);

    await finalizer.reconcile();

    expect(saver.saved, isEmpty);
    expect(store.records, isEmpty);
  });

  test('a record with foreign metaData is dropped without saving', () async {
    addRecord('t1', TaskStatus.complete, metaData: 'something else');

    await finalizer.reconcile();

    expect(saver.saved, isEmpty);
    expect(store.records, isEmpty);
  });

  test('concurrent reconciles save a download exactly once', () async {
    addRecord('t1', TaskStatus.complete);
    saver.gate = Completer<void>();

    final first = finalizer.reconcile();
    final second = finalizer.reconcile();
    await Future<void>.delayed(Duration.zero);
    saver.gate!.complete();
    await Future.wait([first, second]);

    expect(saver.saved, hasLength(1));
    expect(notifications.notified, hasLength(1));
  });

  test('a failed save still removes the file and record (no retry loop)', () async {
    final file = addRecord('t1', TaskStatus.complete);
    saver.failWith = MediaSaveException('not a valid video');

    await finalizer.reconcile(); // must not throw

    expect(file.existsSync(), isFalse);
    expect(store.records, isEmpty);
    expect(notifications.notified, isEmpty);
  });
}
