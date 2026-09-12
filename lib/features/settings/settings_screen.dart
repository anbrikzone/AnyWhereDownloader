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
import 'services_screen.dart';
import 'update_sheet.dart';

/// Fixed width shared by the WhatsApp archive and "Save location" dropdowns
/// (`_Dropdown`'s `width` param) — wide enough for `AudioSaveRoot`'s longest
/// label (`Notifications`) so the value text starts at the same indent and
/// the arrow lands at the same spot on every row, regardless of how short
/// that row's own selected label is (`Off`, `Pictures`, `DCIM`, `Movies`,
/// `Music`, ...).
const _dropdownAlignedWidth = 130.0;

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final themeMode = ref.watch(themeModeProvider);
    final enabledServices = ref.watch(enabledServicesProvider);
    final clipboardAutoPaste = ref.watch(clipboardAutoPasteEnabledProvider);
    final repeatVideo = ref.watch(repeatVideoEnabledProvider);
    final locale = ref.watch(localeProvider);
    final statusArchive = ref.watch(statusArchiveRetentionProvider);
    final mediaSaveRoot = ref.watch(mediaSaveRootProvider);
    final audioSaveRoot = ref.watch(audioSaveRootProvider);
    final versionLabel =
        ref.watch(appVersionLabelProvider).valueOrNull ?? kAppVersion;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          ListTile(
            title: Text(l10n.appearanceSection),
            trailing: _Dropdown<ThemeMode>(
              value: themeMode,
              items: {
                ThemeMode.system: l10n.systemDefaultOption,
                ThemeMode.light: l10n.lightThemeOption,
                ThemeMode.dark: l10n.darkThemeOption,
              },
              onChanged: (mode) => _setThemeMode(ref, mode),
            ),
          ),
          const Divider(),
          ListTile(
            title: Text(l10n.servicesSection),
            subtitle: Text(l10n.servicesEnabledSubtitle(
              ServiceType.values.where((s) => enabledServices[s] ?? true).length,
              ServiceType.values.length,
            )),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ServicesScreen()),
            ),
          ),
          const Divider(),
          _SectionHeader(l10n.clipboardSection),
          SwitchListTile(
            title: Text(l10n.clipboardAutoPasteTitle),
            subtitle: Text(l10n.clipboardAutoPasteSubtitle),
            value: clipboardAutoPaste,
            onChanged: (enabled) => ref
                .read(clipboardAutoPasteEnabledProvider.notifier)
                .setEnabled(enabled),
          ),
          const Divider(),
          _SectionHeader(l10n.playbackSection),
          SwitchListTile(
            title: Text(l10n.repeatVideoTitle),
            subtitle: Text(l10n.repeatVideoSubtitle),
            value: repeatVideo,
            onChanged: (enabled) => ref
                .read(repeatVideoEnabledProvider.notifier)
                .setEnabled(enabled),
          ),
          const Divider(),
          _SectionHeader(l10n.whatsappSection),
          ListTile(
            title: Text(l10n.statusArchiveTitle),
            subtitle: Text(l10n.statusArchiveSubtitle),
            trailing: _Dropdown<StatusArchiveRetention>(
              value: statusArchive,
              items: {
                StatusArchiveRetention.off: l10n.statusArchiveOff,
                StatusArchiveRetention.oneWeek: l10n.statusArchiveWeek,
                StatusArchiveRetention.oneMonth: l10n.statusArchiveMonth,
              },
              onChanged: (value) => ref
                  .read(statusArchiveRetentionProvider.notifier)
                  .setRetention(value),
              width: _dropdownAlignedWidth,
            ),
          ),
          const Divider(),
          _SectionHeader(l10n.saveLocationSection),
          ListTile(
            title: Text(l10n.saveLocationMediaTitle),
            subtitle: Text(l10n.saveLocationMediaSubtitle),
            trailing: _Dropdown<MediaSaveRoot>(
              value: mediaSaveRoot,
              items: {
                for (final root in MediaSaveRoot.values)
                  root: root.androidDirectoryName,
              },
              onChanged: (value) => _onMediaSaveRootChanged(context, ref, l10n, value),
              // Fixed so this row's arrow lines up with the audio row's
              // below regardless of which option is selected — see the
              // width param's doc on `_Dropdown`. Wide enough for the
              // longest label either dropdown can show ("Notifications").
              width: _dropdownAlignedWidth,
            ),
          ),
          ListTile(
            title: Text(l10n.saveLocationAudioTitle),
            subtitle: Text(l10n.saveLocationAudioSubtitle),
            trailing: _Dropdown<AudioSaveRoot>(
              value: audioSaveRoot,
              items: {
                for (final root in AudioSaveRoot.values)
                  root: root.androidDirectoryName,
              },
              onChanged: (value) => _onAudioSaveRootChanged(context, ref, l10n, value),
              width: _dropdownAlignedWidth,
            ),
          ),
          const Divider(),
          ListTile(
            title: Text(l10n.languageSection),
            trailing: _Dropdown<Locale?>(
              value: locale,
              items: {
                null: l10n.systemDefaultOption,
                const Locale('en'): 'English',
                const Locale('ru'): 'Русский',
                const Locale('kk'): 'Қазақша',
              },
              onChanged: (value) =>
                  ref.read(localeProvider.notifier).setLocale(value),
            ),
          ),
          const Divider(),
          _SectionHeader(l10n.aboutSection),
          ListTile(
            leading: const Icon(Icons.science_outlined),
            title: Text(l10n.betaNoticeTitle),
            subtitle: Text(l10n.betaNoticeBody),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(l10n.sourceCodeTitle),
            subtitle: const Text(kRepoDisplayUrl),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () =>
                ref.read(updateControllerProvider.notifier).openRepositoryPage(),
          ),
          ListTile(
            title: Text(l10n.whatsNewTitle),
            subtitle: Text(l10n.versionLabel(versionLabel)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ChangelogScreen()),
            ),
          ),
          const _UpdateRow(),
          const _YtDlpRow(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  void _setThemeMode(WidgetRef ref, ThemeMode? mode) {
    if (mode == null) return;
    ref.read(themeModeProvider.notifier).setThemeMode(mode);
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
  final fullyMoved =
      pending == null ? true : await service.completeMigrationAfterConsent(pending);

  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop(); // dismiss the busy dialog
  showAppToast(context, fullyMoved ? l10n.rootMoveDone : l10n.rootMoveIncomplete);
}

/// Compact dropdown for a settings row — takes far less vertical space than
/// a `RadioListTile` group when there are only a few mutually-exclusive
/// options, at the cost of the options not all being visible at once.
///
/// [width] is optional — without it (the default, every other row using
/// this) the button hugs its own selected label, so two rows whose values
/// differ in length (e.g. `Movies` vs `Music`) show their dropdown arrow at
/// different horizontal positions, which reads as misaligned when the rows
/// sit directly under each other (reported on-device 2026-09-13, the two
/// "Save location" rows). Passing a fixed [width] (with `isExpanded: true`)
/// pins the arrow to the same right edge on every row regardless of the
/// selected label's length, at the cost of a visible gap before the arrow
/// for a short label in a [width] sized for a longer one.
class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    this.width,
  });

  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final button = DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isDense: true,
        isExpanded: width != null,
        items: [
          for (final entry in items.entries)
            DropdownMenuItem<T>(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: (selected) {
          if (selected != null || items.containsKey(null)) {
            onChanged(selected as T);
          }
        },
      ),
    );
    return width == null ? button : SizedBox(width: width, child: button);
  }
}

