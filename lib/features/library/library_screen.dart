import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../core/l10n/status_message.dart';
import '../../core/storage/media_library_service.dart';
import '../../core/ui/app_toast.dart';
import '../../l10n/app_localizations.dart';
import 'library_controller.dart';
import 'library_folder_screen.dart';
import 'library_grid.dart';
import 'library_preview.dart';

export 'library_grid.dart' show LibraryGrid;

/// Library (redesign variant A, approved 2026-11-14): a day-grouped feed
/// with a type filter, source chips with counts, a playlists strip, search,
/// and a floating Share/Delete bar while selecting.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _searching = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Home's "Recent" strip and the service screens read this controller
    // too, so a migration may already be pending before Library ever
    // mounts — `ref.listen` below only sees later changes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(libraryControllerProvider).pendingMigrationConsent != null) {
        _showMigrationConsentDialog(
          context,
          ref.read(libraryControllerProvider.notifier),
          AppLocalizations.of(context)!,
        );
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _closeSearch() {
    _searchController.clear();
    ref.read(libraryControllerProvider.notifier).setSearchQuery('');
    setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(libraryControllerProvider);
    final controller = ref.read(libraryControllerProvider.notifier);

    ref.listen(libraryControllerProvider, (previous, next) {
      final message = next.statusMessage;
      if (message != null && message != previous?.statusMessage) {
        final text = resolveStatusMessage(l10n, message);
        showAppToast(context, text);
      }
      // Only on the null -> non-null transition — a decline clears this
      // back to null (see `LibraryController.postponeMigration`), and the
      // next `attemptMigration()` (next time Library loads) sets a fresh
      // one, which should prompt again rather than silently give up.
      final pendingConsent = next.pendingMigrationConsent;
      if (pendingConsent != null && previous?.pendingMigrationConsent == null) {
        _showMigrationConsentDialog(context, controller, l10n);
      }
    });

    final showActionBar = state.selectionMode && state.selectedIds.isNotEmpty;

    return PopScope(
      canPop: !state.selectionMode && !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (state.selectionMode) {
          controller.exitSelectionMode();
        } else if (_searching) {
          _closeSearch();
        }
      },
      child: Scaffold(
        appBar: _buildAppBar(context, l10n, state, controller),
        body: Stack(
          children: [
            Positioned.fill(
              child: _buildBody(context, l10n, state, controller),
            ),
            if (showActionBar)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _FloatingActionBar(
                  busy: state.busy,
                  onShare: controller.shareSelected,
                  // No in-app confirmation: on Android 11+ deleteWithIds()
                  // goes through MediaStore.createDeleteRequest(), which
                  // shows the OS's own prompt for the whole batch.
                  onDelete: controller.deleteSelected,
                ),
              ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    AppLocalizations l10n,
    LibraryState state,
    LibraryController controller,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (state.selectionMode) {
      final visibleIds = [
        for (final item in state.visibleItems ?? const <LibraryItem>[])
          item.asset.id,
      ];
      final allSelected =
          visibleIds.isNotEmpty && state.selectedIds.containsAll(visibleIds);
      return AppBar(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        leading: IconButton(
          tooltip: l10n.cancelSelectionTooltip,
          icon: const Icon(Icons.close),
          onPressed: controller.exitSelectionMode,
        ),
        title: Text(l10n.itemsSelectedCount(state.selectedIds.length)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: OutlinedButton(
              onPressed: visibleIds.isEmpty
                  ? null
                  : () => controller.toggleSelectedGroup(visibleIds),
              child: Text(
                allSelected ? l10n.deselectAllTooltip : l10n.selectAllTooltip,
              ),
            ),
          ),
        ],
      );
    }

    if (_searching) {
      return AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: _closeSearch,
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: l10n.librarySearchHint,
            border: InputBorder.none,
          ),
          onChanged: controller.setSearchQuery,
        ),
        actions: [
          ValueListenableBuilder(
            valueListenable: _searchController,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: l10n.clearTooltip,
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      controller.setSearchQuery('');
                    },
                  ),
          ),
        ],
      );
    }

    final total = state.items.valueOrNull?.length;
    return AppBar(
      toolbarHeight: 68,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.libraryTitle),
          if (total != null && total > 0)
            Text(
              l10n.libraryFileCount(total),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      actions: [
        if (state.hasAccess) ...[
          IconButton(
            tooltip: l10n.searchTooltip,
            icon: const Icon(Icons.search),
            onPressed: () => setState(() => _searching = true),
          ),
          PopupMenuButton<LibrarySortOption>(
            tooltip: l10n.sortTooltip,
            icon: const Icon(Icons.sort),
            initialValue: state.sortOption,
            onSelected: controller.setSortOption,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: LibrarySortOption.dateNewest,
                child: Text(l10n.newestFirst),
              ),
              PopupMenuItem(
                value: LibrarySortOption.dateOldest,
                child: Text(l10n.oldestFirst),
              ),
              PopupMenuItem(
                value: LibrarySortOption.nameAZ,
                child: Text(l10n.nameAZ),
              ),
              PopupMenuItem(
                value: LibrarySortOption.nameZA,
                child: Text(l10n.nameZA),
              ),
            ],
          ),
          IconButton(
            tooltip: l10n.selectTooltip,
            icon: const Icon(Icons.check_box_outlined),
            onPressed: controller.enterSelectionMode,
          ),
        ],
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    LibraryState state,
    LibraryController controller,
  ) {
    if (state.checkingPermission) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!state.hasAccess) {
      return _PermissionPrompt(
        deniedBefore: state.requestedBefore,
        onRequest: controller.requestPermission,
        onOpenSettings: controller.openSettings,
      );
    }

    return state.items.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorState(
        message: l10n.couldNotLoadLibrary(error.toString()),
        onRetry: controller.refresh,
      ),
      data: (allItems) {
        if (allItems.isEmpty) {
          return _EmptyState(onRefresh: controller.refresh);
        }
        final visible = state.visibleItems ?? const <LibraryItem>[];
        final folders = state.visibleFolders;
        final counts = state.sourceCounts;

        final header = <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: _TypeFilterBar(
                value: state.typeFilter,
                labels: {
                  LibraryTypeFilter.all: l10n.filterAll,
                  LibraryTypeFilter.video: l10n.filterTypeVideo,
                  LibraryTypeFilter.photo: l10n.filterTypePhoto,
                  LibraryTypeFilter.audio: l10n.filterTypeAudio,
                },
                onChanged: controller.setTypeFilter,
              ),
            ),
          ),
          if (state.availableSources.length > 1)
            SliverToBoxAdapter(
              child: _SourceFilterRow(
                sources: state.sourcesByCount,
                counts: counts,
                selected: state.sourceFilter,
                onSelected: controller.setSourceFilter,
              ),
            ),
          // Folders (playlist downloads, backlog #7) hidden while
          // selecting — the top-level selection model only knows about
          // individual assets, not "select every item in this folder".
          if (folders.isNotEmpty && !state.selectionMode)
            SliverToBoxAdapter(
              child: _FolderRow(
                folders: folders,
                onOpened: controller.refresh,
                onDelete: controller.deleteFolder,
              ),
            ),
        ];

        return RefreshIndicator(
          onRefresh: controller.refresh,
          child: LibraryGrid(
            items: visible,
            selectedIds: state.selectedIds,
            selectionMode: state.selectionMode,
            headerSlivers: header,
            groupByDay: state.sortedByDate,
            showSource: state.sourceFilter == null,
            onSelectGroup: controller.toggleSelectedGroup,
            emptyChild: folders.isEmpty ? const _NoMatchesState() : null,
            bottomPadding: state.selectionMode ? 96 : 16,
            onLongPressSelect: (index) {
              if (!state.selectionMode) {
                controller.enterSelectionMode();
              }
              controller.toggleSelected(visible[index].asset.id);
            },
            onTap: (index) {
              final asset = visible[index].asset;
              if (state.selectionMode) {
                controller.toggleSelected(asset.id);
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LibraryPreviewPage(
                      assets: [for (final item in visible) item.asset],
                      initialIndex: index,
                    ),
                  ),
                );
              }
            },
          ),
        );
      },
    );
  }
}

