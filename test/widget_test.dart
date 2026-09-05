import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anywhere_downloader/main.dart';

void main() {
  testWidgets('App shows the home screen with a WhatsApp tile', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: AnyWhereDownloaderApp()),
    );
    await tester.pump();

    expect(find.text('AnyWhere Downloader'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
  });
}
