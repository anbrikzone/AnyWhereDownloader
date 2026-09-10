import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
/// A texture-mode `VideoPlayer` in an `AspectRatio` box that hides the thin
/// green edge some hardware decoders bleed along the right / bottom of the
/// frame. Used by the **long-press peek previews only** — the full-screen
/// player (`VideoPlayerView`) renders through a native ExoPlayer surface
/// (`VideoViewType.platformView`) instead, which has no such artefact.
///
/// The cause is sub-pixel: when the video texture is laid out a fraction
/// larger than the decoded frame, the GPU's bilinear sampler reads past the
/// valid luma/chroma into undefined YUV (Y≈U≈V≈0), which converts to green.
/// Fix: paint the picture a hair (`_overscan`) larger than its box and let
/// the box clip it, so the bad edge falls just outside the visible area.
/// The crop is ~0.5% per side — visually nil, and only ever hides the
/// artefact strip, never real content.
class VideoSurface extends StatelessWidget {
  const VideoSurface(this.controller, {super.key, this.aspectRatioOverride});

  final VideoPlayerController controller;

  /// Ratio to use instead of the controller's own (for callers tracking a
  /// late-settling value). Falls back to 16∶9 until a real ratio arrives.
  final double? aspectRatioOverride;

  static const double _overscan = 1.01;

