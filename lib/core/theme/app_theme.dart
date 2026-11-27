import 'package:flutter/material.dart';

/// Material 3 light/dark themes from a teal seed.
class AppTheme {
  AppTheme._();

  static ThemeData light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
    scrollbarTheme: _scrollbar,
  );

  static ThemeData dark = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: Brightness.dark,
    ),
    scrollbarTheme: _scrollbar,
  );

  /// A slim thumb that widens only while it's being dragged, so it stays
  /// unobtrusive but is still easy to grab.
  static final _scrollbar = ScrollbarThemeData(
    thickness: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.dragged) ? 8 : 4,
    ),
    radius: const Radius.circular(4),
    crossAxisMargin: 2,
  );
}
