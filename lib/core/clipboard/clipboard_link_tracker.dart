/// Tracks the last clipboard link that was either auto-inserted into a URL
/// field or explicitly dismissed (the user cleared the field), so it isn't
/// offered again — shared across screens (`HomeScreen`, `YouTubeScreen`)
/// since each has its own clipboard-check logic but a user's "no thanks"
/// on one screen should stick when they land on the other with the same
/// clipboard content still present.
class ClipboardLinkTracker {
  ClipboardLinkTracker._();

  static final instance = ClipboardLinkTracker._();

  String? _lastHandled;

  bool shouldOffer(String text) => text != _lastHandled;

  void markHandled(String text) => _lastHandled = text;

  /// Forget the last-handled link, so an identical URL copied again is
  /// offered afresh. Called when the user clears the URL field: clearing
  /// is "not this one right now", not "never auto-paste this string again"
  /// — and `_clearUrl` also wipes the system clipboard, which is what
  /// actually stops a stale clip being re-offered on the next cold start.
  void forget() => _lastHandled = null;
}
