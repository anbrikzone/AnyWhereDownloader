import 'package:anywhere_downloader/core/extraction/media_extractor.dart';
import 'package:anywhere_downloader/core/yt_dlp_engine/yt_dlp_engine.dart';
import 'package:anywhere_downloader/services/instagram/instagram_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeEngine implements YtDlpEngine {
  _FakeEngine(this.items);

  final List<RawVideoInfo> items;

  @override
  Future<PostItemsResult> getPostItems(String url) async =>
      PostItemsResult(title: 'Post by someone', items: items);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A photo item as yt-dlp dumps it: no formats, no image `ext`, the
/// full-size original as `thumbnail`.
RawVideoInfo _photo(String name) => RawVideoInfo(
  title: 'Video by someone',
  thumbnailUrl: 'https://scontent.cdninstagram.com/v/$name.jpg?stp=dst-jpg_e35',
  durationSeconds: 0,
  formats: const [],
  ext: null,
  directUrl: null,
);

RawVideoInfo _video(String name) => RawVideoInfo(
  title: 'Video by someone',
  thumbnailUrl: 'https://scontent.cdninstagram.com/v/$name-thumb.jpg',
  durationSeconds: 12,
  formats: [
    RawFormat(
      formatId: '1',
      ext: 'mp4',
      vcodec: null,
      acodec: null,
      height: 0,
      width: 0,
      formatNote: null,
      url: 'https://scontent.cdninstagram.com/v/$name.mp4',
      fileSizeBytes: 0,
      httpHeaders: null,
      tbrKbps: 0,
    ),
  ],
  ext: 'mp4',
  directUrl: null,
);

Future<MediaInfo> _extract(List<RawVideoInfo> items, [String query = '']) =>
    InstagramExtractor(engine: _FakeEngine(items))
        .extract('https://www.instagram.com/p/C0dEaBc999/$query');

void main() {
  test('recognizes post links, with or without the account in front', () {
    final extractor = InstagramExtractor(engine: _FakeEngine(const []));
    for (final url in [
      'https://www.instagram.com/p/C0dEaBc999/?img_index=4',
      'https://www.instagram.com/some.account/p/C0dEaBc123/',
      'https://www.instagram.com/someone/reel/C1abc/',
      'https://instagram.com/reel/C1abc',
      'https://www.instagram.com/tv/C1abc/',
      'https://www.instagram.com/stories/someone/123/',
    ]) {
      expect(extractor.canHandle(url), isTrue, reason: url);
    }
    for (final url in [
      'https://www.instagram.com/some.account/',
      'https://www.instagram.com/p/',
      'https://www.instagram.com/explore/tags/x/',
      'https://example.com/p/abc/',
    ]) {
      expect(extractor.canHandle(url), isFalse, reason: url);
    }
  });

  test('carouselIndexOf reads the 1-based img_index as 0-based', () {
    expect(carouselIndexOf('https://www.instagram.com/p/X/?img_index=4&xtok=a'), 3);
    expect(carouselIndexOf('https://www.instagram.com/p/X/?img_index=1'), 0);
    expect(carouselIndexOf('https://www.instagram.com/p/X/'), isNull);
    expect(carouselIndexOf('https://www.instagram.com/p/X/?img_index=0'), isNull);
    expect(carouselIndexOf('https://www.instagram.com/p/X/?img_index=x'), isNull);
  });

  test('a carousel becomes one item per photo/video, in post order', () async {
    final info = await _extract([_photo('a'), _video('b'), _photo('c')]);

    expect(info.isMultiItem, isTrue);
    expect(info.title, 'Post by someone');
    expect(info.items.map((i) => i.variant.type), [
      MediaVariantType.image,
      MediaVariantType.video,
      MediaVariantType.image,
    ]);
    final photo = info.items.first.variant;
    expect(photo.sourceUrl, contains('/a.jpg'));
    expect(photo.container, 'jpg');
    expect(info.items[1].variant.sourceUrl, endsWith('/b.mp4'));
    // No img_index: nothing is "current", the first item stands in.
    expect(info.currentItemIndex, isNull);
    expect(info.variants.single.sourceUrl, photo.sourceUrl);
  });

  test('img_index picks the current item', () async {
    final info = await _extract(
      [_photo('a'), _photo('b'), _photo('c'), _photo('d')],
      '?img_index=4&xtok=abc',
    );
    expect(info.currentItemIndex, 3);
    expect(info.variants.single.sourceUrl, contains('/d.jpg'));
  });

  test('an item with nothing downloadable is skipped, img_index follows', () async {
    final broken = RawVideoInfo(
      title: null,
      thumbnailUrl: null,
      durationSeconds: 0,
      formats: const [],
      ext: null,
      directUrl: null,
    );
    final info = await _extract(
      [_photo('a'), broken, _photo('c')],
      '?img_index=3',
    );
    expect(info.items, hasLength(2));
    expect(info.currentItemIndex, 1);
    expect(info.variants.single.sourceUrl, contains('/c.jpg'));
  });

  test('an img_index past the end names no current item', () async {
    final info = await _extract([_photo('a'), _photo('b')], '?img_index=9');
    expect(info.currentItemIndex, isNull);
  });

  test('a single photo post is one image variant, not a carousel', () async {
    final info = await _extract([_photo('only')]);
    expect(info.isMultiItem, isFalse);
    expect(info.items, isEmpty);
    expect(info.variants.single.type, MediaVariantType.image);
    expect(info.variants.single.sourceUrl, contains('/only.jpg'));
  });

  test('a reel keeps its progressive video variant', () async {
    final info = await _extract([_video('reel')]);
    expect(info.isMultiItem, isFalse);
    expect(info.variants.single.type, MediaVariantType.video);
    expect(info.variants.single.sourceUrl, endsWith('/reel.mp4'));
  });

  test('nothing downloadable at all is an ExtractionException', () async {
    expect(
      () => _extract(const []),
      throwsA(isA<ExtractionException>()),
    );
  });
}
