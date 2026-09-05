import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Lets the user edit the suggested filename before a download starts.
/// Returns null if cancelled. Not YouTube-specific — reusable by
/// Instagram/X later.
Future<String?> showRenameDialog({
  required BuildContext context,
  required String initialName,
}) {
  final controller = TextEditingController(text: initialName);
  return showDialog<String>(
    context: context,
    builder: (context) {
      final l10n = AppLocalizations.of(context)!;
      return AlertDialog(
        title: Text(l10n.saveAsTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.fileNameLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              Navigator.of(context).pop(name.isEmpty ? initialName : name);
            },
            child: Text(l10n.downloadButton),
          ),
        ],
      );
    },
  );
}
