import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../clipboard/clipboard_link_tracker.dart';
import '../theme/app_colors.dart';

/// The link card shared by Home and every service screen: a filled URL
/// field (Paste inside it while empty, Clear once filled) above one big
/// action button.
class LinkInputCard extends StatelessWidget {
  const LinkInputCard({
    super.key,
    required this.controller,
    required this.hintText,
    required this.buttonLabel,
    required this.buttonIcon,
    required this.onSubmit,
    required this.onClear,
    this.onPaste,
    this.errorText,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String hintText;
  final String buttonLabel;
  final Widget buttonIcon;
  final VoidCallback onSubmit;
  final VoidCallback onClear;

  /// Defaults to pasting the clipboard text into [controller].
  final VoidCallback? onPaste;
  final String? errorText;

  /// False while a fetch/download runs: field and buttons are disabled.
  final bool enabled;

  static const double _rowHeight = 48;
  static final _buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(20),
  );

  Future<void> _defaultPaste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    ClipboardLinkTracker.instance.markHandled(text);
    controller.text = text;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.cardSurface,
      borderRadius: BorderRadius.circular(28),
      elevation: 1,
      shadowColor: Colors.black26,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // One row on the same 8dp grid as the button below: a 48dp icon
            // box flush left, the field, and a 48dp-tall Paste (or Clear)
            // flush right — so the left/right edges line up with Download.
            SizedBox(
              height: _rowHeight,
              child: Row(
                children: [
                  SizedBox(
                    width: _rowHeight,
                    child: Icon(Icons.link, color: scheme.onSurfaceVariant),
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      enabled: enabled,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) {
                        if (enabled) onSubmit();
                      },
                      decoration: InputDecoration(
                        hintText: hintText,
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                      ),
                    ),
                  ),
                  ValueListenableBuilder(
                    valueListenable: controller,
                    builder: (context, value, _) => value.text.isEmpty
                        ? FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, _rowHeight),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              shape: _buttonShape,
                            ),
                            onPressed: enabled
                                ? (onPaste ?? _defaultPaste)
                                : null,
                            child: Text(l10n.pasteButton),
                          )
                        : SizedBox.square(
                            dimension: _rowHeight,
                            child: IconButton(
                              icon: const Icon(Icons.clear),
                              tooltip: l10n.clearTooltip,
                              onPressed: enabled ? onClear : null,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            if (errorText != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(_rowHeight, 2, 8, 2),
                child: Text(
                  errorText!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(_rowHeight),
                shape: _buttonShape,
              ),
              onPressed: enabled ? onSubmit : null,
              icon: buttonIcon,
              label: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}
