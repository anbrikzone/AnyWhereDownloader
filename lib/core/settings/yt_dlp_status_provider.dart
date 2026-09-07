import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../yt_dlp_engine/yt_dlp_engine.dart';

/// State for the Settings → About "yt-dlp engine" row: the bundled binary's
/// version + last self-update outcome, plus whether a manual update is
/// currently running.
class YtDlpStatusState {
  const YtDlpStatusState({
    this.info,
    this.loading = true,
    this.updating = false,
  });

  final YtDlpStatusInfo? info;
  final bool loading;
  final bool updating;

  YtDlpStatusState copyWith({
    YtDlpStatusInfo? info,
    bool? loading,
    bool? updating,
  }) {
    return YtDlpStatusState(
      info: info ?? this.info,
      loading: loading ?? this.loading,
      updating: updating ?? this.updating,
    );
  }
}

class YtDlpStatusController extends StateNotifier<YtDlpStatusState> {
  YtDlpStatusController({YtDlpEngine? engine})
    : _engine = engine ?? YtDlpEngine(),
      super(const YtDlpStatusState()) {
    refresh();
  }

  final YtDlpEngine _engine;

  Future<void> refresh() async {
    try {
      final info = await _engine.getYtDlpStatus();
      if (mounted) state = state.copyWith(info: info, loading: false);
    } catch (_) {
      if (mounted) state = state.copyWith(loading: false);
    }
  }

  /// Forces a bundled-yt-dlp update. Returns the outcome so the caller can
  /// show a toast; null if the native call itself failed.
  Future<YtDlpStatusInfo?> updateNow() async {
    if (state.updating) return null;
    state = state.copyWith(updating: true);
    try {
      final info = await _engine.updateYtDlp();
      if (mounted) {
        state = state.copyWith(info: info, updating: false, loading: false);
      }
      return info;
    } catch (_) {
      if (mounted) state = state.copyWith(updating: false);
      return null;
    }
  }
}

final ytDlpStatusProvider =
    StateNotifierProvider<YtDlpStatusController, YtDlpStatusState>(
      (ref) => YtDlpStatusController(),
    );
