import 'package:flutter/services.dart';

import '../logging/app_log.dart';

/// Where a notification tap should land: the Downloads screen for a
/// download still running, the Library tab for one already saved.
enum AppRoute { downloads, library }

/// Delivers notification-tap routes to the app shell. Two sources:
/// - the native notifications (yt-dlp service progress, "saved" summary)
///   carry the route as a `MainActivity` intent extra — drained once via
///   `getInitialRoute` on a cold start, pushed as `route` while running
///   (`android/.../AppRoutes.kt`, `MainActivity.kt`);
/// - `background_downloader`'s own notifications report taps through its
///   `taskNotificationTapCallback` (wired in `DownloadFinalizer`), which
///   calls [dispatch].
/// A route that arrives before the shell registered its handler is kept and
/// delivered on [init].
class AppRouteService {
  AppRouteService._();

  static final instance = AppRouteService._();

  static const _channel = MethodChannel('anywhere_downloader/app_route');

  void Function(AppRoute route)? _handler;
  AppRoute? _pending;

  /// Registers [handler] (call once, from `MainShell`) and delivers any
  /// route the app was cold-started with.
  void init(void Function(AppRoute route) handler) {
    _handler = handler;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'route') dispatchName(call.arguments as String?);
    });
    final pending = _pending;
    _pending = null;
    if (pending != null) handler(pending);
    _drainInitial();
  }

  Future<void> _drainInitial() async {
    try {
      dispatchName(await _channel.invokeMethod<String>('getInitialRoute'));
    } on MissingPluginException {
      // No native side (tests).
    } catch (e, st) {
      logError('AppRouteService.drainInitial', e, st);
    }
  }

  void dispatchName(String? name) {
    final route = switch (name) {
      'downloads' => AppRoute.downloads,
      'library' => AppRoute.library,
      _ => null,
    };
    if (route != null) dispatch(route);
  }

  void dispatch(AppRoute route) {
    final handler = _handler;
    if (handler == null) {
      _pending = route;
    } else {
      handler(route);
    }
  }
}
