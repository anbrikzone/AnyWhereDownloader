import 'package:anywhere_downloader/core/extraction/media_extractor.dart';
import 'package:anywhere_downloader/core/yt_dlp_engine/yt_dlp_engine.dart';
import 'package:anywhere_downloader/services/pinterest/pinterest_extractor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeEngine implements YtDlpEngine {
  _FakeEngine(this.info);

  final RawVideoInfo info;
  final requested = <String>[];

  @override
  Future<RawVideoInfo> getInfo(String url) async {
    requested.add(url);
    return info;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

RawFormat _f(String id, String url, {int height = 0}) => RawFormat(
      formatId: id,
      ext: 'mp4',
      vcodec: null,
      acodec: null,
      height: height,
      width: 0,
      formatNote: null,
      url: url,
      fileSizeBytes: 0,
      httpHeaders: null,
      tbrKbps: 0,
    );

RawVideoInfo _info({List<RawFormat> formats = const [], String? thumb}) =>
    RawVideoInfo(
      title: 'Origami',
      thumbnailUrl: thumb,
      durationSeconds: 57,
      formats: formats,
      ext: null,
      directUrl: null,
    );

void main() {
  final extractor = PinterestExtractor(engine: _FakeEngine(_info()));

  test('recognizes pin links on any Pinterest domain and pin.it', () {
    expect(extractor.canHandle('https://www.pinterest.com/pin/664281013778109217/'), isTrue);
    expect(extractor.canHandle('https://ru.pinterest.com/pin/123/'), isTrue);
    expect(extractor.canHandle('https://pinterest.co.uk/pin/some-title--2885187256207927'), isTrue);
    expect(extractor.canHandle('https://pin.it/4AbCdEf'), isTrue);
    expect(extractor.canHandle('https://www.pinterest.com/someuser/boards/'), isFalse);
    expect(extractor.canHandle('https://notpinterest.com/pin/1/'), isFalse);
  });

  test('video pin: progressive MP4s best-first, HLS skipped', () async {
    final engine = _FakeEngine(_info(formats: [
      _f('V_HLSV4-1', 'https://v.pinimg.com/a.m3u8', height: 1080),
      _f('V_720P', 'https://v.pinimg.com/720.mp4', height: 1280),
      _f('V_EXP4', 'https://v.pinimg.com/exp4.mp4', height: 640),
    ]));
    final info = await PinterestExtractor(engine: engine)
        .extract('https://www.pinterest.com/pin/1/');
    expect(info.variants.map((v) => v.sourceUrl), [
      'https://v.pinimg.com/720.mp4',
      'https://v.pinimg.com/exp4.mp4',
    ]);
  });

  test('image pin: the thumbnail becomes an image download', () async {
    final engine = _FakeEngine(
      _info(thumb: 'https://i.pinimg.com/originals/ab/cd/ef.png'),
    );
    final info = await PinterestExtractor(engine: engine)
        .extract('https://www.pinterest.com/pin/1/');
    expect(info.variants.single.type, MediaVariantType.image);
    expect(info.variants.single.container, 'png');
  });

  test('pin.it is expanded through redirects to a clean pin URL', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'pin.it') {
        return http.Response('', 301, headers: {
          'location': 'https://api.pinterest.com/url_shortener/4AbCdEf/redirect/',
        });
      }
      return http.Response('', 302, headers: {
        'location': 'https://www.pinterest.com/pin/987654321/sent/?invite_code=x&sender=y',
      });
    });
    final engine = _FakeEngine(_info(thumb: 'https://i.pinimg.com/x.jpg'));
    await PinterestExtractor(engine: engine, client: client)
        .extract('https://pin.it/4AbCdEf');
    expect(engine.requested.single, 'https://www.pinterest.com/pin/987654321/sent/');
  });
}