/// Dark pill floating above the grid while items are selected.
class _FloatingActionBar extends StatelessWidget {
  const _FloatingActionBar({
    required this.busy,
    required this.onShare,
    required this.onDelete,
  });

  final bool busy;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.inverseSurface,
      elevation: 6,
      borderRadius: BorderRadius.circular(32),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onInverseSurface,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: busy ? null : onShare,
                icon: const Icon(Icons.share_outlined),
                label: Text(l10n.shareButton),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.errorContainer,
                  foregroundColor: scheme.onErrorContainer,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: busy ? null : onDelete,
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.deleteButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Explains *why* before the system write-access consent dialog appears —
/// added after on-device feedback that it otherwise popped up with no
/// warning. "Not now" (or dismissing) postpones; Library asks again next
/// time it loads (see `LibraryController.postponeMigration`) rather than
/// giving up, since pre-existing downloads always end up migrated
/// eventually and new downloads already use the new layout either way.
Future<void> _showMigrationConsentDialog(
  BuildContext context,
  LibraryController controller,
  AppLocalizations l10n,
) async {
  final proceed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.migrationConsentDialogTitle),
      content: Text(l10n.migrationConsentDialogBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.migrationConsentNotNow),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.migrationConsentContinue),
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  if (proceed == true) {
    await controller.confirmMigration();
  } else {
    controller.postponeMigration();
  }
}

