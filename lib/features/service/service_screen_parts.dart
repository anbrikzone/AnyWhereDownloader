import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/download/download_registry.dart';
import '../../core/navigation/app_route_service.dart';
import '../../core/storage/media_library_service.dart';
import '../../l10n/app_localizations.dart';
import '../downloads/downloads_screen.dart';
import '../library/library_controller.dart';
import '../library/library_grid.dart';

/// Per-source download stats (count + newest date) from the Library's
/// MediaStore read — empty without gallery access.
Map<String, ({int count, DateTime latest})> libraryStatsBySource(
  LibraryState library,
) {
  final stats = <String, ({int count, DateTime latest})>{};
  if (!library.hasAccess) return stats;
  for (final item in library.items.valueOrNull ?? const <LibraryItem>[]) {
    final prev = stats[item.source];
    final at = item.downloadedAt;
    stats[item.source] = (
      count: (prev?.count ?? 0) + 1,
      latest: prev == null || at.isAfter(prev.latest) ? at : prev.latest,
    );
  }
  return stats;
}

/// "60 files · Nov 24" (or "· today" / "· yesterday").
String libraryStatsLabel(
  BuildContext context,
  ({int count, DateTime latest}) s,
) {
  final l10n = AppLocalizations.of(context)!;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(s.latest.year, s.latest.month, s.latest.day);
  final diff = today.difference(day).inDays;
  final when = diff == 0
      ? l10n.groupToday.toLowerCase()
      : diff == 1
      ? l10n.groupYesterday.toLowerCase()
      : DateFormat.MMMd(
          Localizations.localeOf(context).toLanguageTag(),
        ).format(s.latest);
  return '${l10n.libraryFileCount(s.count)} · $when';
}

/// AppBar action opening the Downloads screen, badged with the number of
/// running downloads.
class DownloadsButton extends ConsumerWidget {
  const DownloadsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(
      downloadRegistryProvider.select((s) => s.active.length),
    );
    return IconButton(
      tooltip: AppLocalizations.of(context)!.downloadsTitle,
      icon: Badge(
        isLabelVisible: active > 0,
        label: Text('$active'),
        child: const Icon(Icons.download_outlined),
      ),
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const DownloadsScreen())),
    );
  }
}

/// A service screen's header: big logo, name, how much was downloaded from
/// it, and chips naming what it can download.
class ServiceHeader extends ConsumerWidget {
  const ServiceHeader({
    super.key,
    required this.title,
    required this.librarySource,
    required this.capabilities,
  });

  /// Brand name, not localized.
  final String title;

  /// Library folder name (`X-Twitter`), used for the logo and the stats.
  final String librarySource;
  final List<String> capabilities;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stats = libraryStatsBySource(
      ref.watch(libraryControllerProvider),
    )[librarySource];
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ServiceLogoBadge(source: librarySource, size: 56, radius: 18),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.headlineSmall),
                    if (stats != null)
                      Text(
                        libraryStatsLabel(context, stats),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in capabilities)
                Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  // widthFactor 1: center vertically without stretching
                  // the chip to the Wrap's full width.
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      c,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The download running on this service screen: title (from the
/// [DownloadRegistry] entry of [registrySource]), progress bar, a detail
/// line, and Pause/Resume + Cancel icon buttons.
class ServiceActiveDownloadCard extends ConsumerWidget {
  const ServiceActiveDownloadCard({
    super.key,
    required this.registrySource,
    required this.progress,
    required this.label,
    required this.paused,
    required this.onCancel,
    this.onTogglePause,
  });

  final String registrySource;

  /// Null animates the bar (nothing reported yet / merging).
  final double? progress;
  final String label;
  final bool paused;
  final VoidCallback onCancel;

  /// Null hides Pause (yt-dlp merge/audio/playlist downloads can't pause).
  final VoidCallback? onTogglePause;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = ref.watch(downloadRegistryProvider.select((s) => s.active));
    final entry = active
        .where((e) => e.source == registrySource)
        .fold<DownloadEntry?>(null, (_, e) => e);
    final onCard = scheme.onPrimaryContainer;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (entry != null) ...[
                      Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: onCard,
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        minHeight: 6,
                        value: progress,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: onCard,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTogglePause != null)
                IconButton(
                  tooltip: paused ? l10n.resumeButton : l10n.pauseButton,
                  color: onCard,
                  icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                  onPressed: onTogglePause,
                ),
              IconButton(
                tooltip: l10n.cancelButton,
                color: onCard,
                icon: const Icon(Icons.close),
                onPressed: onCancel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the Library tab filtered to [librarySource].
void openLibraryFor(WidgetRef ref, String librarySource) {
  ref.read(libraryControllerProvider.notifier).setSourceFilter(librarySource);
  AppRouteService.instance.dispatch(AppRoute.library);
}
