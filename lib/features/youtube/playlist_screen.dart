import 'package:flutter/material.dart';

import '../../core/yt_dlp_engine/yt_dlp_engine.dart';
import '../../l10n/app_localizations.dart';
import '../../services/youtube/youtube_playlist.dart';

/// What the picker returns: which 1-based positions to download, and the one
/// shared quality to use for all of them.
class PlaylistPick {
  const PlaylistPick({required this.positions, required this.quality});

  final List<int> positions;
  final PlaylistQuality quality;
}

/// Half-height bottom sheet — same shape as the single-video format sheet —
/// listing a playlist's entries with a checkbox each (all ticked by default)
/// plus one shared quality choice. Resolves to a [PlaylistPick] on confirm,
/// null on dismiss.
Future<PlaylistPick?> showPlaylistPickerSheet({
  required BuildContext context,
  required String playlistTitle,
  required List<PlaylistEntryInfo> entries,
}) {
  return showModalBottomSheet<PlaylistPick>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _PlaylistPickerBody(
      playlistTitle: playlistTitle,
      entries: entries,
    ),
  );
}

class _PlaylistPickerBody extends StatefulWidget {
  const _PlaylistPickerBody({
    required this.playlistTitle,
    required this.entries,
  });

  final String playlistTitle;
  final List<PlaylistEntryInfo> entries;

  @override
  State<_PlaylistPickerBody> createState() => _PlaylistPickerBodyState();
}

class _PlaylistPickerBodyState extends State<_PlaylistPickerBody> {
  late final Set<int> _selected = {
    for (final e in widget.entries) e.position,
  };
  PlaylistQuality _quality = PlaylistQuality.upTo720;

  void _toggle(int position, bool? on) {
    setState(() {
      if (on ?? false) {
        _selected.add(position);
      } else {
        _selected.remove(position);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final total = widget.entries.length;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.playlistTitle.isEmpty
                          ? l10n.playlistPickerTitle
                          : widget.playlistTitle,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: _selected.length == total
                        ? null
                        : () => setState(() => _selected
                            .addAll(widget.entries.map((e) => e.position))),
                    child: Text(l10n.playlistSelectAll),
                  ),
                  TextButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => setState(_selected.clear),
                    child: Text(l10n.playlistSelectNone),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(
                l10n.playlistSelectedCount(_selected.length, total),
                style: theme.textTheme.bodySmall,
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: PlaylistQuality.values.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final q = PlaylistQuality.values[i];
                  return Align(
                    alignment: Alignment.center,
                    child: ChoiceChip(
                      label: Text(q.label),
                      selected: _quality == q,
                      onSelected: (_) => setState(() => _quality = q),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 12),
            Flexible(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: widget.entries.length,
                itemBuilder: (context, i) {
                  final e = widget.entries[i];
                  return CheckboxListTile(
                    dense: true,
                    value: _selected.contains(e.position),
                    onChanged: (on) => _toggle(e.position, on),
                    title: Text(
                      '${e.position}. ${e.title.isEmpty ? '—' : e.title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle:
                        e.durationSeconds != null && e.durationSeconds! > 0
                        ? Text(_formatDuration(e.durationSeconds!))
                        : null,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(
                        PlaylistPick(
                          positions: _selected.toList()..sort(),
                          quality: _quality,
                        ),
                      ),
                icon: const Icon(Icons.download),
                label: Text(l10n.playlistDownloadButton(_selected.length)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}
