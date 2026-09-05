import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clipboard/clipboard_link_tracker.dart';
import '../../core/l10n/status_message.dart';
import '../../core/settings/settings_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../services/x_twitter/x_twitter_extractor.dart';
import '../format_selection/format_selection_sheet.dart';
import '../format_selection/rename_dialog.dart';
import 'x_twitter_controller.dart';

/// Modeled closely on `TikTokScreen`/`YouTubeScreen`, minus the
/// adaptive/merge-path UI (pause/cancel row, download-phase label) —
/// X/Twitter's formats are always muxed (see `XTwitterExtractor`), so
/// pause/resume always applies and there's no "video/audio/merging" phase
/// to show.
class XTwitterScreen extends ConsumerStatefulWidget {
  const XTwitterScreen({super.key, this.initialUrl});

  final String? initialUrl;

  @override
  ConsumerState<XTwitterScreen> createState() => _XTwitterScreenState();
}

class _XTwitterScreenState extends ConsumerState<XTwitterScreen>
    with WidgetsBindingObserver {
  late final _urlController = TextEditingController(text: widget.initialUrl);
  final _extractor = XTwitterExtractor();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialUrl != null && widget.initialUrl!.trim().isNotEmpty) {
      // Already have an actionable URL from Home — don't also check the
      // clipboard and potentially overwrite it before the auto-fetch runs.
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
    // Same guard as `YouTubeScreen`/`HomeScreen` — Home stays mounted
    // underneath (MainShell's IndexedStack) even while this screen is
    // pushed on top, and both register the same lifecycle observer.
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    if (!ref.read(clipboardAutoPasteEnabledProvider)) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    if (!ClipboardLinkTracker.instance.shouldOffer(text)) return;
    if (!_extractor.canHandle(text)) return;
    final busy = ref.read(xTwitterControllerProvider).busy;
    if (busy) return;

    ClipboardLinkTracker.instance.markHandled(text);
    if (!mounted) return;
    setState(() => _urlController.text = text);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.clipboardLinkPasted)),
      );
  }

  /// Clears the URL field and, since the system clipboard is what keeps
  /// re-offering this same link, wipes it too — same behavior (and the
  /// same OS-level "Copied to clipboard" pill tradeoff) as `YouTubeScreen`.
  Future<void> _clearUrl() async {
    ClipboardLinkTracker.instance.markHandled(_urlController.text);
    await Clipboard.setData(const ClipboardData(text: ''));
    if (!mounted) return;
    setState(() => _urlController.clear());
  }

  Future<void> _onFetchPressed() async {
    final controller = ref.read(xTwitterControllerProvider.notifier);
    final info = await controller.fetchInfo(_urlController.text);
    if (info == null || !mounted) return;

    final suggestedName = XTwitterController.suggestedFileName(info.title);

    // Loop rather than a single pass: cancelling the rename dialog should
    // return to the format sheet, not abandon the whole flow.
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
    final state = ref.watch(xTwitterControllerProvider);
    final controller = ref.read(xTwitterControllerProvider.notifier);

    ref.listen(xTwitterControllerProvider, (previous, next) {
      final message = next.statusMessage;
      if (message != null && message != previous?.statusMessage) {
        final text = resolveStatusMessage(l10n, message);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(text)));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('X / Twitter')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.xTwitterUrlHint,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              enabled: !state.busy,
              decoration: InputDecoration(
                labelText: l10n.xTwitterUrlLabel,
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

String _progressLabel(AppLocalizations l10n, XTwitterState state) {
  final percent = (state.progress * 100).toStringAsFixed(0);
  return state.paused ? l10n.pausedPercent(percent) : l10n.downloadingPercent(percent);
}
