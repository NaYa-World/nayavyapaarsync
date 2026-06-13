import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:godown_management/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: VyapaarSyncApp(),
      ),
    );

    // Verify that the root widget is rendered.
    expect(find.byType(VyapaarSyncApp), findsOneWidget);

    // Pump the timer of splash screen initialization
    await tester.pump(const Duration(seconds: 2));
  });
}
