import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:video_player/video_player.dart';

import '../../core/storage/saf_service.dart';
import '../../services/whatsapp/whatsapp_status_reader.dart';

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
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) => _StatusPreviewItem(
          key: ValueKey(widget.items[index].uri),
          item: widget.items[index],
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
  const _StatusPreviewItem({super.key, required this.item});

  final StatusItem item;

  @override
  State<_StatusPreviewItem> createState() => _StatusPreviewItemState();
}

class _StatusPreviewItemState extends State<_StatusPreviewItem> {
  final _safService = SafService();
  final _safStream = SafStream();

  String? _imagePath;
  VideoPlayerController? _videoController;
  String? _tempPath;
  bool _loading = true;
  bool _failed = false;

  // See `LibraryPreviewPage` for the full rationale — ported as-is
  // (controls start hidden, only appear on touch, rather than flashing on
  // open).
  bool _controlsVisible = false;
  Timer? _hideControlsTimer;

  // See `LibraryPreviewPage`'s field comment for the full story (a real
  // logcat-confirmed MediaCodec flush-storm root cause, not a Flutter-level
  // state bug — two earlier reactive-watchdog attempts didn't fix it).
  // Fixed the same way here: `_ScrubBar` replaces `VideoProgressIndicator`
  // with throttled seeks, ported as-is.
  Duration? _previewPosition;

  // See `LibraryPreviewPage` for the full rationale — ported as-is.
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
    final tempPath = _tempPath;
    if (oldController == null || tempPath == null) return;
    _recovering = true;
    final resumePosition = oldController.value.position;
    try {
      final newController = VideoPlayerController.file(File(tempPath));
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
    try {
      final tempDir = await getTemporaryDirectory();
      if (widget.item.mediaType == StatusMediaType.image) {
        final destPath =
            '${tempDir.path}/wa_preview_${widget.item.uri.hashCode}.jpg';
        final ok = await _safService.saveThumbnailToFile(
          uri: widget.item.uri,
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
            '${tempDir.path}/wa_preview_${DateTime.now().microsecondsSinceEpoch}_${widget.item.name}';
        await _safStream.copyToLocalFile(widget.item.uri, destPath);
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
    _hideControlsTimer?.cancel();
    _pauseFlashTimer?.cancel();
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
    if (_failed) {
      return const Icon(
        Icons.broken_image_outlined,
        color: Colors.white54,
        size: 64,
      );
    }
    final controller = _videoController;
    if (controller != null && controller.value.isInitialized) {
      return GestureDetector(
        onTap: () {
          // See `LibraryPreviewPage` for why resuming hides immediately
          // instead of scheduling the usual 1s delay — ported as-is.
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
            // See `LibraryPreviewPage` for the full rationale — ported
            // as-is.
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
    if (_imagePath != null) {
      return InteractiveViewer(child: Image.file(File(_imagePath!)));
    }
    return const Icon(
      Icons.broken_image_outlined,
      color: Colors.white54,
      size: 64,
    );
  }
}

/// Replaces `VideoProgressIndicator(allowScrubbing: true)` — see
/// `LibraryPreviewPage`'s identical widget for the full rationale (a real
/// logcat-confirmed MediaCodec flush-storm caused by the package's own
/// unthrottled `VideoScrubber`), ported here directly rather than shared,
/// same as `_SeekButton` below.
class _ScrubBar extends StatefulWidget {
  const _ScrubBar({
    required this.controller,
    required this.onPositionPreview,
    required this.onScrubEnd,
  });

  final VideoPlayerController controller;
  final ValueChanged<Duration?> onPositionPreview;
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
                          // See `LibraryPreviewPage` for the full rationale
                          // — `StackFit.expand` is load-bearing, ported
                          // as-is (a childless `ColoredBox` collapses to
                          // zero under the default loose Stack constraints,
                          // which is why the track was invisible before).
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              const ColoredBox(color: Colors.white12),
                              FractionallySizedBox(
                                widthFactor: playedFraction,
                                alignment: Alignment.centerLeft,
                                child: const ColoredBox(
                                  color: Colors.redAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Grabbable vertical handle — see `LibraryPreviewPage`
                      // for the full rationale, ported as-is. Already only
                      // ever rendered while `_ScrubBar` itself is (the
                      // parent gates the whole time/scrub row on
                      // `_controlsVisible`).
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

/// A large skip-seek button with an opaque circular backdrop — see
/// `LibraryPreviewPage`'s identical widget for the full rationale, ported
/// here directly rather than shared (both preview implementations are
/// already independent, not sharing code, per the existing pattern in this
/// codebase).
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
      final tempDir = await getTemporaryDirectory();
      if (widget.item.mediaType == StatusMediaType.image) {
        final destPath =
            '${tempDir.path}/wa_peek_${widget.item.uri.hashCode}.jpg';
        final ok = await _safService.saveThumbnailToFile(
          uri: widget.item.uri,
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
            '${tempDir.path}/wa_peek_${DateTime.now().microsecondsSinceEpoch}_${widget.item.name}';
        await _safStream.copyToLocalFile(widget.item.uri, destPath);
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
