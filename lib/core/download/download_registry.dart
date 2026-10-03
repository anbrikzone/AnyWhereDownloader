import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/status_message.dart';
import '../logging/app_log.dart';

/// What a download produces — picks the row icon and the MIME type used to
/// open the saved file.
enum DownloadKind { video, audio, image, playlist }

enum DownloadStatus { running, paused, completed, failed, canceled }

/// One download shown on the Downloads screen (backlog #19). Active entries
/// live only in memory; finished ones are kept as history (persisted, see
/// [DownloadRegistry]).
class DownloadEntry {
  const DownloadEntry({
    required this.id,
    required this.source,
    required this.title,
    required this.kind,
    required this.status,
    required this.startedAt,
    this.progress = 0,
    this.canPause = false,
    this.finishedAt,
    this.contentUri,
    this.error,
    this.savedCount,
    this.failedCount,
  });

  final String id;

  /// Brand name of the service ("YouTube", "Pinterest", …) — not localized.
  final String source;
  final String title;
  final DownloadKind kind;
  final DownloadStatus status;

  /// 0..1; 0 means "nothing reported yet" (the screen animates instead).
  final double progress;
  final bool canPause;
  final DateTime startedAt;
  final DateTime? finishedAt;

  /// The saved MediaStore item, for "tap to open". Null for a playlist
  /// (many files) or anything that didn't complete.
  final String? contentUri;
  final String? error;

  /// Playlist outcome counts.
  final int? savedCount;
  final int? failedCount;

  bool get isActive =>
      status == DownloadStatus.running || status == DownloadStatus.paused;

  String get mimeType => switch (kind) {
        DownloadKind.audio => 'audio/*',
        DownloadKind.image => 'image/*',
        _ => 'video/*',
      };

  DownloadEntry copyWith({
    DownloadStatus? status,
    double? progress,
    bool? canPause,
    DateTime? finishedAt,
    String? contentUri,
    String? error,
    int? savedCount,
    int? failedCount,
  }) {
    return DownloadEntry(
      id: id,
      source: source,
      title: title,
      kind: kind,
      startedAt: startedAt,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      canPause: canPause ?? this.canPause,
      finishedAt: finishedAt ?? this.finishedAt,
      contentUri: contentUri ?? this.contentUri,
      error: error ?? this.error,
      savedCount: savedCount ?? this.savedCount,
      failedCount: failedCount ?? this.failedCount,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'source': source,
        'title': title,
        'kind': kind.name,
        'status': status.name,
        'startedAt': startedAt.millisecondsSinceEpoch,
        'finishedAt': finishedAt?.millisecondsSinceEpoch,
        'contentUri': contentUri,
        'error': error,
        'savedCount': savedCount,
        'failedCount': failedCount,
      };

  static DownloadEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      final finished = raw['finishedAt'] as int?;
      return DownloadEntry(
        id: raw['id'] as String,
        source: raw['source'] as String,
        title: raw['title'] as String,
        kind: DownloadKind.values.byName(raw['kind'] as String),
        status: DownloadStatus.values.byName(raw['status'] as String),
        startedAt: DateTime.fromMillisecondsSinceEpoch(raw['startedAt'] as int),
        finishedAt: finished == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(finished),
        progress: 1,
        contentUri: raw['contentUri'] as String?,
        error: raw['error'] as String?,
        savedCount: raw['savedCount'] as int?,
        failedCount: raw['failedCount'] as int?,
      );
    } catch (_) {
      return null; // A malformed or older-format row is dropped, not fatal.
    }
  }
}

/// How the Downloads screen drives a running download — wired by the
/// controller that owns it, since only it holds the task / process id.
class DownloadControls {
  const DownloadControls({required this.cancel, this.togglePause});

  final Future<void> Function() cancel;

  /// Null when the download can't pause (the yt-dlp service path).
  final Future<void> Function()? togglePause;
}

class DownloadRegistryState {
  const DownloadRegistryState({this.active = const [], this.history = const []});

  /// Running/paused downloads, oldest first.
  final List<DownloadEntry> active;

  /// Finished downloads, newest first, at most [DownloadRegistry.historyLimit].
  final List<DownloadEntry> history;
}

/// Persists [DownloadRegistryState.history] — a seam so tests don't need a
/// real `shared_preferences`.
abstract class DownloadHistoryStore {
  Future<List<DownloadEntry>> load();
  Future<void> save(List<DownloadEntry> history);
}

