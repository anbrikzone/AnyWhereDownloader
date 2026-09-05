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

/// Generic bottom sheet for picking one [MediaVariant] out of several.
/// Not YouTube-specific — reusable once Instagram/X also offer variants.
Future<FormatSelectionResult?> showFormatSelectionSheet({
  required BuildContext context,
  required String title,
  required List<MediaVariant> variants,
}) {
  return showModalBottomSheet<FormatSelectionResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: variants.length,
                  itemBuilder: (context, index) {
                    final variant = variants[index];
                    return ListTile(
                      leading: Icon(_iconFor(variant.type)),
                      title: Text(_title(context, variant)),
                      subtitle: Text(_subtitle(context, variant)),
                      trailing: IconButton(
                        tooltip: AppLocalizations.of(context)!.renameTooltip,
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => Navigator.of(context).pop(
                          FormatSelectionResult(
                            variant: variant,
                            rename: true,
                          ),
                        ),
                      ),
                      onTap: () => Navigator.of(context).pop(
                        FormatSelectionResult(variant: variant, rename: false),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
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
