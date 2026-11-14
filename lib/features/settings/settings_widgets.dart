import 'package:flutter/material.dart';

/// Building blocks shared by the Settings hub and its section pages — the
/// rounded-card look of the 2026-11-14 redesign (variant B).

/// Small primary-colored label above a card.
class SettingsSectionLabel extends StatelessWidget {
  const SettingsSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// White (surface) rounded container; children are separated by hairlines.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children, this.padding});

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Title + optional subtitle with a trailing [Switch]; the whole row toggles.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      secondary: leading,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// A title/subtitle block followed by a full-width [SegmentedButton] — for a
/// setting with 2–3 short options, so every option is visible at once.
class SettingsSegmentRow<T> extends StatelessWidget {
  const SettingsSegmentRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.bodyLarge),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SegmentedButton<T>(
            segments: [
              for (final entry in options.entries)
                ButtonSegment<T>(
                  value: entry.key,
                  label: Text(
                    entry.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            selected: {value},
            showSelectedIcon: false,
            onSelectionChanged: (selected) => onChanged(selected.first),
          ),
        ],
      ),
    );
  }
}

/// Title/subtitle block followed by wrapping [ChoiceChip]s — for a setting
/// with more options than fit a segmented button (the save folders).
class SettingsChipsRow<T> extends StatelessWidget {
  const SettingsChipsRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.options,
    required this.onChanged,
    this.recommended,
    this.recommendedLabel,
  });

  final String title;
  final String? subtitle;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final T? recommended;
  final String? recommendedLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.bodyLarge),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in options.entries)
                ChoiceChip(
                  label: Text(
                    entry.key == recommended && recommendedLabel != null
                        ? '${entry.value} · $recommendedLabel'
                        : entry.value,
                  ),
                  selected: entry.key == value,
                  onSelected: (_) => onChanged(entry.key),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Rounded tonal square holding a section/row icon.
class SettingsIconBox extends StatelessWidget {
  const SettingsIconBox({
    super.key,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: foreground, size: 22),
    );
  }
}
