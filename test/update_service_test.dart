import 'dart:convert';

import 'package:anywhere_downloader/core/changelog/changelog.dart';
import 'package:anywhere_downloader/core/update/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _releaseJson(String tag) => jsonEncode({
      'tag_name': tag,
      'html_url': 'https://github.com/acme/app/releases/tag/$tag',
      'body': 'Notes for $tag',
      'assets': [
        {
          'name': 'app-arm64-v8a-release.apk',
          'browser_download_url': 'https://example.com/arm64.apk',
          'size': 80000000,
        },
        {
          'name': 'app-armeabi-v7a-release.apk',
          'browser_download_url': 'https://example.com/armv7.apk',
          'size': 73000000,
        },
      ],
    });

void main() {
  test('newer tag yields an UpdateInfo', () async {
    final svc = UpdateService(
      repoSlug: 'acme/app',
      client: MockClient(
        (_) async => http.Response(_releaseJson('v99.0.0'), 200),
      ),
    );
    final info = await svc.checkForUpdate();
    expect(info, isNotNull);
    expect(info!.version, '99.0.0');
    expect(info.releaseNotes, 'Notes for v99.0.0');
    expect(info.assets, hasLength(2));
  });

  test('equal version yields null', () async {
    final svc = UpdateService(
      repoSlug: 'acme/app',
      client: MockClient(
        (_) async => http.Response(_releaseJson('v$kAppVersion'), 200),
      ),
    );
    expect(await svc.checkForUpdate(), isNull);
  });

  test('older tag yields null', () async {
    final svc = UpdateService(
      repoSlug: 'acme/app',
      client: MockClient(
        (_) async => http.Response(_releaseJson('v0.0.1'), 200),
      ),
    );
    expect(await svc.checkForUpdate(), isNull);
  });

  test('non-200 yields null', () async {
    final svc = UpdateService(
      repoSlug: 'acme/app',
      client: MockClient((_) async => http.Response('nope', 404)),
    );
    expect(await svc.checkForUpdate(), isNull);
  });

  test('malformed JSON yields null', () async {
    final svc = UpdateService(
      repoSlug: 'acme/app',
      client: MockClient((_) async => http.Response('{ not json', 200)),
    );
    expect(await svc.checkForUpdate(), isNull);
  });

  test('placeholder repo slug never hits the network', () async {
    var called = false;
    final svc = UpdateService(
      client: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );
    expect(await svc.checkForUpdate(), isNull);
    expect(called, isFalse);
  });

  test('assetForAbis prefers the first supported ABI', () async {
    final svc = UpdateService(
      repoSlug: 'acme/app',
      client: MockClient(
        (_) async => http.Response(_releaseJson('v99.0.0'), 200),
      ),
    );
    final info = (await svc.checkForUpdate())!;

    expect(
      info.assetForAbis(['arm64-v8a', 'armeabi-v7a'])!.name,
      'app-arm64-v8a-release.apk',
    );
    expect(
      info.assetForAbis(['armeabi-v7a'])!.name,
      'app-armeabi-v7a-release.apk',
    );
    expect(info.assetForAbis(['x86_64']), isNull);
  });
}
