import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../core/settings/app_settings_service.dart';
import '../../core/settings/settings_providers.dart';
import '../../core/storage/media_library_service.dart';
import '../../l10n/app_localizations.dart';
import 'library_preview.dart';

/// Short badge text + brand color per Library source (the folder name under
/// `AnyWhereDownloader/`). Brand names stay untranslated.
const librarySourceBadges = <String, (String, Color)>{
  'YouTube': ('YT', Color(0xFFC4302B)),
  'Instagram': ('IG', Color(0xFFB42F72)),
  'WhatsApp': ('WA', Color(0xFF1B8A4B)),
  'TikTok': ('TT', Color(0xFF161D1C)),
  'X-Twitter': ('X', Color(0xFF161D1C)),
  'LinkedIn': ('in', Color(0xFF0A66C2)),
  'Pinterest': ('P', Color(0xFFB7081B)),
};

/// [librarySourceBadges] lookup that also accepts a service's display
/// title (`X / Twitter`), as the download registry records it.
(String, Color)? librarySourceBadgeFor(String source) =>
    librarySourceBadges[source] ??
    librarySourceBadges[source.replaceAll(' / ', '-')];

/// Brand logo per Library source (Font Awesome brand glyphs).
const librarySourceLogos = <String, FaIconData>{
  'YouTube': FontAwesomeIcons.youtube,
  'Instagram': FontAwesomeIcons.instagram,
  'WhatsApp': FontAwesomeIcons.whatsapp,
  'TikTok': FontAwesomeIcons.tiktok,
  'X-Twitter': FontAwesomeIcons.xTwitter,
  'LinkedIn': FontAwesomeIcons.linkedinIn,
  'Pinterest': FontAwesomeIcons.pinterestP,
};

/// A service's white logo on its brand color, in a rounded square (the
/// short text label stands in for a source without a logo). Near-black
/// brands (TikTok, X) get a faint outline on dark surfaces.
class ServiceLogoBadge extends StatelessWidget {
  const ServiceLogoBadge({
    super.key,
    required this.source,
    this.size = 56,
    this.radius,
    this.outlineOnDark = true,
  });

  /// A Library source (`X-Twitter`) or a service title (`X / Twitter`).
  final String source;
  final double size;
  final double? radius;
  final bool outlineOnDark;

