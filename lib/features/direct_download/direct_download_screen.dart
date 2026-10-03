import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clipboard/clipboard_link_tracker.dart';
import '../../core/logging/app_log.dart';
import '../../core/extraction/media_extractor.dart';
import '../../core/settings/settings_providers.dart';
import '../../core/ui/app_toast.dart';
import '../../l10n/app_localizations.dart';
import '../format_selection/format_selection_sheet.dart';
import '../format_selection/rename_dialog.dart';
import '../settings/status_message_presenter.dart';
import 'direct_download_controller.dart';
import 'direct_download_service.dart';

/// The screen for every [DirectDownloadService] (TikTok, X/Twitter,
/// Instagram, LinkedIn). Modeled closely on `YouTubeScreen`, minus the
/// adaptive/merge-path UI (download-phase label) — these formats are always
/// muxed or a single photo, so pause/resume always applies.
class DirectDownloadScreen extends ConsumerStatefulWidget {
  const DirectDownloadScreen({
    super.key,
    required this.service,
    this.initialUrl,
  });

  /// Must be one [DirectDownloadService.of] knows.
  final ServiceType service;
  final String? initialUrl;

  @override
  ConsumerState<DirectDownloadScreen> createState() =>
      _DirectDownloadScreenState();
}

class _DirectDownloadScreenState extends ConsumerState<DirectDownloadScreen>
    with WidgetsBindingObserver {
  late final _urlController = TextEditingController(text: widget.initialUrl);
  late final _provider = directDownloadControllerProvider(widget.service);
  late final _service = DirectDownloadService.of(widget.service)!;

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

  static const _clipTag = 'Clipboard/Service';

  Future<void> _checkClipboard() async {
    // Same guard as `YouTubeScreen`/`HomeScreen` — Home stays mounted
    // underneath (MainShell's IndexedStack) even while this screen is
    // pushed on top, and both register the same lifecycle observer.
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    if (!ref.read(clipboardAutoPasteEnabledProvider)) return;
    // Nothing to auto-fill once the field has content — and not reading the
    // clipboard here is what stops Android's system "pasted from your
    // clipboard" toast firing on every return to the app.
    if (_urlController.text.trim().isNotEmpty) {
      return logInfo(_clipTag, 'skip: URL field not empty');
    }
    // hasStrings() inspects the clip's type, not its content, so it does
    // not trigger that toast; only getData() (the real read) does.
    if (!await Clipboard.hasStrings()) {
      return logInfo(_clipTag, 'skip: clipboard has no text (or no focus yet)');
    }
    if (!mounted) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      return logInfo(_clipTag, 'skip: clipboard read returned empty');
    }
    if (!ClipboardLinkTracker.instance.shouldOffer(text)) {
      return logInfo(_clipTag, 'skip: this link was already offered');
    }
    if (!ref.read(_provider.notifier).canHandle(text)) return;
    if (ref.read(_provider).busy) return;

    ClipboardLinkTracker.instance.markHandled(text);
    if (!mounted) return;
    setState(() => _urlController.text = text);
    showAppToast(context, AppLocalizations.of(context)!.clipboardLinkPasted);
  }

  /// Clears the URL field and wipes the system clipboard too — same
  /// behavior (and the same OS-toast tradeoff) as `YouTubeScreen`. The
  /// tracker is forgotten, not marked handled, so re-copying the same URL
  /// on purpose still auto-pastes it.
  Future<void> _clearUrl() async {
    ClipboardLinkTracker.instance.forget();
    await Clipboard.setData(const ClipboardData(text: ''));
    if (!mounted) return;
    setState(() => _urlController.clear());
  }

  /// Empties the URL field once its link has been used (a download was
  /// started), so the next copied link auto-pastes on return — the clipboard
  /// check skips a non-empty field. The link is marked handled so the same
  /// clip isn't pasted straight back. The system clipboard is left alone.
  void _consumeUrl() {
    final url = _urlController.text.trim();
    if (url.isNotEmpty) ClipboardLinkTracker.instance.markHandled(url);
    if (mounted) setState(() => _urlController.clear());
  }

  Future<void> _onFetchPressed() async {
    final controller = ref.read(_provider.notifier);
    final info = await controller.fetchInfo(_urlController.text);
    if (info == null || !mounted) return;

    final suggestedName = controller.suggestedFileName(info.title);

    // A single image variant (a photo post) is not a choice — download it
    // straight away instead of showing a one-row format sheet.
    if (isSingleImageDownload(info)) {
      _consumeUrl();
      await controller.downloadVariant(info.variants.single, suggestedName);
      return;
    }

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

      _consumeUrl();
      await controller.downloadVariant(result.variant, chosenName);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(_provider);
    final controller = ref.read(_provider.notifier);

    ref.listen(_provider, (previous, next) {
      final message = next.statusMessage;
      if (message != null && message != previous?.statusMessage) {
        showStatusMessage(context, message);
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(_service.title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _service.urlHint(l10n),
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              enabled: !state.busy,
              decoration: InputDecoration(
                labelText: _service.urlLabel(l10n),
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
                  // A yt-dlp merge download (HLS-only Pinterest video) can
                  // only be canceled, like YouTube's high-res path.
                  if (state.canPause) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: controller.togglePause,
                        icon: Icon(state.paused ? Icons.play_arrow : Icons.pause),
                        label: Text(
                          state.paused ? l10n.resumeButton : l10n.pauseButton,
                        ),
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

String _progressLabel(AppLocalizations l10n, DirectDownloadState state) {
  final percent = (state.progress * 100).toStringAsFixed(0);
  return state.paused ? l10n.pausedPercent(percent) : l10n.downloadingPercent(percent);
}
