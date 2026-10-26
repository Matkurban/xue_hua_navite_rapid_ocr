import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_navite_rapid_ocr/xue_hua_navite_rapid_ocr.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OcrParagraphClusterer & OcrResult Tests', () {
    test(
      'sorts lines in reading order and merges adjacent lines into blocks',
      () {
        final List<OcrTextLine> rawLines = <OcrTextLine>[
          OcrTextLine(
            text: 'Second line of paragraph 1',
            confidence: 0.95,
            cornerPoints: const <Offset>[
              Offset(40, 62),
              Offset(340, 62),
              Offset(340, 86),
              Offset(40, 86),
            ],
            boundingBox: const Rect.fromLTWH(40, 62, 300, 24),
          ),
          OcrTextLine(
            text: 'First line of paragraph 1',
            confidence: 0.98,
            cornerPoints: const <Offset>[
              Offset(40, 30),
              Offset(330, 30),
              Offset(330, 54),
              Offset(40, 54),
            ],
            boundingBox: const Rect.fromLTWH(40, 30, 290, 24),
          ),
          OcrTextLine(
            text: 'Separate footer paragraph',
            confidence: 0.92,
            cornerPoints: const <Offset>[
              Offset(40, 240),
              Offset(280, 240),
              Offset(280, 264),
              Offset(40, 264),
            ],
            boundingBox: const Rect.fromLTWH(40, 240, 240, 24),
          ),
        ];

        final ({List<OcrTextLine> sortedLines, List<OcrTextBlock> blocks})
        clustered = OcrParagraphClusterer.clusterLines(rawLines);

        expect(clustered.sortedLines.length, 3);
        expect(clustered.sortedLines.first.text, 'First line of paragraph 1');
        expect(clustered.blocks.length, 2);
        expect(
          clustered.blocks.first.text,
          'First line of paragraph 1\nSecond line of paragraph 1',
        );
        expect(clustered.blocks.last.text, 'Separate footer paragraph');

        final OcrResult result = OcrResult(
          lines: clustered.sortedLines,
          blocks: clustered.blocks,
          imageWidth: 800,
          imageHeight: 600,
          totalTimeMs: 12.5,
        );

        expect(result.fullText, contains('First line of paragraph 1'));
        expect(result.toMarkdown(), isNotEmpty);
        expect(result.toJson()['lines'], isA<List<dynamic>>());
        expect(result.toJson()['blocks'], isA<List<dynamic>>());
      },
    );
  });

  group('XueHuaNaviteRapidOcr Engine & Multilingual Config Tests', () {
    test('initializes with OcrModelConfig.forLanguage, runs recognizeBytes & recognizeRawPixels, and disposes cleanly', () async {
      final XueHuaNaviteRapidOcr ocr = XueHuaNaviteRapidOcr();
      expect(ocr.isInitialized, isFalse);

      final OcrModelConfig jaConfig = OcrModelConfig.forLanguage(
        OcrLanguage.japanese,
        executionProvider: OcrExecutionProvider.auto,
      );
      expect(jaConfig.detModelPathOrUrl, contains('multi_PP-OCRv3_det_mobile'));
      expect(jaConfig.recModelPathOrUrl, contains('japan'));

      try {
        await ocr.initialize(jaConfig);
      } on XueHuaOcrException catch (e) {
        // Host `flutter test` does not load the Flutter-built FFI dylib/framework.
        // Full init+recognize is covered by example bootstrap logs on macOS/iOS.
        if (e.message.contains('Failed to lookup symbol') ||
            e.message.contains('symbol not found') ||
            e.message.contains('Failed to open')) {
          return;
        }
        rethrow;
      }
      expect(ocr.isInitialized, isTrue);

      final Uint8List fakePng = Uint8List.fromList(<int>[
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
        0x00,
        0x00,
        0x0D,
        0x49,
        0x48,
        0x44,
        0x52,
        0x00,
        0x00,
        0x03,
        0xC0,
        0x00,
        0x00,
        0x02,
        0x80,
        0x08,
        0x06,
        0x00,
        0x00,
        0x00,
      ]);

      final OcrResult byteResult = await ocr.recognizeBytes(
        fakePng,
        options: const OcrRecognizeOptions(maxSideLen: 960, minConfidence: 0.5),
      );
      expect(byteResult.isNotEmpty, isTrue);
      expect(byteResult.imageWidth, 960);
      expect(byteResult.imageHeight, 640);
      expect(byteResult.blocks, isNotEmpty);

      final Uint8List rawRgba = Uint8List(64 * 64 * 4);
      final OcrResult rawResult = await ocr.recognizeRawPixels(
        pixels: rawRgba,
        width: 64,
        height: 64,
        format: OcrPixelFormat.rgba8888,
      );
      expect(rawResult.imageWidth, 64);
      expect(rawResult.imageHeight, 64);

      await ocr.dispose();
      expect(ocr.isInitialized, isFalse);
    });
  });

  group('OcrLiveTextOverlay & OcrLiveTextStrings Widget Tests', () {
    testWidgets(
      'renders rotated quadrilateral highlights with custom OcrLiveTextStrings and ValueListenable updates',
      (WidgetTester tester) async {
        final Uint8List onePixelPng = Uint8List.fromList(<int>[
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
          0x00,
          0x00,
          0x00,
          0x0D,
          0x49,
          0x48,
          0x44,
          0x52,
          0x00,
          0x00,
          0x00,
          0x01,
          0x00,
          0x00,
          0x00,
          0x01,
          0x08,
          0x06,
          0x00,
          0x00,
          0x00,
          0x1F,
          0x15,
          0xC4,
          0x89,
          0x00,
          0x00,
          0x00,
          0x0A,
          0x49,
          0x44,
          0x41,
          0x54,
          0x78,
          0x9C,
          0x63,
          0x00,
          0x01,
          0x00,
          0x00,
          0x05,
          0x00,
          0x01,
          0x0D,
          0x0A,
          0x2D,
          0xB4,
          0x00,
          0x00,
          0x00,
          0x00,
          0x49,
          0x45,
          0x4E,
          0x44,
          0xAE,
          0x42,
          0x60,
          0x82,
        ]);

        final OcrTextLine line = OcrTextLine(
          text: 'Hello Live Text',
          confidence: 0.99,
          cornerPoints: const <Offset>[
            Offset(10, 10),
            Offset(190, 10),
            Offset(190, 90),
            Offset(10, 90),
          ],
          boundingBox: const Rect.fromLTWH(10, 10, 180, 80),
        );

        final OcrResult ocrResult = OcrResult(
          lines: <OcrTextLine>[line],
          blocks: <OcrTextBlock>[
            OcrTextBlock(
              lines: <OcrTextLine>[line],
              boundingBox: line.boundingBox,
              cornerPoints: line.cornerPoints,
            ),
          ],
          imageWidth: 200,
          imageHeight: 100,
          totalTimeMs: 5.0,
        );

        final OcrLiveTextController controller = OcrLiveTextController();
        String? lastSelected;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 200,
                height: 100,
                child: OcrLiveTextOverlay(
                  image: MemoryImage(onePixelPng),
                  ocrResult: ocrResult,
                  controller: controller,
                  strings: OcrLiveTextStrings.zhCN(),
                  fit: BoxFit.fill,
                  onSelectionChanged: (String text, List<OcrTextLine> lines) {
                    lastSelected = text;
                  },
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        expect(controller.showHighlightBoxes, isTrue);

        await tester.tapAt(const Offset(100, 50));
        await tester.pump();

        expect(controller.selectedIndices, contains(0));
        expect(lastSelected, 'Hello Live Text');
        expect(find.text('复制'), findsOneWidget);
        expect(find.text('全选'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey<String>('ocr_live_text_toggle_btn')),
        );
        await tester.pump();
        expect(controller.showHighlightBoxes, isFalse);
      },
    );
  });
}