  @override
  Widget build(BuildContext context) {
    final key = librarySourceBadges.containsKey(source)
        ? source
        : source.replaceAll(' / ', '-');
    final badge = librarySourceBadges[key];
    final logo = librarySourceLogos[key];
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: badge?.$2 ?? scheme.primary,
        borderRadius: BorderRadius.circular(radius ?? size * 0.32),
        border: outlineOnDark && Theme.of(context).brightness == Brightness.dark
            ? Border.all(color: Colors.white24)
            : null,
      ),
      child: logo != null
          ? FaIcon(logo, size: size * 0.5, color: Colors.white)
          : Text(
              badge?.$1 ?? (source.isEmpty ? '' : source.substring(0, 1)),
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.3,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

/// Display name for a Library source (`X-Twitter` is a folder-safe name).
String librarySourceLabel(String source) =>
    source == 'X-Twitter' ? 'X / Twitter' : source;

/// Grid of downloaded assets, optionally grouped into day sections, with
/// arbitrary [headerSlivers] scrolling above it (Library's filters and
/// playlists). Owns the [ScrollController] so it can (a) drive a thicker,
/// always-visible [Scrollbar] and (b) force-close whatever long-press
/// "peek" video is playing the instant a real drag starts — without (b) a
/// peek's `VideoPlayerController` can keep playing while its tile is
/// recycled, a known way to exhaust Android's video decoder resources.
class LibraryGrid extends ConsumerStatefulWidget {
  const LibraryGrid({
    super.key,
    required this.items,
    required this.selectedIds,
    required this.selectionMode,
    required this.onTap,
    this.onLongPressSelect,
    this.headerSlivers = const [],
    this.groupByDay = false,
    this.onSelectGroup,
    this.showSource = false,
    this.emptyChild,
    this.bottomPadding = 8,
  });

  final List<LibraryItem> items;
  final Set<String> selectedIds;
  final bool selectionMode;

  /// Index into [items].
  final ValueChanged<int> onTap;

  /// Called on long-press instead of opening the peek when Settings →
  /// "Long press on media" is [LongPressAction.select]. Null = always peek.
  final ValueChanged<int>? onLongPressSelect;

  final List<Widget> headerSlivers;

  /// Split [items] (already in date order) into "Today" / "Yesterday" /
  /// date sections.
  final bool groupByDay;

  /// "Select day" in a section header while selecting; gets that day's ids.
  final ValueChanged<List<String>>? onSelectGroup;

  /// Brand badge on each tile — off where every item has the same source.
  final bool showSource;

  /// Shown under [headerSlivers] when [items] is empty.
  final Widget? emptyChild;

  /// Space below the last row (e.g. clearance for a floating action bar).
  final double bottomPadding;

  @override
  ConsumerState<LibraryGrid> createState() => LibraryGridState();
}

class LibraryGridState extends ConsumerState<LibraryGrid> {
  final ScrollController _scrollController = ScrollController();

  /// The thick scrollbar stays hidden at the very top, where it would sit
  /// on top of the filter row; it appears once the list has moved.
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final scrolled = _scrollController.offset > 0;
      if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    });
  }

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

  /// Contiguous runs of [LibraryGrid.items] sharing a calendar day.
  List<({String label, int start, int end})> _dayGroups(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    String labelFor(DateTime d) {
      final day = DateTime(d.year, d.month, d.day);
      final diff = today.difference(day).inDays;
      if (diff == 0) return l10n.groupToday;
      if (diff == 1) return l10n.groupYesterday;
      return d.year == now.year
          ? DateFormat.MMMMd(localeTag).format(d)
          : DateFormat.yMMMMd(localeTag).format(d);
    }

    final groups = <({String label, int start, int end})>[];
    final items = widget.items;
    var start = 0;
    for (var i = 1; i <= items.length; i++) {
      final split =
          i == items.length ||
          !DateUtils.isSameDay(
            items[i].downloadedAt,
            items[start].downloadedAt,
          );
      if (split) {
        groups.add((
          label: labelFor(items[start].downloadedAt),
          start: start,
          end: i,
        ));
        start = i;
      }
    }
    return groups;
  }

  Widget _tile(int index, bool longPressSelects) {
    final item = widget.items[index];
    final onSelect = widget.onLongPressSelect;
    return _LibraryTile(
      key: ValueKey(item.asset.id),
      item: item,
      showSource: widget.showSource,
      selected: widget.selectedIds.contains(item.asset.id),
      selectionActive: widget.selectionMode,
      onTap: () => widget.onTap(index),
      onLongPressSelect: longPressSelects && onSelect != null
          ? () => onSelect(index)
          : null,
      onPeekOpened: _registerPeek,
      onPeekClosed: _unregisterPeek,
    );
  }

  SliverGrid _grid(int start, int end, bool longPressSelects) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, i) => _tile(start + i, longPressSelects),
        childCount: end - start,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final longPressSelects =
        widget.onLongPressSelect != null &&
        ref.watch(longPressActionProvider) == LongPressAction.select;

    final slivers = <Widget>[...widget.headerSlivers];
    if (widget.items.isEmpty) {
      if (widget.emptyChild != null) {
        slivers.add(
          SliverFillRemaining(hasScrollBody: false, child: widget.emptyChild),
        );
      }
    } else if (widget.groupByDay) {
      for (final group in _dayGroups(context)) {
        final ids = [
          for (var i = group.start; i < group.end; i++)
            widget.items[i].asset.id,
        ];
        final onSelectGroup = widget.onSelectGroup;
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: SizedBox(
                height: 36,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        group.label,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (widget.selectionMode && onSelectGroup != null)
                      TextButton(
                        onPressed: () => onSelectGroup(ids),
                        child: Text(l10n.selectDayButton),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          '${ids.length}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        slivers.add(
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: _grid(group.start, group.end, longPressSelects),
          ),
        );
      }
    } else {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          sliver: _grid(0, widget.items.length, longPressSelects),
        ),
      );
    }
    slivers.add(
      SliverToBoxAdapter(child: SizedBox(height: widget.bottomPadding)),
    );

    return NotificationListener<ScrollStartNotification>(
      onNotification: (_) {
        _closeActivePeek?.call();
        return false;
      },
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: _scrolled,
        thickness: 10,
        radius: const Radius.circular(6),
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: slivers,
        ),
      ),
    );
  }
}

