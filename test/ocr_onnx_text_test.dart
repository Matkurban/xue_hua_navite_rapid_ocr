import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_navite_rapid_ocr/xue_hua_navite_rapid_ocr.dart';

/// Real RapidOCR text. Skips when the host has not downloaded models, ONNX
/// Runtime 1.20.1, or a CMake build of the plugin:
/// `scripts/download_models.sh`, `scripts/download_onnxruntime.sh`,
/// `scripts/build_native.sh`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'recognizeBytes returns RapidOCR characters, not a placeholder',
    () async {
      final bool hasNativeEngine = File(
            'build/native/libxue_hua_navite_rapid_ocr.so',
          ).existsSync() ||
          File('build/native/libxue_hua_navite_rapid_ocr.dylib').existsSync() ||
          File('build/native/xue_hua_navite_rapid_ocr.dll').existsSync();
      final bool hasOrt = File('build/native/libonnxruntime.so.1').existsSync() ||
          File('build/native/libonnxruntime.dylib').existsSync() ||
          File('build/native/onnxruntime.dll').existsSync();
      final List<File> required = <File>[
        File('assets/models/ch_PP-OCRv4_det_mobile.onnx'),
        File('assets/models/ch_ppocr_mobile_v2.0_cls_mobile.onnx'),
        File('assets/models/ch_PP-OCRv4_rec_mobile.onnx'),
        File('assets/models/ppocr_keys_v1.txt'),
        File('test/fixtures/rapidocr_hello_zh.png'),
        File('example/ocr_overlay_complaint.png'),
      ];
      if (!hasNativeEngine ||
          !hasOrt ||
          required.any((File file) => !file.existsSync())) {
        markTestSkipped(
          'ONNX models, ONNX Runtime, or build/native are absent. '
          'Run scripts/download_models.sh, scripts/download_onnxruntime.sh, '
          'and scripts/build_native.sh.',
        );
      }

      final XueHuaNaviteRapidOcr ocr = XueHuaNaviteRapidOcr();
      await ocr.initialize(
        OcrModelConfig.forLanguage(
          OcrLanguage.chineseAndEnglish,
          executionProvider: OcrExecutionProvider.cpu,
          numThreads: 4,
          enableHardwareAcceleration: false,
        ),
      );
      addTearDown(ocr.dispose);

      final OcrResult hello = await ocr.recognizeBytes(
        await File('test/fixtures/rapidocr_hello_zh.png').readAsBytes(),
      );
      expect(hello.fullText, contains('Hello'));
      expect(hello.fullText, contains('你好'));
      expect(
        hello.lines.map((OcrTextLine line) => line.text),
        isNot(contains('\u2026')),
      );

      final OcrResult complaint = await ocr.recognizeBytes(
        await File('example/ocr_overlay_complaint.png').readAsBytes(),
      );
      expect(complaint.imageWidth, 822);
      expect(complaint.imageHeight, 1666);
      expect(complaint.fullText, contains('Confidential'));
      expect(
        complaint.lines.where((OcrTextLine line) => line.angle.abs() > 4),
        isEmpty,
      );
      expect(
        complaint.lines.map((OcrTextLine line) => line.text),
        isNot(contains('\u2026')),
      );
    },
  );
}
