import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/changelog/changelog.dart';
import '../../core/extraction/media_extractor.dart';
import '../../core/settings/app_settings_service.dart';
import '../../core/settings/settings_providers.dart';
import '../../core/settings/yt_dlp_status_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/update/update_providers.dart';
import '../../l10n/app_localizations.dart';
import 'settings_pages.dart';
import 'settings_widgets.dart';
import 'update_sheet.dart';

/// Settings hub (redesign variant B, approved 2026-11-14): an app card with
/// the update check, four quick tiles (two toggles, theme, language), and a
/// list of sections that each open their own page (`settings_pages.dart`).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final clipboardAutoPaste = ref.watch(clipboardAutoPasteEnabledProvider);
    final repeatVideo = ref.watch(repeatVideoEnabledProvider);
    final longPress = ref.watch(longPressActionProvider);
    final retention = ref.watch(statusArchiveRetentionProvider);
    final mediaRoot = ref.watch(mediaSaveRootProvider);
    final audioRoot = ref.watch(audioSaveRootProvider);
    final enabled = ref.watch(enabledServicesProvider);
    final enabledCount = ServiceType.values
        .where((s) => enabled[s] ?? true)
        .length;

    final themeLabels = {
      ThemeMode.system: l10n.systemDefaultOption,
      ThemeMode.light: l10n.lightThemeOption,
      ThemeMode.dark: l10n.darkThemeOption,
    };
    final localeLabels = <Locale?, String>{
      null: l10n.systemDefaultOption,
      const Locale('en'): 'English',
      const Locale('ru'): 'Русский',
      const Locale('kk'): 'Қазақша',
    };
    final archiveLabels = {
      StatusArchiveRetention.off: l10n.statusArchiveOff,
      StatusArchiveRetention.oneWeek: l10n.statusArchiveWeek,
      StatusArchiveRetention.oneMonth: l10n.statusArchiveMonth,
    };
    final longPressLabel = longPress == LongPressAction.select
        ? l10n.longPressSelect
        : l10n.longPressPreview;

    void open(Widget page) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 32),
        children: [
          const _AppCard(),
          SettingsSectionLabel(l10n.quickSettingsSection),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _QuickTile(
                        icon: Icons.content_paste_go_outlined,
                        title: l10n.autoPasteShort,
                        value: clipboardAutoPaste
                            ? l10n.settingOn
                            : l10n.settingOff,
                        active: clipboardAutoPaste,
                        onTap: () => ref
                            .read(clipboardAutoPasteEnabledProvider.notifier)
                            .setEnabled(!clipboardAutoPaste),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _QuickTile(
                        icon: Icons.repeat,
                        title: l10n.repeatVideoTitle,
                        value: repeatVideo ? l10n.settingOn : l10n.settingOff,
                        active: repeatVideo,
                        onTap: () => ref
                            .read(repeatVideoEnabledProvider.notifier)
                            .setEnabled(!repeatVideo),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _QuickTile(
                        icon: Icons.contrast,
                        title: l10n.themeTitle,
                        value: themeLabels[themeMode]!,
                        onTap: () async {
                          final picked = await _pickOption<ThemeMode>(
                            context,
                            title: l10n.themeTitle,
                            options: themeLabels,
                            current: themeMode,
                          );
                          if (picked != null) {
                            ref
                                .read(themeModeProvider.notifier)
                                .setThemeMode(picked.value);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _QuickTile(
                        icon: Icons.language,
                        title: l10n.languageSection,
                        value: localeLabels[locale] ?? l10n.systemDefaultOption,
                        onTap: () async {
                          final picked = await _pickOption<Locale?>(
                            context,
                            title: l10n.languageSection,
                            options: localeLabels,
                            current: locale,
                          );
                          if (picked != null) {
                            ref
                                .read(localeProvider.notifier)
                                .setLocale(picked.value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SettingsSectionLabel(l10n.allSettingsSection),
          SettingsCard(
            children: [
              _SectionRow(
                icon: Icons.download_outlined,
                background: scheme.primaryContainer,
                foreground: scheme.onPrimaryContainer,
                title: l10n.downloadsFoldersTitle,
                summary:
                    '${mediaRoot.androidDirectoryName} · '
                    '${audioRoot.androidDirectoryName} · '
                    '${l10n.servicesEnabledSubtitle(enabledCount, ServiceType.values.length)}',
                onTap: () => open(const DownloadsSettingsPage()),
              ),
              _SectionRow(
                icon: Icons.smart_display_outlined,
                background: scheme.secondaryContainer,
                foreground: scheme.onSecondaryContainer,
                title: l10n.playbackSection,
                summary: l10n.longPressSummary(longPressLabel),
                onTap: () => open(const PlaybackSettingsPage()),
              ),
              _SectionRow(
                icon: Icons.chat_outlined,
                background: scheme.tertiaryContainer,
                foreground: scheme.onTertiaryContainer,
                title: 'WhatsApp',
                summary: l10n.statusArchiveSummary(archiveLabels[retention]!),
                onTap: () => open(const WhatsAppSettingsPage()),
              ),
              _SectionRow(
                icon: Icons.info_outline,
                background: scheme.surfaceContainerHighest,
                foreground: scheme.onSurfaceVariant,
                title: l10n.aboutSection,
                summary: l10n.aboutSummary,
                onTap: () => open(const AboutSettingsPage()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Wraps the picked value so a sheet dismissed without a choice (null) is
/// distinguishable from picking the `null` option ("System default").
class _Picked<T> {
  const _Picked(this.value);
  final T value;
}

Future<_Picked<T>?> _pickOption<T>(
  BuildContext context, {
  required String title,
  required Map<T, String> options,
  required T current,
}) {
  return showModalBottomSheet<_Picked<T>>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          for (final entry in options.entries)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              title: Text(entry.value),
              trailing: entry.key == current
                  ? Icon(
                      Icons.check,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onTap: () => Navigator.of(context).pop(_Picked<T>(entry.key)),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// App identity + update status + one "Check"/"Update" button.
class _AppCard extends ConsumerStatefulWidget {
  const _AppCard();

  @override
  ConsumerState<_AppCard> createState() => _AppCardState();
}

class _AppCardState extends ConsumerState<_AppCard> {
  bool _pulsing = false;
  Timer? _pulseTimer;

  @override
  void dispose() {
    _pulseTimer?.cancel();
    super.dispose();
  }

  void _check() {
    startUpdateCheck(ref);
    setState(() => _pulsing = true);
    _pulseTimer?.cancel();
    _pulseTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _pulsing = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final appState = ref.watch(updateControllerProvider);
    final ytState = ref.watch(ytDlpStatusProvider);
    final version =
        ref.watch(appVersionLabelProvider).valueOrNull ?? kAppVersion;

    final hasAppUpdate =
        appState is UpdateAvailable ||
        appState is UpdateDownloading ||
        appState is UpdateReadyToInstall ||
        appState is UpdateError;
    final ytFailed = ytState.info?.lastUpdateStatus == 'failed';

    IconData? statusIcon;
    String? status;
    if (appState is UpdateAvailable) {
      status = l10n.updateAvailable(appState.info.version);
      statusIcon = Icons.new_releases_outlined;
    } else if (appState is UpdateReadyToInstall) {
      status = l10n.updateAvailable(appState.info.version);
      statusIcon = Icons.new_releases_outlined;
    } else if (appState is UpdateDownloading) {
      status = l10n.updateDownloadingLabel;
    } else if (appState is UpdateError) {
      status = l10n.updateFailed;
      statusIcon = Icons.error_outline;
    } else if (_pulsing || appState is UpdateChecking) {
      status = l10n.updateChecking;
    } else if (appState is UpdateUpToDate) {
      status = ytFailed
          ? '${l10n.appNoUpdateLabel} · ${l10n.ytDlpFailedShort}'
          : l10n.allUpToDate;
      statusIcon = ytFailed ? Icons.error_outline : Icons.check_circle_outline;
    } else {
      final yt = ytState.info?.version;
      status = yt == null ? null : l10n.ytDlpVersionLabel(yt);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/icon/icon.png',
                    width: 56,
                    height: 56,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AnyWhere Downloader',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${l10n.versionLabel(version)} · ${l10n.betaNoticeTitle}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (statusIcon != null) ...[
                  Icon(statusIcon, size: 18, color: scheme.onPrimaryContainer),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    status ?? '',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _pulsing
                      ? null
                      : hasAppUpdate
                      ? () => showUpdateSheet(context)
                      : _check,
                  child: _pulsing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          hasAppUpdate ? l10n.updateButton : l10n.checkButton,
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One quick-settings tile. [active] fills it with the primary color (a
/// toggle that is on); a tile without [active] is a plain picker.
class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.active,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;
  final bool? active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = active == true;
    final bg = on ? scheme.primary : scheme.cardSurface;
    final fg = on ? scheme.onPrimary : scheme.onSurface;
    final sub = on
        ? scheme.onPrimary.withValues(alpha: 0.85)
        : scheme.onSurfaceVariant;

    final tile = Material(
      color: bg,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: on
                      ? scheme.onPrimary.withValues(alpha: 0.18)
                      : scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: on ? scheme.onPrimary : scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(color: fg),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: sub),
              ),
            ],
          ),
        ),
      ),
    );
    if (active == null) return tile;
    return Semantics(toggled: on, button: true, child: tile);
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.title,
    required this.summary,
    required this.onTap,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final String title;
  final String summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: SettingsIconBox(
        icon: icon,
        background: background,
        foreground: foreground,
      ),
      title: Text(title),
      subtitle: Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
