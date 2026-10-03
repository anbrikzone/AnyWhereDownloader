import 'dart:io';

import 'package:anywhere_downloader/core/download/ytdlp_service_download.dart';
import 'package:anywhere_downloader/core/extraction/media_extractor.dart';
import 'package:anywhere_downloader/core/l10n/status_message.dart';
import 'package:anywhere_downloader/core/storage/media_save_service.dart';
import 'package:anywhere_downloader/core/yt_dlp_engine/yt_dlp_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeEngine implements YtDlpEngine {
  _FakeEngine({this.result, this.error});

  final MergeDownloadResult? result;
  final Object? error;
  final calls = <Map<String, Object?>>[];

  Future<MergeDownloadResult> _answer(Map<String, Object?> call) async {
    calls.add(call);
    if (error != null) throw error!;
    return result!;
  }

  @override
  Future<MergeDownloadResult> downloadMerge({
    required String url,
    required String formatSelector,
    required String outputPath,
    required String processId,
    required String relativePath,
    int? durationSeconds,
    void Function(MergeProgress progress)? onProgress,
  }) => _answer({
    'kind': 'merge',
    'selector': formatSelector,
    'outputPath': outputPath,
    'relativePath': relativePath,
  });

  @override
  Future<MergeDownloadResult> downloadAudio({
    required String url,
    required String audioFormat,
    required int audioQualityKbps,
    required String outputPath,
    required String processId,
    required String relativePath,
    int? durationSeconds,
    void Function(MergeProgress progress)? onProgress,
  }) => _answer({
    'kind': 'audio',
    'format': audioFormat,
    'kbps': audioQualityKbps,
    'relativePath': relativePath,
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMediaSaveService implements MediaSaveService {
  @override
  Future<String> resolveRelativePath(String album, {required bool isAudio}) async =>
      '${isAudio ? 'Music' : 'Pictures'}/$album';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _video = MediaVariant(
  type: MediaVariantType.video,
  resolutionLabel: '1080p',
  container: 'mp4',
  approxSizeBytes: null,
  sourceUrl: 'https://youtu.be/x',
  mergeFormatSelector: '137+ba/b',
);

final _audio = MediaVariant(
  type: MediaVariantType.audio,
  resolutionLabel: null,
  container: 'mp3',
  approxSizeBytes: null,
  sourceUrl: 'https://youtu.be/x',
  audioSpec: AudioSpec(format: 'mp3', qualityKbps: 192),
);

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('awd_svc'));
  tearDown(() => tmp.delete(recursive: true));

  YtDlpServiceDownload downloader(_FakeEngine engine) => YtDlpServiceDownload(
    engine: engine,
    mediaSaveService: _FakeMediaSaveService(),
    tempDirectory: () async => tmp,
  );

  test('merge: per-download work dir, gallery root, saved on complete', () async {
    final engine = _FakeEngine(result: MergeDownloadResult(status: 'complete'));
    final message = await downloader(engine).merge(
      variant: _video,
      filename: 'clip.mp4',
      album: 'AnyWhereDownloader/YouTube',
      processId: '42',
    );
    expect(message.key, StatusMessageKey.saved);
    final call = engine.calls.single;
    expect(call['kind'], 'merge');
    expect(call['selector'], '137+ba/b');
    expect(call['relativePath'], 'Pictures/AnyWhereDownloader/YouTube');
    expect(call['outputPath'], '${tmp.path}/ytdlp_42/clip.mp4');
    expect(Directory('${tmp.path}/ytdlp_42').existsSync(), isTrue);
  });

  test('audio: goes to the audio root with the variant spec', () async {
    final engine = _FakeEngine(result: MergeDownloadResult(status: 'canceled'));
    final message = await downloader(engine).audio(
      variant: _audio,
      filename: 'song.mp3',
      album: 'AnyWhereDownloader/YouTube',
      processId: '7',
    );
    expect(message.key, StatusMessageKey.downloadCanceled);
    expect(engine.calls.single, {
      'kind': 'audio',
      'format': 'mp3',
      'kbps': 192,
      'relativePath': 'Music/AnyWhereDownloader/YouTube',
    });
  });

  test('a native error or a thrown exception becomes downloadFailed', () async {
    final failed = await downloader(
      _FakeEngine(result: MergeDownloadResult(status: 'error', error: 'ffmpeg died')),
    ).merge(variant: _video, filename: 'a.mp4', album: 'A', processId: '1');
    expect(failed.key, StatusMessageKey.downloadFailed);
    expect(failed.error, 'ffmpeg died');

    final thrown = await downloader(
      _FakeEngine(error: StateError('channel gone')),
    ).merge(variant: _video, filename: 'a.mp4', album: 'A', processId: '2');
    expect(thrown.key, StatusMessageKey.downloadFailed);
    expect(thrown.error, contains('channel gone'));
  });
}
