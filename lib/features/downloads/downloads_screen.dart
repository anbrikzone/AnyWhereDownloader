import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/download/download_registry.dart';
import '../../core/notifications/media_notification_service.dart';
import '../../core/ui/app_toast.dart';
import '../../l10n/app_localizations.dart';

/// Every download the app is running or recently finished, whichever screen
/// started it (backlog #19) — reached from the Home AppBar. Active rows have
/// progress plus Pause/Resume (direct downloads only) and Cancel; finished
/// rows open the saved file on tap.
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

    final empty = downloads.active.isEmpty && downloads.history.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.downloadsTitle),
        actions: [
          if (downloads.history.isNotEmpty)
            IconButton(
              tooltip: l10n.downloadsClearHistory,
              icon: const Icon(Icons.delete_sweep_outlined),
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
              children: [
                if (downloads.active.isNotEmpty) ...[
                  _SectionHeader(l10n.downloadsActiveSection),
                  for (final entry in downloads.active)
                    _ActiveTile(entry: entry, registry: registry),
                ],
                if (downloads.history.isNotEmpty) ...[
                  _SectionHeader(l10n.downloadsHistorySection),
                  for (final entry in downloads.history)
                    _FinishedTile(
                      entry: entry,
                      onOpen: entry.contentUri == null
                          ? null
                          : () async {
                              final opened = await opener.openFile(
                                entry.contentUri!,
                              );
                              if (!opened && context.mounted) {
                                showAppToast(context, l10n.downloadsOpenFailed);
                              }
                            },
                    ),
                ],
              ],
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

IconData _kindIcon(DownloadKind kind) => switch (kind) {
      DownloadKind.video => Icons.videocam_outlined,
      DownloadKind.audio => Icons.audiotrack_outlined,
      DownloadKind.image => Icons.image_outlined,
      DownloadKind.playlist => Icons.playlist_play,
    };

class _ActiveTile extends StatelessWidget {
  const _ActiveTile({required this.entry, required this.registry});

  final DownloadEntry entry;
  final DownloadRegistry registry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final paused = entry.status == DownloadStatus.paused;
    final percent = (entry.progress * 100).toStringAsFixed(0);
    final status = paused
        ? l10n.pausedPercent(percent)
        : entry.progress > 0
            ? l10n.downloadingPercent(percent)
            : l10n.downloadStarting;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Icon(_kindIcon(entry.kind)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                // Animate until there's real progress, like the service
                // screens do.
                LinearProgressIndicator(
                  value: entry.progress > 0 || paused ? entry.progress : null,
                ),
                const SizedBox(height: 4),
                Text(
                  '${entry.source} · $status',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (entry.canPause)
            IconButton(
              tooltip: paused ? l10n.resumeButton : l10n.pauseButton,
              icon: Icon(paused ? Icons.play_arrow : Icons.pause),
              onPressed: () => registry.togglePause(entry.id),
            ),
          IconButton(
            tooltip: l10n.cancelButton,
            icon: const Icon(Icons.close),
            onPressed: () => registry.cancel(entry.id),
          ),
        ],
      ),
    );
  }
}

class _FinishedTile extends StatelessWidget {
  const _FinishedTile({required this.entry, required this.onOpen});

  final DownloadEntry entry;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final (String status, Color? color) = switch (entry.status) {
      DownloadStatus.completed when entry.kind == DownloadKind.playlist => (
          l10n.playlistSavedResult(entry.savedCount ?? 0, entry.failedCount ?? 0),
          null,
        ),
      DownloadStatus.completed => (l10n.savedMessage, null),
      DownloadStatus.canceled => (l10n.downloadStatusCanceled, null),
      _ => (
          entry.error == null || entry.error!.isEmpty
              ? l10n.downloadStatusFailed
              : '${l10n.downloadStatusFailed}: ${entry.error}',
          theme.colorScheme.error,
        ),
    };
    return ListTile(
      leading: Icon(_kindIcon(entry.kind)),
      title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${entry.source} · $status',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: color == null ? null : TextStyle(color: color),
      ),
      trailing: onOpen == null ? null : const Icon(Icons.open_in_new),
      onTap: onOpen,
    );
  }
}
