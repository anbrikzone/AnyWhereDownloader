import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../preview/video_player_view.dart';

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
  void _attachController(VideoPlayerController controller, {bool loop = true}) {
    controller
      ..setLooping(loop)
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final type = widget.asset.type;

    if (type == AssetType.audio) {
      // MediaStore audio is flaky to resolve to a local File on the first
      // open (the tap-to-open path hit exactly this) — play from the
      // content:// URI, falling back to a File only if there's no URL.
      final url = await widget.asset.getMediaUrl();
      final file = url == null ? await widget.asset.file : null;
      if (!mounted) return;
      if (url == null && file == null) {
        setState(() => _loading = false);
        return;
      }
      final controller = url != null
          ? VideoPlayerController.contentUri(Uri.parse(url))
          : VideoPlayerController.file(file!);
      try {
        await controller.initialize();
      } catch (_) {
        await controller.dispose();
        if (mounted) setState(() => _loading = false);
        return;
      }
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _attachController(controller, loop: false);
      setState(() {
        _videoController = controller;
        _loading = false;
      });
      return;
    }

    final file = await widget.asset.file;
    if (!mounted) return;
    if (file == null) {
      setState(() => _loading = false);
      return;
    }
    if (type == AssetType.video) {
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

  bool get _isAudio => widget.asset.type == AssetType.audio;

  @override
  void dispose() {
    _stuckCheckTimer?.cancel();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    final controller = _videoController;
    if (controller != null && controller.value.isInitialized) {
      return SizedBox.expand(
        child: VideoPlayerView(controller: controller, isAudio: _isAudio),
      );
    }
    if (_file != null) {
      return Center(
        child: _ZoomableImage(
          file: _file!,
          onZoomChanged: widget.onZoomChanged,
        ),
      );
    }
    return const Center(
      child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
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

  // Double-tap is detected from raw pointer events via a [Listener], not a
  // `GestureDetector`: once zoomed in the image becomes pannable, and
  // `InteractiveViewer`'s own scale/pan recognizer then wins the gesture
  // arena and swallows `GestureDetector.onDoubleTap` — so double-tap
  // *zoom-out* never fired. A `Listener` is passive (never joins the arena)
  // so it still sees every tap; the guards below keep a pan or pinch from
  // being mistaken for one.
  static const _tapSlop = 24.0;
  int _downPointers = 0;
  int? _trackedPointer;
  Offset? _trackedDownGlobal;
  bool _trackedMoved = false;
  DateTime? _lastTapAt;
  Offset? _lastTapLocal;

  void _onPointerDown(PointerDownEvent event) {
    _downPointers++;
    if (_downPointers > 1) {
      // Second finger down → pinch, not a tap sequence.
      _trackedPointer = null;
      _lastTapAt = null;
      return;
    }
    _trackedPointer = event.pointer;
    _trackedDownGlobal = event.position;
    _trackedMoved = false;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _trackedPointer || _trackedDownGlobal == null) return;
    if ((event.position - _trackedDownGlobal!).distance > _tapSlop) {
      _trackedMoved = true;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_downPointers > 0) _downPointers--;
    if (event.pointer != _trackedPointer) return;
    _trackedPointer = null;
    if (_trackedMoved) {
      _lastTapAt = null;
      return;
    }
    final now = DateTime.now();
    final lastAt = _lastTapAt;
    final lastLocal = _lastTapLocal;
    if (lastAt != null &&
        now.difference(lastAt) < const Duration(milliseconds: 300) &&
        lastLocal != null &&
        (event.localPosition - lastLocal).distance < _tapSlop * 2) {
      _lastTapAt = null;
      _doubleTapPosition = event.localPosition;
      _handleDoubleTap();
    } else {
      _lastTapAt = now;
      _lastTapLocal = event.localPosition;
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_downPointers > 0) _downPointers--;
    if (event.pointer == _trackedPointer) _trackedPointer = null;
  }

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
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
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

  bool get _isAudio => widget.asset.type == AssetType.audio;

  Future<void> _load() async {
    if (widget.asset.type == AssetType.video || _isAudio) {
      final VideoPlayerController controller;
      if (_isAudio) {
        final url = await widget.asset.getMediaUrl();
        final file = url == null ? await widget.asset.file : null;
        if (!mounted || (url == null && file == null)) return;
        controller = url != null
            ? VideoPlayerController.contentUri(Uri.parse(url))
            : VideoPlayerController.file(file!);
      } else {
        final file = await widget.asset.file;
        if (!mounted || file == null) return;
        controller = VideoPlayerController.file(file);
      }
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller
        ..setLooping(!_isAudio)
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
      if (_isAudio) {
        return const Icon(Icons.music_note, color: Colors.white24, size: 96);
      }
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
