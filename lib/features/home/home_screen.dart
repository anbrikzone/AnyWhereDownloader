import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../core/clipboard/clipboard_link_tracker.dart';
import '../../core/download/download_registry.dart';
import '../../core/extraction/extractor_registry.dart';
import '../../core/extraction/media_extractor.dart';
import '../../core/navigation/app_route_service.dart';
import '../../core/settings/settings_providers.dart';
import '../../core/ui/link_input_card.dart';
import '../../core/share/share_intent_service.dart';
import '../../core/storage/media_library_service.dart';
import '../../core/update/update_providers.dart';
import '../../services/instagram/instagram_extractor.dart';
import '../../services/linkedin/linkedin_extractor.dart';
import '../../services/pinterest/pinterest_extractor.dart';
import '../../services/tiktok/tiktok_extractor.dart';
import '../../services/x_twitter/x_twitter_extractor.dart';
import '../../services/youtube/youtube_extractor.dart';
import '../../core/ui/app_toast.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
import '../direct_download/direct_download_screen.dart';
import '../downloads/downloads_screen.dart';
import '../library/library_controller.dart';
import '../library/library_grid.dart';
import '../library/library_preview.dart';
import '../settings/settings_screen.dart';
import '../whatsapp/whatsapp_status_screen.dart';
import '../youtube/youtube_screen.dart';

/// Static per-service definition — everything about a service that doesn't
/// depend on the user's Settings toggle (see `_ServiceEntry` below for the
/// combined, per-build view that adds the live `enabled` flag).
class _ServiceDef {
  const _ServiceDef({
    required this.serviceType,
    required this.title,
    required this.icon,
    required this.source,
    this.builder,
  });

  final ServiceType serviceType;
  final String title;
  final IconData icon;

  /// Its folder name under `AnyWhereDownloader/` — keys the brand badge.
  final String source;
  final WidgetBuilder? builder;
}

class _ServiceEntry {
  const _ServiceEntry({
    required this.title,
    required this.icon,
    required this.source,
    required this.enabled,
    this.builder,
  });

  final String title;
  final IconData icon;
  final String source;
  final bool enabled;
  final WidgetBuilder? builder;
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  static const _serviceDefs = <_ServiceDef>[
    _ServiceDef(
      serviceType: ServiceType.youtube,
      title: 'YouTube',
      icon: Icons.smart_display_outlined,
      source: 'YouTube',
      builder: _buildYouTube,
    ),
    _ServiceDef(
      serviceType: ServiceType.whatsapp,
      title: 'WhatsApp',
      icon: Icons.chat_outlined,
      source: 'WhatsApp',
      builder: _buildWhatsApp,
    ),
    _ServiceDef(
      serviceType: ServiceType.tiktok,
      title: 'TikTok',
      icon: Icons.music_note_outlined,
      source: 'TikTok',
      builder: _buildTikTok,
    ),
    _ServiceDef(
      serviceType: ServiceType.xTwitter,
      title: 'X / Twitter',
      icon: Icons.alternate_email,
      source: 'X-Twitter',
      builder: _buildXTwitter,
    ),
    _ServiceDef(
      serviceType: ServiceType.instagram,
      title: 'Instagram',
      icon: Icons.camera_alt_outlined,
      source: 'Instagram',
      builder: _buildInstagram,
    ),
    _ServiceDef(
      serviceType: ServiceType.linkedin,
      title: 'LinkedIn',
      icon: Icons.work_outline,
      source: 'LinkedIn',
      builder: _buildLinkedIn,
    ),
    _ServiceDef(
      serviceType: ServiceType.pinterest,
      title: 'Pinterest',
      icon: Icons.push_pin_outlined,
      source: 'Pinterest',
      builder: _buildPinterest,
    ),
  ];

