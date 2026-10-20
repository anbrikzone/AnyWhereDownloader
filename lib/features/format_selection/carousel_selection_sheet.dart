import 'package:flutter/material.dart';

import '../../core/extraction/media_extractor.dart';
import '../../l10n/app_localizations.dart';

/// Bottom sheet for a multi-item post (an Instagram carousel): a thumbnail
/// grid to pick which items to download. Starts with only the item the link
/// points at selected ([MediaInfo.currentItemIndex]), or every item when it
/// names none. Returns the picked items in post order, or null if dismissed.
Future<List<MediaItem>?> showCarouselSelectionSheet({
  required BuildContext context,
  required MediaInfo info,
}) {
  return showModalBottomSheet<List<MediaItem>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _CarouselSheet(info: info),
  );
}

class _CarouselSheet extends StatefulWidget {
  const _CarouselSheet({required this.info});

  final MediaInfo info;

  @override
  State<_CarouselSheet> createState() => _CarouselSheetState();
}

class _CarouselSheetState extends State<_CarouselSheet> {
  late final List<MediaItem> _items = widget.info.items;
  late final Set<int> _selected = widget.info.currentItemIndex == null
      ? {for (var i = 0; i < _items.length; i++) i}
      : {widget.info.currentItemIndex!};

  bool get _allSelected => _selected.length == _items.length;

  void _toggle(int index) => setState(() {
    if (!_selected.remove(index)) _selected.add(index);
  });

  void _toggleAll() => setState(() {
    if (_allSelected) {
      _selected.clear();
    } else {
      _selected.addAll([for (var i = 0; i < _items.length; i++) i]);
    }
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final current = widget.info.currentItemIndex;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.carouselSheetTitle(_items.length),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: _toggleAll,
                    child: Text(
                      _allSelected
                          ? l10n.deselectAllTooltip
                          : l10n.selectAllTooltip,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                ),
                itemCount: _items.length,
                itemBuilder: (context, index) => _Tile(
                  item: _items[index],
                  number: index + 1,
                  selected: _selected.contains(index),
                  isCurrent: index == current,
                  currentLabel: l10n.carouselCurrentItem,
                  onTap: () => _toggle(index),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.of(context).pop([
                        for (var i = 0; i < _items.length; i++)
                          if (_selected.contains(i)) _items[i],
                      ]),
                icon: const Icon(Icons.download),
                label: Text(l10n.carouselDownloadSelected(_selected.length)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.item,
    required this.number,
    required this.selected,
    required this.isCurrent,
    required this.currentLabel,
    required this.onTap,
  });

  final MediaItem item;
  final int number;
  final bool selected;
  final bool isCurrent;
  final String currentLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final thumb = item.thumbnailUrl;
    final isVideo = item.variant.type == MediaVariantType.video;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: thumb == null
                  ? const Icon(Icons.image_outlined)
                  : Image.network(
                      thumb,
                      fit: BoxFit.cover,
                      // Full-size originals — decode at grid size only.
                      cacheWidth: 300,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
            ),
            if (!selected) ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
            if (selected)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.primary, width: 3),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            Positioned(
              top: 4,
              right: 4,
              child: Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? scheme.primary : Colors.white,
              ),
            ),
            Positioned(
              left: 6,
              bottom: 4,
              child: Row(
                children: [
                  if (isVideo)
                    const Icon(Icons.videocam, color: Colors.white, size: 18),
                  Text(
                    isCurrent ? '$number · $currentLabel' : '$number',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(blurRadius: 3)],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
