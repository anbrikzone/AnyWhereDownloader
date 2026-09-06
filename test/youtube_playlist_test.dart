import 'package:anywhere_downloader/services/youtube/youtube_playlist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('YouTubePlaylistUrl classification', () {
    test('bare playlist link is a pure playlist', () {
      const url = 'https://www.youtube.com/playlist?list=PL123abc';
      expect(YouTubePlaylistUrl.isPurePlaylistUrl(url), isTrue);
      expect(YouTubePlaylistUrl.isVideoInPlaylistUrl(url), isFalse);
    });

    test('watch link with a list is a video-in-playlist', () {
      const url = 'https://www.youtube.com/watch?v=abc123&list=PL123abc';
      expect(YouTubePlaylistUrl.isVideoInPlaylistUrl(url), isTrue);
      expect(YouTubePlaylistUrl.isPurePlaylistUrl(url), isFalse);
    });

    test('mix / radio lists (RD…) are not treated as playlists', () {
      const watch = 'https://www.youtube.com/watch?v=abc123&list=RD123';
      expect(YouTubePlaylistUrl.isVideoInPlaylistUrl(watch), isFalse);
      expect(YouTubePlaylistUrl.isPurePlaylistUrl(watch), isFalse);
    });

    test('plain video link is neither', () {
      const url = 'https://youtu.be/abc123';
      expect(YouTubePlaylistUrl.isPurePlaylistUrl(url), isFalse);
      expect(YouTubePlaylistUrl.isVideoInPlaylistUrl(url), isFalse);
    });
  });

  group('YouTubePlaylistUrl.itemsSpec', () {
    test('null when every position is selected', () {
      expect(YouTubePlaylistUrl.itemsSpec([1, 2, 3, 4, 5], 5), isNull);
    });

    test('compresses a subset into ranges', () {
      expect(
        YouTubePlaylistUrl.itemsSpec([1, 2, 3, 5, 7, 8], 10),
        '1-3,5,7-8',
      );
    });

    test('handles a single item', () {
      expect(YouTubePlaylistUrl.itemsSpec([4], 10), '4');
    });

    test('unsorted input is normalised', () {
      expect(YouTubePlaylistUrl.itemsSpec([8, 1, 2, 7, 3], 10), '1-3,7-8');
    });
  });

  group('PlaylistQuality', () {
    test('video presets carry a format selector, audio does not', () {
      expect(PlaylistQuality.upTo1080.formatSelector, isNotNull);
      expect(PlaylistQuality.upTo720.isAudio, isFalse);
      expect(PlaylistQuality.audioMp3.formatSelector, isNull);
      expect(PlaylistQuality.audioMp3.audioFormat, 'mp3');
      expect(PlaylistQuality.audioMp3.audioQualityKbps, 320);
    });
  });
}
