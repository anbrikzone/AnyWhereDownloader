import 'package:anywhere_downloader/core/storage/status_archive_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StatusArchiveService archive-name encoding', () {
    test('round-trips a normal status filename', () {
      final encoded = StatusArchiveService.encodeName(1712345678901, 'abc123.jpg');
      expect(encoded, '1712345678901__abc123.jpg');

      final decoded = StatusArchiveService.decodeName(encoded);
      expect(decoded, isNotNull);
      expect(decoded!.archivedAtMillis, 1712345678901);
      expect(decoded.originalName, 'abc123.jpg');
    });

    test('keeps the original name intact when it contains a double underscore',
        () {
      final encoded = StatusArchiveService.encodeName(42, 'foo__bar.mp4');
      final decoded = StatusArchiveService.decodeName(encoded);
      expect(decoded!.archivedAtMillis, 42);
      expect(decoded.originalName, 'foo__bar.mp4');
    });

    test('rejects names that are not <millis>__<name>', () {
      expect(StatusArchiveService.decodeName('no-separator.jpg'), isNull);
      expect(StatusArchiveService.decodeName('__leading.jpg'), isNull);
      expect(StatusArchiveService.decodeName('123__'), isNull);
      expect(StatusArchiveService.decodeName('notanumber__x.jpg'), isNull);
    });
  });
}
