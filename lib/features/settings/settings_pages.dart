import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/changelog/changelog.dart';
import '../../core/extraction/media_extractor.dart';
import '../../core/settings/app_settings_service.dart';
import '../../core/settings/settings_providers.dart';
import '../../core/settings/yt_dlp_status_provider.dart';
import '../../core/storage/media_library_service.dart';
import '../../core/ui/app_toast.dart';
import '../../core/update/update_providers.dart';
import '../../core/update/update_service.dart' show kRepoDisplayUrl;
import '../../l10n/app_localizations.dart';
import 'changelog_screen.dart';
import 'settings_widgets.dart';
import 'update_sheet.dart';

/// Brand names, deliberately untranslated (see CLAUDE.md "Multi-language
/// support").
const serviceLabels = {
  ServiceType.youtube: 'YouTube',
  ServiceType.whatsapp: 'WhatsApp',
  ServiceType.tiktok: 'TikTok',
  ServiceType.xTwitter: 'X / Twitter',
  ServiceType.instagram: 'Instagram',
  ServiceType.linkedin: 'LinkedIn',
  ServiceType.pinterest: 'Pinterest',
};

Widget _sectionPage(BuildContext context, String title, List<Widget> body) {
  return Scaffold(
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    appBar: AppBar(
      title: Text(title),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    ),
    body: ListView(padding: const EdgeInsets.only(bottom: 32), children: body),
  );
}

/// "Downloads & folders": save roots, clipboard auto-paste, and the
/// per-service toggles (formerly their own `ServicesScreen`).
class DownloadsSettingsPage extends ConsumerWidget {
  const DownloadsSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final mediaSaveRoot = ref.watch(mediaSaveRootProvider);
    final audioSaveRoot = ref.watch(audioSaveRootProvider);
    final clipboardAutoPaste = ref.watch(clipboardAutoPasteEnabledProvider);
    final enabled = ref.watch(enabledServicesProvider);
    final enabledCount = ServiceType.values
        .where((s) => enabled[s] ?? true)
        .length;

    return _sectionPage(context, l10n.downloadsFoldersTitle, [
      SettingsSectionLabel(l10n.saveLocationSection),
      SettingsCard(
        children: [
          SettingsChipsRow<MediaSaveRoot>(
            title: l10n.saveLocationMediaTitle,
            subtitle: l10n.saveLocationMediaSubtitle,
            value: mediaSaveRoot,
            options: {
              for (final root in MediaSaveRoot.values)
                root: root.androidDirectoryName,
            },
            recommended: MediaSaveRoot.pictures,
            recommendedLabel: l10n.recommendedBadge,
            onChanged: (value) =>
                _onMediaSaveRootChanged(context, ref, l10n, value),
          ),
          SettingsChipsRow<AudioSaveRoot>(
            title: l10n.saveLocationAudioTitle,
            subtitle: l10n.saveLocationAudioSubtitle,
            value: audioSaveRoot,
            options: {
              for (final root in AudioSaveRoot.values)
                root: root.androidDirectoryName,
            },
            recommended: AudioSaveRoot.music,
            recommendedLabel: l10n.recommendedBadge,
            onChanged: (value) =>
                _onAudioSaveRootChanged(context, ref, l10n, value),
          ),
        ],
      ),
      SettingsSectionLabel(l10n.linksSection),
      SettingsCard(
        children: [
          SettingsSwitchRow(
            title: l10n.clipboardAutoPasteTitle,
            subtitle: l10n.clipboardAutoPasteSubtitle,
            value: clipboardAutoPaste,
            onChanged: (value) => ref
                .read(clipboardAutoPasteEnabledProvider.notifier)
                .setEnabled(value),
          ),
        ],
      ),
      SettingsSectionLabel(
        '${l10n.servicesSection} · '
        '${l10n.servicesEnabledSubtitle(enabledCount, ServiceType.values.length)}',
      ),
      SettingsCard(
        children: [
          for (final service in ServiceType.values)
            SettingsSwitchRow(
              title: serviceLabels[service] ?? service.name,
              value: enabled[service] ?? true,
              onChanged: (value) => ref
                  .read(enabledServicesProvider.notifier)
                  .setEnabled(service, value),
            ),
        ],
      ),
    ]);
  }
}

/// "Playback": repeat video + what a long-press on media does.
class PlaybackSettingsPage extends ConsumerWidget {
  const PlaybackSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final repeatVideo = ref.watch(repeatVideoEnabledProvider);
    final longPress = ref.watch(longPressActionProvider);

