import 'package:flutter/material.dart';

import '../../core/l10n/status_message.dart';
import '../../core/ui/app_toast.dart';
import '../../l10n/app_localizations.dart';
import 'settings_screen.dart';

/// Shows a controller's [StatusMessage]: a toast normally, or — when the
/// failure looks like a stale yt-dlp ([StatusMessage.suggestYtDlpUpdate]) —
/// a dialog pointing at Settings' update check. yt-dlp never updates itself
/// on its own (user decision 2026-10-03), so this prompt is how a user
/// finds out an update would help.
void showStatusMessage(BuildContext context, StatusMessage message) {
  final l10n = AppLocalizations.of(context)!;
  if (!message.suggestYtDlpUpdate) {
    showAppToast(context, resolveStatusMessage(l10n, message));
    return;
  }
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.ytDlpOutdatedTitle),
      content: Text(l10n.ytDlpOutdatedBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.closeButton),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
          },
          child: Text(l10n.openSettingsButton),
        ),
      ],
    ),
  );
}
