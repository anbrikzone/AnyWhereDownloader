import 'package:anywhere_downloader/core/navigation/app_route_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a route dispatched before the shell is ready is delivered on init, '
      'and names map to routes', () async {
    final service = AppRouteService.instance;
    service.dispatchName('library'); // e.g. a plugin tap during cold start
    final got = <AppRoute>[];
    service.init(got.add);
    await pumpEventQueue();
    expect(got, [AppRoute.library]);

    service.dispatchName('downloads');
    service.dispatchName('something-else');
    service.dispatchName(null);
    expect(got, [AppRoute.library, AppRoute.downloads]);
  });
}
