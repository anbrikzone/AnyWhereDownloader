import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n/status_message.dart';
import '../../core/storage/media_library_service.dart';
import '../../core/storage/media_save_service.dart';

enum LibrarySortOption { dateNewest, dateOldest, nameAZ, nameZA }

/// One drill-in folder in Library — every item sharing a (source,
/// playlistLabel) pair (see `LibraryItem.playlistLabel`), newest-first.
class LibraryFolder {
  LibraryFolder({required this.source, required this.label, required this.items});

  final String source;
  final String label;
  final List<LibraryItem> items;

  int get count => items.length;
}

class LibraryState {
  const LibraryState({
    this.checkingPermission = true,
    this.permission,
    this.requestedBefore = false,
    this.items = const AsyncValue.loading(),
    this.sourceFilter,
    this.sortOption = LibrarySortOption.dateNewest,
    this.selectionMode = false,
    this.selectedIds = const {},
    this.busy = false,
    this.statusMessage,
  });

  final bool checkingPermission;
  final PermissionState? permission;

  /// True once a permission request has actually been made at least once.
  /// After a real denial, Android stops showing the system dialog on
  /// subsequent requests — re-requesting then silently no-ops, which looks
  /// like a broken button unless the UI offers an "open Settings" escape
  /// hatch instead of just retrying.
  final bool requestedBefore;

  final AsyncValue<List<LibraryItem>> items;

  /// null = all sources. One of the values in [availableSources].
  final String? sourceFilter;
  final LibrarySortOption sortOption;

  /// Whether tapping a tile toggles selection instead of opening the full
  /// preview. Entered/exited explicitly via a toolbar button — never a
  /// side effect of long-press, so long-press is reliably "peek" and tap
  /// is reliably "open" outside of this mode.
  final bool selectionMode;
  final Set<String> selectedIds;
  final bool busy;
  final StatusMessage? statusMessage;

  bool get hasAccess => permission?.isAuth == true || permission?.hasAccess == true;

  /// Distinct sources present in the unfiltered list, for building filter
  /// chips. Not stored separately — always derived from [items].
  List<String> get availableSources {
    final all = items.valueOrNull;
    if (all == null) return const [];
    final sources = all.map((i) => i.source).toSet().toList()..sort();
    return sources;
  }

  /// [items], filtered by [sourceFilter] and sorted by [sortOption]. Only
  /// meaningful once [items] has data — null while loading/erroring. Excludes
  /// playlist items (`playlistLabel != null`) — those are shown grouped via
  /// [visibleFolders] instead of mixed into this flat list.
  List<LibraryItem>? get visibleItems {
    final all = items.valueOrNull;
    if (all == null) return null;
    final filtered = all
        .where((i) => i.playlistLabel == null)
        .where((i) => sourceFilter == null || i.source == sourceFilter)
        .toList();
    filtered.sort((a, b) {
      switch (sortOption) {
        case LibrarySortOption.dateNewest:
          return b.asset.createDateTime.compareTo(a.asset.createDateTime);
        case LibrarySortOption.dateOldest:
          return a.asset.createDateTime.compareTo(b.asset.createDateTime);
        case LibrarySortOption.nameAZ:
          return (a.asset.title ?? '').compareTo(b.asset.title ?? '');
        case LibrarySortOption.nameZA:
          return (b.asset.title ?? '').compareTo(a.asset.title ?? '');
      }
    });
    return filtered;
  }

  /// Playlist folders present, filtered by [sourceFilter] and sorted
  /// newest-first by their most recent item. Empty until [items] has data.
  List<LibraryFolder> get visibleFolders {
    final all = items.valueOrNull;
    if (all == null) return const [];
    final grouped = <(String, String), List<LibraryItem>>{};
    for (final item in all) {
      final label = item.playlistLabel;
      if (label == null) continue;
      if (sourceFilter != null && item.source != sourceFilter) continue;
      grouped.putIfAbsent((item.source, label), () => []).add(item);
    }
    final folders = grouped.entries.map((entry) {
      final list = entry.value
        ..sort(
          (a, b) => b.asset.createDateTime.compareTo(a.asset.createDateTime),
        );
      return LibraryFolder(
        source: entry.key.$1,
        label: entry.key.$2,
        items: list,
      );
    }).toList();
    folders.sort(
      (a, b) => b.items.first.asset.createDateTime
          .compareTo(a.items.first.asset.createDateTime),
    );
    return folders;
  }

  LibraryState copyWith({
    bool? checkingPermission,
    PermissionState? permission,
    bool? requestedBefore,
    AsyncValue<List<LibraryItem>>? items,
    String? sourceFilter,
    bool clearSourceFilter = false,
    LibrarySortOption? sortOption,
    bool? selectionMode,
    Set<String>? selectedIds,
    bool? busy,
    StatusMessage? statusMessage,
    bool clearStatusMessage = false,
  }) {
    return LibraryState(
      checkingPermission: checkingPermission ?? this.checkingPermission,
      permission: permission ?? this.permission,
      requestedBefore: requestedBefore ?? this.requestedBefore,
      items: items ?? this.items,
      sourceFilter: clearSourceFilter ? null : (sourceFilter ?? this.sourceFilter),
      sortOption: sortOption ?? this.sortOption,
      selectionMode: selectionMode ?? this.selectionMode,
      selectedIds: selectedIds ?? this.selectedIds,
      busy: busy ?? this.busy,
      statusMessage: clearStatusMessage
          ? null
          : (statusMessage ?? this.statusMessage),
    );
  }
}

class LibraryController extends StateNotifier<LibraryState> {
  LibraryController({MediaLibraryService? service, MediaSaveService? saveService})
    : _service = service ?? MediaLibraryService(),
      _saveService = saveService ?? MediaSaveService(),
      super(const LibraryState()) {
    _init();
  }

