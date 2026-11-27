import 'package:flutter/material.dart';

/// App-wide color roles on top of the Material 3 [ColorScheme].
extension AppColors on ColorScheme {
  /// Background for raised cards and tiles. In light mode a white card on
  /// the tinted page; in dark mode a step *lighter* than the page (M3
  /// elevation reads as lighter in dark) — `surfaceContainerLowest` there
  /// is darker than the page and made cards look like holes.
  Color get cardSurface => brightness == Brightness.dark
      ? surfaceContainerHigh
      : surfaceContainerLowest;
}
