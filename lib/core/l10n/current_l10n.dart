import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';

/// The app's active [AppLocalizations], for code with no `BuildContext` —
/// mainly notification text built by controllers and handed to native code.
/// Kept current by `MaterialApp.builder` (`main.dart`), so it follows the
/// in-app language choice, not just the system locale — which is also why
/// native notification strings come from here rather than Android `values-*`
/// resources (those only follow the system language).
class CurrentL10n {
  CurrentL10n._();

  static AppLocalizations? _value;

  static AppLocalizations get value =>
      _value ?? lookupAppLocalizations(const Locale('en'));

  /// Returns true when the active language actually changed (including the
  /// very first call), so the caller can re-apply locale-dependent config.
  static bool update(AppLocalizations l10n) {
    if (_value?.localeName == l10n.localeName) return false;
    _value = l10n;
    return true;
  }
}
