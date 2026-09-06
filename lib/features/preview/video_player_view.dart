import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// WhatsApp-style full-screen player controls over an already-initialized
/// [controller]. Shared by the Library and WhatsApp-status preview pages —
/// the host owns the controller (create / dispose / stuck-decoder recovery),
/// this widget only renders the surface + controls and drives playback.
///
/// Interaction model:
/// - tap anywhere → show / hide the controls overlay (never toggles play)
/// - centre play/pause button → toggles playback
/// - double-tap the left / right half → seek −10s / +10s, with a ripple
/// - drag the fat round scrubber thumb (it highlights while dragged) to seek
/// - the speed chip cycles 1× → 1.5× → 2×
class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({
    super.key,
    required this.controller,
    this.isAudio = false,
  });

  final VideoPlayerController controller;

  /// Audio has no picture — show an art placeholder + a centred transport
  /// row instead of the full-bleed video stack.
  final bool isAudio;

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView>
    with SingleTickerProviderStateMixin {
  static const _speeds = <double>[1.0, 1.5, 2.0];
  static const _autoHide = Duration(seconds: 3);
  static const _seekStep = Duration(seconds: 10);

  bool _controlsVisible = true;
  Timer? _hideTimer;
  Duration? _scrubPreview;
  double _speed = 1.0;

  // Double-tap seek ripple.
  late final AnimationController _seekFx = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );
  bool _seekFxLeft = true;
  Offset? _doubleTapLocal;

  VideoPlayerController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onTick);
    _restartHideTimer();
  }

  @override
  void didUpdateWidget(VideoPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTick);
      _c.addListener(_onTick);
      // A stuck-decoder recovery swaps in a fresh controller at 1×; keep the
      // user's chosen speed.
      if (_speed != 1.0) _c.setPlaybackSpeed(_speed);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onTick);
    _hideTimer?.cancel();
    _seekFx.dispose();
    super.dispose();
  }

  void _onTick() {
    // Keep the controls up once playback ends so the replay button is
    // reachable; otherwise let the auto-hide timer run.
    if (_c.value.isCompleted && !_controlsVisible && mounted) {
      setState(() => _controlsVisible = true);
    }
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    if (_c.value.isPlaying) {
      _hideTimer = Timer(_autoHide, () {
        if (mounted) setState(() => _controlsVisible = false);
      });
    }
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _restartHideTimer();
  }

  void _togglePlay() {
    setState(() {
      if (_c.value.isPlaying) {
        _c.pause();
        _controlsVisible = true;
        _hideTimer?.cancel();
      } else {
        _c.play();
        _controlsVisible = true;
        _restartHideTimer();
      }
    });
  }

  void _seekRelative(Duration offset) {
    final d = _c.value.duration;
    var target = _c.value.position + offset;
    if (target < Duration.zero) target = Duration.zero;
    if (target > d) target = d;
    _c.seekTo(target);
    _restartHideTimer();
  }

  void _handleDoubleTap() {
    final width = context.size?.width ?? MediaQuery.of(context).size.width;
    final left = (_doubleTapLocal?.dx ?? width / 2) < width / 2;
    setState(() => _seekFxLeft = left);
    _seekFx.forward(from: 0);
    _seekRelative(left ? -_seekStep : _seekStep);
  }

  void _cycleSpeed() {
    setState(() {
      _speed = _speeds[(_speeds.indexOf(_speed) + 1) % _speeds.length];
    });
    _c.setPlaybackSpeed(_speed);
    _restartHideTimer();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isAudio) return _buildAudio();
    return _buildVideo();
  }

  // ---- video ---------------------------------------------------------------

  Widget _buildVideo() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      onDoubleTapDown: (d) => _doubleTapLocal = d.localPosition,
      onDoubleTap: _handleDoubleTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _c.value.aspectRatio == 0
                  ? 16 / 9
                  : _c.value.aspectRatio,
              child: VideoPlayer(_c),
            ),
          ),

          // Double-tap seek ripple, on the tapped half.
          Positioned.fill(
            child: _SeekRipple(animation: _seekFx, left: _seekFxLeft),
          ),

          // Centre play/pause — always up while paused, otherwise with the
          // rest of the controls.
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: _c,
            builder: (context, value, _) {
              final show = _controlsVisible || !value.isPlaying;
              return IgnorePointer(
                ignoring: !show,
                child: AnimatedOpacity(
                  opacity: show ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Center(
                    child: _RoundIconButton(
                      icon: value.isPlaying
                          ? Icons.pause
                          : (value.isCompleted
                                ? Icons.replay
                                : Icons.play_arrow),
                      size: 44,
                      onTap: _togglePlay,
                    ),
                  ),
                ),
              );
            },
          ),

          // Skip ±10 buttons on the centre line.
          if (_controlsVisible)
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(
                    child: Center(
                      child: _RoundIconButton(
                        icon: Icons.replay_10,
                        size: 34,
                        onTap: () {
                          setState(() => _seekFxLeft = true);
                          _seekFx.forward(from: 0);
                          _seekRelative(-_seekStep);
                        },
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: _RoundIconButton(
                        icon: Icons.forward_10,
                        size: 34,
                        onTap: () {
                          setState(() => _seekFxLeft = false);
                          _seekFx.forward(from: 0);
                          _seekRelative(_seekStep);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Bottom transport bar, pinned to the screen edge.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedSlide(
              offset: _controlsVisible ? Offset.zero : const Offset(0, 1),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: _bottomBar(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black54],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 10, 8),
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: _c,
            builder: (context, value, _) {
              final pos = _scrubPreview ?? value.position;
              return Row(
                children: [
                  Text(
                    _fmt(pos),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ScrubBar(
                      controller: _c,
                      onPositionPreview: (p) =>
                          setState(() => _scrubPreview = p),
                      onInteraction: _restartHideTimer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _fmt(value.duration),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _SpeedButton(speed: _speed, onTap: _cycleSpeed),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ---- audio --------------------------------------------------------------

  Widget _buildAudio() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.music_note, size: 120, color: Colors.white24),
          const SizedBox(height: 44),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: _c,
            builder: (context, value, _) => Text(
              '${_fmt(_scrubPreview ?? value.position)} / ${_fmt(value.duration)}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          const SizedBox(height: 8),
          _ScrubBar(
            controller: _c,
            onPositionPreview: (p) => setState(() => _scrubPreview = p),
            onInteraction: () {},
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: _c,
                builder: (context, value, _) => IconButton(
                  iconSize: 64,
                  color: Colors.white,
                  icon: Icon(
                    value.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                  ),
                  onPressed: () =>
                      value.isPlaying ? _c.pause() : _c.play(),
                ),
              ),
              const SizedBox(width: 12),
              _SpeedButton(speed: _speed, onTap: _cycleSpeed),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  }
}

/// Circular translucent icon button with a quick tap scale-bounce.
class _RoundIconButton extends StatefulWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.size = 40,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  State<_RoundIconButton> createState() => _RoundIconButtonState();
}

class _RoundIconButtonState extends State<_RoundIconButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.86 : 1,
        duration: const Duration(milliseconds: 90),
        child: Container(
          padding: EdgeInsets.all(widget.size * 0.28),
          decoration: const BoxDecoration(
            color: Colors.black45,
            shape: BoxShape.circle,
          ),
          child: Icon(widget.icon, color: Colors.white, size: widget.size),
        ),
      ),
    );
  }
}

/// The "±10s" feedback for a double-tap: an expanding circle on one screen
/// half plus the skip icon, fading out.
class _SeekRipple extends StatelessWidget {
  const _SeekRipple({required this.animation, required this.left});

  final Animation<double> animation;
  final bool left;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = animation.value;
          if (t == 0 || t == 1) return const SizedBox.shrink();
          final opacity = (1 - t).clamp(0.0, 1.0);
          return Align(
            alignment: left ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Opacity(
                opacity: opacity,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10 * opacity),
                    borderRadius: BorderRadius.horizontal(
                      left: left
                          ? Radius.zero
                          : const Radius.circular(1000),
                      right: left
                          ? const Radius.circular(1000)
                          : Radius.zero,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        left ? Icons.fast_rewind : Icons.fast_forward,
                        color: Colors.white,
                        size: 34,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        left ? '-10s' : '+10s',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The 1× / 1.5× / 2× chip.
class _SpeedButton extends StatelessWidget {
  const _SpeedButton({required this.speed, required this.onTap});

  final double speed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = speed == speed.roundToDouble()
        ? '${speed.toStringAsFixed(1)}x'
        : '${speed}x';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Fat track, round drag-highlighted thumb. Throttles real `seekTo()` while
/// dragging (unthrottled per-event seeks can wedge some hardware H.264
/// decoders — see the preview pages' stuck-decoder recovery), always seeks
/// precisely on release, and owns pause-during-drag / resume-after (captured
/// at drag start, not inferred).
class _ScrubBar extends StatefulWidget {
  const _ScrubBar({
    required this.controller,
    required this.onPositionPreview,
    required this.onInteraction,
  });

  final VideoPlayerController controller;

  /// Live drag target while dragging, `null` once it ends.
  final ValueChanged<Duration?> onPositionPreview;

  /// Any touch on the bar — lets the host restart its controls auto-hide.
  final VoidCallback onInteraction;

  @override
  State<_ScrubBar> createState() => _ScrubBarState();
}

class _ScrubBarState extends State<_ScrubBar> {
  static const _throttle = Duration(milliseconds: 400);
  static const _track = 5.0;
  static const _thumb = 14.0;
  static const _thumbActive = 22.0;
  static const _row = 26.0;

  Duration? _dragPosition;
  DateTime? _lastSeekAt;
  Timer? _pendingSeek;
  bool _wasPlaying = false;
  bool _dragging = false;

  Duration _positionFromDx(double dx, double width) {
    final duration = widget.controller.value.duration;
    if (width <= 0 || duration == Duration.zero) return Duration.zero;
    final fraction = (dx / width).clamp(0.0, 1.0);
    return duration * fraction;
  }

  void _throttledSeek(Duration target) {
    final now = DateTime.now();
    final last = _lastSeekAt;
    final elapsed = last == null ? _throttle : now.difference(last);
    if (elapsed >= _throttle) {
      _pendingSeek?.cancel();
      _lastSeekAt = now;
      widget.controller.seekTo(target);
      return;
    }
    _pendingSeek?.cancel();
    _pendingSeek = Timer(_throttle - elapsed, () {
      _lastSeekAt = DateTime.now();
      widget.controller.seekTo(target);
    });
  }

  void _onDragStart(double dx, double width) {
    _wasPlaying = widget.controller.value.isPlaying;
    widget.controller.pause();
    final target = _positionFromDx(dx, width);
    setState(() {
      _dragging = true;
      _dragPosition = target;
    });
    widget.onPositionPreview(target);
    widget.onInteraction();
    _throttledSeek(target);
  }

  void _onDragUpdate(double dx, double width) {
    final target = _positionFromDx(dx, width);
    setState(() => _dragPosition = target);
    widget.onPositionPreview(target);
    _throttledSeek(target);
  }

  Future<void> _onDragEnd() async {
    _pendingSeek?.cancel();
    final target = _dragPosition;
    if (target != null) await widget.controller.seekTo(target);
    if (!mounted) return;
    setState(() {
      _dragging = false;
      _dragPosition = null;
    });
    widget.onPositionPreview(null);
    if (_wasPlaying) await widget.controller.play();
    widget.onInteraction();
  }

  @override
  void dispose() {
    _pendingSeek?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            widget.onInteraction();
            _throttledSeek(_positionFromDx(d.localPosition.dx, width));
          },
          onHorizontalDragStart: (d) =>
              _onDragStart(d.localPosition.dx, width),
          onHorizontalDragUpdate: (d) =>
              _onDragUpdate(d.localPosition.dx, width),
          onHorizontalDragEnd: (_) => _onDragEnd(),
          onHorizontalDragCancel: _onDragEnd,
          child: SizedBox(
            width: width,
            height: _row,
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: widget.controller,
              builder: (context, value, _) {
                final duration = value.duration;
                final position = _dragPosition ?? value.position;
                final fraction = duration == Duration.zero
                    ? 0.0
                    : (position.inMilliseconds / duration.inMilliseconds)
                          .clamp(0.0, 1.0);
                final thumbSize = _dragging ? _thumbActive : _thumb;
                final centerX = fraction * width;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Align(
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: width,
                        height: _track,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(_track / 2),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              const ColoredBox(color: Colors.white24),
                              FractionallySizedBox(
                                widthFactor: fraction,
                                alignment: Alignment.centerLeft,
                                child: ColoredBox(color: accent),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Halo while dragging.
                    if (_dragging)
                      Positioned(
                        left: (centerX - (_thumbActive + 12) / 2).clamp(
                          0.0,
                          width - (_thumbActive + 12),
                        ),
                        top: (_row - (_thumbActive + 12)) / 2,
                        child: Container(
                          width: _thumbActive + 12,
                          height: _thumbActive + 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent.withValues(alpha: 0.30),
                          ),
                        ),
                      ),
                    Positioned(
                      left: (centerX - thumbSize / 2).clamp(
                        0.0,
                        width - thumbSize,
                      ),
                      top: (_row - thumbSize) / 2,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: thumbSize,
                        height: thumbSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: const [
                            BoxShadow(color: Colors.black45, blurRadius: 3),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
