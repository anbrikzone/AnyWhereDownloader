import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../core/l10n/status_message.dart';
import '../../core/storage/media_library_service.dart';
import '../../core/ui/app_toast.dart';
import '../../l10n/app_localizations.dart';
import 'library_controller.dart';
import 'library_preview.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(libraryControllerProvider);
    final controller = ref.read(libraryControllerProvider.notifier);

    ref.listen(libraryControllerProvider, (previous, next) {
      final message = next.statusMessage;
      if (message != null && message != previous?.statusMessage) {
        final text = resolveStatusMessage(l10n, message);
        showAppToast(context, text);
      }
    });

    return Scaffold(
      appBar: AppBar(
        leading: state.selectionMode
            ? IconButton(
                tooltip: l10n.cancelSelectionTooltip,
                icon: const Icon(Icons.close),
                onPressed: controller.exitSelectionMode,
              )
            : null,
        title: Text(
          state.selectionMode
              ? l10n.itemsSelectedCount(state.selectedIds.length)
              : l10n.libraryTitle,
        ),
        actions: [
          if (state.hasAccess && !state.selectionMode) ...[
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
              icon: const Icon(Icons.checklist),
              onPressed: controller.enterSelectionMode,
            ),
          ],
          if (state.hasAccess)
            IconButton(
              tooltip: l10n.refreshTooltip,
              icon: const Icon(Icons.refresh),
              onPressed: state.busy ? null : controller.refresh,
            ),
        ],
      ),
      body: _buildBody(context, l10n, state, controller),
      bottomNavigationBar: state.selectionMode && state.selectedIds.isNotEmpty
          ? _ActionBar(
              count: state.selectedIds.length,
              busy: state.busy,
              onShare: controller.shareSelected,
              // No in-app confirmation dialog: Android's scoped storage
              // makes photo_manager's deleteWithIds() go through
              // MediaStore.createDeleteRequest() on Android 11+, which
              // shows the OS's own "Allow … to delete?" prompt (with a
              // thumbnail) for the whole batch. A second, app-drawn
              // confirmation on top of that is just double friction.
              onDelete: controller.deleteSelected,
            )
          : null,
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
        final visible = state.visibleItems ?? const [];
        return Column(
          children: [
            if (state.availableSources.length > 1)
              _SourceFilterRow(
                sources: state.availableSources,
                selected: state.sourceFilter,
                onSelected: controller.setSourceFilter,
              ),
            Expanded(
              child: visible.isEmpty
                  ? const _NoMatchesState()
                  : _LibraryGrid(
                      items: visible,
                      selectedIds: state.selectedIds,
                      selectionMode: state.selectionMode,
                      onTap: (index) {
                        final asset = visible[index].asset;
                        if (state.selectionMode) {
                          controller.toggleSelected(asset.id);
                        } else {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => LibraryPreviewPage(
                                assets: [
                                  for (final item in visible) item.asset,
                                ],
                                initialIndex: index,
                              ),
                            ),
                          );
                        }
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _SourceFilterRow extends StatelessWidget {
  const _SourceFilterRow({
    required this.sources,
    required this.selected,
    required this.onSelected,
  });

  final List<String> sources;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(l10n.filterAll),
              selected: selected == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final source in sources)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(source),
                selected: selected == source,
                onSelected: (_) => onSelected(source),
              ),
            ),
        ],
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
                  label: Text(deniedBefore ? l10n.tryAgainButton : l10n.allowAccessButton),
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
            const Icon(Icons.error_outline, size: 56, color: Colors.red),
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

