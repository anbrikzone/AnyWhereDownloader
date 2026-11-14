import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/media_library_service.dart';
import '../../l10n/app_localizations.dart';
import 'library_controller.dart';
import 'library_preview.dart';
import 'library_screen.dart';

/// "Downloaded" grid under a service screen's URL field — the Library
/// items saved under that service's folder ([source], e.g. `YouTube`,
/// `X-Twitter`), so the screen isn't empty. Reads the shared
/// [libraryControllerProvider]; it only *checks* gallery permission (the
/// request happens on an explicit tap), same as Library itself.
class ServiceDownloadsSection extends ConsumerStatefulWidget {
  const ServiceDownloadsSection({
    super.key,
    required this.source,
    required this.downloading,
  });

  final String source;

  /// The owning screen's download state — a true→false edge means a file
  /// may have just landed, so the list is re-read.
  final bool downloading;

  @override
  ConsumerState<ServiceDownloadsSection> createState() =>
      _ServiceDownloadsSectionState();
}

class _ServiceDownloadsSectionState
    extends ConsumerState<ServiceDownloadsSection> {
  /// Last loaded list, shown while a refresh is in flight so the grid
  /// doesn't flash a spinner after every download.
  List<LibraryItem>? _lastItems;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void didUpdateWidget(ServiceDownloadsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.downloading && !widget.downloading) {
      // Give MediaStore a moment to index the just-saved file.
      _refreshTimer?.cancel();
      _refreshTimer = Timer(const Duration(milliseconds: 600), _refresh);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    final state = ref.read(libraryControllerProvider);
    // Still checking → the controller loads on its own once it knows.
    if (state.checkingPermission || !state.hasAccess || state.busy) return;
    ref.read(libraryControllerProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(libraryControllerProvider);
    final theme = Theme.of(context);

    if (state.checkingPermission) return const SizedBox.shrink();
    if (!state.hasAccess) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(
              l10n.serviceDownloadsNoAccess,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: state.requestedBefore
                  ? ref.read(libraryControllerProvider.notifier).openSettings
                  : ref
                        .read(libraryControllerProvider.notifier)
                        .requestPermission,
              child: Text(l10n.allowAccessButton),
            ),
          ],
        ),
      );
    }

    final all = state.items.valueOrNull;
    if (all != null) {
      _lastItems = all.where((i) => i.source == widget.source).toList()
        ..sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
    }
    final items = _lastItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(
            items == null || items.isEmpty
                ? l10n.serviceDownloadsHeader
                : '${l10n.serviceDownloadsHeader} · ${items.length}',
            style: theme.textTheme.titleSmall,
          ),
        ),
        Expanded(
          child: items == null
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
              ? Center(
                  child: Text(
                    l10n.serviceDownloadsEmpty,
                    style: const TextStyle(color: Colors.grey),
                  ),
                )
              : LibraryGrid(
                  items: items,
                  selectedIds: const {},
                  selectionMode: false,
                  onTap: (index) => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LibraryPreviewPage(
                        assets: [for (final item in items) item.asset],
                        initialIndex: index,
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
