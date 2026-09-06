import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:video_player/video_player.dart';

import '../../core/storage/saf_service.dart';
import '../../services/whatsapp/whatsapp_status_reader.dart';
import '../preview/video_player_view.dart';

/// Full-screen preview, pushed on tap — same UX as `LibraryPreviewPage`
/// (skip buttons, time label, show-controls-on-touch with auto-hide, and —
/// swipe between items, ported from the same feature added to Library — see
/// that file for the full design rationale, ported here directly rather
/// than redesigned). Each page is its own `_StatusPreviewItem`; `PageView`'s
/// normal lazy build/dispose behavior keeps at most a page or two mounted
/// at once as the user swipes, so temp-file copies and video controllers
/// for far-away items are never created in the first place.
class StatusPreviewPage extends StatefulWidget {
  const StatusPreviewPage({
    super.key,
    required this.items,
    required this.initialIndex,
  });

  final List<StatusItem> items;
  final int initialIndex;

  @override
  State<StatusPreviewPage> createState() => _StatusPreviewPageState();
}

class _StatusPreviewPageState extends State<StatusPreviewPage> {
  late final PageController _pageController = PageController(
    initialPage: widget.initialIndex,
  );
  late int _currentIndex = widget.initialIndex;

  // True while the current image is zoomed in (or a two-finger pinch is in
  // progress) — freezes page swiping so the gesture pans/zooms the image
  // instead of flicking to the next status. Same coordination as
  // `library_preview.dart`.
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
        title: widget.items.length > 1
            ? Text(
                '${_currentIndex + 1} / ${widget.items.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              )
            : null,
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.items.length,
        physics: _pageLocked
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(),
        onPageChanged: (index) => setState(() {
          _currentIndex = index;
          _pageLocked = false;
        }),
        itemBuilder: (context, index) => _StatusPreviewItem(
          key: ValueKey(widget.items[index].uri),
          item: widget.items[index],
          onZoomChanged: (zoomed) {
            if (zoomed != _pageLocked) setState(() => _pageLocked = zoomed);
          },
        ),
      ),
    );
  }
}

/// One swipeable page's worth of content — everything `StatusPreviewPage`
/// used to own directly before it became a `PageView` of these. Logic is
/// unchanged from before the swipe feature; only the enclosing `Scaffold`/
/// `AppBar` moved up to the new parent widget.
class _StatusPreviewItem extends StatefulWidget {
  const _StatusPreviewItem({
    super.key,
    required this.item,
    this.onZoomChanged,
  });

  final StatusItem item;

  /// Fired by the zoomable image when it zooms in/out (or a pinch starts/
  /// ends) so the parent can freeze/unfreeze page swiping.
  final ValueChanged<bool>? onZoomChanged;

  @override
  State<_StatusPreviewItem> createState() => _StatusPreviewItemState();
}

class _StatusPreviewItemState extends State<_StatusPreviewItem> {
  final _safService = SafService();
  final _safStream = SafStream();

  String? _imagePath;
  VideoPlayerController? _videoController;

  /// A temp file this widget created and must delete on dispose. Null for an
  /// archived status, whose video is played straight from its (permanent)
  /// local archive file — see [_playbackPath].
  String? _tempPath;

  /// The local file the video is actually playing from — the temp copy for
  /// a fresh status, the archive file for an archived one. Used by the
  /// stuck-decoder recovery, which must not depend on [_tempPath].
  String? _playbackPath;
  bool _loading = true;
  bool _failed = false;

