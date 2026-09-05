import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/changelog/changelog.dart';
import '../../core/settings/settings_providers.dart';
import '../../l10n/app_localizations.dart';

/// "What's new" — the full [kChangelog] rendered newest-first. Reached from
/// the Settings "About" row. Note text is picked per the active app
/// language (falling back to English), independent of which `AppLocalizations`
/// strings the surrounding chrome uses.
class ChangelogScreen extends ConsumerWidget {
  const ChangelogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final localeCode = ref.watch(localeProvider)?.languageCode ??
        Localizations.localeOf(context).languageCode;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.whatsNewTitle)),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: kChangelog.length,
        separatorBuilder: (_, _) => const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Divider(height: 1),
        ),
        itemBuilder: (context, index) {
          final entry = kChangelog[index];
          return _EntryCard(entry: entry, localeCode: localeCode);
        },
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.localeCode});

  final ChangelogEntry entry;
  final String localeCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final grouped = entry.notesFor(localeCode);

    String labelFor(ChangeKind kind) => switch (kind) {
          ChangeKind.added => l10n.changelogAdded,
          ChangeKind.changed => l10n.changelogChanged,
          ChangeKind.fixed => l10n.changelogFixed,
        };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${entry.version}  ·  ${entry.date}',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        for (final kind in ChangeKind.values)
          if ((grouped[kind] ?? const []).isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              labelFor(kind),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            for (final note in grouped[kind]!)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: theme.textTheme.bodyMedium),
                    Expanded(
                      child: Text(note, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
          ],
      ],
    );
  }
}