/// "Check for updates" row. A tap kicks off **both** checks — the app
/// (GitHub release, [updateControllerProvider]) and the YouTube engine
/// ([ytDlpStatusProvider]) — in the background and returns immediately: the
/// row keeps showing the last known result the whole time, never a
/// blocking spinner. A short cosmetic pulse (≤2 s) acknowledges the tap;
/// the real network calls run their own timeouts unwatched and update the
/// row if and when anything changed. If an app update is found, the tap
/// opens [showUpdateSheet] instead.
class _UpdateRow extends ConsumerStatefulWidget {
  const _UpdateRow();

  @override
  ConsumerState<_UpdateRow> createState() => _UpdateRowState();
}

class _UpdateRowState extends ConsumerState<_UpdateRow> {
  bool _pulsing = false;
  Timer? _pulseTimer;

  @override
  void dispose() {
    _pulseTimer?.cancel();
    super.dispose();
  }

  void _startCheck() {
    // Fire-and-forget — neither call is awaited, nothing blocks.
    unawaited(ref.read(updateControllerProvider.notifier).checkNow());
    unawaited(ref.read(ytDlpStatusProvider.notifier).updateNow());
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

    final hasAppUpdate = appState is UpdateAvailable ||
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

/// Read-only "yt-dlp" line under [_UpdateRow] — just shows the installed
/// engine version and last-update result. The check/update action lives in
/// [_UpdateRow] now; this is here so the version is visible at a glance.
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
