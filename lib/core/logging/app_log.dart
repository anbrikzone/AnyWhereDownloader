import 'package:flutter/foundation.dart';

/// Records an error that is deliberately swallowed (best-effort work whose
/// failure mustn't break the flow) so the reason still reaches logcat —
/// including in release builds: `adb logcat | grep AWD`. Without this a
/// silent `catch` left nothing to diagnose on-device.
void logError(String tag, Object error, [StackTrace? stack]) {
  debugPrint('[AWD][$tag] $error');
  if (stack != null) {
    // The top frames are enough to locate it; a full trace floods logcat.
    debugPrint(stack.toString().split('\n').take(6).join('\n'));
  }
}

/// A one-line diagnostic for on-device debugging (same `AWD` logcat tag as
/// [logError]) — for flows that silently decide *not* to act, such as the
/// clipboard auto-paste check.
void logInfo(String tag, String message) {
  debugPrint('[AWD][$tag] $message');
}
