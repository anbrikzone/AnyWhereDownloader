import 'package:anywhere_downloader/core/storage/media_library_service.dart';
import 'package:anywhere_downloader/core/storage/media_save_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every call instead of touching a real native bridge, so
/// [MediaLibraryService.migrateLegacyFolders]'s orchestration (attempt every
/// bucket, batch any bug-#5 `needsPermissionUris` into one consent prompt,
/// retry once) can be driven directly via the `saveService` injection point.
class _FakeMediaSaveService extends MediaSaveService {
  _FakeMediaSaveService({
    required this.buckets,
    this.permissionNeededOldPaths = const {},
    this.grantWriteAccess = true,
  });

  /// bucket id -> raw relativePath, as `queryLibraryBucketPaths` would return.
  final Map<String, String> buckets;

  /// Old relativePaths whose *first* [moveBucket] call reports a row needing
  /// consent (simulating a bug-#5 `RecoverableSecurityException`).
  final Set<String> permissionNeededOldPaths;
  final bool grantWriteAccess;

  final Map<String, int> moveBucketCallCounts = {};
  final List<List<String>> requestWriteAccessCalls = [];
  final List<String> cleanupCalls = [];

  @override
  Future<Map<String, String>> queryLibraryBucketPaths() async => Map.of(buckets);

  @override
  Future<MoveBucketOutcome> moveBucket(String oldRelativePath, String newRelativePath) async {
    final callCount = (moveBucketCallCounts[oldRelativePath] ?? 0) + 1;
    moveBucketCallCounts[oldRelativePath] = callCount;
    if (permissionNeededOldPaths.contains(oldRelativePath) && callCount == 1) {
      return (moved: 0, total: 1, needsPermissionUris: ['content://fake/$oldRelativePath']);
    }
    return (moved: 1, total: 1, needsPermissionUris: const <String>[]);
  }

  @override
  Future<bool> requestWriteAccess(List<String> uris) async {
    requestWriteAccessCalls.add(uris);
    return grantWriteAccess;
  }

