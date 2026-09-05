import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/extraction/media_extractor.dart';
import '../../core/settings/settings_providers.dart';
import '../../l10n/app_localizations.dart';

/// Brand names, deliberately untranslated (see CLAUDE.md "Multi-language
/// support").
const serviceLabels = {
  ServiceType.youtube: 'YouTube',
  ServiceType.whatsapp: 'WhatsApp',
  ServiceType.tiktok: 'TikTok',
  ServiceType.xTwitter: 'X / Twitter',
  ServiceType.instagram: 'Instagram',
  ServiceType.linkedin: 'LinkedIn',
};

/// Per-service enable/disable toggles, moved off the main Settings list into
/// their own screen so Settings stays compact (one "Services" row).
class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final enabled = ref.watch(enabledServicesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.servicesSection)),
      body: ListView(
        children: [
          for (final service in ServiceType.values)
            SwitchListTile(
              title: Text(serviceLabels[service] ?? service.name),
              value: enabled[service] ?? true,
              onChanged: (value) => ref
                  .read(enabledServicesProvider.notifier)
                  .setEnabled(service, value),
            ),
        ],
      ),
    );
  }
}