  static Widget _buildYouTube(BuildContext _) => const YouTubeScreen();
  static Widget _buildWhatsApp(BuildContext _) => const WhatsAppStatusScreen();
  static Widget _buildTikTok(BuildContext _) =>
      const DirectDownloadScreen(service: ServiceType.tiktok);
  static Widget _buildXTwitter(BuildContext _) =>
      const DirectDownloadScreen(service: ServiceType.xTwitter);
  static Widget _buildInstagram(BuildContext _) =>
      const DirectDownloadScreen(service: ServiceType.instagram);
  static Widget _buildLinkedIn(BuildContext _) =>
      const DirectDownloadScreen(service: ServiceType.linkedin);
  static Widget _buildPinterest(BuildContext _) =>
      const DirectDownloadScreen(service: ServiceType.pinterest);

  /// Extractor factories keyed by service — used to build a fresh
  /// `ExtractorRegistry` containing only the currently-enabled services
  /// (see `_buildRegistry`). WhatsApp has no entry: it isn't URL-based (see
  /// `MediaExtractor`'s doc comment), so it never participates in URL
  /// resolution regardless of its enabled state.
  static final _extractorFactories = <ServiceType, MediaExtractor Function()>{
    ServiceType.youtube: YouTubeExtractor.new,
    ServiceType.tiktok: TikTokExtractor.new,
    ServiceType.xTwitter: XTwitterExtractor.new,
    ServiceType.instagram: InstagramExtractor.new,
    ServiceType.linkedin: LinkedInExtractor.new,
    ServiceType.pinterest: PinterestExtractor.new,
  };

  /// Built fresh from the current Settings toggle state on every call
  /// (rather than cached) so clipboard-detect and the URL bar always
  /// respect the latest enable/disable choice, even if it changed while
  /// this screen has stayed mounted (`MainShell`'s `IndexedStack` keeps it
  /// alive underneath the other tabs).
  ExtractorRegistry _buildRegistry() {
    final enabledMap = ref.read(enabledServicesProvider);
    final extractors = <MediaExtractor>[
      for (final entry in _extractorFactories.entries)
        if (enabledMap[entry.key] ?? true) entry.value(),
    ];
    return ExtractorRegistry(extractors);
  }

