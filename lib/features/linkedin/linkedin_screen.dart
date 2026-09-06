import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clipboard/clipboard_link_tracker.dart';
import '../../core/l10n/status_message.dart';
import '../../core/settings/settings_providers.dart';
import '../../core/ui/app_toast.dart';
import '../../l10n/app_localizations.dart';
import '../../services/linkedin/linkedin_extractor.dart';
import '../format_selection/format_selection_sheet.dart';
import '../format_selection/rename_dialog.dart';
import 'linkedin_controller.dart';

/// Modeled on `InstagramScreen`/`XTwitterScreen` — LinkedIn downloads
/// always go through the pausable `background_downloader` path, so no
/// adaptive/merge-path UI is needed.
class LinkedInScreen extends ConsumerStatefulWidget {
  const LinkedInScreen({super.key, this.initialUrl});

  final String? initialUrl;

  @override
  ConsumerState<LinkedInScreen> createState() => _LinkedInScreenState();
}

class _LinkedInScreenState extends ConsumerState<LinkedInScreen>
    with WidgetsBindingObserver {
  late final _urlController = TextEditingController(text: widget.initialUrl);
  final _extractor = LinkedInExtractor();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialUrl != null && widget.initialUrl!.trim().isNotEmpty) {
      ClipboardLinkTracker.instance.markHandled(widget.initialUrl!.trim());
      WidgetsBinding.instance.addPostFrameCallback((_) => _onFetchPressed());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkClipboard());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _urlController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkClipboard();
    }
  }

  Future<void> _checkClipboard() async {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    if (!ref.read(clipboardAutoPasteEnabledProvider)) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    if (!ClipboardLinkTracker.instance.shouldOffer(text)) return;
    if (!_extractor.canHandle(text)) return;
    if (ref.read(linkedInControllerProvider).busy) return;

    ClipboardLinkTracker.instance.markHandled(text);
    if (!mounted) return;
    setState(() => _urlController.text = text);
    showAppToast(context, AppLocalizations.of(context)!.clipboardLinkPasted);
  }

  Future<void> _clearUrl() async {
    ClipboardLinkTracker.instance.markHandled(_urlController.text);
    await Clipboard.setData(const ClipboardData(text: ''));
    if (!mounted) return;
    setState(() => _urlController.clear());
  }

  Future<void> _onFetchPressed() async {
    final controller = ref.read(linkedInControllerProvider.notifier);
    final info = await controller.fetchInfo(_urlController.text);
    if (info == null || !mounted) return;

    final suggestedName = LinkedInController.suggestedFileName(info.title);

    // A single image variant is not a choice — download it straight away
    // instead of showing a one-row format sheet.
    if (isSingleImageDownload(info)) {
      await controller.downloadVariant(info.variants.single, suggestedName);
      return;
    }

    // Loop so cancelling the rename dialog returns to the format sheet.
    while (true) {
      if (!mounted) return;
      final result = await showFormatSelectionSheet(
        context: context,
        title: info.title,
        variants: info.variants,
      );
      if (result == null || !mounted) return;

      String chosenName;
      if (result.rename) {
        final edited = await showRenameDialog(
          context: context,
          initialName: suggestedName,
        );
        if (!mounted) return;
        if (edited == null) continue;
        chosenName = edited;
      } else {
        chosenName = suggestedName;
      }

      await controller.downloadVariant(result.variant, chosenName);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(linkedInControllerProvider);
    final controller = ref.read(linkedInControllerProvider.notifier);

    ref.listen(linkedInControllerProvider, (previous, next) {
      final message = next.statusMessage;
      if (message != null && message != previous?.statusMessage) {
        final text = resolveStatusMessage(l10n, message);
        showAppToast(context, text);
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('LinkedIn')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.linkedinUrlHint,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              enabled: !state.busy,
              decoration: InputDecoration(
                labelText: l10n.linkedinUrlLabel,
                border: const OutlineInputBorder(),
                suffixIcon: ValueListenableBuilder(
                  valueListenable: _urlController,
                  builder: (context, value, _) {
                    if (value.text.isEmpty) return const SizedBox.shrink();
                    return IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: l10n.clearTooltip,
                      onPressed: state.busy ? null : _clearUrl,
                    );
                  },
                ),
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => state.busy ? null : _onFetchPressed(),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: state.busy ? null : _onFetchPressed,
              icon: state.fetching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(state.fetching ? l10n.fetchingButton : l10n.goButton),
            ),
            if (state.downloading) ...[
              const SizedBox(height: 24),
              LinearProgressIndicator(value: state.progress),
              const SizedBox(height: 8),
              Text(_progressLabel(l10n, state)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: controller.togglePause,
                      icon: Icon(state.paused ? Icons.play_arrow : Icons.pause),
                      label: Text(state.paused ? l10n.resumeButton : l10n.pauseButton),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: controller.cancelDownload,
                      icon: const Icon(Icons.close),
                      label: Text(l10n.cancelButton),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _progressLabel(AppLocalizations l10n, LinkedInState state) {
  final percent = (state.progress * 100).toStringAsFixed(0);
  return state.paused ? l10n.pausedPercent(percent) : l10n.downloadingPercent(percent);
}
