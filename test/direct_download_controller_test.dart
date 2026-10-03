import 'package:anywhere_downloader/core/extraction/media_extractor.dart';
import 'package:anywhere_downloader/core/l10n/status_message.dart';
import 'package:anywhere_downloader/features/direct_download/direct_download_controller.dart';
import 'package:anywhere_downloader/features/direct_download/direct_download_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeExtractor implements MediaExtractor {
  _FakeExtractor({this.handles = true, this.error});

  final bool handles;
  final Object? error;

  @override
  ServiceType get serviceType => ServiceType.tiktok;

  @override
  bool canHandle(String url) => handles;

  @override
  Future<MediaInfo> extract(String url) async {
    if (error != null) throw error!;
    return MediaInfo(title: 't', thumbnailUrl: null, variants: const []);
  }
}

const _directTypes = [
  ServiceType.tiktok,
  ServiceType.xTwitter,
  ServiceType.instagram,
  ServiceType.linkedin,
  ServiceType.pinterest,
];

void main() {
  test('exactly the direct-download services are configured', () {
    for (final type in ServiceType.values) {
      final service = DirectDownloadService.of(type);
      if (_directTypes.contains(type)) {
        expect(service?.type, type);
      } else {
        expect(service, isNull, reason: '$type has its own feature');
      }
    }
  });

  test('X/Twitter saves into a slash-free folder', () {
    expect(DirectDownloadService.xTwitter.librarySource, isNot(contains('/')));
  });

  for (final type in _directTypes) {
    final service = DirectDownloadService.of(type)!;

    test('${service.title}: empty title falls back to its own file name', () {
      final controller = DirectDownloadController(
        service,
        extractor: _FakeExtractor(),
      );
      expect(controller.suggestedFileName('  '), service.fallbackFileName);
      expect(controller.suggestedFileName('a/b:c'), 'a_b_c');
    });

    test('${service.title}: a foreign link gets its "not a … link" status', () async {
      final controller = DirectDownloadController(
        service,
        extractor: _FakeExtractor(handles: false),
      );
      expect(await controller.fetchInfo('https://example.com/x'), isNull);
      expect(controller.state.statusMessage?.key, service.notHandledKey);
    });

    test('${service.title}: a generic fetch failure uses its fetch-failed key', () async {
      final controller = DirectDownloadController(
        service,
        extractor: _FakeExtractor(error: StateError('boom')),
      );
      expect(await controller.fetchInfo('https://example.com/x'), isNull);
      expect(controller.state.statusMessage?.key, service.fetchFailedKey);
      expect(controller.state.fetching, isFalse);
    });
  }

  test('an ExtractionException keeps its code and detail for localizing',
      () async {
    final controller = DirectDownloadController(
      DirectDownloadService.tiktok,
      extractor: _FakeExtractor(
        error: ExtractionException(
          ExtractionErrorCode.lookupHttpError,
          detail: 'HTTP 503',
        ),
      ),
    );
    await controller.fetchInfo('https://www.tiktok.com/@a/video/1');
    final message = controller.state.statusMessage;
    expect(message?.key, StatusMessageKey.extractionFailed);
    expect(message?.extractionCode, ExtractionErrorCode.lookupHttpError);
    expect(message?.error, 'HTTP 503');
  });
}