  final _urlController = TextEditingController();
  String? _urlError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkClipboard());
    // Home stays mounted for the app's whole life (index 0 of MainShell's
    // IndexedStack), so it's the right place to receive share-sheet links —
    // same as it owns the clipboard auto-detect.
    ShareIntentService.instance.init(_handleSharedUrl);
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
    // Home keeps running its lifecycle observer even while another screen
    // (e.g. YouTubeScreen) is pushed on top of it (MainShell's IndexedStack
    // keeps Home mounted) — without this guard, Home would steal the
    // clipboard text via the shared ClipboardLinkTracker on every resume
    // even when it isn't the visible screen.
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
    if (_buildRegistry().resolve(text) == null) return;

    ClipboardLinkTracker.instance.markHandled(text);
    if (!mounted) return;
    setState(() {
      _urlController.text = text;
      _urlError = null;
    });
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
    setState(() {
      _urlController.clear();
      _urlError = null;
    });
  }

  void _onGoPressed() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    final extractor = _buildRegistry().resolve(url);
    if (extractor == null) {
      setState(
        () => _urlError = AppLocalizations.of(context)!.linkNotRecognized,
      );
      return;
    }
    // The service screen now owns the link; empty Home's field so the next
    // copied link auto-pastes here (the clipboard check skips a filled
    // field), and mark it handled so it isn't pasted straight back.
    ClipboardLinkTracker.instance.markHandled(url);
    setState(() {
      _urlError = null;
      _urlController.clear();
    });
    _navigateForService(extractor.serviceType, url);
  }

  /// Handles a link handed to the app from another app's system "Share"
  /// sheet. An explicit user action, so — unlike the clipboard check — it's
  /// honoured regardless of which tab is showing; it drops the link into
  /// the URL field and opens the matching service screen. An unrecognized
  /// or disabled service gets a toast (visible from any tab) plus the usual
  /// in-field error.
  void _handleSharedUrl(String url) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final extractor = _buildRegistry().resolve(url);
    setState(() {
      _urlController.text = url;
      _urlError = extractor == null ? l10n.linkNotRecognized : null;
    });
    if (extractor == null) {
      showAppToast(context, l10n.linkNotRecognized);
      return;
    }
    // Keep the clipboard check from re-offering the same link right after,
    // and leave Home's field empty for the next one (see _onGoPressed).
    ClipboardLinkTracker.instance.markHandled(url);
    setState(() => _urlController.clear());
    _navigateForService(extractor.serviceType, url);
  }

  void _navigateForService(ServiceType type, String url) {
    switch (type) {
      case ServiceType.youtube:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => YouTubeScreen(initialUrl: url)),
        );
      case ServiceType.tiktok ||
          ServiceType.xTwitter ||
          ServiceType.instagram ||
          ServiceType.linkedin ||
          ServiceType.pinterest:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                DirectDownloadScreen(service: type, initialUrl: url),
          ),
        );
      case ServiceType.whatsapp:
        setState(
          () =>
              _urlError = AppLocalizations.of(context)!.whatsappNotSupportedYet,
        );
    }
  }

  /// Whether the cold-start check has found a newer release — drives the
  /// dot on the Settings gear.
  bool _updateAvailable(WidgetRef ref) {
    final s = ref.watch(updateControllerProvider);
    return s is UpdateAvailable ||
        s is UpdateDownloading ||
        s is UpdateReadyToInstall;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final enabledMap = ref.watch(enabledServicesProvider);
    final services = [
      for (final def in _serviceDefs)
        _ServiceEntry(
          title: def.title,
          icon: def.icon,
          source: def.source,
          enabled: enabledMap[def.serviceType] ?? true,
          builder: def.builder,
        ),
    ];
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final library = ref.watch(libraryControllerProvider);
    final stats = <String, ({int count, DateTime latest})>{};
    if (library.hasAccess) {
      for (final item in library.items.valueOrNull ?? const <LibraryItem>[]) {
        final prev = stats[item.source];
        final at = item.downloadedAt;
        stats[item.source] = (
          count: (prev?.count ?? 0) + 1,
          latest: prev == null || at.isAfter(prev.latest) ? at : prev.latest,
        );
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'AnyWhere Downloader',
          style: theme.textTheme.titleMedium?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          _DownloadsButton(tooltip: l10n.downloadsTitle),
          IconButton(
            tooltip: l10n.settingsTooltip,
            icon: _updateAvailable(ref)
                ? const Badge(child: Icon(Icons.settings_outlined))
                : const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          const SizedBox(height: 12),
          LinkInputCard(
            controller: _urlController,
            hintText: l10n.homeUrlHint,
            errorText: _urlError,
            onPaste: _pasteFromClipboard,
            onClear: _clearUrl,
            onSubmit: _onGoPressed,
            buttonIcon: const Icon(Icons.download),
            buttonLabel: l10n.downloadButton,
          ),
          const _ActiveDownloadCard(),
          _HomeSectionLabel(l10n.servicesSection),
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              mainAxisExtent: 68,
            ),
            children: [
              for (final service in services)
                _ServiceTile(
                  service: service,
                  stats: stats[service.source],
                  onTap: () => _onTileTap(service),
                ),
            ],
          ),
          const _RecentStrip(),
        ],
      ),
    );
  }

  /// "Paste" inside the link field — an explicit clipboard read (unlike
  /// `_checkClipboard`, no recognition check: the user asked for it).
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (!mounted || text == null || text.isEmpty) return;
    ClipboardLinkTracker.instance.markHandled(text);
    setState(() {
      _urlController.text = text;
      _urlError = null;
    });
  }

  void _onTileTap(_ServiceEntry service) {
    if (!service.enabled || service.builder == null) {
      showAppToast(
        context,
        AppLocalizations.of(context)!.serviceDisabledSnack(service.title),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: service.builder!));
  }
}

