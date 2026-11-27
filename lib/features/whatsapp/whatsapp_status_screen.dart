import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/l10n/status_message.dart';
import '../../core/logging/app_log.dart';
import '../../core/settings/app_settings_service.dart';
import '../../core/settings/settings_providers.dart';
import '../../core/storage/media_save_service.dart';
import '../../core/storage/saf_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/app_toast.dart';
import '../../l10n/app_localizations.dart';
import '../../services/whatsapp/whatsapp_status_reader.dart';
import '../library/library_grid.dart';
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
        showAppToast(context, text);
      }
    });

    // Only split into tabs once there's actually something in the archive —
    // otherwise it's just the single fresh grid, exactly as before.
    final showTabs = state.treeUri != null && state.archivedItems.isNotEmpty;

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
          // The brand header below the bar names the screen; the bar only
          // titles itself while selecting.
          title: state.selectionMode
              ? Text(l10n.itemsSelectedCount(state.selectedUris.length))
              : null,
          actions: [
            if (state.treeUri != null && !state.selectionMode)
              IconButton(
                tooltip: l10n.selectTooltip,
                icon: const Icon(Icons.checklist),
                onPressed: controller.enterSelectionMode,
              ),
            if (state.treeUri != null)
              IconButton(
                tooltip: l10n.changeFolderTooltip,
                icon: const Icon(Icons.drive_folder_upload_outlined),
                onPressed: state.busy ? null : controller.forgetFolder,
              ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: _buildBody(context, l10n, state, controller, showTabs),
            ),
            if (state.selectionMode && state.selectedUris.isNotEmpty)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: SafeArea(
                  top: false,
                  child: _ActionBar(
                    count: state.selectedUris.length,
                    saving: state.saving,
                    sharing: state.sharing,
                    onSave: controller.saveSelected,
                    onShare: controller.shareSelected,
                  ),
                ),
              ),
          ],
        ),
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
    final recentCount = state.items.valueOrNull?.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WhatsAppHeader(
            subtitle: recentCount == null
                ? null
                : l10n.whatsappStatusCount(recentCount),
            onRefresh: state.busy ? null : controller.refresh,
          ),
          if (showTabs) ...[
            _PillTabBar(
              labels: [
                '${l10n.statusTabRecent}  ${recentCount ?? ''}'.trim(),
                '${l10n.statusTabArchived}  ${state.archivedItems.length}',
              ],
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: showTabs
                ? TabBarView(
                    children: [
                      recentView,
                      _buildArchivedView(context, l10n, state, controller),
                    ],
                  )
                : recentView,
          ),
        ],
      ),
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
          child: Text(l10n.whatsappArchiveEmpty, textAlign: TextAlign.center),
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
      onLongPressSelect: (index) {
        if (!state.selectionMode) controller.enterSelectionMode();
        controller.toggleSelected(statuses[index].uri);
      },
      onTap: (index) {
        final item = statuses[index];
        if (state.selectionMode) {
          controller.toggleSelected(item.uri);
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  StatusPreviewPage(items: statuses, initialIndex: index),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
    );
    Widget step(int n, String text) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$n',
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(text, style: theme.textTheme.bodyMedium),
          ),
        ),
      ],
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _WhatsAppHeader(subtitle: l10n.whatsappSetupSubtitle),
        Material(
          color: scheme.cardSurface,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.whatsappSetupTitle, style: theme.textTheme.titleMedium),
                const SizedBox(height: 16),
                step(1, l10n.whatsappSetupStep1),
                const SizedBox(height: 14),
                step(2, l10n.whatsappSetupStep2),
                const SizedBox(height: 14),
                step(3, l10n.whatsappSetupStep3),
                const SizedBox(height: 20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: buttonShape,
                  ),
                  onPressed: () => onPick(business: false),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('WhatsApp'),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: buttonShape,
                  ),
                  onPressed: () => onPick(business: true),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('WhatsApp Business'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Brand header shared by the setup and status views: logo, name, one
/// line of detail, and (once a folder is set) a Refresh button.
class _WhatsAppHeader extends StatelessWidget {
  const _WhatsAppHeader({required this.subtitle, this.onRefresh});

  final String? subtitle;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 14),
      child: Row(
        children: [
          const ServiceLogoBadge(source: 'WhatsApp', size: 56, radius: 18),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('WhatsApp', style: theme.textTheme.headlineSmall),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (onRefresh != null)
            IconButton(
              tooltip: l10n.refreshTooltip,
              icon: const Icon(Icons.refresh),
              onPressed: onRefresh,
            ),
        ],
      ),
    );
  }
}

