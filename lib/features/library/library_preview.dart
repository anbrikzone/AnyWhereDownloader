import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

/// Full-screen preview, pushed on tap. A `PageView` over [assets] from
/// [initialIndex] lets the user swipe between items; its lazy page
/// build/dispose keeps only one or two `VideoPlayerController`s alive.
class LibraryPreviewPage extends StatefulWidget {
  const LibraryPreviewPage({
    super.key,
    required this.assets,
    required this.initialIndex,
  });

  final List<AssetEntity> assets;
  final int initialIndex;

  @override
  State<LibraryPreviewPage> createState() => _LibraryPreviewPageState();
}

class _LibraryPreviewPageState extends State<LibraryPreviewPage> {
  late final PageController _pageController = PageController(
    initialPage: widget.initialIndex,
  );
  late int _currentIndex = widget.initialIndex;

  // True while the current image is zoomed in (or a two-finger pinch is in
  // progress) — freezes page swiping so the gesture pans/zooms the image
  // instead of flicking to the next item.
  bool _pageLocked = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: widget.assets.length > 1
            ? Text(
                '${_currentIndex + 1} / ${widget.assets.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              )
            : null,
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.assets.length,
        physics: _pageLocked
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(),
        onPageChanged: (index) => setState(() {
          _currentIndex = index;
          _pageLocked = false;
        }),
        itemBuilder: (context, index) => _LibraryPreviewItem(
          key: ValueKey(widget.assets[index].id),
          asset: widget.assets[index],
          onZoomChanged: (zoomed) {
            if (zoomed != _pageLocked) setState(() => _pageLocked = zoomed);
          },
        ),
      ),
    );
  }
}

/// One swipeable page: the image or video player plus its controls.
class _LibraryPreviewItem extends StatefulWidget {
  const _LibraryPreviewItem({
    super.key,
    required this.asset,
    this.onZoomChanged,
  });

  final AssetEntity asset;

  /// Fired by the zoomable image when it zooms in/out (or a pinch starts/
  /// ends) so the parent can freeze/unfreeze page swiping.
  final ValueChanged<bool>? onZoomChanged;

  @override
  State<_LibraryPreviewItem> createState() => _LibraryPreviewItemState();
}

class _LibraryPreviewItemState extends State<_LibraryPreviewItem> {
  File? _file;
  File? _videoFile;
  VideoPlayerController? _videoController;
  bool _loading = true;

  // Seek/time controls: hidden until the video is tapped, then auto-hide
  // after a few seconds — but only while playing (nothing to declutter
  // while paused).
  bool _controlsVisible = false;
  Timer? _hideControlsTimer;

  // Drag target while scrubbing, so the time label tracks the thumb rather
  // than the throttled playback position.
  Duration? _previewPosition;

  // Brief pause-icon flash on an explicit tap-to-play (not on _ScrubBar's
  // auto-resume) — a quick "playing now" acknowledgement.
  bool _pauseFlashVisible = false;
  Timer? _pauseFlashTimer;