class PrefsDownloadHistoryStore implements DownloadHistoryStore {
  static const _key = 'download_history_v1';

  @override
  Future<List<DownloadEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded.map(DownloadEntry.fromJson).whereType<DownloadEntry>().toList();
  }

  @override
  Future<void> save(List<DownloadEntry> history) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(history.map((e) => e.toJson()).toList()),
    );
  }
}

/// The one place every controller reports its downloads to (backlog #19),
/// so the Downloads screen can list and control them no matter which
/// screen started them. In-memory for active downloads; finished ones move
/// into a persisted history. A download that outlives the Flutter UI (saved
/// natively / by `DownloadFinalizer`) isn't re-attached here — the system
/// notification still covers it.
class DownloadRegistry extends StateNotifier<DownloadRegistryState> {
  DownloadRegistry({DownloadHistoryStore? store})
      : _store = store ?? PrefsDownloadHistoryStore(),
        super(const DownloadRegistryState()) {
    _loaded = _load();
  }

  static const historyLimit = 30;

  final DownloadHistoryStore _store;
  final _controls = <String, DownloadControls>{};
  late final Future<void> _loaded;

  /// Completes once the persisted history has been read (tests await it).
  Future<void> get ready => _loaded;

  Future<void> _load() async {
    try {
      final history = await _store.load();
      if (!mounted) return;
      // Anything finished before the load completed stays on top.
      state = DownloadRegistryState(
        active: state.active,
        history: [...state.history, ...history].take(historyLimit).toList(),
      );
    } catch (e, st) {
      logError('DownloadRegistry.load', e, st);
    }
  }

  void begin({
    required String id,
    required String source,
    required String title,
    required DownloadKind kind,
    required DownloadControls controls,
  }) {
    _controls[id] = controls;
    final entry = DownloadEntry(
      id: id,
      source: source,
      title: title,
      kind: kind,
      status: DownloadStatus.running,
      startedAt: DateTime.now(),
      canPause: controls.togglePause != null,
    );
    state = DownloadRegistryState(
      active: [...state.active.where((e) => e.id != id), entry],
      history: state.history,
    );
  }

  void progress(String id, double progress) =>
      _updateActive(id, (e) => e.copyWith(progress: progress.clamp(0.0, 1.0)));

  void setPaused(String id, bool paused) => _updateActive(
        id,
        (e) => e.copyWith(
          status: paused ? DownloadStatus.paused : DownloadStatus.running,
        ),
      );

  /// Moves [id] into history with the outcome the controller already shows
  /// as a toast/notification ([message]).
  void finish(String id, StatusMessage message, {String? contentUri}) {
    final index = state.active.indexWhere((e) => e.id == id);
    if (index < 0) return;
    _controls.remove(id);
    final entry = state.active[index];
    final finished = switch (message.key) {
      StatusMessageKey.saved => entry.copyWith(
          status: DownloadStatus.completed,
          contentUri: contentUri,
        ),
      StatusMessageKey.playlistSaved => entry.copyWith(
          status: DownloadStatus.completed,
          savedCount: message.count,
          failedCount: message.failedCount,
        ),
      StatusMessageKey.downloadCanceled =>
        entry.copyWith(status: DownloadStatus.canceled),
      _ => entry.copyWith(status: DownloadStatus.failed, error: message.error),
    }.copyWith(progress: 1, finishedAt: DateTime.now());
    final history = [finished, ...state.history].take(historyLimit).toList();
    state = DownloadRegistryState(
      active: [...state.active]..removeAt(index),
      history: history,
    );
    _persist(history);
  }

  Future<void> togglePause(String id) async =>
      await _controls[id]?.togglePause?.call();

  Future<void> cancel(String id) async => await _controls[id]?.cancel();

  void clearHistory() {
    state = DownloadRegistryState(active: state.active);
    _persist(const []);
  }

  void _updateActive(String id, DownloadEntry Function(DownloadEntry) change) {
    final index = state.active.indexWhere((e) => e.id == id);
    if (index < 0) return;
    final active = [...state.active];
    active[index] = change(active[index]);
    state = DownloadRegistryState(active: active, history: state.history);
  }

  void _persist(List<DownloadEntry> history) {
    _store.save(history).catchError((Object e, StackTrace st) {
      logError('DownloadRegistry.save', e, st);
    });
  }
}

final downloadRegistryProvider =
    StateNotifierProvider<DownloadRegistry, DownloadRegistryState>(
  (ref) => DownloadRegistry(),
);
