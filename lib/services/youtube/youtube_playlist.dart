/// One shared quality choice applied to every selected item of a playlist
/// download — a playlist can't show a per-video format sheet, so the user
/// picks one of these up front.
enum PlaylistQuality {
  /// Best available up to 1080p.
  upTo1080,
  upTo720,
  upTo360,

  /// Audio only, MP3 320 kbps.
  audioMp3;

  bool get isAudio => this == PlaylistQuality.audioMp3;

  /// yt-dlp `-f` selector for the video presets; null for [audioMp3]
  /// (which goes through `-x --audio-format mp3` instead).
  String? get formatSelector => switch (this) {
    PlaylistQuality.upTo1080 =>
      'bv*[height<=1080]+ba/b[height<=1080]/bv*+ba/b',
    PlaylistQuality.upTo720 =>
      'bv*[height<=720]+ba/b[height<=720]/b[height<=720]/bv*+ba/b',
    PlaylistQuality.upTo360 => 'b[height<=360]/bv*[height<=360]+ba/b',
    PlaylistQuality.audioMp3 => null,
  };

  String? get audioFormat => isAudio ? 'mp3' : null;
  int get audioQualityKbps => isAudio ? 320 : 0;

  /// Short label for the picker chips (brand-neutral, not localized — same
  /// treatment as the single-video format rows).
  String get label => switch (this) {
    PlaylistQuality.upTo1080 => '≤ 1080p',
    PlaylistQuality.upTo720 => '720p',
    PlaylistQuality.upTo360 => '360p',
    PlaylistQuality.audioMp3 => 'MP3 320',
  };
}

/// YouTube playlist-URL classification + the `--playlist-items` spec
/// builder. Kept separate from [YouTubeExtractor] (which only deals with
/// single-video info) so the playlist flow doesn't touch that path.
class YouTubePlaylistUrl {
  YouTubePlaylistUrl._();

  static bool _isYouTubeHost(Uri uri) {
    final h = uri.host.toLowerCase();
    return h == 'youtube.com' ||
        h == 'www.youtube.com' ||
        h == 'm.youtube.com' ||
        h == 'music.youtube.com';
  }

  /// The `list` query parameter, if any.
  static String? listIdOf(String url) =>
      Uri.tryParse(url.trim())?.queryParameters['list'];

  /// A `list` id we can actually enumerate and download. Mix / radio
  /// auto-lists (`RD…`) and the "my mix" (`UL…`) lists are dynamic /
  /// effectively endless, so they're treated as "not a playlist" — the URL
  /// falls through to the single-video path.
  static bool isDownloadableList(String? listId) =>
      listId != null &&
      listId.isNotEmpty &&
      !listId.startsWith('RD') &&
      !listId.startsWith('UL');

  /// `youtube.com/playlist?list=…` — a bare playlist link, go straight to
  /// the playlist picker.
  static bool isPurePlaylistUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !_isYouTubeHost(uri)) return false;
    if (!uri.path.contains('playlist')) return false;
    return isDownloadableList(uri.queryParameters['list']);
  }

  /// `watch?v=…&list=…` — a video that's also part of a playlist. The
  /// caller should ask the user which they meant.
  static bool isVideoInPlaylistUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !_isYouTubeHost(uri)) return false;
    if ((uri.queryParameters['v'] ?? '').isEmpty) return false;
    return isDownloadableList(uri.queryParameters['list']);
  }

  /// A yt-dlp `--playlist-items` spec (`"1,3,5-7"`) for the selected
  /// 1-based [positions]. Returns null when they cover every position
  /// `1..total` — yt-dlp then just downloads the lot.
  static String? itemsSpec(Iterable<int> positions, int total) {
    final sorted = positions.toSet().toList()..sort();
    if (sorted.isEmpty || sorted.length >= total) return null;
    final ranges = <String>[];
    var start = sorted.first;
    var prev = sorted.first;
    for (final n in sorted.skip(1)) {
      if (n == prev + 1) {
        prev = n;
        continue;
      }
      ranges.add(start == prev ? '$start' : '$start-$prev');
      start = n;
      prev = n;
    }
    ranges.add(start == prev ? '$start' : '$start-$prev');
    return ranges.join(',');
  }
}
