import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../extraction/media_extractor.dart';
import 'app_settings_service.dart';

/// Persisted theme choice. Starts at [ThemeMode.system] (the app's previous
/// hardcoded default) and loads the real persisted value asynchronously —
/// same "reasonable default, then correct once loaded" pattern as
/// `WhatsAppStatusController._init`.
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController({AppSettingsService? settingsService})
    : _settingsService = settingsService ?? AppSettingsService(),
      super(ThemeMode.system) {
    _init();
  }

  final AppSettingsService _settingsService;

  Future<void> _init() async {
    state = await _settingsService.getThemeMode();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await _settingsService.setThemeMode(mode);
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeController, ThemeMode>(
  (ref) => ThemeModeController(),
);

/// Per-service enable/disable map, read by `HomeScreen` (tile visibility)
/// and used to build `ExtractorRegistry` with only the enabled extractors.
/// Starts with every service enabled (matching the previous hardcoded
/// defaults) and loads persisted overrides asynchronously.
class EnabledServicesController extends StateNotifier<Map<ServiceType, bool>> {
  EnabledServicesController({AppSettingsService? settingsService})
    : _settingsService = settingsService ?? AppSettingsService(),
      super({for (final service in ServiceType.values) service: true}) {
    _init();
  }

  final AppSettingsService _settingsService;

  Future<void> _init() async {
    final loaded = <ServiceType, bool>{};
    for (final service in ServiceType.values) {
      loaded[service] = await _settingsService.isServiceEnabled(service);
    }
    state = loaded;
  }

  Future<void> setEnabled(ServiceType service, bool enabled) async {
    state = {...state, service: enabled};
    await _settingsService.setServiceEnabled(service, enabled);
  }
}

final enabledServicesProvider =
    StateNotifierProvider<EnabledServicesController, Map<ServiceType, bool>>(
      (ref) => EnabledServicesController(),
    );

/// Whether a recognized clipboard link is auto-inserted into a URL field
/// (`HomeScreen`/`YouTubeScreen`/`TikTokScreen`/`XTwitterScreen`/
/// `InstagramScreen` each check this before doing so). Starts `true` — the
/// previous hardcoded behavior — and loads the persisted value the same
/// "default now, correct once loaded" way as the other controllers here.
class ClipboardAutoPasteController extends StateNotifier<bool> {
  ClipboardAutoPasteController({AppSettingsService? settingsService})
    : _settingsService = settingsService ?? AppSettingsService(),
      super(true) {
    _init();
  }

  final AppSettingsService _settingsService;

  Future<void> _init() async {
    state = await _settingsService.getClipboardAutoPasteEnabled();
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await _settingsService.setClipboardAutoPasteEnabled(enabled);
  }
}

final clipboardAutoPasteEnabledProvider =
    StateNotifierProvider<ClipboardAutoPasteController, bool>(
      (ref) => ClipboardAutoPasteController(),
    );

/// Persisted UI language choice. Null means "System default" — `main.dart`
/// passes this straight through as `MaterialApp.locale`, so null lets
/// Flutter's own locale resolution pick the best match from
/// `AppLocalizations.supportedLocales` against the device locale. Starts
/// null (system default) and loads the real persisted value asynchronously,
/// same pattern as [ThemeModeController].
class LocaleController extends StateNotifier<Locale?> {
  LocaleController({AppSettingsService? settingsService})
    : _settingsService = settingsService ?? AppSettingsService(),
      super(null) {
    _init();
  }

  final AppSettingsService _settingsService;

  Future<void> _init() async {
    state = await _settingsService.getLocale();
  }

  Future<void> setLocale(Locale? locale) async {
    state = locale;
    await _settingsService.setLocale(locale);
  }
}

final localeProvider = StateNotifierProvider<LocaleController, Locale?>(
  (ref) => LocaleController(),
);
