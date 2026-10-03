import 'package:anywhere_downloader/core/yt_dlp_engine/yt_dlp_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

PlatformException _yt(String message) =>
    PlatformException(code: 'yt_dlp_error', message: message);

void main() {
  test('flags yt-dlp errors carrying its "update me" bug-report suffix', () {
    expect(
      looksLikeOutdatedYtDlp(_yt(
        'ERROR: [instagram] abc: Unable to extract data; please report this '
        'issue ... Confirm you are on the latest version using  yt-dlp -U',
      )),
      isTrue,
    );
    expect(
      looksLikeOutdatedYtDlp(_yt('ERROR: unable to download video data: HTTP Error 403: Forbidden')),
      isTrue,
    );
  });

  test('ignores expected errors and non-yt-dlp failures', () {
    expect(
      looksLikeOutdatedYtDlp(_yt(
        'ERROR: [instagram:story] You need to log in to access this content.',
      )),
      isFalse,
    );
    expect(
      looksLikeOutdatedYtDlp(
        PlatformException(code: 'unknown_error', message: 'yt-dlp -U'),
      ),
      isFalse,
    );
    expect(looksLikeOutdatedYtDlp(StateError('x')), isFalse);
  });
}
