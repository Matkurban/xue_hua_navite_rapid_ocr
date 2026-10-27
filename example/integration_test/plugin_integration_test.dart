import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_navite_rapid_ocr/xue_hua_navite_rapid_ocr.dart';

/// Real-device coverage of public OCR + Live Text APIs.
///
/// Run with:
/// `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/plugin_integration_test.dart`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late XueHuaNaviteRapidOcr ocr;
  late Uint8List helloPng;
  late Uint8List helloRgba;
  late int helloWidth;
  late int helloHeight;

  setUpAll(() async {
    ocr = XueHuaNaviteRapidOcr();
    final ByteData data = await rootBundle.load(
      'assets/test/rapidocr_hello_zh.png',
    );
    helloPng = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    expect(helloPng, isNotEmpty);

    final ui.Codec codec = await ui.instantiateImageCodec(helloPng);
    final ui.FrameInfo frame = await codec.getNextFrame();
    helloWidth = frame.image.width;
    helloHeight = frame.image.height;
    final ByteData? rgba = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    expect(rgba, isNotNull);
    helloRgba = rgba!.buffer.asUint8List();

    await ocr.initialize(
      OcrModelConfig.forLanguage(
        OcrLanguage.chineseAndEnglish,
        executionProvider: OcrExecutionProvider.cpu,
        numThreads: 2,
        enableHardwareAcceleration: false,
      ),
    );
    expect(ocr.isInitialized, isTrue);
  });

  tearDownAll(() async {
    await ocr.dispose();
    expect(ocr.isInitialized, isFalse);
  });

  testWidgets('recognizeBytes returns Hello/你好 from fixture PNG', (
    WidgetTester tester,
  ) async {
    final OcrResult result =
        await tester.runAsync(
              () => ocr.recognizeBytes(
                helloPng,
                options: const OcrRecognizeOptions(
                  maxSideLen: 960,
                  minConfidence: 0.3,
                  doAngle: true,
                ),
              ),
            )
            as OcrResult;

    expect(result.imageWidth, greaterThan(0));
    expect(result.imageHeight, greaterThan(0));
    expect(result.lines, isNotEmpty, reason: 'fullText=${result.fullText}');
    expect(result.fullText, contains('Hello'));
    expect(result.fullText, contains('你好'));
    expect(result.toMarkdown(), isNotEmpty);
    expect(result.toJson()['lines'], isA<List<dynamic>>());
  });

  testWidgets('recognizeRawPixels returns text from fixture RGBA', (
    WidgetTester tester,
  ) async {
    final OcrResult result =
        await tester.runAsync(
              () => ocr.recognizeRawPixels(
                pixels: helloRgba,
                width: helloWidth,
                height: helloHeight,
                format: OcrPixelFormat.rgba8888,
                options: const OcrRecognizeOptions(minConfidence: 0.3),
              ),
            )
            as OcrResult;

    expect(result.lines, isNotEmpty, reason: 'fullText=${result.fullText}');
    expect(
      result.fullText,
      anyOf(contains('Hello'), contains('你好'), contains('OCR')),
    );
  });

  testWidgets('recognizeFile reads a temp PNG path', (
    WidgetTester tester,
  ) async {
    final String path =
        '${Directory.systemTemp.path}${Platform.pathSeparator}xh_rapid_ocr_it.png';
    await File(path).writeAsBytes(helloPng, flush: true);

    final OcrResult result =
        await tester.runAsync(
              () => ocr.recognizeFile(
                path,
                options: const OcrRecognizeOptions(minConfidence: 0.3),
              ),
            )
            as OcrResult;

    expect(result.lines, isNotEmpty, reason: 'fullText=${result.fullText}');
    expect(result.fullText, anyOf(contains('Hello'), contains('你好')));
  });

  testWidgets('OcrLiveTextController selection + overlay pumps', (
    WidgetTester tester,
  ) async {
    final OcrResult result =
        await tester.runAsync(() => ocr.recognizeBytes(helloPng)) as OcrResult;
    expect(result.lines, isNotEmpty);

    final OcrLiveTextController controller = OcrLiveTextController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 240,
            child: OcrLiveTextOverlay(
              image: MemoryImage(helloPng),
              ocrResult: result,
              controller: controller,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.byType(OcrLiveTextOverlay), findsOneWidget);

    controller.selectAll(result.lines.length);
    await tester.pump();
    expect(controller.selectedIndices.length, result.lines.length);

    controller.clearSelection();
    await tester.pump();
    expect(controller.selectedIndices, isEmpty);

    controller.toggleHighlightBoxes(false);
    await tester.pump();
    expect(controller.showHighlightBoxes, isFalse);
  });

  testWidgets('complaint fixture returns Confidential text', (
    WidgetTester tester,
  ) async {
    final ByteData data = await rootBundle.load(
      'assets/test/ocr_overlay_complaint.png',
    );
    final Uint8List png = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );

    final OcrResult result =
        await tester.runAsync(() => ocr.recognizeBytes(png)) as OcrResult;
    expect(result.lines, isNotEmpty, reason: 'fullText=${result.fullText}');
    expect(result.fullText, contains('Confidential'));
  });
}
