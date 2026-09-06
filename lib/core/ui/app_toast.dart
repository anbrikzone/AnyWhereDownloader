import 'dart:async';

import 'package:flutter/material.dart';

/// A compact toast anchored to the **top** of the screen — replaces the
/// bottom `SnackBar`s, which overlapped the bottom nav bar on Home/Library
/// and looked dated. Slides in under the status bar, holds briefly, slides
/// out; tap to dismiss early. Only one shows at a time.
void showAppToast(BuildContext context, String message) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  _current?.call();

  late OverlayEntry entry;
  void remove() {
    entry.remove();
    if (_current == remove) _current = null;
  }

  entry = OverlayEntry(
    builder: (context) => _AppToast(
      message: message,
      onDismissed: remove,
      bindClose: (close) => _current = () {
        _current = null;
        close();
      },
    ),
  );
  _current = remove;
  overlay.insert(entry);
}

/// Dismisses whatever toast is currently showing (used to replace it with a
/// newer one immediately).
void Function()? _current;

class _AppToast extends StatefulWidget {
  const _AppToast({
    required this.message,
    required this.onDismissed,
    required this.bindClose,
  });

  final String message;
  final VoidCallback onDismissed;

  /// Hands the parent a callback that plays the exit animation then removes
  /// the entry — so a replacing toast can retire this one gracefully.
  final void Function(VoidCallback close) bindClose;

  @override
  State<_AppToast> createState() => _AppToastState();
}

class _AppToastState extends State<_AppToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _anim,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  Timer? _holdTimer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    widget.bindClose(_close);
    _anim.forward();
    final hold = (2000 + widget.message.length * 22).clamp(1800, 5000);
    _holdTimer = Timer(Duration(milliseconds: hold), _close);
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _holdTimer?.cancel();
    if (mounted) {
      await _anim.reverse();
    }
    widget.onDismissed();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _curve.dispose();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -1),
          end: Offset.zero,
        ).animate(_curve),
        child: FadeTransition(
          opacity: _curve,
          child: Center(
            child: GestureDetector(
              onTap: _close,
              child: Material(
                color: theme.colorScheme.inverseSurface,
                elevation: 6,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  child: Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onInverseSurface,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
