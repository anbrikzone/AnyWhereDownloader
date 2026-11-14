import 'package:anywhere_downloader/core/storage/media_library_service.dart';
import 'package:anywhere_downloader/features/library/library_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';

LibraryItem _item(
  String id,
  String source,
  AssetType type, {
  String? title,
  String? playlist,
  int modifiedSecond = 1000,
}) {
  return LibraryItem(
    asset: AssetEntity(
      id: id,
      typeInt: switch (type) {
        AssetType.image => 1,
        AssetType.video => 2,
        AssetType.audio => 3,
        AssetType.other => 0,
      },
      width: 100,
      height: 100,
      title: title ?? '$id.mp4',
      modifiedDateSecond: modifiedSecond,
    ),
    source: source,
    albumName: 'AnyWhereDownloader/$source',
    root: 'Pictures',
    playlistLabel: playlist,
  );
}

void main() {
  final items = [
    _item('v1', 'YouTube', AssetType.video, title: 'Flutter talk.mp4'),
    _item('a1', 'YouTube', AssetType.audio, title: 'Theme song.mp3'),
    _item('p1', 'Instagram', AssetType.image, title: 'beach.jpg'),
    _item('v2', 'TikTok', AssetType.video, title: 'dance.mp4'),
    _item('pl1', 'YouTube', AssetType.video, playlist: 'Mix'),
  ];
  LibraryState stateWith({
    LibraryTypeFilter type = LibraryTypeFilter.all,
    String query = '',
    String? source,
  }) => LibraryState(
    items: AsyncValue.data(items),
    typeFilter: type,
    searchQuery: query,
    sourceFilter: source,
  );

  List<String> ids(List<LibraryItem>? list) =>
      [for (final i in list!) i.asset.id]..sort();

  test('type filter keeps only that media type (playlist items excluded)', () {
    expect(ids(stateWith(type: LibraryTypeFilter.video).visibleItems), [
      'v1',
      'v2',
    ]);
    expect(ids(stateWith(type: LibraryTypeFilter.audio).visibleItems), ['a1']);
    expect(ids(stateWith(type: LibraryTypeFilter.photo).visibleItems), ['p1']);
  });

  test('search is a case-insensitive substring match on the title', () {
    expect(ids(stateWith(query: 'FLUTTER').visibleItems), ['v1']);
    expect(ids(stateWith(query: 'zzz').visibleItems), isEmpty);
  });

  test('source, type and search combine', () {
    expect(
      ids(
        stateWith(
          source: 'YouTube',
          type: LibraryTypeFilter.video,
        ).visibleItems,
      ),
      ['v1'],
    );
  });

  test('sourceCounts follow the type filter and search, not the source', () {
    expect(stateWith(source: 'TikTok').sourceCounts, {
      'YouTube': 3,
      'Instagram': 1,
      'TikTok': 1,
    });
    expect(stateWith(type: LibraryTypeFilter.video).sourceCounts, {
      'YouTube': 2,
      'TikTok': 1,
    });
  });

  test('source chips are ordered by count, most first, ties by name', () {
    expect(stateWith().sourcesByCount, ['YouTube', 'Instagram', 'TikTok']);
    expect(stateWith(type: LibraryTypeFilter.video).sourcesByCount, [
      'YouTube',
      'TikTok',
      'Instagram',
    ]);
  });

  test('playlist folders respect the type filter', () {
    expect(stateWith().visibleFolders.single.label, 'Mix');
    expect(stateWith(type: LibraryTypeFilter.audio).visibleFolders, isEmpty);
  });

  test('sortedByDate only for the two date orders', () {
    expect(const LibraryState().sortedByDate, isTrue);
    expect(
      const LibraryState(sortOption: LibrarySortOption.nameAZ).sortedByDate,
      isFalse,
    );
  });
}
