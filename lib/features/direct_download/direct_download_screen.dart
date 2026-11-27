import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clipboard/clipboard_link_tracker.dart';
import '../../core/extraction/media_extractor.dart';
import '../../core/settings/settings_providers.dart';
import '../../core/ui/link_input_card.dart';
import '../../core/ui/app_toast.dart';
import '../../l10n/app_localizations.dart';
import '../library/service_downloads_section.dart';
import '../service/service_screen_parts.dart';
import '../format_selection/carousel_selection_sheet.dart';
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

  Future<void> _checkClipboard() async {
    // Same guard as `YouTubeScreen`/`HomeScreen` — Home stays mounted
    // underneath (MainShell's IndexedStack) even while this screen is
    // pushed on top, and both register the same lifecycle observer.
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    if (!ref.read(clipboardAutoPasteEnabledProvider)) return;
    // Nothing to auto-fill once the field has content — and not reading the
    // clipboard here is what stops Android's system "pasted from your
    // clipboard" toast firing on every return to the app.
    if (_urlController.text.trim().isNotEmpty) return;
    // hasStrings() inspects the clip's type, not its content, so it does
    // not trigger that toast; only getData() (the real read) does.
    if (!await Clipboard.hasStrings()) return;
    if (!mounted) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    if (!ClipboardLinkTracker.instance.shouldOffer(text)) return;
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

    // A multi-item post (an Instagram carousel): pick which items, then
    // download them one after another — no per-item format choice.
    if (info.isMultiItem) {
      final picked = await showCarouselSelectionSheet(
        context: context,
        info: info,
      );
      if (picked == null || !mounted) return;
      _consumeUrl();
      await controller.downloadItems(picked, suggestedName);
      return;
    }

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
      appBar: AppBar(actions: const [DownloadsButton()]),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ServiceHeader(
              title: _service.title,
              librarySource: _service.librarySource,
              capabilities: _service.capabilities(l10n),
            ),
            LinkInputCard(
              controller: _urlController,
              hintText: _service.urlLabel(l10n),
              enabled: !state.busy,
              onClear: _clearUrl,
              onSubmit: _onFetchPressed,
              buttonIcon: state.fetching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              buttonLabel: state.fetching
                  ? l10n.fetchingButton
                  : l10n.goButton,
            ),
            if (state.downloading)
              ServiceActiveDownloadCard(
                registrySource: _service.title,
                // Nothing reported yet (yt-dlp is still re-extracting, or an
                // HLS stream hasn't produced a fragment count) — animate
                // instead of showing a frozen-looking 0%.
                progress: state.progress > 0 || state.paused
                    ? state.progress
                    : null,
                label: _progressLabel(l10n, state),
                paused: state.paused,
                // A yt-dlp merge download (HLS-only Pinterest video) can
                // only be canceled, like YouTube's high-res path.
                onTogglePause: state.canPause ? controller.togglePause : null,
                onCancel: controller.cancelDownload,
              ),
            Expanded(
              child: ServiceDownloadsSection(
                source: _service.librarySource,
                downloading: state.downloading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _progressLabel(AppLocalizations l10n, DirectDownloadState state) {
  final percent = (state.progress * 100).toStringAsFixed(0);
  if (state.paused) return l10n.pausedPercent(percent);
  if (state.progress <= 0) return l10n.downloadStarting;
  return l10n.downloadingPercent(percent);
}
