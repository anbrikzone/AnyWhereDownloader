import 'package:flutter/services.dart';

/// Receives text shared into the app from another app's system "Share"
/// sheet (`ACTION_SEND` `text/plain`) — the natural way to hand a YouTube /
/// TikTok / WhatsApp / X / Instagram / LinkedIn link to a downloader
/// without copy-pasting.
///
/// Native side: `android/.../MainActivity.kt` on the
/// `anywhere_downloader/share_intent` channel. `getInitialSharedText`
/// returns (once) the text the app was cold-started with; the native side
/// pushes `sharedText` for a share that arrives while the app is already
/// running. Mirrors the thin-MethodChannel style of the other bridges
/// (`UpdateInstaller`, `MediaNotificationService`) rather than adding
/// `receive_sharing_intent`.
class ShareIntentService {
  ShareIntentService._();

  static final instance = ShareIntentService._();

  static const _channel = MethodChannel('anywhere_downloader/share_intent');

  void Function(String url)? _onShared;

  /// Registers [handler] for shared links and immediately drains any
  /// cold-start share. Call once, from the always-mounted shell
  /// (`HomeScreen`). Calling again just replaces the handler.
  void init(void Function(String url) handler) {
    _onShared = handler;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedText') {
        _dispatch(call.arguments as String?);
      }
    });
    _drainInitial();
  }

  Future<void> _drainInitial() async {
    try {
      _dispatch(await _channel.invokeMethod<String>('getInitialSharedText'));
    } catch (_) {
      // No share bridge (e.g. an older engine) or nothing to drain.
    }
  }

  void _dispatch(String? raw) {
    final url = extractFirstUrl(raw);
    if (url != null) _onShared?.call(url);
  }
}

/// Pulls the first `http(s)` URL out of shared text — apps often share
/// `"caption text … https://link … via App"`, not a bare URL. Trailing
/// punctuation that can't be part of a URL is trimmed. Returns null when
/// there's no URL.
String? extractFirstUrl(String? text) {
  if (text == null) return null;
  final match = RegExp(r'https?://[^\s]+').firstMatch(text);
  if (match == null) return null;
  var url = match.group(0)!;
  // Strip common trailing wrappers ("(https://x)", "link.", "url,").
  while (url.isNotEmpty && ')].,;"\''.contains(url[url.length - 1])) {
    url = url.substring(0, url.length - 1);
  }
  return url.isEmpty ? null : url;
}
