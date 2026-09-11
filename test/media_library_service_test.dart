import 'package:anywhere_downloader/core/storage/media_library_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('albumNameForPlaylist', () {
    test('builds the 3-segment convention', () {
      expect(
        albumNameForPlaylist('YouTube', 'Chill Mix'),
        'AnyWhereDownloader - YouTube - Chill Mix',
      );
    });

    test('sanitizes / and \\ in the playlist title, same as the source', () {
      expect(
        albumNameForPlaylist('YouTube', 'Rock/Pop mix\\2026'),
        'AnyWhereDownloader - YouTube - Rock-Pop mix-2026',
      );
    });

    test('caps an unusually long playlist title at 80 chars', () {
      final longTitle = 'x' * 200;
      final album = albumNameForPlaylist('YouTube', longTitle);
      final label = album.substring('AnyWhereDownloader - YouTube - '.length);
      expect(label.length, 80);
    });

    test('falls back to a placeholder for an empty/whitespace title', () {
      expect(
        albumNameForPlaylist('YouTube', '   '),
        'AnyWhereDownloader - YouTube - Playlist',
      );
    });
  });

  group('parseLibraryAlbumName', () {
    test('a plain service album has no playlist label', () {
      final parsed = parseLibraryAlbumName('AnyWhereDownloader - YouTube');
      expect(parsed?.source, 'YouTube');
      expect(parsed?.playlistLabel, isNull);
    });

    test('a playlist album splits into source + label', () {
      final parsed = parseLibraryAlbumName(
        'AnyWhereDownloader - YouTube - Chill Mix',
      );
      expect(parsed?.source, 'YouTube');
      expect(parsed?.playlistLabel, 'Chill Mix');
    });

    test('a playlist title containing " - " keeps it in the label', () {
      final parsed = parseLibraryAlbumName(
        'AnyWhereDownloader - YouTube - Lofi - Study Mix',
      );
      expect(parsed?.source, 'YouTube');
      expect(parsed?.playlistLabel, 'Lofi - Study Mix');
    });

    test('the bare prefix with no source is "Unknown"', () {
      final parsed = parseLibraryAlbumName('AnyWhereDownloader');
      expect(parsed?.source, 'Unknown');
      expect(parsed?.playlistLabel, isNull);
    });

    test('an unrelated album name is not parsed', () {
      expect(parseLibraryAlbumName('Some Other Album'), isNull);
    });

    test('round-trips with albumNameForPlaylist', () {
      final album = albumNameForPlaylist('X-Twitter', 'Great threads');
      final parsed = parseLibraryAlbumName(album);
      expect(parsed?.source, 'X-Twitter');
      expect(parsed?.playlistLabel, 'Great threads');
    });
  });
}