  void _flashPauseIcon() {
    _pauseFlashTimer?.cancel();
    setState(() => _pauseFlashVisible = true);
    _pauseFlashTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() => _pauseFlashVisible = false);
    });
  }

  // Rapid scrubbing can wedge some Android hardware H.264 decoders (Exynos
  // seen via logcat): playback reports `isPlaying: true` but no frames
  // advance, and no `play()`/`pause()` recovers it — only recreating the
  // controller (as a screen off/on cycle does) does. `_scheduleStuckCheck`/
  // `_checkStuck` detect the stall; `_recoverFromStuckDecoder` rebuilds the
  // controller at the same position. `_ScrubBar` throttling makes it rare
  // but not impossible. Full history in CLAUDE.md "Library".
  Timer? _stuckCheckTimer;
  Duration? _lastStuckCheckPosition;
  bool _recovering = false;

  void _scheduleStuckCheck() {
    _stuckCheckTimer?.cancel();
    _stuckCheckTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _checkStuck(),
    );
  }

  Future<void> _checkStuck() async {
    if (_recovering || !mounted) return;
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    final value = controller.value;
    if (!value.isPlaying || value.isBuffering) {
      // Not expected to be advancing right now (paused, mid-drag, or
      // genuinely buffering) — don't compare across this gap once playback
      // resumes, or a legitimate pause would look like a freeze.
      _lastStuckCheckPosition = null;
      return;
    }
    final position = value.position;
    final lastPosition = _lastStuckCheckPosition;
    _lastStuckCheckPosition = position;
    if (lastPosition != null &&
        (position - lastPosition).abs() < const Duration(milliseconds: 200)) {
      await _recoverFromStuckDecoder();
    }
  }

  Future<void> _recoverFromStuckDecoder() async {
    final oldController = _videoController;
    final file = _videoFile;
    if (oldController == null || file == null) return;
    _recovering = true;
    final resumePosition = oldController.value.position;
    try {
      final newController = VideoPlayerController.file(file);
      await newController.initialize();
      if (!mounted) {
        await newController.dispose();
        return;
      }
      await newController.seekTo(resumePosition);
      _attachController(newController);
      await oldController.dispose();
      setState(() => _videoController = newController);
    } finally {
      _recovering = false;
      _lastStuckCheckPosition = null;
    }
  }

  // Shared by both the initial load and stuck-recovery paths, so the two
  // can't drift apart (autoplay/looping/volume/mute-watchdog setup).
  void _attachController(VideoPlayerController controller) {
    controller
      ..setLooping(true)
      ..setVolume(1)
      ..play();
    // Watchdog: a controller started while another is still tearing down
    // its audio session can get silently ducked to volume 0 on real
    // devices. This page never plays muted, so force it back. (CLAUDE.md
    // "Library" has the details.)
    controller.addListener(() {
      if (controller.value.volume == 0 && !controller.value.isCompleted) {
        controller.setVolume(1);
      }
    });
  }

  void _scheduleAutoHideControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      if (_videoController?.value.isPlaying == true) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final file = await widget.asset.file;
    if (!mounted) return;
    if (file == null) {
      setState(() => _loading = false);
      return;
    }
    if (widget.asset.type == AssetType.video) {
      // Play straight from the MediaStore-backed file — an earlier local
      // copy step was measured to dominate open time (~3.5s of ~3.7s for a
      // 547MB video) and wasn't what fixed the mute bug (the watchdog is).
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _attachController(controller);
      setState(() {
        _videoController = controller;
        _videoFile = file;
        _loading = false;
      });
      _scheduleStuckCheck();
    } else {
      setState(() {
        _file = file;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _pauseFlashTimer?.cancel();
    _stuckCheckTimer?.cancel();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _seekBy(VideoPlayerController controller, Duration offset) {
    final duration = controller.value.duration;
    var target = controller.value.position + offset;
    if (target < Duration.zero) target = Duration.zero;
    if (target > duration) target = duration;
    return controller.seekTo(target);
  }

  static String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0
        ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds'
        : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Center(child: _buildContent());
  }

  Widget _buildContent() {
    if (_loading) {
      return const CircularProgressIndicator(color: Colors.white);
    }
    final controller = _videoController;
    if (controller != null && controller.value.isInitialized) {
      return GestureDetector(
        onTap: () {
          // On resume, hide controls immediately (not after the usual delay)
          // so they don't linger out of sync with the pause icon. On pause,
          // show them and leave them up.
          final wasPlaying = controller.value.isPlaying;
          setState(() {
            if (wasPlaying) {
              controller.pause();
              _controlsVisible = true;
            } else {
              controller.play();
              _controlsVisible = false;
            }
          });
          _hideControlsTimer?.cancel();
          if (!wasPlaying) _flashPauseIcon();
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                if (value.isPlaying) return const SizedBox.shrink();
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 48,
                  ),
                );
              },
            ),
            // Transient pause-icon flash on tap-to-play — see _flashPauseIcon.
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _pauseFlashVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOut,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.pause,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              ),
            ),
            // Skip buttons on the vertical centre line, one per screen half.
            if (_controlsVisible)
              Positioned.fill(
                child: Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: _SeekButton(
                          icon: Icons.replay_10,
                          onPressed: () {
                            _seekBy(controller, const Duration(seconds: -10));
                            _scheduleAutoHideControls();
                          },
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: _SeekButton(
                          icon: Icons.forward_10,
                          onPressed: () {
                            _seekBy(controller, const Duration(seconds: 10));
                            _scheduleAutoHideControls();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_controlsVisible)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: controller,
                      builder: (context, value, _) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_formatDuration(_previewPosition ?? value.position)} / '
                            '${_formatDuration(value.duration)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                    _ScrubBar(
                      controller: controller,
                      onPositionPreview: (position) =>
                          setState(() => _previewPosition = position),
                      onScrubEnd: _scheduleAutoHideControls,
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    if (_file != null) {
      return _ZoomableImage(
        file: _file!,
        onZoomChanged: widget.onZoomChanged,
      );
    }
    return const Icon(
      Icons.broken_image_outlined,
      color: Colors.white54,
      size: 64,
    );
  }
}

