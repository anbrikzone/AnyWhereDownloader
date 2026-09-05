import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../extraction/media_extractor.dart';

/// How long auto-archived WhatsApp statuses are kept before the opportunistic
/// cleanup (on WhatsApp-screen refresh) deletes them. [off] disables the
/// whole feature.
enum StatusArchiveRetention {
  off,
  oneWeek,
  oneMonth;

  Duration get duration => switch (this) {
        StatusArchiveRetention.off => Duration.zero,
        StatusArchiveRetention.oneWeek => const Duration(days: 7),
        StatusArchiveRetention.oneMonth => const Duration(days: 30),
      };
}

/// Thin wrapper around `shared_preferences` for user-facing settings —
/// mirrors `SafService`'s style (isolates the plugin behind plain get/set
/// methods so the rest of the app never touches `SharedPreferences`
/// directly).
class AppSettingsService {
  static const _themeModeKey = 'settings_theme_mode';
  static const _serviceEnabledPrefix = 'settings_service_enabled_';
  static const _clipboardAutoPasteKey = 'settings_clipboard_auto_paste';
  static const _localeKey = 'settings_locale';
  static const _lastUpdateCheckKey = 'settings_last_update_check_ms';
  static const _statusArchiveRetentionKey = 'settings_status_archive_retention';
  static const _archivedStatusLedgerKey = 'settings_archived_status_ledger';

  Future<ThemeMode> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_themeModeKey);
    return switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.name);
  }

  /// Every service defaults to enabled — matches the hardcoded defaults
  /// every service has had up to now.
  Future<bool> isServiceEnabled(ServiceType service) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_serviceEnabledPrefix${service.name}') ?? true;
  }

  Future<void> setServiceEnabled(ServiceType service, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_serviceEnabledPrefix${service.name}', enabled);
  }

  /// Defaults to `true` — matches the previously-hardcoded behavior (see
  /// "Home URL bar / clipboard / download engine round 2" in CLAUDE.md),
  /// now made an explicit user choice instead.
  Future<bool> getClipboardAutoPasteEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_clipboardAutoPasteKey) ?? true;
  }

  Future<void> setClipboardAutoPasteEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_clipboardAutoPasteKey, enabled);
  }

  /// Null means "System default" — `MaterialApp.locale` then lets Flutter
  /// resolve the best match from `supportedLocales` against the device
  /// locale itself, rather than this app pinning one.
  Future<Locale?> getLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_localeKey);
    return stored == null ? null : Locale(stored);
  }

  Future<void> setLocale(Locale? locale) async {
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_localeKey);
    } else {
      await prefs.setString(_localeKey, locale.languageCode);
    }
  }

  /// When the app last completed a GitHub-release update check. Null if it
  /// never has. Used to throttle the silent cold-start check to ≤ once/day.
  Future<DateTime?> getLastUpdateCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_lastUpdateCheckKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setLastUpdateCheck(DateTime when) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastUpdateCheckKey, when.millisecondsSinceEpoch);
  }

  /// WhatsApp status auto-archive retention. Defaults to [off] — opt-in.
  Future<StatusArchiveRetention> getStatusArchiveRetention() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_statusArchiveRetentionKey);
    return StatusArchiveRetention.values.firstWhere(
      (v) => v.name == stored,
      orElse: () => StatusArchiveRetention.off,
    );
  }

  Future<void> setStatusArchiveRetention(StatusArchiveRetention value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_statusArchiveRetentionKey, value.name);
  }

  /// Dedup ledger for the archiver: status filename -> epoch millis it was
  /// archived. JSON-encoded to a single string.
  Future<Map<String, int>> getArchivedStatusLedger() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_archivedStatusLedgerKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  Future<void> setArchivedStatusLedger(Map<String, int> ledger) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_archivedStatusLedgerKey, jsonEncode(ledger));
  }
}
