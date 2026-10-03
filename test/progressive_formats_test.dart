import 'package:anywhere_downloader/core/extraction/progressive_formats.dart';
import 'package:anywhere_downloader/core/yt_dlp_engine/yt_dlp_engine.dart';
import 'package:flutter_test/flutter_test.dart';

RawFormat _f(String url, {int height = 0, double tbr = 0, String? id}) =>
    RawFormat(
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
      tbrKbps: tbr,
    );

void main() {
  test('reads a LinkedIn-style height token from the URL path', () {
    expect(
      heightOf(_f('https://dms.licdn.com/playlist/vid/v2/X/mp4-720p-30fp-crf28/0/1?e=1')),
      720,
    );
    expect(heightOf(_f('https://cdn.example/o1/v/t16/abc.mp4?efg=x')), 0);
    expect(heightOf(_f('https://cdn.example/a.mp4', height: 1080)), 1080);
  });

  test('collapses indistinguishable formats to the last (best) yt-dlp entry',
      () {
    final variants = progressiveVideoVariants(
      [_f('https://ig/a?sig=1'), _f('https://ig/a?sig=2'), _f('https://ig/a?sig=3')],
      durationSeconds: 0,
    );
    expect(variants, hasLength(1));
    expect(variants.single.sourceUrl, 'https://ig/a?sig=3');
  });

  test('ranks by height, then bitrate, and labels unknown heights by bitrate',
      () {
    final variants = progressiveVideoVariants(
      [
        _f('https://li/low', tbr: 400),
        _f('https://li/high', tbr: 1500),
        _f('https://li/mp4-640p-30fp/1'),
      ],
      durationSeconds: 0,
    );
    expect(variants.map((v) => v.sourceUrl), [
      'https://li/mp4-640p-30fp/1',
      'https://li/high',
      'https://li/low',
    ]);
    expect(variants.first.resolutionLabel, '640p');
    expect(variants[1].resolutionLabel, isNull);
    expect(variants[1].bitrateKbps, 1500);
  });
}