/// `m:ss`, or `h:mm:ss` from an hour up.
String formatMediaDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

class _LibraryTile extends StatefulWidget {
  const _LibraryTile({
    required super.key,
    required this.item,
    required this.showSource,
    required this.selected,
    required this.selectionActive,
    required this.onTap,
    this.onLongPressSelect,
    required this.onPeekOpened,
    required this.onPeekClosed,
  });

  final LibraryItem item;
  final bool showSource;
  final bool selected;
  final bool selectionActive;
  final VoidCallback onTap;
  final VoidCallback? onLongPressSelect;
  final ValueChanged<VoidCallback> onPeekOpened;
  final ValueChanged<VoidCallback> onPeekClosed;

  @override
  State<_LibraryTile> createState() => _LibraryTileState();
}

class _LibraryTileState extends State<_LibraryTile> {
  // Keyed by "assetId_size" and shared across tile instances so
  // recycling tiles while scrolling doesn't re-fetch the same thumbnail
  // over the platform channel every time.
  static final Map<String, Future<Uint8List?>> _thumbnailCache = {};

  late Future<Uint8List?> _thumbnail;
  OverlayEntry? _peekEntry;
  VoidCallback? _closePeekCallback;

  AssetEntity get _asset => widget.item.asset;

  @override
  void initState() {
    super.initState();
    // Audio has no meaningful thumbnail — MediaStore returned garbled bytes
    // for it. Skip the fetch and let the fallback icon stand in.
    _thumbnail = _asset.type == AssetType.audio
        ? Future<Uint8List?>.value(null)
        : _thumbnailCache.putIfAbsent(
            '${_asset.id}_240',
            () => _asset.thumbnailDataWithSize(const ThumbnailSize(240, 240)),
          );
  }

  void _openPeek() {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (_) => LibraryPeekPreview(asset: _asset),
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
    final scheme = Theme.of(context).colorScheme;
    final badge = librarySourceBadges[widget.item.source];
    final selectsOnLongPress = widget.onLongPressSelect != null;

    return GestureDetector(
      // opaque so a tap anywhere on the tile registers, not just where a
      // hit-testable child happens to be painted.
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onLongPressSelect,
      onLongPressStart: selectsOnLongPress ? null : (_) => _openPeek(),
      onLongPressEnd: selectsOnLongPress ? null : (_) => _closePeek(),
      onLongPressCancel: selectsOnLongPress ? null : _closePeek,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: FutureBuilder<Uint8List?>(
                future: _thumbnail,
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (bytes != null) {
                    return Image.memory(bytes, fit: BoxFit.cover);
                  }
                  return _TileFallbackIcon(type: _asset.type);
                },
              ),
            ),
            if (widget.showSource && badge != null)
              Positioned(
                left: 6,
                top: 6,
                child: ServiceLogoBadge(
                  source: widget.item.source,
                  size: 22,
                  radius: 7,
                  outlineOnDark: false,
                ),
              ),
            if (_asset.type == AssetType.video)
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    formatMediaDuration(_asset.duration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            if (widget.selected)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.primary, width: 3),
                  borderRadius: BorderRadius.circular(12),
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
                    color: widget.selected ? scheme.primary : Colors.black26,
                    border: widget.selected
                        ? null
                        : Border.all(color: Colors.white, width: 2),
                  ),
                  child: widget.selected
                      ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
                      : null,
                ),
              ),
          ],
        ),
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
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