    return _sectionPage(context, l10n.playbackSection, [
      const SizedBox(height: 12),
      SettingsCard(
        children: [
          SettingsSwitchRow(
            title: l10n.repeatVideoTitle,
            subtitle: l10n.repeatVideoSubtitle,
            value: repeatVideo,
            onChanged: (value) =>
                ref.read(repeatVideoEnabledProvider.notifier).setEnabled(value),
          ),
          SettingsSegmentRow<LongPressAction>(
            title: l10n.longPressTitle,
            subtitle: l10n.longPressSubtitle,
            value: longPress,
            options: {
              LongPressAction.preview: l10n.longPressPreview,
              LongPressAction.select: l10n.longPressSelect,
            },
            onChanged: (value) =>
                ref.read(longPressActionProvider.notifier).setAction(value),
          ),
        ],
      ),
    ]);
  }
}

/// "WhatsApp": the status-archive retention.
class WhatsAppSettingsPage extends ConsumerWidget {
  const WhatsAppSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final retention = ref.watch(statusArchiveRetentionProvider);

    return _sectionPage(context, 'WhatsApp', [
      const SizedBox(height: 12),
      SettingsCard(
        children: [
          SettingsSegmentRow<StatusArchiveRetention>(
            title: l10n.statusArchiveTitle,
            subtitle: l10n.statusArchiveSubtitle,
            value: retention,
            options: {
              StatusArchiveRetention.off: l10n.statusArchiveOff,
              StatusArchiveRetention.oneWeek: l10n.statusArchiveWeek,
              StatusArchiveRetention.oneMonth: l10n.statusArchiveMonth,
            },
            onChanged: (value) => ref
                .read(statusArchiveRetentionProvider.notifier)
                .setRetention(value),
          ),
        ],
      ),
    ]);
  }
}

/// "About": beta notice, update check, yt-dlp, what's new, source code.
class AboutSettingsPage extends ConsumerWidget {
  const AboutSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final versionLabel =
        ref.watch(appVersionLabelProvider).valueOrNull ?? kAppVersion;

    return _sectionPage(context, l10n.aboutSection, [
      const SizedBox(height: 12),
      SettingsCard(
        children: [
          const UpdateRow(),
          const _YtDlpRow(),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: Text(l10n.whatsNewTitle),
            subtitle: Text(l10n.versionLabel(versionLabel)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ChangelogScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(l10n.sourceCodeTitle),
            subtitle: const Text(kRepoDisplayUrl),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => ref
                .read(updateControllerProvider.notifier)
                .openRepositoryPage(),
          ),
        ],
      ),
      const SizedBox(height: 12),
      SettingsCard(
        children: [
          ListTile(
            leading: const Icon(Icons.science_outlined),
            title: Text(l10n.betaNoticeTitle),
            subtitle: Text(l10n.betaNoticeBody),
          ),
        ],
      ),
    ]);
  }
}

/// New downloads use [value] immediately either way; only asks about
/// relocating *existing* ones if it actually changed.
Future<void> _onMediaSaveRootChanged(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
  MediaSaveRoot value,
) async {
  final previous = ref.read(mediaSaveRootProvider);
  ref.read(mediaSaveRootProvider.notifier).setRoot(value);
  if (value == previous || !context.mounted) return;
  await _offerToMoveExisting(
    context: context,
    l10n: l10n,
    newRootLabel: value.androidDirectoryName,
    attempt: () => MediaLibraryService().attemptMoveRoot(
      isAudio: false,
      fromRoot: previous.androidDirectoryName,
      toRoot: value.androidDirectoryName,
    ),
  );
}

/// Audio counterpart of [_onMediaSaveRootChanged].
Future<void> _onAudioSaveRootChanged(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
  AudioSaveRoot value,
) async {
  final previous = ref.read(audioSaveRootProvider);
  ref.read(audioSaveRootProvider.notifier).setRoot(value);
  if (value == previous || !context.mounted) return;
  await _offerToMoveExisting(
    context: context,
    l10n: l10n,
    newRootLabel: value.androidDirectoryName,
    attempt: () => MediaLibraryService().attemptMoveRoot(
      isAudio: true,
      fromRoot: previous.androidDirectoryName,
      toRoot: value.androidDirectoryName,
    ),
  );
}

/// Shared "move existing downloads too?" flow for both save-location
/// dropdowns — added 2026-09-13 after on-device feedback that changing the
/// setting alone left old files behind (confirmed as intended, but the user
/// wanted the *option* to relocate them too). Reuses the exact
/// [MediaLibraryService.attemptMoveRoot]/`completeMigrationAfterConsent`
/// two-phase consent shape already built for backlog #7's legacy-folder
/// migration — a deliberate root change hits the identical
/// `RecoverableSecurityException` requirement a `RELATIVE_PATH` move always
/// does (see `MediaSaveBridge.moveBucket`'s bug #5 doc), so the same batched
/// single-dialog-then-retry flow applies here unchanged.
Future<void> _offerToMoveExisting({
  required BuildContext context,
  required AppLocalizations l10n,
  required String newRootLabel,
  required Future<PendingMigrationConsent?> Function() attempt,
}) async {
  final proceed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.rootMoveConfirmTitle),
      content: Text(l10n.rootMoveConfirmBody(newRootLabel)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.rootMoveConfirmNo),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.rootMoveConfirmYes),
        ),
      ],
    ),
  );
  if (proceed != true || !context.mounted) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      content: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(l10n.rootMoveInProgress)),
        ],
      ),
    ),
  );

  final service = MediaLibraryService();
  final pending = await attempt();
  final fullyMoved = pending == null
      ? true
      : await service.completeMigrationAfterConsent(pending);

  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop(); // dismiss the busy dialog
  showAppToast(
    context,
    fullyMoved ? l10n.rootMoveDone : l10n.rootMoveIncomplete,
  );
}