/// "All sources" + one chip per source, each with its brand dot and count.
class _SourceFilterRow extends StatelessWidget {
  const _SourceFilterRow({
    required this.sources,
    required this.counts,
    required this.selected,
    required this.onSelected,
  });

  final List<String> sources;
  final Map<String, int> counts;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        children: [
          _SourceChip(
            label: l10n.allSourcesChip,
            selected: selected == null,
            onTap: () => onSelected(null),
          ),
          for (final source in sources)
            // A source with nothing under the current type filter / search
            // is hidden, unless it's the one selected.
            if ((counts[source] ?? 0) > 0 || selected == source)
              _SourceChip(
                label: librarySourceLabel(source),
                count: counts[source] ?? 0,
                dotColor:
                    librarySourceBadges[source]?.$2 ??
                    theme.colorScheme.outline,
                selected: selected == source,
                onTap: () => onSelected(source),
              ),
        ],
      ),
    );
  }
}

/// Horizontal strip of playlist-download folders (backlog #7), each a 2×2
/// mosaic of its newest items.
class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.folders,
    required this.onOpened,
    required this.onDelete,
  });

  final List<LibraryFolder> folders;

  /// Called after returning from a folder's drill-in page — a share/delete
  /// there can change what the top-level grid should show.
  final VoidCallback onOpened;

  /// Long-press a card's "Delete playlist" action.
  final ValueChanged<LibraryFolder> onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.libraryPlaylistsHeader,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text(
                '${folders.length}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 152,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: folders.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final folder = folders[index];
              return _FolderCard(
                folder: folder,
                onReturn: onOpened,
                onDelete: () => onDelete(folder),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({
    required this.folder,
    required this.onReturn,
    required this.onDelete,
  });

  final LibraryFolder folder;
  final VoidCallback onReturn;
  final VoidCallback onDelete;

  Future<void> _showActions(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final delete = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.delete_outline),
          title: Text(l10n.deletePlaylistTooltip),
          onTap: () => Navigator.of(context).pop(true),
        ),
      ),
    );
    if (delete == true) onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final covers = folder.items.take(4).map((i) => i.asset).toList();
    return SizedBox(
      width: 156,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  PlaylistFolderPage(title: folder.label, items: folder.items),
            ),
          );
          onReturn();
        },
        onLongPress: () => _showActions(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 104,
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                  childAspectRatio: 77 / 51,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  children: [
                    for (var i = 0; i < 4; i++)
                      i < covers.length
                          ? _FolderThumbnail(asset: covers[i])
                          : ColoredBox(
                              color: theme.colorScheme.surfaceContainerHighest,
                            ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              folder.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge,
            ),
            Text(
              '${folder.count}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderThumbnail extends StatelessWidget {
  const _FolderThumbnail({required this.asset});

  final AssetEntity asset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: asset.type == AssetType.audio
          ? Icon(Icons.audiotrack_outlined, color: scheme.onSurfaceVariant)
          : FutureBuilder<Uint8List?>(
              future: asset.thumbnailDataWithSize(
                const ThumbnailSize(160, 160),
              ),
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (bytes == null) return const SizedBox.shrink();
                return Image.memory(bytes, fit: BoxFit.cover);
              },
            ),
    );
  }
}

