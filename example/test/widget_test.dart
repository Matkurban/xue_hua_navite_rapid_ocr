import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_navite_rapid_ocr_example/main.dart';

void main() {
  testWidgets('XueHuaRapidOcrExampleApp renders tabs and controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const XueHuaRapidOcrExampleApp());
    expect(find.text('XueHua Native RapidOCR (6-Platform)'), findsOneWidget);
    expect(find.text('Live Text Overlay'), findsOneWidget);
    expect(find.text('Paragraph Blocks'), findsOneWidget);
  });
}
