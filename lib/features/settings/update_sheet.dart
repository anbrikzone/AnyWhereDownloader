import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/update/update_providers.dart';
import '../../l10n/app_localizations.dart';

/// Bottom sheet driving the in-app update flow: shows the new version's
/// release notes and a primary button that walks through
/// download → install, reflecting [updateControllerProvider] live.
Future<void> showUpdateSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _UpdateSheet(),
  );
}

class _UpdateSheet extends ConsumerWidget {
  const _UpdateSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(updateControllerProvider);
    final controller = ref.read(updateControllerProvider.notifier);
    final theme = Theme.of(context);

    final info = switch (state) {
      UpdateAvailable(:final info) => info,
      UpdateDownloading(:final info) => info,
      UpdateReadyToInstall(:final info) => info,
      UpdateError(:final info?) => info,
      _ => null,
    };
    if (info == null) return const SizedBox.shrink();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.updateAvailable(info.version),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.updateReleaseNotesTitle,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 8),
            if (info.releaseNotes.isNotEmpty)
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    info.releaseNotes,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            _PrimaryAction(state: state, controller: controller),
            TextButton(
              onPressed: controller.openReleasePage,
              child: Text(l10n.updateOpenReleasePage),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({required this.state, required this.controller});

  final UpdateState state;
  final UpdateController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    switch (state) {
      case UpdateDownloading(:final progress):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.updateDownloadingLabel,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress >= 0 && progress <= 1 ? progress : null,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: controller.cancelDownload,
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
          ],
        );

      case UpdateReadyToInstall():
        return FilledButton.icon(
          onPressed: controller.install,
          icon: const Icon(Icons.install_mobile_outlined),
          label: Text(l10n.updateInstallButton),
        );

      case UpdateError():
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.updateFailed,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: controller.startDownload,
              child: Text(l10n.updateRetryButton),
            ),
          ],
        );

      case UpdateAvailable(:final info):
        final asset = info.assets.isNotEmpty ? info.assets.first : null;
        final size = asset != null && asset.sizeBytes > 0
            ? _formatSize(asset.sizeBytes)
            : '';
        return FilledButton.icon(
          onPressed: controller.startDownload,
          icon: const Icon(Icons.download_outlined),
          label: Text(size.isEmpty
              ? l10n.updateDownloadButtonPlain
              : l10n.updateDownloadButton(size)),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  static String _formatSize(int bytes) {
    const mb = 1024 * 1024;
    return '${(bytes / mb).toStringAsFixed(0)} MB';
  }
}
