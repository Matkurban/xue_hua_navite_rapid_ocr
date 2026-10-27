import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xue_hua_navite_rapid_ocr_example/main.dart' as app;

/// Smoke-drives the example app bootstrap (engine init + sample OCR).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('example boots and shows RapidOCR demo chrome', (
    WidgetTester tester,
  ) async {
    app.main();
    await tester.pump();

    final DateTime deadline = DateTime.now().add(const Duration(seconds: 120));
    bool sawTitle = false;
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.textContaining('RapidOCR').evaluate().isNotEmpty ||
          find.textContaining('OCR').evaluate().isNotEmpty ||
          find.textContaining('Engine').evaluate().isNotEmpty) {
        sawTitle = true;
        break;
      }
    }
    expect(sawTitle, isTrue, reason: 'example UI never showed OCR chrome');

    // Keep the tree mounted briefly so bootstrap async can finish without setState-after-dispose.
    await tester.pump(const Duration(seconds: 2));
  });
}
