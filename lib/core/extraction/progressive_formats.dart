import '../yt_dlp_engine/yt_dlp_engine.dart';
import 'media_extractor.dart';

/// `mp4-720p-30fp-crf28`-style quality token in a URL path (LinkedIn's
/// `dms.licdn.com` streams carry one; yt-dlp reports no height for them).
final _pathHeight = RegExp(r'[-_/](\d{3,4})p(?=[-_/.\d]|$)');

/// yt-dlp's height, else one parsed from the URL path, else 0.
int heightOf(RawFormat f) {
  if (f.height > 0) return f.height;
  final path = Uri.tryParse(f.url ?? '')?.path ?? '';
  final m = _pathHeight.firstMatch(path);
  return m == null ? 0 : int.parse(m.group(1)!);
}

/// `720p`-style label from the frame's *short* side when both sides are
/// known — a vertical 576×1024 video is "576p", not "1024p", same convention
/// as YouTube Shorts — else from [heightOf]. Null when nothing is known.
String? qualityLabelOf(RawFormat f) {
  final height = heightOf(f);
  if (f.width > 0 && height > 0) {
    return '${f.width < height ? f.width : height}p';
  }
  return height > 0 ? '${height}p' : null;
}

/// Progressive [formats] → one video variant per *distinguishable* quality,
/// best first. Ranked by height, then bitrate, then yt-dlp's own order
/// (it lists formats worst → best). Formats that nothing tells apart — same
/// height, bitrate and size, typically Instagram's `video_versions` that are
/// one asset under different signed URLs — collapse to the best-ranked one,
/// so the sheet never shows several identical "mp4 · size unknown" rows.
List<MediaVariant> progressiveVideoVariants(
  List<RawFormat> formats, {
  required int durationSeconds,
  String Function(RawFormat f)? container,
}) {
  final indexed = formats.indexed.toList()
    ..sort((a, b) {
      final byHeight = heightOf(b.$2).compareTo(heightOf(a.$2));
      if (byHeight != 0) return byHeight;
      final byTbr = b.$2.tbrKbps.compareTo(a.$2.tbrKbps);
      if (byTbr != 0) return byTbr;
      return b.$1.compareTo(a.$1);
    });

  final seen = <String>{};
  final variants = <MediaVariant>[];
  for (final (_, f) in indexed) {
    final url = f.url;
    if (url == null) continue;
    final height = heightOf(f);
    final size = f.estimatedSizeBytes(durationSeconds);
    final key = '$height|${f.tbrKbps.round()}|${size ?? 0}';
    if (!seen.add(key)) continue;
    variants.add(
      MediaVariant(
        type: MediaVariantType.video,
        resolutionLabel: qualityLabelOf(f),
        container: container?.call(f) ?? f.ext ?? 'mp4',
        approxSizeBytes: size,
        sourceUrl: url,
        requestHeaders: f.httpHeaders,
        bitrateKbps: f.tbrKbps > 0 ? f.tbrKbps.round() : null,
      ),
    );
  }
  return variants;
}