  // See `LibraryPreviewPage` for the full rationale — ported as-is. The
  // recovery target here is `_tempPath` (already a local file, unlike
  // Library's MediaStore-backed `AssetEntity.file`) rather than a separate
  // field.
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
    final playbackPath = _playbackPath;
    if (oldController == null || playbackPath == null) return;
    _recovering = true;
    final resumePosition = oldController.value.position;
    try {
      final newController = VideoPlayerController.file(File(playbackPath));
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

  // See `LibraryPreviewPage` for the full rationale — ported as-is.
  void _attachController(VideoPlayerController controller) {
    controller
      ..setLooping(true)
      ..setVolume(1)
      ..play();
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
    try {
      final item = widget.item;

      // Archived status: the file is already a local file in the app's
      // private archive. Play/show it directly — no SAF thumbnail, no temp
      // copy, and crucially nothing to delete on dispose.
      if (item.isArchived) {
        final path = item.localPath!;
        if (item.mediaType == StatusMediaType.image) {
          if (!mounted) return;
          setState(() {
            _imagePath = path;
            _loading = false;
          });
        } else {
          final controller = VideoPlayerController.file(File(path));
          await controller.initialize();
          if (!mounted) {
            await controller.dispose();
            return;
          }
          _attachController(controller);
          setState(() {
            _videoController = controller;
            _playbackPath = path;
            _loading = false;
          });
          _scheduleStuckCheck();
        }
        return;
      }

      final tempDir = await getTemporaryDirectory();
      if (item.mediaType == StatusMediaType.image) {
        final destPath =
            '${tempDir.path}/wa_preview_${item.uri.hashCode}.jpg';
        final ok = await _safService.saveThumbnailToFile(
          uri: item.uri,
          width: 1600,
          height: 1600,
          destPath: destPath,
        );
        if (!mounted) return;
        setState(() {
          _imagePath = ok ? destPath : null;
          _failed = !ok;
          _loading = false;
        });
      } else {
        final destPath =
            '${tempDir.path}/wa_preview_${DateTime.now().microsecondsSinceEpoch}_${item.name}';
        await _safStream.copyToLocalFile(item.uri, destPath);
        final controller = VideoPlayerController.file(File(destPath));
        await controller.initialize();
        if (!mounted) {
          await controller.dispose();
          await File(destPath).delete();
          return;
        }
        _attachController(controller);
        setState(() {
          _videoController = controller;
          _tempPath = destPath;
          _playbackPath = destPath;
          _loading = false;
        });
        _scheduleStuckCheck();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _stuckCheckTimer?.cancel();
    _videoController?.dispose();
    final tempPath = _tempPath;
    if (tempPath != null) {
      File(tempPath).exists().then((exists) {
        if (exists) File(tempPath).delete();
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_failed) {
      return const Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: Colors.white54,
          size: 64,
        ),
      );
    }
    final controller = _videoController;
    if (controller != null && controller.value.isInitialized) {
      return SizedBox.expand(
        child: VideoPlayerView(controller: controller),
      );
    }
    if (_imagePath != null) {
      return Center(
        child: _ZoomableImage(
          file: File(_imagePath!),
          onZoomChanged: widget.onZoomChanged,
        ),
      );
    }
    return const Center(
      child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
    );
  }
}

/// An image with pinch-zoom (`InteractiveViewer`) plus double-tap zoom —
/// a direct port of the one in `library_preview.dart` (kept duplicated, not
/// shared, matching this file pair's convention). [onZoomChanged] lets the
/// parent freeze the `PageView` while zoomed so a pinch isn't stolen as a
/// swipe to the next status.
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

  bool get _isZoomedIn => _controller.value.getMaxScaleOnAxis() > 1.01;

  void _setZoomReported(bool zoomed) {
    if (zoomed == _reportedZoomed) return;
    _reportedZoomed = zoomed;
    widget.onZoomChanged?.call(zoomed);
  }

  void _syncZoomState() => _setZoomReported(_isZoomedIn);

  void _handleDoubleTap() {
    final position = _doubleTapPosition;
    final Matrix4 target;
    if (_isZoomedIn || position == null) {
      target = Matrix4.identity();
    } else {
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
        onInteractionStart: (details) {
          if (details.pointerCount >= 2) _setZoomReported(true);
        },
        onInteractionEnd: (_) => _setZoomReported(_isZoomedIn),
        child: Image.file(widget.file),
      ),
    );
  }
}

/// Full-screen "peek" preview shown while the user holds down a status
/// tile. Closed by the caller (on long-press release) via [OverlayEntry]
/// removal — this widget only renders content and cleans up its own temp
/// file, it does not manage its own lifecycle in the overlay.
class StatusPeekPreview extends StatefulWidget {
  const StatusPeekPreview({super.key, required this.item});

  final StatusItem item;

  @override
  State<StatusPeekPreview> createState() => _StatusPeekPreviewState();
}

class _StatusPeekPreviewState extends State<StatusPeekPreview> {
  final _safService = SafService();
  final _safStream = SafStream();

  String? _imagePath;
  VideoPlayerController? _videoController;
  String? _videoTempPath;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final item = widget.item;

      // Archived status — a local private file already. Show/play directly;
      // `_videoTempPath` stays null so dispose never deletes the archive.
      if (item.isArchived) {
        final path = item.localPath!;
        if (item.mediaType == StatusMediaType.image) {
          if (!mounted) return;
          setState(() {
            _imagePath = path;
            _loading = false;
          });
          return;
        }
        final controller = VideoPlayerController.file(File(path));
        await controller.initialize();
        if (!mounted) {
          await controller.dispose();
          return;
        }
        controller
          ..setLooping(true)
          ..setVolume(1)
          ..play();
        controller.addListener(() {
          if (controller.value.volume == 0 && !controller.value.isCompleted) {
            controller.setVolume(1);
          }
        });
        setState(() {
          _videoController = controller;
          _loading = false;
        });
        return;
      }

      final tempDir = await getTemporaryDirectory();
      if (item.mediaType == StatusMediaType.image) {
        final destPath =
            '${tempDir.path}/wa_peek_${item.uri.hashCode}.jpg';
        final ok = await _safService.saveThumbnailToFile(
          uri: item.uri,
          width: 1600,
          height: 1600,
          destPath: destPath,
        );
        if (!mounted) return;
        setState(() {
          _imagePath = ok ? destPath : null;
          _failed = !ok;
          _loading = false;
        });
      } else {
        final destPath =
            '${tempDir.path}/wa_peek_${DateTime.now().microsecondsSinceEpoch}_${item.name}';
        await _safStream.copyToLocalFile(item.uri, destPath);
        final controller = VideoPlayerController.file(File(destPath));
        await controller.initialize();
        if (!mounted) {
          await controller.dispose();
          await File(destPath).delete();
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
          _videoTempPath = destPath;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    final tempPath = _videoTempPath;
    if (tempPath != null) {
      File(tempPath).exists().then((exists) {
        if (exists) File(tempPath).delete();
      });
    }
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
    if (_failed) {
      return const Icon(
        Icons.broken_image_outlined,
        color: Colors.white54,
        size: 64,
      );
    }
    if (_imagePath != null) {
      return InteractiveViewer(child: Image.file(File(_imagePath!)));
    }
    final controller = _videoController;
    if (controller != null && controller.value.isInitialized) {
      return AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: VideoPlayer(controller),
      );
    }
    return const CircularProgressIndicator(color: Colors.white);
  }
}
