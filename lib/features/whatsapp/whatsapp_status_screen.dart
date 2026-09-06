import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/l10n/status_message.dart';
import '../../core/storage/media_save_service.dart';
import '../../core/storage/saf_service.dart';
import '../../l10n/app_localizations.dart';
import '../../services/whatsapp/whatsapp_status_reader.dart';
import 'whatsapp_status_controller.dart';
import 'whatsapp_status_preview.dart';

class WhatsAppStatusScreen extends ConsumerWidget {
  const WhatsAppStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(whatsAppStatusControllerProvider);
    final controller = ref.read(whatsAppStatusControllerProvider.notifier);

    ref.listen(whatsAppStatusControllerProvider, (previous, next) {
      final message = next.lastResultMessage;
      if (message != null && message != previous?.lastResultMessage) {
        final text = resolveStatusMessage(l10n, message);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(text)));
      }
    });

    // Only split into tabs once there's actually something in the archive —
    // otherwise it's just the single fresh grid, exactly as before.
    final showTabs =
        state.treeUri != null && state.archivedItems.isNotEmpty;

    return DefaultTabController(
      length: showTabs ? 2 : 1,
      child: Scaffold(
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
                ? l10n.itemsSelectedCount(state.selectedUris.length)
                : 'WhatsApp',
          ),
          actions: [
            if (state.treeUri != null && !state.selectionMode)
              IconButton(
                tooltip: l10n.selectTooltip,
                icon: const Icon(Icons.checklist),
                onPressed: controller.enterSelectionMode,
              ),
            if (state.treeUri != null)
              IconButton(
                tooltip: l10n.refreshTooltip,
                icon: const Icon(Icons.refresh),
                onPressed: state.busy ? null : controller.refresh,
              ),
            if (state.treeUri != null)
              IconButton(
                tooltip: l10n.changeFolderTooltip,
                icon: const Icon(Icons.drive_folder_upload_outlined),
                onPressed: state.busy ? null : controller.forgetFolder,
              ),
          ],
          bottom: showTabs
              ? TabBar(
                  tabs: [
                    Tab(text: l10n.statusTabRecent),
                    Tab(text: l10n.statusTabArchived),
                  ],
                )
              : null,
        ),
        body: _buildBody(context, l10n, state, controller, showTabs),
        bottomNavigationBar:
            state.selectionMode && state.selectedUris.isNotEmpty
            ? _ActionBar(
                count: state.selectedUris.length,
                saving: state.saving,
                sharing: state.sharing,
                onSave: controller.saveSelected,
                onShare: controller.shareSelected,
              )
            : null,
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    WhatsAppStatusState state,
    WhatsAppStatusController controller,
    bool showTabs,
  ) {
    if (state.checkingFolder) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.treeUri == null) {
      return _FolderPickerPrompt(onPick: controller.pickFolder);
    }

    final recentView = _buildRecentView(context, l10n, state, controller);
    if (!showTabs) return recentView;

    return TabBarView(
      children: [
        recentView,
        _buildArchivedView(context, l10n, state, controller),
      ],
    );
  }

  Widget _buildRecentView(
    BuildContext context,
    AppLocalizations l10n,
    WhatsAppStatusState state,
    WhatsAppStatusController controller,
  ) {
    return state.items.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorState(
        message: l10n.couldNotReadFolder(error.toString()),
        onRetry: controller.refresh,
        onPickAgain: controller.pickFolder,
      ),
      data: (statuses) {
        if (statuses.isEmpty) {
          return _EmptyState(onRefresh: controller.refresh);
        }
        return _buildGrid(context, state, controller, statuses);
      },
    );
  }

  Widget _buildArchivedView(
    BuildContext context,
    AppLocalizations l10n,
    WhatsAppStatusState state,
    WhatsAppStatusController controller,
  ) {
    final archived = state.archivedItems;
    if (archived.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.whatsappArchiveEmpty,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return _buildGrid(context, state, controller, archived);
  }

  Widget _buildGrid(
    BuildContext context,
    WhatsAppStatusState state,
    WhatsAppStatusController controller,
    List<StatusItem> statuses,
  ) {
    return _StatusGrid(
      items: statuses,
      selectedUris: state.selectedUris,
      selectionMode: state.selectionMode,
      onTap: (index) {
        final item = statuses[index];
        if (state.selectionMode) {
          controller.toggleSelected(item.uri);
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => StatusPreviewPage(
                items: statuses,
                initialIndex: index,
              ),
            ),
          );
        }
      },
    );
  }
}

class _FolderPickerPrompt extends StatelessWidget {
  const _FolderPickerPrompt({required this.onPick});