  final MediaLibraryService _service;
  final MediaSaveService _saveService;

  /// Only *checks* the current permission — does not prompt. Actually
  /// requesting (which shows the system dialog, at least the first time)
  /// only happens from [requestPermission], triggered by an explicit user
  /// tap. Checking status this way on mount means the "Allow access"
  /// button's first tap is always the real first OS-level request, which
  /// is the one guaranteed to show a dialog — Android may silently stop
  /// showing it on later re-requests after a denial.
  Future<void> _init() async {
    final permission = await _service.currentPermission();
    state = state.copyWith(checkingPermission: false, permission: permission);
    if (state.hasAccess) {
      await refresh();
    }
  }

  Future<void> requestPermission() async {
    state = state.copyWith(checkingPermission: true);
    final permission = await _service.ensurePermission();
    state = state.copyWith(
      checkingPermission: false,
      permission: permission,
      requestedBefore: true,
    );
    if (state.hasAccess) {
      await refresh();
    }
  }

  Future<void> openSettings() => _service.openSettings();

  Future<void> refresh() async {
    if (!state.hasAccess) return;
    state = state.copyWith(items: const AsyncValue.loading());
    try {
      final items = await _service.loadDownloadedAssets();
      state = state.copyWith(items: AsyncValue.data(items));
    } catch (error, stackTrace) {
      state = state.copyWith(items: AsyncValue.error(error, stackTrace));
    }
  }

  void setSourceFilter(String? source) {
    state = source == null
        ? state.copyWith(clearSourceFilter: true)
        : state.copyWith(sourceFilter: source);
  }

  void setSortOption(LibrarySortOption option) {
    state = state.copyWith(sortOption: option);
  }

  void enterSelectionMode() {
    state = state.copyWith(selectionMode: true, selectedIds: {});
  }

  /// Exits selection mode and clears the selection — the "cancel" action.
  void exitSelectionMode() {
    state = state.copyWith(selectionMode: false, selectedIds: {});
  }

  void toggleSelected(String id) {
    final selected = {...state.selectedIds};
    if (!selected.remove(id)) {
      selected.add(id);
    }
    state = state.copyWith(selectedIds: selected);
  }

  Future<void> shareSelected() async {
    final items = state.items.valueOrNull;
    if (items == null || state.selectedIds.isEmpty || state.busy) return;

    final selected = items.where((i) => state.selectedIds.contains(i.asset.id));
    state = state.copyWith(busy: true, clearStatusMessage: true);
    try {
      final files = <XFile>[];
      for (final item in selected) {
        final file = await item.asset.file;
        if (file != null) files.add(XFile(file.path));
      }
      if (files.isNotEmpty) {
        await SharePlus.instance.share(ShareParams(files: files));
      }
      state = state.copyWith(busy: false, selectedIds: {});
    } catch (error) {
      state = state.copyWith(
        busy: false,
        statusMessage: const StatusMessage(StatusMessageKey.couldNotShareFiles),
      );
    }
  }

  Future<void> deleteSelected() async {
    if (state.selectedIds.isEmpty || state.busy) return;
    final targeted = (state.items.valueOrNull ?? const [])
        .where((i) => state.selectedIds.contains(i.asset.id))
        .toList();
    state = state.copyWith(busy: true, clearStatusMessage: true);
    try {
      final deleted = await _service.delete(state.selectedIds.toList());
      unawaited(_cleanupEmptyAlbums(targeted, deleted.toSet()));
      state = state.copyWith(
        busy: false,
        selectedIds: {},
        statusMessage: StatusMessage(
          StatusMessageKey.deletedCount,
          count: deleted.length,
        ),
      );
      await refresh();
    } catch (error) {
      state = state.copyWith(
        busy: false,
        statusMessage: StatusMessage(
          StatusMessageKey.deleteFailed,
          error: error.toString(),
        ),
      );
    }
  }

  /// Deletes every item in [folder] at once — added after on-device feedback
  /// that removing a whole downloaded playlist meant opening its drill-in
  /// page and selecting every tile individually.
  Future<void> deleteFolder(LibraryFolder folder) async {
    if (state.busy) return;
    state = state.copyWith(busy: true, clearStatusMessage: true);
    try {
      final ids = folder.items.map((i) => i.asset.id).toList();
      final deleted = await _service.delete(ids);
      unawaited(_cleanupEmptyAlbums(folder.items, deleted.toSet()));
      state = state.copyWith(
        busy: false,
        statusMessage: StatusMessage(
          StatusMessageKey.deletedCount,
          count: deleted.length,
        ),
      );
      await refresh();
    } catch (error) {
      state = state.copyWith(
        busy: false,
        statusMessage: StatusMessage(
          StatusMessageKey.deleteFailed,
          error: error.toString(),
        ),
      );
    }
  }

  /// Best-effort: for every distinct album a just-deleted item came from,
  /// try to remove the now-possibly-empty on-disk directory. Deliberately
  /// fire-and-forget from the caller's perspective (never throws, doesn't
  /// affect the already-reported delete result either way — see
  /// `MediaSaveService.cleanupEmptyAlbumDir`).
  Future<void> _cleanupEmptyAlbums(
    List<LibraryItem> targeted,
    Set<String> deletedIds,
  ) async {
    final albums = <(String, bool)>{
      for (final item in targeted)
        if (deletedIds.contains(item.asset.id))
          (item.albumName, item.asset.type == AssetType.audio),
    };
    for (final (album, isAudio) in albums) {
      await _saveService.cleanupEmptyAlbumDir(album, isAudio: isAudio);
    }
  }
}

final libraryControllerProvider =
    StateNotifierProvider<LibraryController, LibraryState>(
      (ref) => LibraryController(),
    );
