import 'media_extractor.dart';

/// Maps a pasted URL to the extractor that can handle it (ТЗ §4.1). Only
/// `YouTubeExtractor` is registered so far — Instagram/X register here too
/// once they exist.
class ExtractorRegistry {
  ExtractorRegistry(this._extractors);

  final List<MediaExtractor> _extractors;

  MediaExtractor? resolve(String url) {
    for (final extractor in _extractors) {
      if (extractor.canHandle(url)) return extractor;
    }
    return null;
  }
}
