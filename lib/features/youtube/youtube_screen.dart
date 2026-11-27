import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clipboard/clipboard_link_tracker.dart';
import '../../core/settings/settings_providers.dart';
import '../../core/ui/link_input_card.dart';
import '../../core/ui/app_toast.dart';
import '../../l10n/app_localizations.dart';
import '../library/service_downloads_section.dart';
import '../service/service_screen_parts.dart';
import '../../services/youtube/youtube_extractor.dart';
import '../../services/youtube/youtube_playlist.dart';
import '../format_selection/format_selection_sheet.dart';
import '../format_selection/rename_dialog.dart';
import '../settings/status_message_presenter.dart';
import 'playlist_screen.dart';
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
    if (!_extractor.canHandle(text)) return;
    final busy = ref.read(youTubeControllerProvider).busy;
    if (busy) return;

    ClipboardLinkTracker.instance.markHandled(text);
    if (!mounted) return;
    setState(() => _urlController.text = text);
    showAppToast(context, AppLocalizations.of(context)!.clipboardLinkPasted);
  }

  /// Clears the URL field and wipes the system clipboard too — that wipe is
  /// what stops the same link being re-offered on a later cold start (the
  /// in-memory `ClipboardLinkTracker` doesn't survive a process restart).
  /// The tracker is *forgotten* rather than marked handled, so re-copying
  /// the identical URL on purpose still auto-pastes it.
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
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    if (YouTubePlaylistUrl.isPurePlaylistUrl(url)) {
      await _startPlaylist(url);
      return;
    }
    if (YouTubePlaylistUrl.isVideoInPlaylistUrl(url)) {
      final choice = await _askVideoOrPlaylist();
      if (!mounted || choice == null) return;
      if (choice == _UrlChoice.playlist) {
        await _startPlaylist(url);
        return;
      }
      // choice == video → fall through to the single-video flow
    }
    await _fetchSingleVideo();
  }

  Future<_UrlChoice?> _askVideoOrPlaylist() {
    final l10n = AppLocalizations.of(context)!;
    return showDialog<_UrlChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.playlistLinkDialogTitle),
        content: Text(l10n.playlistLinkDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_UrlChoice.video),
            child: Text(l10n.playlistLinkThisVideo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_UrlChoice.playlist),
            child: Text(l10n.playlistLinkWhole),
          ),
        ],
      ),
    );
  }

  Future<void> _startPlaylist(String url) async {
    final controller = ref.read(youTubeControllerProvider.notifier);
    final info = await controller.fetchPlaylist(url);
    if (info == null || !mounted) return;
    final pick = await showPlaylistPickerSheet(
      context: context,
      playlistTitle: info.title,
      entries: info.entries,
    );
    if (pick == null || !mounted || pick.positions.isEmpty) return;
    _consumeUrl();
    await controller.downloadPlaylist(
      playlistUrl: url,
      selectedPositions: pick.positions,
      totalInPlaylist: info.entries.length,
      quality: pick.quality,
      playlistTitle: info.title,
      channelName: info.uploader,
    );
  }

  Future<void> _fetchSingleVideo() async {
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

      _consumeUrl();
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
              title: 'YouTube',
              librarySource: 'YouTube',
              capabilities: [
                l10n.capVideo4k,
                l10n.capShorts,
                l10n.capPlaylists,
                'MP3 / M4A',
              ],
            ),
            LinkInputCard(
              controller: _urlController,
              hintText: l10n.youtubeUrlLabel,
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
                registrySource: 'YouTube',
                progress:
                    ((state.downloadPhase == 'merging' ||
                                state.downloadPhase == 'converting') &&
                            !state.mergeDurationKnown) ||
                        (state.progress <= 0 && !state.paused)
                    ? null
                    : state.progress,
                label: _progressLabel(l10n, state),
                paused: state.paused,
                onTogglePause: state.canPause ? controller.togglePause : null,
                onCancel: controller.cancelDownload,
              ),
            Expanded(
              child: ServiceDownloadsSection(
                source: 'YouTube',
                downloading: state.downloading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _UrlChoice { video, playlist }

String _progressLabel(AppLocalizations l10n, YouTubeState state) {
  final percent = (state.progress * 100).toStringAsFixed(0);
  if (state.paused) return l10n.pausedPercent(percent);
  switch (state.downloadPhase) {
    case 'playlist':
      final total = state.playlistTotal ?? 0;
      final base = l10n.playlistProgressLabel(
        state.playlistCurrentIndex.clamp(0, total == 0 ? 0 : total),
        total,
      );
      final phase = state.playlistItemPhase;
      final sub = switch (phase) {
        'video' => l10n.playlistPhaseVideo,
        'audio' => l10n.playlistPhaseAudio,
        'merging' => l10n.playlistPhaseMerging,
        'converting' => l10n.playlistPhaseConverting,
        _ => null,
      };
      if (sub == null) return base;
      // yt-dlp gives no % for the merge/convert step — show the phase alone.
      final showPct = phase == 'video' || phase == 'audio';
      if (!showPct) return '$base · $sub';
      final pct = (state.playlistItemProgress * 100).toStringAsFixed(0);
      return '$base · $sub $pct%';
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
      return state.progress <= 0
          ? l10n.downloadStarting
          : l10n.downloadingPercent(percent);
  }
}
