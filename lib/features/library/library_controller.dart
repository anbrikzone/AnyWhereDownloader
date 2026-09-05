import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n/status_message.dart';
import '../../core/storage/media_library_service.dart';

enum LibrarySortOption { dateNewest, dateOldest, nameAZ, nameZA }

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
  /// meaningful once [items] has data — null while loading/erroring.
  List<LibraryItem>? get visibleItems {
    final all = items.valueOrNull;
    if (all == null) return null;
    final filtered = sourceFilter == null
        ? all
        : all.where((i) => i.source == sourceFilter).toList();
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
  LibraryController({MediaLibraryService? service})
    : _service = service ?? MediaLibraryService(),
      super(const LibraryState()) {
    _init();
  }

  final MediaLibraryService _service;

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
    state = state.copyWith(busy: true, clearStatusMessage: true);
    try {
      final deleted = await _service.delete(state.selectedIds.toList());
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
}

final libraryControllerProvider =
    StateNotifierProvider<LibraryController, LibraryState>(
      (ref) => LibraryController(),
    );