/// Kicks off **both** update checks — the app (GitHub release) and the
/// YouTube engine (yt-dlp) — fire-and-forget; their providers update the UI.
void startUpdateCheck(WidgetRef ref) {
  unawaited(ref.read(updateControllerProvider.notifier).checkNow());
  unawaited(ref.read(ytDlpStatusProvider.notifier).updateNow());
}

/// "Check for updates" row. A tap kicks off **both** checks — the app
/// (GitHub release, [updateControllerProvider]) and the YouTube engine
/// ([ytDlpStatusProvider]) — in the background and returns immediately: the
/// row keeps showing the last known result the whole time, never a
/// blocking spinner. A short cosmetic pulse (≤2 s) acknowledges the tap;
/// the real network calls run their own timeouts unwatched and update the
/// row if and when anything changed. If an app update is found, the tap
/// opens [showUpdateSheet] instead.
class UpdateRow extends ConsumerStatefulWidget {
  const UpdateRow({super.key});

  @override
  ConsumerState<UpdateRow> createState() => _UpdateRowState();
}

class _UpdateRowState extends ConsumerState<UpdateRow> {
  bool _pulsing = false;
  Timer? _pulseTimer;

  @override
  void dispose() {
    _pulseTimer?.cancel();
    super.dispose();
  }

  void _startCheck() {
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
    final appState = ref.watch(updateControllerProvider);
    final ytState = ref.watch(ytDlpStatusProvider);

    final hasAppUpdate =
        appState is UpdateAvailable ||
        appState is UpdateDownloading ||
        appState is UpdateReadyToInstall ||
        appState is UpdateError;

    // Short yt-dlp clause appended to the "no app update" line.
    String ytClause() => switch (ytState.info?.lastUpdateStatus) {
      'done' => l10n.ytDlpUpdatedToShort(ytState.info?.version ?? ''),
      'upToDate' => l10n.ytDlpCurrentShort,
      'failed' => l10n.ytDlpFailedShort,
      _ => '',
    };

    String? subtitle;
    if (appState is UpdateAvailable) {
      subtitle = l10n.updateAvailable(appState.info.version);
    } else if (appState is UpdateReadyToInstall) {
      subtitle = l10n.updateAvailable(appState.info.version);
    } else if (appState is UpdateDownloading) {
      subtitle = l10n.updateDownloadingLabel;
    } else if (appState is UpdateError) {
      subtitle = l10n.updateFailed;
    } else if (appState is UpdateUpToDate) {
      final yt = ytClause();
      subtitle = yt.isEmpty
          ? l10n.appNoUpdateLabel
          : '${l10n.appNoUpdateLabel} · $yt';
    } else {
      // Not checked yet this session — show "checking…" only during the pulse.
      subtitle = _pulsing ? l10n.updateChecking : null;
    }

    return ListTile(
      leading: hasAppUpdate
          ? const Badge(child: Icon(Icons.system_update_outlined))
          : const Icon(Icons.system_update_outlined),
      title: Text(l10n.checkForUpdatesTitle),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: _pulsing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: () {
        if (hasAppUpdate) {
          showUpdateSheet(context);
        } else {
          _startCheck();
        }
      },
    );
  }
}

/// Read-only "yt-dlp" line under [UpdateRow] — just shows the installed
/// engine version and last-update result. The check/update action lives in
/// [UpdateRow] now; this is here so the version is visible at a glance.
class _YtDlpRow extends ConsumerWidget {
  const _YtDlpRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(ytDlpStatusProvider);
    final info = state.info;

    final String subtitle;
    if (state.updating) {
      subtitle = l10n.ytDlpUpdatingLabel;
    } else if (state.loading || info == null) {
      subtitle = l10n.ytDlpEngineChecking;
    } else {
      final version = info.version != null
          ? l10n.ytDlpVersionLabel(info.version!)
          : l10n.ytDlpVersionUnknown;
      final status = switch (info.lastUpdateStatus) {
        'done' => l10n.ytDlpStatusUpdated,
        'upToDate' => l10n.ytDlpStatusUpToDate,
        'failed' => l10n.ytDlpStatusUpdateFailed,
        _ => l10n.ytDlpStatusNotYet,
      };
      subtitle = '$version · $status';
    }

    return ListTile(
      dense: true,
      leading: const Icon(Icons.terminal_outlined),
      title: const Text('yt-dlp'),
      subtitle: Text(subtitle),
    );
  }
}
