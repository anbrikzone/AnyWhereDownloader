import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/download/download_registry.dart';
import '../../core/notifications/media_notification_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/app_toast.dart';
import '../../l10n/app_localizations.dart';
import '../library/library_grid.dart';

/// Every download the app is running or recently finished, whichever screen
/// started it (backlog #19). Running ones are tonal cards with progress plus
/// Pause/Resume (direct downloads only) and Cancel; finished ones are grouped
/// by day in rounded cards and open the saved file on tap.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key, this.mediaNotificationService});

  /// Injectable for tests; opens saved files.
  final MediaNotificationService? mediaNotificationService;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final downloads = ref.watch(downloadRegistryProvider);
    final registry = ref.read(downloadRegistryProvider.notifier);
    final opener = mediaNotificationService ?? MediaNotificationService();

    Future<void> open(DownloadEntry entry) async {
      final opened = await opener.openFile(entry.contentUri!);
      if (!opened && context.mounted) {
        showAppToast(context, l10n.downloadsOpenFailed);
      }
    }

    final empty = downloads.active.isEmpty && downloads.history.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.downloadsTitle),
        actions: [
          if (downloads.history.isNotEmpty)
            IconButton(
              tooltip: l10n.downloadsClearHistory,
              icon: const Icon(Icons.delete_outline),
              onPressed: registry.clearHistory,
            ),
        ],
      ),
      body: empty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  l10n.downloadsEmpty,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                if (downloads.active.isNotEmpty) ...[
                  _SectionLabel(
                    l10n.downloadsActiveSection,
                    count: downloads.active.length,
                  ),
                  for (final entry in downloads.active)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ActiveCard(entry: entry, registry: registry),
                    ),
                ],
                for (final group in _dayGroups(context, downloads.history)) ...[
                  _SectionLabel(group.label),
                  _HistoryCard(
                    children: [
                      for (final entry in group.entries)
                        _FinishedRow(
                          entry: entry,
                          onOpen: entry.contentUri == null
                              ? null
                              : () => open(entry),
                        ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}

/// [history] (newest first) split into runs sharing a calendar day:
/// "Today", "Yesterday", then dates.
List<({String label, List<DownloadEntry> entries})> _dayGroups(
  BuildContext context,
  List<DownloadEntry> history,
) {
  final l10n = AppLocalizations.of(context)!;
  final localeTag = Localizations.localeOf(context).toLanguageTag();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  String labelFor(DateTime d) {
    final diff = today.difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff == 0) return l10n.groupToday;
    if (diff == 1) return l10n.groupYesterday;
    return d.year == now.year
        ? DateFormat.MMMMd(localeTag).format(d)
        : DateFormat.yMMMMd(localeTag).format(d);
  }

  final groups = <({String label, List<DownloadEntry> entries})>[];
  for (final entry in history) {
    final label = labelFor(entry.finishedAt ?? entry.startedAt);
    if (groups.isNotEmpty && groups.last.label == label) {
      groups.last.entries.add(entry);
    } else {
      groups.add((label: label, entries: [entry]));
    }
  }
  return groups;
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title, {this.count});

  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
          if (count != null)
            Text(
              '$count',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _ActiveCard extends StatelessWidget {
  const _ActiveCard({required this.entry, required this.registry});

  final DownloadEntry entry;
  final DownloadRegistry registry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onCard = scheme.onPrimaryContainer;
    final paused = entry.status == DownloadStatus.paused;
    final percent = (entry.progress * 100).toStringAsFixed(0);
    final status = paused
        ? l10n.pausedPercent(percent)
        : entry.progress > 0
        ? l10n.downloadingPercent(percent)
        : l10n.downloadStarting;
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Row(
          children: [
            ServiceLogoBadge(source: entry.source, size: 40, radius: 12),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(color: onCard),
                  ),
                  const SizedBox(height: 6),
                  // Animate until there's real progress, like the service
                  // screens do.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: entry.progress > 0 || paused
                          ? entry.progress
                          : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    status,
                    style: theme.textTheme.bodySmall?.copyWith(color: onCard),
                  ),
                ],
              ),
            ),
            if (entry.canPause)
              IconButton(
                tooltip: paused ? l10n.resumeButton : l10n.pauseButton,
                color: onCard,
                icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                onPressed: () => registry.togglePause(entry.id),
              ),
            IconButton(
              tooltip: l10n.cancelButton,
              color: onCard,
              icon: const Icon(Icons.close),
              onPressed: () => registry.cancel(entry.id),
            ),
          ],
        ),
      ),
    );
  }
}

/// A day's finished downloads in one rounded card, rows split by dividers.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.cardSurface,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _FinishedRow extends StatelessWidget {
  const _FinishedRow({required this.entry, required this.onOpen});

  final DownloadEntry entry;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (String status, IconData icon, Color color) = switch (entry.status) {
      DownloadStatus.completed when entry.kind == DownloadKind.playlist => (
        l10n.playlistSavedResult(entry.savedCount ?? 0, entry.failedCount ?? 0),
        Icons.check,
        scheme.primary,
      ),
      DownloadStatus.completed => (l10n.savedMessage, Icons.check, scheme.primary),
      DownloadStatus.canceled => (
        l10n.downloadStatusCanceled,
        Icons.close,
        scheme.onSurfaceVariant,
      ),
      _ => (
        entry.error == null || entry.error!.isEmpty
            ? l10n.downloadStatusFailed
            : '${l10n.downloadStatusFailed}: ${entry.error}',
        Icons.error_outline,
        scheme.error,
      ),
    };
    final time = DateFormat.Hm(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(entry.finishedAt ?? entry.startedAt);
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            ServiceLogoBadge(source: entry.source, size: 40, radius: 12),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(icon, size: 14, color: color),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '$status · $time',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (onOpen != null)
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
