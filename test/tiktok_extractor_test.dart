import 'dart:convert';

import 'package:anywhere_downloader/core/extraction/media_extractor.dart';
import 'package:anywhere_downloader/services/tiktok/tiktok_extractor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

TikTokExtractor _extractorReturning(Map<String, dynamic> data) {
  return TikTokExtractor(
    client: MockClient(
      (_) async => http.Response(jsonEncode({'code': 0, 'data': data}), 200),
    ),
  );
}

const _url = 'https://www.tiktok.com/@someone/photo/7400000000000000000';

void main() {
  test('a photo post yields its first image, never the `play` audio track', () async {
    // Shape of tikwm's answer for a slideshow: duration 0, `images` filled,
    // `play` pointing at the background music.
    final info = await _extractorReturning({
      'title': 'Trip',
      'duration': 0,
      'cover': 'https://p16.tiktokcdn.com/cover.jpeg',
      'play': 'https://sf16.tiktokcdn.com/music.mp3',
      'images': [
        'https://p16.tiktokcdn.com/obj/one~tplv-photomode-image.jpeg?x=1',
        'https://p16.tiktokcdn.com/obj/two~tplv-photomode-image.jpeg?x=2',
      ],
    }).extract(_url);

    final variant = info.variants.single;
    expect(variant.type, MediaVariantType.image);
    expect(variant.sourceUrl, contains('one~tplv-photomode-image.jpeg'));
    expect(variant.container, 'jpeg');
    expect(info.title, 'Trip');
  });

  test('a photo post without a caption gets a photo title', () async {
    final info = await _extractorReturning({
      'title': '',
      'images': ['https://p16.tiktokcdn.com/obj/a.webp'],
    }).extract(_url);

    expect(info.title, 'TikTok photo');
    expect(info.variants.single.container, 'webp');
  });

  test('a video post still yields HD + SD video variants', () async {
    final info = await _extractorReturning({
      'title': 'Clip',
      'duration': 12,
      'play': 'https://v16.tiktokcdn.com/sd.mp4',
      'hdplay': 'https://v16.tiktokcdn.com/hd.mp4',
      'size': 100,
      'hd_size': 200,
    }).extract('https://www.tiktok.com/@someone/video/1');

    expect(info.variants.map((v) => v.resolutionLabel), ['HD', 'SD']);
    expect(info.variants.every((v) => v.type == MediaVariantType.video), isTrue);
  });

  test('an empty images list falls through to the video path', () async {
    final info = await _extractorReturning({
      'title': 'Clip',
      'images': <String>[],
      'play': 'https://v16.tiktokcdn.com/sd.mp4',
    }).extract('https://www.tiktok.com/@someone/video/1');

    expect(info.variants.single.type, MediaVariantType.video);
  });

  test('imageContainerFor falls back to jpg for an unknown extension', () {
    expect(imageContainerFor('https://x.com/a/b'), 'jpg');
    expect(imageContainerFor('https://x.com/a.PNG?q=1'), 'png');
  });
}
