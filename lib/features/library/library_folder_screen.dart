import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/storage/media_library_service.dart';
import '../../core/storage/media_save_service.dart';
import '../../l10n/app_localizations.dart';
import 'library_preview.dart';
import 'library_screen.dart';

/// Drill-in view of one playlist folder (backlog #7) — a fixed, already-
/// loaded [items] list rather than a live Riverpod-backed screen: the parent
/// `LibraryScreen` refreshes itself (and thus its folder list) when this
/// page is popped, so this page only needs to track its own selection state
/// and reflect a delete performed here immediately, not stay reactive to
/// changes made elsewhere while it's open.
class PlaylistFolderPage extends StatefulWidget {
  const PlaylistFolderPage({
    super.key,
    required this.title,
    required this.items,
  });

  final String title;
  final List<LibraryItem> items;

  @override
  State<PlaylistFolderPage> createState() => _PlaylistFolderPageState();
}

class _PlaylistFolderPageState extends State<PlaylistFolderPage> {
  final _service = MediaLibraryService();
  final _saveService = MediaSaveService();
  late List<LibraryItem> _items;
  bool _selectionMode = false;
  Set<String> _selectedIds = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.items);
  }

  void _enterSelectionMode() {
    setState(() {
      _selectionMode = true;
      _selectedIds = {};
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds = {};
    });
  }

  void _toggleSelected(String id) {
    final selected = {..._selectedIds};
    if (!selected.remove(id)) {
      selected.add(id);
    }
    setState(() => _selectedIds = selected);
  }

  /// Selects every item, or (if all are already selected) clears the
  /// selection — deleting/sharing a whole playlist at once shouldn't require
  /// tapping every tile individually.
  void _toggleSelectAll() {
    setState(() {
      _selectedIds = _selectedIds.length == _items.length
          ? {}
          : _items.map((i) => i.asset.id).toSet();
    });
  }

  Future<void> _shareSelected() async {
    if (_selectedIds.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final files = <XFile>[];
      for (final item in _items.where((i) => _selectedIds.contains(i.asset.id))) {
        final file = await item.asset.file;
        if (file != null) files.add(XFile(file.path));
      }
      if (files.isNotEmpty) {
        await SharePlus.instance.share(ShareParams(files: files));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _selectedIds = {};
        });
      }
    }
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty || _busy) return;
    setState(() => _busy = true);
    final targeted = _items.where((i) => _selectedIds.contains(i.asset.id)).toList();
    final deleted = await _service.delete(_selectedIds.toList());
    final deletedSet = deleted.toSet();
    // Best-effort: if that emptied the playlist's whole album directory,
    // try to remove it too (see `MediaSaveService.cleanupEmptyAlbumDir`) —
    // deleting a whole downloaded playlist shouldn't leave a bare empty
    // folder behind.
    final albums = <(String, bool)>{
      for (final item in targeted)
        if (deletedSet.contains(item.asset.id))
          (item.albumName, item.asset.type == AssetType.audio),
    };
    for (final (album, isAudio) in albums) {
      unawaited(_saveService.cleanupEmptyAlbumDir(album, isAudio: isAudio));
    }
    if (!mounted) return;
    setState(() {
      _items.removeWhere((i) => deletedSet.contains(i.asset.id));
      _selectedIds = {};
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        leading: _selectionMode
            ? IconButton(
                tooltip: l10n.cancelSelectionTooltip,
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
              )
            : null,
        title: Text(
          _selectionMode
              ? l10n.itemsSelectedCount(_selectedIds.length)
              : widget.title,
        ),
        actions: [
          if (!_selectionMode)
            IconButton(
              tooltip: l10n.selectTooltip,
              icon: const Icon(Icons.checklist),
              onPressed: _items.isEmpty ? null : _enterSelectionMode,
            )
          else
            IconButton(
              tooltip: _selectedIds.length == _items.length
                  ? l10n.deselectAllTooltip
                  : l10n.selectAllTooltip,
              icon: Icon(
                _selectedIds.length == _items.length
                    ? Icons.deselect
                    : Icons.select_all,
              ),
              onPressed: _toggleSelectAll,
            ),
        ],
      ),
      body: _items.isEmpty
          ? Center(child: Text(l10n.libraryNoDownloads))
          : LibraryGrid(
              items: _items,
              selectedIds: _selectedIds,
              selectionMode: _selectionMode,
              onTap: (index) {
                final asset = _items[index].asset;
                if (_selectionMode) {
                  _toggleSelected(asset.id);
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LibraryPreviewPage(
                        assets: [for (final item in _items) item.asset],
                        initialIndex: index,
                      ),
                    ),
                  );
                }
              },
            ),
      bottomNavigationBar: _selectionMode && _selectedIds.isNotEmpty
          ? LibraryActionBar(
              count: _selectedIds.length,
              busy: _busy,
              onShare: _shareSelected,
              onDelete: _deleteSelected,
            )
          : null,
    );
  }
}