/// An image with pinch-zoom (`InteractiveViewer`) plus double-tap zoom:
/// first double-tap zooms in centred on the tapped point, a second one
/// (while zoomed) resets to fit.
///
/// Lives inside the preview `PageView`. Left alone, the `PageView` grabs the
/// horizontal part of a two-finger pinch and flicks to the next item, so
/// [onZoomChanged] tells the parent to freeze paging while zoomed in — or as
/// soon as a second finger goes down, so the pinch is never stolen.
class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({required this.file, this.onZoomChanged});

  final File file;
  final ValueChanged<bool>? onZoomChanged;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage>
    with SingleTickerProviderStateMixin {
  static const _zoomScale = 2.5;

  final _controller = TransformationController();
  Offset? _doubleTapPosition;
  AnimationController? _animation;
  bool _reportedZoomed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncZoomState);
  }

  @override
  void dispose() {
    _controller.removeListener(_syncZoomState);
    _animation?.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Notify the parent only on an actual change, so the `PageView` physics
  /// aren't rebuilt on every pan frame.
  void _setZoomReported(bool zoomed) {
    if (zoomed == _reportedZoomed) return;
    _reportedZoomed = zoomed;
    widget.onZoomChanged?.call(zoomed);
  }

  void _syncZoomState() => _setZoomReported(_isZoomedIn);

  bool get _isZoomedIn => _controller.value.getMaxScaleOnAxis() > 1.01;

  void _handleDoubleTap() {
    final position = _doubleTapPosition;
    final Matrix4 target;
    if (_isZoomedIn || position == null) {
      target = Matrix4.identity();
    } else {
      // Keep the tapped point fixed while scaling up (works because we only
      // ever zoom in from the identity/fit state).
      target = Matrix4.identity()
        ..translateByDouble(
          -position.dx * (_zoomScale - 1),
          -position.dy * (_zoomScale - 1),
          0,
          1,
        )
        ..scaleByDouble(_zoomScale, _zoomScale, _zoomScale, 1);
    }
    _animateTo(target);
  }

  void _animateTo(Matrix4 target) {
    _animation?.dispose();
    final animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    final tween = Matrix4Tween(begin: _controller.value, end: target).animate(
      CurvedAnimation(parent: animation, curve: Curves.easeOut),
    );
    tween.addListener(() => _controller.value = tween.value);
    _animation = animation;
    animation.forward();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (details) => _doubleTapPosition = details.localPosition,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _controller,
        maxScale: 5,
        // A second finger down means a pinch is starting — lock paging
        // immediately, before the scale actually changes, so the PageView
        // can't claim the horizontal drift first.
        onInteractionStart: (details) {
          if (details.pointerCount >= 2) _setZoomReported(true);
        },
        // Back to fit after the gesture → let paging resume.
        onInteractionEnd: (_) => _setZoomReported(_isZoomedIn),
        child: Image.file(widget.file),
      ),
    );
  }
}

/// A large skip-seek button with an opaque circular backdrop for contrast
/// against bright video.
class _SeekButton extends StatelessWidget {
  const _SeekButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.black54,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
        iconSize: 40,
        padding: const EdgeInsets.all(14),
      ),
    );
  }
}

/// Replaces `VideoProgressIndicator(allowScrubbing: true)`, whose
/// unthrottled per-event `seekTo()` can wedge some hardware decoders (see
/// the `_stuckCheckTimer` field comment). Throttles real seeks to one per
/// [_throttle] while dragging, always seeks precisely on release, and owns
/// pause-during-drag/resume-after (captured at drag start, not inferred).
class _ScrubBar extends StatefulWidget {
  const _ScrubBar({
    required this.controller,
    required this.onPositionPreview,
    required this.onScrubEnd,
  });

  final VideoPlayerController controller;

  /// Live drag target while dragging, `null` once it ends — lets the parent
  /// show the drag position in its time label.
  final ValueChanged<Duration?> onPositionPreview;

  /// Fired after the drag ends (and playback resumed, if it had been
  /// playing) so the parent can restart its controls auto-hide timer.
  final VoidCallback onScrubEnd;

  @override
  State<_ScrubBar> createState() => _ScrubBarState();
}

class _ScrubBarState extends State<_ScrubBar> {
  static const _throttle = Duration(milliseconds: 400);
  static const _thumbWidth = 4.0;
  static const _thumbHeight = 16.0;

  Duration? _dragPosition;
  DateTime? _lastSeekAt;
  Timer? _pendingSeek;
  bool _wasPlaying = false;