/// Recent / Archived switch drawn as a pill segmented control; drives the
/// enclosing [DefaultTabController].
class _PillTabBar extends StatelessWidget {
  const _PillTabBar({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      height: 44,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(22),
      ),
      child: TabBar(
        dividerHeight: 0,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: scheme.cardSurface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1)),
          ],
        ),
        labelColor: scheme.onSurface,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: theme.textTheme.labelLarge,
        splashBorderRadius: BorderRadius.circular(20),
        tabs: [for (final label in labels) Tab(text: label)],
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
            Icon(
              Icons.error_outline,
              size: 56,
              color: Theme.of(context).colorScheme.error,
            ),
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
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
    );
    // Floating card over the grid, like Library's selection bar.
    return Material(
      color: Theme.of(context).colorScheme.cardSurface,
      borderRadius: BorderRadius.circular(28),
      elevation: 6,
      shadowColor: Colors.black38,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: shape,
                ),
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
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: shape,
                ),
                onPressed: busy ? null : onSave,
                icon: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download),
                label: Text(
                  saving ? l10n.savingButton : l10n.saveCountButton(count),
                ),
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
class _StatusGrid extends ConsumerStatefulWidget {
  const _StatusGrid({
    required this.items,
    required this.selectedUris,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPressSelect,
  });

  final List<StatusItem> items;
  final Set<String> selectedUris;
  final bool selectionMode;
  final ValueChanged<int> onTap;

  /// Called on long-press instead of the peek when Settings → "Long press
  /// on media" is [LongPressAction.select].
  final ValueChanged<int> onLongPressSelect;

  @override
  ConsumerState<_StatusGrid> createState() => _StatusGridState();
}

class _StatusGridState extends ConsumerState<_StatusGrid> {
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
    final longPressSelects =
        ref.watch(longPressActionProvider) == LongPressAction.select;
    return NotificationListener<ScrollStartNotification>(
      onNotification: (_) {
        _closeActivePeek?.call();
        return false;
      },
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        child: GridView.builder(
          controller: _scrollController,
          // Room under the last row for the floating selection bar.
          padding: EdgeInsets.only(bottom: widget.selectionMode ? 96 : 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
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
              onLongPressSelect: longPressSelects
                  ? () => widget.onLongPressSelect(index)
                  : null,
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
    this.onLongPressSelect,
    required this.onPeekOpened,
    required this.onPeekClosed,
  });

  final StatusItem item;
  final bool selected;
  final bool selectionActive;
  final VoidCallback onTap;
  final VoidCallback? onLongPressSelect;
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
        final destPath = '${tempDir.path}/wa_arch_thumb_${path.hashCode}.jpg';
        final ok = await MediaSaveService().saveVideoThumbnail(
          sourcePath: path,
          destPath: destPath,
          width: 240,
          height: 240,
        );
        return ok ? destPath : null;
      }

      final destPath = '${tempDir.path}/wa_thumb_${item.uri.hashCode}.jpg';
      final ok = await SafService().saveThumbnailToFile(
        uri: item.uri,
        width: 240,
        height: 240,
        destPath: destPath,
      );
      return ok ? destPath : null;
    } catch (e, st) {
      logError('WhatsAppStatusScreen.generateThumbnail', e, st);
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
      onLongPress: widget.onLongPressSelect,
      onLongPressStart: widget.onLongPressSelect == null
          ? (_) => _openPeek()
          : null,
      onLongPressEnd: widget.onLongPressSelect == null
          ? (_) => _closePeek()
          : null,
      onLongPressCancel: widget.onLongPressSelect == null ? _closePeek : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: FutureBuilder<String?>(
                future: _thumbnailPath,
                builder: (context, snapshot) {
                  final path = snapshot.data;
                  if (path != null) {
                    return Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      // Archived images resolve to the raw full-res status
                      // file — decode it down to roughly tile size (3-col
                      // grid) instead of full resolution per tile.
                      cacheWidth: 480,
                      errorBuilder: (_, _, _) => const _TileFallbackIcon(),
                    );
                  }
                  return const _TileFallbackIcon();
                },
              ),
            ),
            // How long ago the status was posted, bottom-left.
            Positioned(
              left: 6,
              bottom: 5,
              child: Text(
                _ageLabel(AppLocalizations.of(context)!, widget.item.lastModified),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 3)],
                ),
              ),
            ),
            if (widget.item.mediaType == StatusMediaType.video)
              Positioned(
                right: 5,
                bottom: 5,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
            if (widget.selected)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            if (widget.selectionActive)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.selected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.black26,
                    border: widget.selected
                        ? null
                        : Border.all(color: Colors.white, width: 2),
                  ),
                  child: widget.selected
                      ? Icon(
                          Icons.check,
                          size: 16,
                          color: Theme.of(context).colorScheme.onPrimary,
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "5 min", "3 h", "2 d" since [at].
String _ageLabel(AppLocalizations l10n, DateTime at) {
  final age = DateTime.now().difference(at);
  if (age.inHours < 1) return l10n.ageMinutes(age.inMinutes.clamp(1, 59));
  if (age.inDays < 1) return l10n.ageHours(age.inHours);
  return l10n.ageDays(age.inDays);
}

class _TileFallbackIcon extends StatelessWidget {
  const _TileFallbackIcon();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.insert_drive_file_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