  @override
  Widget build(BuildContext context) {
    final raw = aspectRatioOverride ?? controller.value.aspectRatio;
    return AspectRatio(
      aspectRatio: raw > 0 ? raw : 16 / 9,
      child: ClipRect(
        child: Transform.scale(
          scale: _overscan,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}

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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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
  bool _wasPlaying = false;

  /// Last video aspect ratio we rendered with. The decoded size — and its
  /// rotation correction — can land a frame or two after `initialize()`,
  /// and [_onTick] otherwise never rebuilds for it, so a rotated/vertical
  /// clip stays stretched until some unrelated `setState`.
  double _lastAspect = 0;

  /// Whether this widget currently holds the screen-awake lock (so it only
  /// toggles it on a real change, and releases exactly what it acquired).
  bool _awake = false;

  VideoPlayerController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c.addListener(_onTick);
    _restartHideTimer();
    _syncWakelock();
  }

  /// Keep the screen on while media is actually playing; let it sleep as
  /// soon as it pauses / ends / this page goes away.
  void _syncWakelock({bool? force}) {
    final want = force ?? (mounted && _c.value.isPlaying);
    if (want == _awake) return;
    _awake = want;
    WakelockPlus.toggle(enable: want);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Never leave the wakelock held while backgrounded.
    if (state != AppLifecycleState.resumed) {
      _syncWakelock(force: false);
    } else {
      _syncWakelock();
    }
  }

  @override
  void didUpdateWidget(VideoPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTick);
      _c.addListener(_onTick);
      // Re-pick up the new controller's aspect ratio on the next tick.
      _lastAspect = 0;
      // A stuck-decoder recovery swaps in a fresh controller at 1×; keep the
      // user's chosen speed.
      if (_speed != 1.0) _c.setPlaybackSpeed(_speed);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.removeListener(_onTick);
    _hideTimer?.cancel();
    _seekFx.dispose();
    _syncWakelock(force: false);
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    // Rebuild when the video's aspect ratio settles (see [_lastAspect]).
    final aspect = _c.value.aspectRatio;
    if (aspect != _lastAspect) {
      _lastAspect = aspect;
      setState(() {});
    }
    // Keep the controls up once playback ends so the replay button is
    // reachable; otherwise let the auto-hide timer run.
    if (_c.value.isCompleted && !_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    // Playback just started (e.g. the host activated this page after a
    // swipe settled) — begin the auto-hide countdown.
    final playing = _c.value.isPlaying;
    if (playing && !_wasPlaying) _restartHideTimer();
    _wasPlaying = playing;
    _syncWakelock();
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
        // After the video has ended (repeat off), the centre button is a
        // Replay — rewind before playing, or play() just no-ops at the end.
        if (_c.value.isCompleted) _c.seekTo(Duration.zero);
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
          // The host builds this player's controller with
          // `VideoViewType.platformView` — a native ExoPlayer surface that
          // applies the codec crop rectangle itself, so no `VideoSurface`
          // overscan-clip is needed here (that's only for the texture-mode
          // peek previews).
          Center(
            child: AspectRatio(
              aspectRatio: _c.value.aspectRatio > 0 ? _c.value.aspectRatio : 16 / 9,
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

/// Fat track, round drag-highlighted thumb. **Does not seek while dragging**
/// — only the thumb and the time label track the finger; one real `seekTo()`
/// runs on release. (Seeking on every drag frame, even throttled, flushes
/// some hardware H.264 decoders into a stall — see the preview pages'
/// stuck-decoder recovery.) Owns pause-during-scrub / resume-after (captured
/// once, guarded by `_pausedByScrub`), shared with the tap-to-seek path.
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
  // A tap-to-seek keeps playback paused this long after the seek before it
  // resumes — a beat for the decoder to present the target frame, and a
  // window for a drag that's really the second half of a tap-then-grab
  // gesture to take over the pause first.
  static const _tapSettle = Duration(milliseconds: 120);
  static const _track = 5.0;
  static const _thumb = 14.0;
  static const _thumbActive = 22.0;
  static const _row = 26.0;

  Duration? _dragPosition;
  Timer? _tapReleaseTimer;
  bool _wasPlaying = false;
  bool _dragging = false;

  /// True while *this* widget holds the controller paused for a scrub (tap
  /// or drag) and still owes it a resume. A drag starting right after a tap
  /// must not re-read `isPlaying` here — it's already false — or the resume
  /// after the drag is lost and the video sits frozen. [_wasPlaying] is
  /// captured once, when the pause is first taken.
  bool _pausedByScrub = false;

  Duration _positionFromDx(double dx, double width) {
    final duration = widget.controller.value.duration;
    if (width <= 0 || duration == Duration.zero) return Duration.zero;
    final fraction = (dx / width).clamp(0.0, 1.0);
    return duration * fraction;
  }

  /// Pause the controller for a scrub and remember whether it was playing —
  /// idempotent, so a tap immediately followed by a drag captures the state
  /// exactly once.
  void _takeoverPause() {
    if (_pausedByScrub) return;
    _wasPlaying = widget.controller.value.isPlaying;
    _pausedByScrub = true;
    widget.controller.pause();
  }

  /// Undo [_takeoverPause] — resume playback iff it was playing when the
  /// scrub began.
  Future<void> _releaseResume() async {
    if (!_pausedByScrub) return;
    _pausedByScrub = false;
    if (_wasPlaying) await widget.controller.play();
  }

  /// A single tap on the track: pause, seek once, resume after [_tapSettle]
  /// — the same pause/resume ownership a drag uses, not a bare `seekTo()` on
  /// the still-playing controller (which, chained into a drag that follows,
  /// was stalling the decoder).
  void _onTapSeek(double dx, double width) {
    final target = _positionFromDx(dx, width);
    widget.onInteraction();
    _takeoverPause();
    setState(() => _dragPosition = target);
    widget.onPositionPreview(target);
    widget.controller.seekTo(target);
    _tapReleaseTimer?.cancel();
    _tapReleaseTimer = Timer(_tapSettle, () async {
      // A drag that began inside the settle window cancelled this timer and
      // now owns the pause/resume; this only runs for a lone tap.
      if (!mounted) return;
      setState(() => _dragPosition = null);
      widget.onPositionPreview(null);
      await _releaseResume();
      widget.onInteraction();
    });
  }

  void _onDragStart(double dx, double width) {
    _tapReleaseTimer?.cancel();
    _takeoverPause();
    final target = _positionFromDx(dx, width);
    setState(() {
      _dragging = true;
      _dragPosition = target;
    });
    widget.onPositionPreview(target);
    widget.onInteraction();
    // No seek here or in _onDragUpdate — only the thumb and the time label
    // follow the finger. The one real seek runs on release; per-frame seeks
    // are the flush storm that stalls the hardware decoder.
  }

  void _onDragUpdate(double dx, double width) {
    final target = _positionFromDx(dx, width);
    setState(() => _dragPosition = target);
    widget.onPositionPreview(target);
  }

  Future<void> _onDragEnd() async {
    _tapReleaseTimer?.cancel();
    final target = _dragPosition;
    if (target != null) await widget.controller.seekTo(target);
    if (!mounted) return;
    setState(() {
      _dragging = false;
      _dragPosition = null;
    });
    widget.onPositionPreview(null);
    await _releaseResume();
    widget.onInteraction();
  }

  @override
  void dispose() {
    _tapReleaseTimer?.cancel();
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
          onTapDown: (d) => _onTapSeek(d.localPosition.dx, width),
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