  @override
  Future<void> cleanupEmptyAlbumDir(String album, {required bool isAudio}) async {
    cleanupCalls.add(album);
  }
}

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

  group('relativePathForSource / relativePathForPlaylist', () {
    test('builds a real nested path, not a dash-joined name', () {
      expect(relativePathForSource('YouTube'), 'AnyWhereDownloader/YouTube');
      expect(
        relativePathForPlaylist('YouTube', 'Chill Mix'),
        'AnyWhereDownloader/YouTube/Chill Mix',
      );
    });

    test('sanitizes a literal / or \\ within a segment', () {
      expect(relativePathForSource('X/Twitter'), 'AnyWhereDownloader/X-Twitter');
      expect(
        relativePathForPlaylist('YouTube', 'Rock/Pop mix'),
        'AnyWhereDownloader/YouTube/Rock-Pop mix',
      );
    });

    test('caps an unusually long playlist title at 80 chars', () {
      final path = relativePathForPlaylist('YouTube', 'x' * 200);
      final label = path.split('/').last;
      expect(label.length, 80);
    });
  });

  group('parseLibraryRelativePath', () {
    test('parses a new nested service folder', () {
      final parsed = parseLibraryRelativePath('Pictures/AnyWhereDownloader/YouTube/');
      expect(parsed?.source, 'YouTube');
      expect(parsed?.playlistLabel, isNull);
      expect(parsed?.isAudio, isFalse);
      expect(parsed?.isLegacyFlat, isFalse);
    });

    test('parses a new nested playlist folder, including under Music/', () {
      final parsed = parseLibraryRelativePath(
        'Music/AnyWhereDownloader/YouTube/Channel - Chill Mix/',
      );
      expect(parsed?.source, 'YouTube');
      expect(parsed?.playlistLabel, 'Channel - Chill Mix');
      expect(parsed?.isAudio, isTrue);
      expect(parsed?.isLegacyFlat, isFalse);
    });

    test('still recognizes a not-yet-migrated legacy flat bucket', () {
      final parsed = parseLibraryRelativePath('Pictures/AnyWhereDownloader - YouTube - Old Mix/');
      expect(parsed?.source, 'YouTube');
      expect(parsed?.playlistLabel, 'Old Mix');
      expect(parsed?.isLegacyFlat, isTrue);
    });

    test('the bare nested root with no service is "Unknown"', () {
      final parsed = parseLibraryRelativePath('Pictures/AnyWhereDownloader/');
      expect(parsed?.source, 'Unknown');
      expect(parsed?.isLegacyFlat, isFalse);
    });

    test('an unrelated relative path is not parsed', () {
      expect(parseLibraryRelativePath('Pictures/Canva/'), isNull);
    });

    test('round-trips through relativePathForPlaylist', () {
      final path = relativePathForPlaylist('LinkedIn', 'Great posts');
      final parsed = parseLibraryRelativePath('Pictures/$path/');
      expect(parsed?.source, 'LinkedIn');
      expect(parsed?.playlistLabel, 'Great posts');
      expect(parsed?.isLegacyFlat, isFalse);
    });
  });

  group('MediaLibraryService.migrateLegacyFolders', () {
    test('is a no-op when nothing legacy is found', () async {
      final fake = _FakeMediaSaveService(
        buckets: {'1': 'Pictures/AnyWhereDownloader/YouTube/'},
      );
      await MediaLibraryService(saveService: fake).migrateLegacyFolders();

      expect(fake.moveBucketCallCounts, isEmpty);
      expect(fake.requestWriteAccessCalls, isEmpty);
      expect(fake.cleanupCalls, isEmpty);
    });

    test('moves every legacy bucket once and cleans each up when nothing needs consent', () async {
      final fake = _FakeMediaSaveService(
        buckets: {
          '1': 'Pictures/AnyWhereDownloader - YouTube - Old Mix/',
          '2': 'Pictures/AnyWhereDownloader - WhatsApp/',
        },
      );
      await MediaLibraryService(saveService: fake).migrateLegacyFolders();

      expect(fake.moveBucketCallCounts, {
        'Pictures/AnyWhereDownloader - YouTube - Old Mix/': 1,
        'Pictures/AnyWhereDownloader - WhatsApp/': 1,
      });
      expect(fake.requestWriteAccessCalls, isEmpty);
      expect(fake.cleanupCalls, unorderedEquals(['AnyWhereDownloader - YouTube - Old Mix', 'AnyWhereDownloader - WhatsApp']));
    });

    test(
      'batches every bucket needing consent into a single requestWriteAccess prompt, then retries once',
      () async {
        final fake = _FakeMediaSaveService(
          buckets: {
            '1': 'Pictures/AnyWhereDownloader - YouTube - Old Mix/',
            '2': 'Pictures/AnyWhereDownloader - WhatsApp/',
          },
          permissionNeededOldPaths: {
            'Pictures/AnyWhereDownloader - YouTube - Old Mix/',
            'Pictures/AnyWhereDownloader - WhatsApp/',
          },
        );
        await MediaLibraryService(saveService: fake).migrateLegacyFolders();

        // One prompt covering both buckets' URIs — not one dialog per bucket.
        expect(fake.requestWriteAccessCalls, hasLength(1));
        expect(fake.requestWriteAccessCalls.single, hasLength(2));

        // Each bucket attempted twice: the refused first pass, then the
        // post-consent retry that succeeds.
        expect(fake.moveBucketCallCounts, {
          'Pictures/AnyWhereDownloader - YouTube - Old Mix/': 2,
          'Pictures/AnyWhereDownloader - WhatsApp/': 2,
        });
        expect(fake.cleanupCalls, hasLength(2));
      },
    );

    test('leaves buckets unmigrated with no retry or cleanup when consent is declined', () async {
      final fake = _FakeMediaSaveService(
        buckets: {'1': 'Pictures/AnyWhereDownloader - YouTube - Old Mix/'},
        permissionNeededOldPaths: {'Pictures/AnyWhereDownloader - YouTube - Old Mix/'},
        grantWriteAccess: false,
      );
      await MediaLibraryService(saveService: fake).migrateLegacyFolders();

      expect(fake.requestWriteAccessCalls, hasLength(1));
      expect(fake.moveBucketCallCounts['Pictures/AnyWhereDownloader - YouTube - Old Mix/'], 1);
      expect(fake.cleanupCalls, isEmpty);
    });
  });
}
