import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/changelog/changelog.dart';
import '../../core/extraction/media_extractor.dart';
import '../../core/settings/settings_providers.dart';
import '../../core/update/update_providers.dart';
import '../../l10n/app_localizations.dart';
import 'changelog_screen.dart';
import 'services_screen.dart';
import 'update_sheet.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final themeMode = ref.watch(themeModeProvider);
    final enabledServices = ref.watch(enabledServicesProvider);
    final clipboardAutoPaste = ref.watch(clipboardAutoPasteEnabledProvider);
    final locale = ref.watch(localeProvider);

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
            title: Text(l10n.whatsNewTitle),
            subtitle: Text(l10n.versionLabel(kAppVersion)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ChangelogScreen()),
            ),
          ),
          const _UpdateRow(),
        ],
      ),
    );
  }

  void _setThemeMode(WidgetRef ref, ThemeMode? mode) {
    if (mode == null) return;
    ref.read(themeModeProvider.notifier).setThemeMode(mode);
  }
}

/// Compact dropdown for a settings row — takes far less vertical space than
/// a `RadioListTile` group when there are only a few mutually-exclusive
/// options, at the cost of the options not all being visible at once.
class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isDense: true,
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
  }
}

/// "Check for updates" row. Reflects [updateControllerProvider]: tapping
/// runs a check when idle, or opens [showUpdateSheet] once an update has
/// been found (or a previous attempt failed).
class _UpdateRow extends ConsumerWidget {
  const _UpdateRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(updateControllerProvider);
    final controller = ref.read(updateControllerProvider.notifier);

    final (subtitle, trailing, hasUpdate) = switch (state) {
      UpdateChecking() => (
          l10n.updateChecking,
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ) as Widget,
          false,
        ),
      UpdateUpToDate() => (l10n.updateUpToDate, null as Widget?, false),
      UpdateAvailable(:final info) =>
        (l10n.updateAvailable(info.version), null, true),
      UpdateDownloading() => (l10n.updateDownloadingLabel, null, true),
      UpdateReadyToInstall(:final info) =>
        (l10n.updateAvailable(info.version), null, true),
      UpdateError() => (l10n.updateFailed, null, true),
      _ => (null as String?, null as Widget?, false),
    };

    return ListTile(
      leading: hasUpdate
          ? Badge(
              child: const Icon(Icons.system_update_outlined),
            )
          : const Icon(Icons.system_update_outlined),
      title: Text(l10n.checkForUpdatesTitle),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: trailing,
      onTap: state is UpdateChecking
          ? null
          : () {
              if (hasUpdate) {
                showUpdateSheet(context);
              } else {
                controller.checkNow();
              }
            },
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
