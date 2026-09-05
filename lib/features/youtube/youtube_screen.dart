import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clipboard/clipboard_link_tracker.dart';
import '../../core/l10n/status_message.dart';
import '../../core/settings/settings_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../services/youtube/youtube_extractor.dart';
import '../format_selection/format_selection_sheet.dart';
import '../format_selection/rename_dialog.dart';
import 'youtube_controller.dart';

class YouTubeScreen extends ConsumerStatefulWidget {
  const YouTubeScreen({super.key, this.initialUrl});

  final String? initialUrl;

  @override
  ConsumerState<YouTubeScreen> createState() => _YouTubeScreenState();
}

class _YouTubeScreenState extends ConsumerState<YouTubeScreen>
    with WidgetsBindingObserver {
  late final _urlController = TextEditingController(text: widget.initialUrl);
  final _extractor = YouTubeExtractor();

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
    // Home stays mounted underneath (MainShell's IndexedStack) even while
    // this screen is pushed on top, and both register the same
    // WidgetsBindingObserver.didChangeAppLifecycleState — without this
    // guard, whichever one runs first on resume steals the clipboard text
    // via the shared ClipboardLinkTracker, leaving the other (even if it's
    // the one actually visible) with nothing to show.
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    if (!ref.read(clipboardAutoPasteEnabledProvider)) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    if (!ClipboardLinkTracker.instance.shouldOffer(text)) return;
    if (!_extractor.canHandle(text)) return;
    final busy = ref.read(youTubeControllerProvider).busy;
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
  /// re-offering this same link, wipes it too — otherwise
  /// `ClipboardLinkTracker`'s "already offered" memory doesn't survive the
  /// app process being killed and relaunched, and the same link gets
  /// auto-pasted again on a later cold start even though the user already
  /// dismissed it.
  Future<void> _clearUrl() async {
    ClipboardLinkTracker.instance.markHandled(_urlController.text);
    await Clipboard.setData(const ClipboardData(text: ''));
    if (!mounted) return;
    setState(() => _urlController.clear());
  }

  Future<void> _onFetchPressed() async {
    final controller = ref.read(youTubeControllerProvider.notifier);
    final info = await controller.fetchInfo(_urlController.text);
    if (info == null || !mounted) return;

    final suggestedName = YouTubeController.suggestedFileName(info.title);

    // Loop rather than a single pass: cancelling the rename dialog should
    // return to the format sheet (so the user can pick a different format
    // or download with the default name), not abandon the whole flow and
    // force a re-fetch via "Go".
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
    final state = ref.watch(youTubeControllerProvider);
    final controller = ref.read(youTubeControllerProvider.notifier);

    ref.listen(youTubeControllerProvider, (previous, next) {
      final message = next.statusMessage;
      if (message != null && message != previous?.statusMessage) {
        final text = resolveStatusMessage(l10n, message);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(text)));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('YouTube')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.youtubeUrlHint,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              enabled: !state.busy,
              decoration: InputDecoration(
                labelText: l10n.youtubeUrlLabel,
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
              LinearProgressIndicator(
                value:
                    (state.downloadPhase == 'merging' ||
                            state.downloadPhase == 'converting') &&
                        !state.mergeDurationKnown
                    ? null
                    : state.progress,
              ),
              const SizedBox(height: 8),
              Text(_progressLabel(l10n, state)),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (state.canPause) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: controller.togglePause,
                        icon: Icon(
                          state.paused ? Icons.play_arrow : Icons.pause,
                        ),
                        label: Text(state.paused ? l10n.resumeButton : l10n.pauseButton),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
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

String _progressLabel(AppLocalizations l10n, YouTubeState state) {
  final percent = (state.progress * 100).toStringAsFixed(0);
  if (state.paused) return l10n.pausedPercent(percent);
  switch (state.downloadPhase) {
    case 'video':
      return l10n.downloadingVideoPercent(percent);
    case 'audio':
      return l10n.downloadingAudioPercent(percent);
    case 'merging':
      return state.mergeDurationKnown
          ? l10n.mergingPercent(percent)
          : l10n.mergingIndeterminate;
    case 'converting':
      return state.mergeDurationKnown
          ? l10n.convertingAudioPercent(percent)
          : l10n.convertingAudioIndeterminate;
    default:
      return l10n.downloadingPercent(percent);
  }
}