  final void Function({required bool business}) onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open, size: 56),
            const SizedBox(height: 16),
            Text(
              l10n.whatsappPickFolderInstructions,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.whatsappPickFolderNote,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => onPick(business: false),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('WhatsApp'),
                ),
                OutlinedButton.icon(
                  onPressed: () => onPick(business: true),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('WhatsApp Business'),
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
            const Icon(Icons.image_not_supported_outlined, size: 56),
            const SizedBox(height: 16),
            Text(l10n.whatsappNoStatuses, textAlign: TextAlign.center),
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
  const _ErrorState({
    required this.message,
    required this.onRetry,
    required this.onPickAgain,
  });

  final String message;
  final VoidCallback onRetry;
  final void Function({required bool business}) onPickAgain;

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
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.retryButton),
                ),
                OutlinedButton.icon(
                  onPressed: () => onPickAgain(business: false),
                  icon: const Icon(Icons.folder_open),
                  label: Text(l10n.pickFolderAgainButton),
                ),
              ],
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
    required this.saving,
    required this.sharing,
    required this.onSave,
    required this.onShare,
  });

  final int count;
  final bool saving;
  final bool sharing;
  final VoidCallback onSave;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final busy = saving || sharing;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : onShare,
                icon: sharing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.share),
                label: Text(sharing ? l10n.sharingButton : l10n.shareButton),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : onSave,
                icon: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download),
                label: Text(saving ? l10n.savingButton : l10n.saveCountButton(count)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grid of statuses — same scrollbar + peek-guard treatment as Library's
/// `_LibraryGrid` (see there for the full rationale): a thicker, always
/// visible scrollbar, and forcing whatever long-press peek video is
/// currently playing to close the instant a real scroll starts, since only
/// one peek/video controller should ever be alive at a time.
class _StatusGrid extends StatefulWidget {
  const _StatusGrid({
    required this.items,
    required this.selectedUris,
    required this.selectionMode,
    required this.onTap,
  });

  final List<StatusItem> items;
  final Set<String> selectedUris;
  final bool selectionMode;
  final ValueChanged<int> onTap;

  @override
  State<_StatusGrid> createState() => _StatusGridState();
}

class _StatusGridState extends State<_StatusGrid> {
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
            final selected = widget.selectedUris.contains(item.uri);
            return _StatusTile(
              key: ValueKey(item.uri),
              item: item,
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

class _StatusTile extends StatefulWidget {
  const _StatusTile({
    required super.key,
    required this.item,
    required this.selected,
    required this.selectionActive,
    required this.onTap,
    required this.onPeekOpened,
    required this.onPeekClosed,
  });

  final StatusItem item;
  final bool selected;
  final bool selectionActive;
  final VoidCallback onTap;
  final ValueChanged<VoidCallback> onPeekOpened;
  final ValueChanged<VoidCallback> onPeekClosed;

  @override
  State<_StatusTile> createState() => _StatusTileState();
}

class _StatusTileState extends State<_StatusTile> {
  // Shared across tile instances, same rationale as Library's tile cache:
  // GridView.builder recycles tiles while scrolling, and without this
  // every scroll-back-into-view would re-generate the same thumbnail.
  static final Map<String, Future<String?>> _thumbnailCache = {};

  late Future<String?> _thumbnailPath;
  OverlayEntry? _peekEntry;
  VoidCallback? _closePeekCallback;

  @override
  void initState() {
    super.initState();
    _thumbnailPath = _thumbnailCache.putIfAbsent(
      widget.item.uri,
      _generateThumbnail,
    );
  }

  Future<String?> _generateThumbnail() async {
    try {
      final item = widget.item;
      final tempDir = await getTemporaryDirectory();

      // Archived items are private local files, not SAF documents — an
      // image renders straight from disk, a video needs a decoded frame
      // from the native bridge (it isn't a MediaStore asset either).
      if (item.isArchived) {
        final path = item.localPath;
        if (path == null) return null;
        if (item.mediaType == StatusMediaType.image) return path;
        final destPath =
            '${tempDir.path}/wa_arch_thumb_${path.hashCode}.jpg';
        final ok = await MediaSaveService().saveVideoThumbnail(
          sourcePath: path,
          destPath: destPath,
          width: 240,
          height: 240,
        );
        return ok ? destPath : null;
      }

      final destPath =
          '${tempDir.path}/wa_thumb_${item.uri.hashCode}.jpg';
      final ok = await SafService().saveThumbnailToFile(
        uri: item.uri,
        width: 240,
        height: 240,
        destPath: destPath,
      );
      return ok ? destPath : null;
    } catch (_) {
      return null;
    }
  }

  void _openPeek() {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (_) => StatusPeekPreview(item: widget.item),
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
      onTap: widget.onTap,
      onLongPressStart: (_) => _openPeek(),
      onLongPressEnd: (_) => _closePeek(),
      onLongPressCancel: _closePeek,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: Colors.black12,
            child: FutureBuilder<String?>(
              future: _thumbnailPath,
              builder: (context, snapshot) {
                final path = snapshot.data;
                if (path != null) {
                  return Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const _TileFallbackIcon(),
                  );
                }
                return const _TileFallbackIcon();
              },
            ),
          ),
          if (widget.item.mediaType == StatusMediaType.video)
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
  const _TileFallbackIcon();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(Icons.insert_drive_file_outlined, color: Colors.white54),
    );
  }
}