class _ActionBar extends StatelessWidget {
  const _ActionBar({
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

/// Grid of downloaded assets. Owns the [ScrollController] so it can (a)
/// drive a thicker, always-visible [Scrollbar] — the default Material one
/// is a hairline that's easy to miss — and (b) force-close whatever
/// long-press "peek" video is currently playing the instant a real drag
/// starts. Without (b), a peek's [VideoPlayerController] can keep playing
/// (and its tile's state can be recycled by `GridView.builder`) while the
/// grid scrolls out from under it, which is the likely source of the
/// "video freezes, play/pause stop responding" reports during scrolling —
/// rapid, overlapping controller creation/disposal is a known way to
/// exhaust the platform's video decoder/texture resources on Android.
class _LibraryGrid extends StatefulWidget {
  const _LibraryGrid({
    required this.items,
    required this.selectedIds,
    required this.selectionMode,
    required this.onTap,
  });

  final List<LibraryItem> items;
  final Set<String> selectedIds;
  final bool selectionMode;
  final ValueChanged<int> onTap;

  @override
  State<_LibraryGrid> createState() => _LibraryGridState();
}

class _LibraryGridState extends State<_LibraryGrid> {
  final ScrollController _scrollController = ScrollController();
  VoidCallback? _closeActivePeek;

  void _registerPeek(VoidCallback close) {
    if (_closeActivePeek != close) {
      _closeActivePeek?.call();
    }
    _closeActivePeek = close;
  }

  void _unregisterPeek(VoidCallback close) {
    if (_closeActivePeek == close) {
      _closeActivePeek = null;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollStartNotification>(
      onNotification: (_) {
        _closeActivePeek?.call();
        return false;
      },
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        thickness: 10,
        radius: const Radius.circular(6),
        child: GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemCount: widget.items.length,
          itemBuilder: (context, index) {
            final item = widget.items[index];
            final asset = item.asset;
            final selected = widget.selectedIds.contains(asset.id);
            return _LibraryTile(
              key: ValueKey(asset.id),
              asset: asset,
              selected: selected,
              selectionActive: widget.selectionMode,
              onTap: () => widget.onTap(index),
              onPeekOpened: _registerPeek,
              onPeekClosed: _unregisterPeek,
            );
          },
        ),
      ),
    );
  }
}

class _LibraryTile extends StatefulWidget {
  const _LibraryTile({
    required super.key,
    required this.asset,
    required this.selected,
    required this.selectionActive,
    required this.onTap,
    required this.onPeekOpened,
    required this.onPeekClosed,
  });

  final AssetEntity asset;
  final bool selected;
  final bool selectionActive;
  final VoidCallback onTap;
  final ValueChanged<VoidCallback> onPeekOpened;
  final ValueChanged<VoidCallback> onPeekClosed;

  @override
  State<_LibraryTile> createState() => _LibraryTileState();
}

class _LibraryTileState extends State<_LibraryTile> {
  // Keyed by "assetId_size" and shared across tile instances so
  // GridView.builder recycling old/new tiles while scrolling doesn't
  // re-fetch the same thumbnail over the platform channel every time —
  // that churn was a plausible contributor to scroll jank/freezes.
  static final Map<String, Future<Uint8List?>> _thumbnailCache = {};

  late Future<Uint8List?> _thumbnail;
  OverlayEntry? _peekEntry;
  VoidCallback? _closePeekCallback;

  @override
  void initState() {
    super.initState();
    // Audio has no meaningful thumbnail — MediaStore returned garbled bytes
    // for it. Skip the fetch and let the fallback icon stand in.
    _thumbnail = widget.asset.type == AssetType.audio
        ? Future<Uint8List?>.value(null)
        : _thumbnailCache.putIfAbsent(
            '${widget.asset.id}_240',
            () => widget.asset
                .thumbnailDataWithSize(const ThumbnailSize(240, 240)),
          );
  }

  void _openPeek() {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (_) => LibraryPeekPreview(asset: widget.asset),
    );
    _peekEntry = entry;
    _closePeekCallback = _closePeek;
    widget.onPeekOpened(_closePeekCallback!);
    overlay.insert(entry);
  }

  void _closePeek() {
    _peekEntry?.remove();
    _peekEntry = null;
    if (_closePeekCallback != null) {
      widget.onPeekClosed(_closePeekCallback!);
      _closePeekCallback = null;
    }
  }

  @override
  void dispose() {
    _peekEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // opaque so a tap anywhere on the tile registers, not just where a
      // hit-testable child happens to be painted.
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPressStart: (_) => _openPeek(),
      onLongPressEnd: (_) => _closePeek(),
      onLongPressCancel: _closePeek,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: Colors.black12,
            child: FutureBuilder<Uint8List?>(
              future: _thumbnail,
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (bytes != null) {
                  return Image.memory(bytes, fit: BoxFit.cover);
                }
                return _TileFallbackIcon(type: widget.asset.type);
              },
            ),
          ),
          if (widget.asset.type == AssetType.video)
            const Align(
              alignment: Alignment.center,
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white70,
                size: 32,
              ),
            ),
          if (widget.selectionActive)
            Positioned(
              top: 4,
              right: 4,
              child: CircleAvatar(
                radius: 12,
                backgroundColor: widget.selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.black45,
                child: Icon(
                  widget.selected ? Icons.check : Icons.circle_outlined,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TileFallbackIcon extends StatelessWidget {
  const _TileFallbackIcon({this.type});

  final AssetType? type;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        type == AssetType.audio
            ? Icons.audiotrack_outlined
            : Icons.insert_drive_file_outlined,
        color: Colors.white54,
      ),
    );
  }
}
