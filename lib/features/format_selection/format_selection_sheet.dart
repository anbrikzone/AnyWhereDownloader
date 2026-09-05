import 'package:flutter/material.dart';

import '../../core/extraction/media_extractor.dart';
import '../../l10n/app_localizations.dart';

/// Result of the format sheet: which [variant] was picked, and whether the
/// user asked to rename before downloading (tapped the row itself starts
/// the download with the default name; tapping the edit icon renames first).
class FormatSelectionResult {
  FormatSelectionResult({required this.variant, required this.rename});

  final MediaVariant variant;
  final bool rename;
}

/// True when [info] offers no real choice to make — exactly one variant and
/// it's an image. Callers skip [showFormatSelectionSheet] and download that
/// variant directly (a single-image post has nothing to pick).
bool isSingleImageDownload(MediaInfo info) =>
    info.variants.length == 1 &&
    info.variants.single.type == MediaVariantType.image;

/// Fixed order the sheet groups variants in.
const _typeOrder = [
  MediaVariantType.video,
  MediaVariantType.audio,
  MediaVariantType.image,
];

/// Generic bottom sheet for picking one [MediaVariant] out of several.
/// Not YouTube-specific. Capped at ~55% of the screen and scrollable —
/// YouTube now offers a long list (many resolutions + audio options) —
/// with a labelled section per media type when more than one is present.
Future<FormatSelectionResult?> showFormatSelectionSheet({
  required BuildContext context,
  required String title,
  required List<MediaVariant> variants,
}) {
  return showModalBottomSheet<FormatSelectionResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final l10n = AppLocalizations.of(context)!;
      final theme = Theme.of(context);

      final groups = <MediaVariantType, List<MediaVariant>>{};
      for (final v in variants) {
        (groups[v.type] ??= <MediaVariant>[]).add(v);
      }
      final presentTypes =
          _typeOrder.where(groups.containsKey).toList(growable: false);
      final showHeaders = presentTypes.length > 1;

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.55,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    for (final type in presentTypes) ...[
                      if (showHeaders)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                          child: Text(
                            _sectionLabel(l10n, type),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      for (final variant in groups[type]!)
                        _VariantRow(variant: variant),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _VariantRow extends StatelessWidget {
  const _VariantRow({required this.variant});

  final MediaVariant variant;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(_iconFor(variant.type)),
      title: Text(_title(context, variant)),
      subtitle: Text(_subtitle(context, variant)),
      trailing: IconButton(
        tooltip: AppLocalizations.of(context)!.renameTooltip,
        icon: const Icon(Icons.edit_outlined),
        onPressed: () => Navigator.of(context).pop(
          FormatSelectionResult(variant: variant, rename: true),
        ),
      ),
      onTap: () => Navigator.of(context).pop(
        FormatSelectionResult(variant: variant, rename: false),
      ),
    );
  }
}

String _sectionLabel(AppLocalizations l10n, MediaVariantType type) {
  switch (type) {
    case MediaVariantType.video:
      return l10n.formatSectionVideo;
    case MediaVariantType.audio:
      return l10n.formatSectionAudio;
    case MediaVariantType.image:
      return l10n.imageLabel;
  }
}

String _title(BuildContext context, MediaVariant variant) {
  final l10n = AppLocalizations.of(context)!;
  switch (variant.type) {
    case MediaVariantType.image:
      return l10n.imageLabel;
    case MediaVariantType.audio:
      final kbps = variant.audioSpec?.qualityKbps;
      return kbps != null ? '$kbps kbps' : l10n.audioOriginalLabel;
    case MediaVariantType.video:
      return variant.resolutionLabel ?? variant.container;
  }
}

IconData _iconFor(MediaVariantType type) {
  switch (type) {
    case MediaVariantType.video:
      return Icons.videocam_outlined;
    case MediaVariantType.audio:
      return Icons.audiotrack_outlined;
    case MediaVariantType.image:
      return Icons.image_outlined;
  }
}

String _subtitle(BuildContext context, MediaVariant variant) {
  final parts = <String>[variant.container.toUpperCase()];
  final size = variant.approxSizeBytes;
  // Always shown with a "~" — even yt-dlp's own reported size can be off
  // by a bit, and sizes without a filesize field are estimated from
  // bitrate × duration, which is rougher still.
  parts.add(
    size != null && size > 0
        ? '~${_formatSize(size)}'
        : AppLocalizations.of(context)!.sizeUnknown,
  );
  return parts.join(' · ');
}

String _formatSize(int bytes) {
  const mb = 1024 * 1024;
  if (bytes >= mb) {
    return '${(bytes / mb).toStringAsFixed(1)} MB';
  }
  const kb = 1024;
  return '${(bytes / kb).toStringAsFixed(0)} KB';
}
