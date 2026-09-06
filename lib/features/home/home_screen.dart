import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/clipboard/clipboard_link_tracker.dart';
import '../../core/extraction/extractor_registry.dart';
import '../../core/extraction/media_extractor.dart';
import '../../core/settings/settings_providers.dart';
import '../../core/update/update_providers.dart';
import '../../services/instagram/instagram_extractor.dart';
import '../../services/linkedin/linkedin_extractor.dart';
import '../../services/tiktok/tiktok_extractor.dart';
import '../../services/x_twitter/x_twitter_extractor.dart';
import '../../services/youtube/youtube_extractor.dart';
import '../../core/ui/app_toast.dart';
import '../../l10n/app_localizations.dart';
import '../instagram/instagram_screen.dart';
import '../linkedin/linkedin_screen.dart';
import '../settings/settings_screen.dart';
import '../tiktok/tiktok_screen.dart';
import '../whatsapp/whatsapp_status_screen.dart';
import '../x_twitter/x_twitter_screen.dart';
import '../youtube/youtube_screen.dart';

/// Static per-service definition — everything about a service that doesn't
/// depend on the user's Settings toggle (see `_ServiceEntry` below for the
/// combined, per-build view that adds the live `enabled` flag).
class _ServiceDef {
  const _ServiceDef({
    required this.serviceType,
    required this.title,
    required this.icon,
    this.builder,
  });

  final ServiceType serviceType;
  final String title;
  final IconData icon;
  final WidgetBuilder? builder;
}

class _ServiceEntry {
  const _ServiceEntry({
    required this.title,
    required this.icon,
    required this.enabled,
    this.builder,
  });

  final String title;
  final IconData icon;
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
      builder: _buildYouTube,
    ),
    _ServiceDef(
      serviceType: ServiceType.whatsapp,
      title: 'WhatsApp',
      icon: Icons.chat_outlined,
      builder: _buildWhatsApp,
    ),
    _ServiceDef(
      serviceType: ServiceType.tiktok,
      title: 'TikTok',
      icon: Icons.music_note_outlined,
      builder: _buildTikTok,
    ),
    _ServiceDef(
      serviceType: ServiceType.xTwitter,
      title: 'X / Twitter',
      icon: Icons.alternate_email,
      builder: _buildXTwitter,
    ),
    _ServiceDef(
      serviceType: ServiceType.instagram,
      title: 'Instagram',
      icon: Icons.camera_alt_outlined,
      builder: _buildInstagram,
    ),
    _ServiceDef(
      serviceType: ServiceType.linkedin,
      title: 'LinkedIn',
      icon: Icons.work_outline,
      builder: _buildLinkedIn,
    ),
  ];

  static Widget _buildYouTube(BuildContext _) => const YouTubeScreen();
  static Widget _buildWhatsApp(BuildContext _) => const WhatsAppStatusScreen();
  static Widget _buildTikTok(BuildContext _) => const TikTokScreen();
  static Widget _buildXTwitter(BuildContext _) => const XTwitterScreen();
  static Widget _buildInstagram(BuildContext _) => const InstagramScreen();
  static Widget _buildLinkedIn(BuildContext _) => const LinkedInScreen();

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
    setState(() => _urlError = null);
    switch (extractor.serviceType) {
      case ServiceType.youtube:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => YouTubeScreen(initialUrl: url)));
      case ServiceType.tiktok:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => TikTokScreen(initialUrl: url)));
      case ServiceType.xTwitter:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => XTwitterScreen(initialUrl: url)),
        );
      case ServiceType.instagram:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => InstagramScreen(initialUrl: url)),
        );
      case ServiceType.linkedin:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => LinkedInScreen(initialUrl: url)),
        );
      case ServiceType.whatsapp:
        setState(
          () => _urlError = AppLocalizations.of(context)!.whatsappNotSupportedYet,
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
          enabled: enabledMap[def.serviceType] ?? true,
          builder: def.builder,
        ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('AnyWhere Downloader'),
        actions: [
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
      body: Column(
        children: [
          const SizedBox(height: 32),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _urlController,
                      decoration: InputDecoration(
                        labelText: l10n.homeUrlHint,
                        border: const OutlineInputBorder(),
                        errorText: _urlError,
                        suffixIcon: ValueListenableBuilder(
                          valueListenable: _urlController,
                          builder: (context, value, _) {
                            if (value.text.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return IconButton(
                              icon: const Icon(Icons.clear),
                              tooltip: l10n.clearTooltip,
                              onPressed: _clearUrl,
                            );
                          },
                        ),
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => _onGoPressed(),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _onGoPressed,
                      child: Text(l10n.goButton),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 2.6,
              ),
              itemCount: services.length,
              itemBuilder: (context, index) {
                final service = services[index];
                return _ServiceCard(
                  service: service,
                  onTap: () => _onTileTap(service),
                );
              },
            ),
          ),
        ],
      ),
    );
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

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service, required this.onTap});

  final _ServiceEntry service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: service.enabled ? 1 : 0.5,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(service.icon, size: 22, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (!service.enabled)
                        Text(
                          AppLocalizations.of(context)!.serviceDisabledLabel,
                          style: Theme.of(context).textTheme.bodySmall,
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