  Duration _positionFromDx(double dx, double width) {
    final duration = widget.controller.value.duration;
    if (width <= 0 || duration == Duration.zero) return Duration.zero;
    final fraction = (dx / width).clamp(0.0, 1.0);
    return duration * fraction;
  }

  void _throttledSeek(Duration target) {
    final now = DateTime.now();
    final lastSeekAt = _lastSeekAt;
    final elapsed = lastSeekAt == null ? _throttle : now.difference(lastSeekAt);
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
    setState(() => _dragPosition = target);
    widget.onPositionPreview(target);
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
    if (target != null) {
      await widget.controller.seekTo(target);
    }
    if (!mounted) return;
    setState(() => _dragPosition = null);
    widget.onPositionPreview(null);
    if (_wasPlaying) {
      await widget.controller.play();
      widget.onScrubEnd();
    }
  }

  @override
  void dispose() {
    _pendingSeek?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _throttledSeek(
              _positionFromDx(details.localPosition.dx, width),
            ),
            onHorizontalDragStart: (details) =>
                _onDragStart(details.localPosition.dx, width),
            onHorizontalDragUpdate: (details) =>
                _onDragUpdate(details.localPosition.dx, width),
            onHorizontalDragEnd: (_) => _onDragEnd(),
            onHorizontalDragCancel: _onDragEnd,
            child: SizedBox(
              width: width,
              height: _thumbHeight,
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: widget.controller,
                builder: (context, value, _) {
                  final duration = value.duration;
                  final position = _dragPosition ?? value.position;
                  final playedFraction = duration == Duration.zero
                      ? 0.0
                      : (position.inMilliseconds / duration.inMilliseconds)
                          .clamp(0.0, 1.0);
                  final maxThumbLeft = width > _thumbWidth
                      ? width - _thumbWidth
                      : 0.0;
                  final thumbLeft = (playedFraction * width - _thumbWidth / 2)
                      .clamp(0.0, maxThumbLeft);
                  return Stack(
                    children: [
                      Align(
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: width,
                          height: 3,
                          // StackFit.expand is required: without it the
                          // childless ColoredBoxes collapse to zero under
                          // Stack's loose constraints and the track is
                          // invisible.
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              const ColoredBox(color: Colors.white12),
                              FractionallySizedBox(
                                widthFactor: playedFraction,
                                // Fill from the left, not centre.
                                alignment: Alignment.centerLeft,
                                child: const ColoredBox(
                                  color: Colors.redAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Grab handle — a full-height vertical bar.
                      Positioned(
                        left: thumbLeft,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: _thumbWidth,
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(
                              _thumbWidth / 2,
                            ),
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
      ),
    );
  }
}

/// Quick "peek" overlay shown while long-pressing a tile — same interaction
/// pattern as `WhatsAppStatusScreen`'s tiles, but reading straight from
/// `AssetEntity` (a plain local file, no SAF copy step needed here).
class LibraryPeekPreview extends StatefulWidget {
  const LibraryPeekPreview({super.key, required this.asset});

  final AssetEntity asset;

  @override
  State<LibraryPeekPreview> createState() => _LibraryPeekPreviewState();
}

class _LibraryPeekPreviewState extends State<LibraryPeekPreview> {
  Uint8List? _imageBytes;
  VideoPlayerController? _videoController;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.asset.type == AssetType.video) {
      final file = await widget.asset.file;
      if (!mounted || file == null) return;
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller
        ..setLooping(true)
        ..setVolume(1)
        ..play();
      // Same watchdog as the full preview pages — a freshly-started
      // controller can end up audio-focus-ducked to 0 (see
      // `LibraryPreviewPage`/`StatusPreviewPage` for the full story).
      controller.addListener(() {
        if (controller.value.volume == 0 && !controller.value.isCompleted) {
          controller.setVolume(1);
        }
      });
      setState(() {
        _videoController = controller;
        _loading = false;
      });
    } else {
      final bytes = await widget.asset.thumbnailDataWithSize(
        const ThumbnailSize(1600, 1600),
      );
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black87,
        child: Center(child: _buildContent()),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const CircularProgressIndicator(color: Colors.white);
    }
    final controller = _videoController;
    if (controller != null && controller.value.isInitialized) {
      return AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: VideoPlayer(controller),
      );
    }
    if (_imageBytes != null) {
      return Image.memory(_imageBytes!);
    }
    return const Icon(
      Icons.broken_image_outlined,
      color: Colors.white54,
      size: 64,
    );
  }
}
