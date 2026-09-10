import 'package:anywhere_downloader/core/share/share_intent_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractFirstUrl', () {
    test('returns null for null / empty / no-URL text', () {
      expect(extractFirstUrl(null), isNull);
      expect(extractFirstUrl(''), isNull);
      expect(extractFirstUrl('just some words'), isNull);
    });

    test('returns a bare URL unchanged', () {
      expect(
        extractFirstUrl('https://youtu.be/dQw4w9WgXcQ'),
        'https://youtu.be/dQw4w9WgXcQ',
      );
    });

    test('pulls the URL out of surrounding caption text', () {
      expect(
        extractFirstUrl('Check this out https://vm.tiktok.com/ZMabc123/ via TikTok'),
        'https://vm.tiktok.com/ZMabc123/',
      );
    });

    test('trims trailing punctuation and wrappers', () {
      expect(
        extractFirstUrl('link: (https://twitter.com/u/status/1).'),
        'https://twitter.com/u/status/1',
      );
      expect(
        extractFirstUrl('see https://www.instagram.com/reel/abc/,'),
        'https://www.instagram.com/reel/abc/',
      );
    });

    test('takes the first URL when several are present', () {
      expect(
        extractFirstUrl('https://a.example/1 and https://b.example/2'),
        'https://a.example/1',
      );
    });

    test('keeps query strings and fragments', () {
      expect(
        extractFirstUrl('https://youtube.com/watch?v=abc&t=30s'),
        'https://youtube.com/watch?v=abc&t=30s',
      );
    });
  });
}