class _NoMatchesState extends StatelessWidget {
  const _NoMatchesState();

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(AppLocalizations.of(context)!.noFilesForFilter));
  }
}

class _PermissionPrompt extends StatelessWidget {
  const _PermissionPrompt({
    required this.deniedBefore,
    required this.onRequest,
    required this.onOpenSettings,
  });

  final bool deniedBefore;
  final VoidCallback onRequest;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_library_outlined, size: 56),
            const SizedBox(height: 16),
            Text(
              deniedBefore
                  ? l10n.libraryAccessDenied
                  : l10n.libraryAllowAccessPrompt,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: onRequest,
                  icon: const Icon(Icons.lock_open),
                  label: Text(
                    deniedBefore ? l10n.tryAgainButton : l10n.allowAccessButton,
                  ),
                ),
                if (deniedBefore)
                  OutlinedButton.icon(
                    onPressed: onOpenSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(l10n.openSettingsButton),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_off_outlined, size: 56),
            const SizedBox(height: 16),
            Text(l10n.libraryNoDownloads, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.refreshTooltip),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 56,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.retryButton),
            ),
          ],
        ),
      ),
    );
  }
}

class LibraryActionBar extends StatelessWidget {
  const LibraryActionBar({
    super.key,
    required this.count,
    required this.busy,
    required this.onShare,
    required this.onDelete,
  });

  final int count;
  final bool busy;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : onShare,
                icon: const Icon(Icons.share),
                label: Text(l10n.shareCountButton(count)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : onDelete,
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.deleteButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "All | Video | Photo | Audio": a rounded track with the selected option
/// on a raised pill — no borders or check mark (Library redesign mockup).
class _TypeFilterBar extends StatelessWidget {
  const _TypeFilterBar({
    required this.value,
    required this.labels,
    required this.onChanged,
  });

  final LibraryTypeFilter value;
  final Map<LibraryTypeFilter, String> labels;
  final ValueChanged<LibraryTypeFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final selectedBg = dark
        ? scheme.primaryContainer
        : scheme.surfaceContainerLowest;
    final selectedFg = dark ? scheme.onPrimaryContainer : scheme.onSurface;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          for (final entry in labels.entries)
            Expanded(
              child: Semantics(
                button: true,
                selected: entry.key == value,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(entry.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: entry.key == value
                          ? selectedBg
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: entry.key == value && !dark
                          ? const [
                              BoxShadow(
                                color: Color(0x1F000000),
                                blurRadius: 2,
                                offset: Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      entry.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: entry.key == value
                            ? selectedFg
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A compact rounded source chip: brand dot, name, muted count; the
/// selected one is filled with the primary color (no check mark).
class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.dotColor,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = selected ? scheme.onPrimary : scheme.onSurface;
    final muted = selected
        ? scheme.onPrimary.withValues(alpha: 0.8)
        : scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? scheme.primary : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dotColor != null) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? scheme.onPrimary
                            : scheme.outlineVariant,
                        width: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(color: fg),
                ),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: muted,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