class _HomeSectionLabel extends StatelessWidget {
  const _HomeSectionLabel(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 0, 6),
      child: SizedBox(
        height: 30,
        child: Row(
          children: [
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.titleSmall),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// The running download (the newest when several run) with its progress;
/// tapping opens the Downloads screen. Hidden when nothing is running.
class _ActiveDownloadCard extends ConsumerWidget {
  const _ActiveDownloadCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(downloadRegistryProvider.select((s) => s.active));
    if (active.isEmpty) return const SizedBox.shrink();
    final entry = active.last;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final percent = (entry.progress * 100).round();
    final title = active.length > 1
        ? '${entry.title} (+${active.length - 1})'
        : entry.title;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const DownloadsScreen())),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                ServiceLogoBadge(source: entry.source, size: 36, radius: 12),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          if (entry.progress > 0)
                            Text(
                              '$percent%',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          minHeight: 6,
                          value: entry.progress > 0 ? entry.progress : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A service card: logo, name, and how many files were downloaded from it
/// plus when the last one was (from the Library list; omitted when the
/// list isn't available, e.g. no gallery access).
class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.service,
    required this.stats,
    required this.onTap,
  });

  final _ServiceEntry service;
  final ({int count, DateTime latest})? stats;
  final VoidCallback onTap;

  String? _meta(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (!service.enabled) return l10n.serviceDisabledLabel;
    final s = stats;
    if (s == null) return null;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meta = _meta(context);
    return Opacity(
      opacity: service.enabled ? 1 : 0.5,
      child: Material(
        color: scheme.cardSurface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                ServiceLogoBadge(source: service.source, size: 40, radius: 12),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      if (meta != null)
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The four newest downloads, plus a link to the Library tab. Reads the
/// shared Library controller, which only *checks* gallery permission —
/// without access, or with nothing downloaded, the strip is hidden.
class _RecentStrip extends ConsumerWidget {
  const _RecentStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(libraryControllerProvider);
    final all = state.items.valueOrNull;
    if (!state.hasAccess || all == null || all.isEmpty) {
      return const SizedBox.shrink();
    }
    final recent = all.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HomeSectionLabel(
          l10n.recentSection,
          trailing: TextButton(
            // Fits the 30dp label row (a default TextButton is 40dp tall
            // and was clipped there).
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () =>
                AppRouteService.instance.dispatch(AppRoute.library),
            child: Text(l10n.libraryTitle),
          ),
        ),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: [
            for (var i = 0; i < recent.length; i++)
              _RecentTile(
                item: recent[i],
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LibraryPreviewPage(
                      assets: [for (final item in recent) item.asset],
                      initialIndex: i,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.item, required this.onTap});

  final LibraryItem item;
  final VoidCallback onTap;

  static final Map<String, Future<Uint8List?>> _cache = {};

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final asset = item.asset;
    final thumb = asset.type == AssetType.audio
        ? Future<Uint8List?>.value(null)
        : _cache.putIfAbsent(
            asset.id,
            () => asset.thumbnailDataWithSize(const ThumbnailSize(200, 200)),
          );
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ColoredBox(
          color: scheme.surfaceContainerHighest,
          child: Stack(
            fit: StackFit.expand,
            children: [
              FutureBuilder<Uint8List?>(
                future: thumb,
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (bytes != null) {
                    return Image.memory(bytes, fit: BoxFit.cover);
                  }
                  return Icon(
                    asset.type == AssetType.audio
                        ? Icons.audiotrack_outlined
                        : Icons.insert_drive_file_outlined,
                    color: scheme.onSurfaceVariant,
                  );
                },
              ),
              Positioned(
                left: 5,
                top: 5,
                child: ServiceLogoBadge(
                  source: item.source,
                  size: 20,
                  radius: 6,
                  outlineOnDark: false,
                ),
              ),
              if (asset.type == AssetType.video)
                Positioned(
                  right: 5,
                  bottom: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      formatMediaDuration(asset.duration),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Home AppBar entry to the Downloads screen (backlog #19), badged with the
/// number of downloads currently running.
class _DownloadsButton extends ConsumerWidget {
  const _DownloadsButton({required this.tooltip});

  final String tooltip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(
      downloadRegistryProvider.select((s) => s.active.length),
    );
    return IconButton(
      tooltip: tooltip,
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
