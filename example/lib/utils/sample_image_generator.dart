import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:xue_hua_navite_rapid_ocr/xue_hua_navite_rapid_ocr.dart';

/// Generates synthetic sample document images (PNG bytes + raw RGBA8888 bytes)
/// tailored to the selected [OcrLanguage] so users can test multilingual OCR
/// and `OcrLiveTextOverlay` offline as well as with picked local images.
class SampleImageGenerator {
  const SampleImageGenerator._();

  static Future<({Uint8List pngBytes, Uint8List rawRgbaBytes})>
  generateForLanguage(OcrLanguage language) async {
    const int width = 960;
    const int height = 640;
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );

    final Paint bgPaint = Paint()..color = const Color(0xFFF8FAFC);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      bgPaint,
    );

    final Paint cardBorder = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(24, 24, width - 48, height - 48),
        const Radius.circular(16),
      ),
      cardBorder,
    );

    void drawDocLine(
      String text,
      Offset pos, {
      double fontSize = 25,
      FontWeight weight = FontWeight.w600,
      Color color = const Color(0xFF0F172A),
      double tiltDeg = 0.0,
    }) {
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      if (tiltDeg != 0.0) {
        canvas.rotate(tiltDeg * math.pi / 180.0);
      }
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: weight,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width - 96);
      tp.paint(canvas, Offset.zero);
      canvas.restore();
    }

    final List<String> lines = _sampleLinesForLanguage(language);

    drawDocLine(
      lines[0],
      const Offset(58, 52),
      fontSize: 29,
      weight: FontWeight.w800,
      color: const Color(0xFF1E3A8A),
    );
    drawDocLine(
      lines[1],
      const Offset(58, 108),
      fontSize: 24,
      color: const Color(0xFF334155),
    );
    drawDocLine(
      lines[2],
      const Offset(58, 205),
      fontSize: 24,
      color: const Color(0xFF0F766E),
      tiltDeg: -1.5,
    );
    drawDocLine(
      lines[3],
      const Offset(58, 262),
      fontSize: 24,
      color: const Color(0xFF0F766E),
      tiltDeg: -1.5,
    );
    drawDocLine(
      lines[4],
      const Offset(76, 396),
      fontSize: 24,
      color: const Color(0xFF1E293B),
    );
    drawDocLine(
      lines[5],
      const Offset(76, 454),
      fontSize: 24,
      weight: FontWeight.w700,
      color: const Color(0xFFB91C1C),
    );

    final ui.Picture picture = recorder.endRecording();
    final ui.Image img = await picture.toImage(width, height);
    final ByteData? pngData = await img.toByteData(
      format: ui.ImageByteFormat.png,
    );
    final ByteData? rawRgbaData = await img.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );

    return (
      pngBytes: pngData?.buffer.asUint8List() ?? Uint8List(0),
      rawRgbaBytes: rawRgbaData?.buffer.asUint8List() ?? Uint8List(0),
    );
  }

  static List<String> _sampleLinesForLanguage(OcrLanguage language) {
    switch (language) {
      case OcrLanguage.japanese:
        return <String>[
          'XueHua RapidOCR 日本語・多言語認識 v1.0.0',
          'PP-OCRv4 / PP-OCRv5 ONNX 高速推論エンジン',
          'ゼロコピー FFI Isolate + WebGPU/WASM 6プラットフォーム対応',
          'DBNet 傾斜ボックス検出・AngleNet 角度補正・CTC デコード',
          '請求書番号: #INV-2026-0892   発行日: 2026-10-26',
          '合計金額: ¥185,000 JPY (オフライン決済完了)',
        ];
      case OcrLanguage.korean:
        return <String>[
          'XueHua RapidOCR 한국어 다국어 인식 v1.0.0',
          'PP-OCRv4 / PP-OCRv5 ONNX 고성능 추론 파이프라인',
          '제로카피 FFI Isolate + WebGPU/WASM 6대 플랫폼 통합 지원',
          'DBNet 다각형 텍스트 검출 및 AngleNet 방향 보정',
          '청구서 번호: #INV-2026-0892   일자: 2026-10-26',
          '총 결제 금액: ₩1,680,000 KRW (오프라인 결제)',
        ];
      case OcrLanguage.latin:
      case OcrLanguage.english:
        return <String>[
          'XueHua Native RapidOCR Multilingual v1.0.0',
          'PP-OCRv4 / PP-OCRv5 ONNX Runtime Pipeline',
          'Français / Deutsch / Español / Italiano / Português',
          'Zero-Copy FFI Isolate + WebGPU/WASM 6-Platform Engine',
          'Invoice #INV-2026-0892   Date: 2026-10-26',
          'Total Amount: €1,280.00 EUR (Paid Offline)',
        ];
      case OcrLanguage.cyrillic:
        return <String>[
          'XueHua RapidOCR Кириллица / Русский v1.0.0',
          'PP-OCRv4 / PP-OCRv5 ONNX локальное распознавание',
          'Поддержка 6 платформ: Android, iOS, Desktop и Web',
          'DBNet детекция полигонов и коррекция угла поворота',
          'Счет № INV-2026-0892   Дата: 2026-10-26',
          'Итого к оплате: 128 000 ₽ RUB',
        ];
      case OcrLanguage.arabic:
        return <String>[
          'XueHua RapidOCR العربية متعدد اللغات v1.0.0',
          'PP-OCRv4 / PP-OCRv5 ONNX Runtime Pipeline',
          'التعرف الضوئي على الحروف بدون اتصال عبر 6 منصات',
          'دعم كامل للغة العربية والإنجليزية والأرقام',
          'Invoice #INV-2026-0892   Date: 2026-10-26',
          'Total Amount: 4,800.00 SAR',
        ];
      case OcrLanguage.chineseAndEnglish:
      case OcrLanguage.multilingual:
        return <String>[
          'XueHua Native RapidOCR v1.0.0',
          'PP-OCRv4 / PP-OCRv5 ONNX Runtime Pipeline',
          '零拷贝 FFI Worker Isolate + WebGPU/WASM 六端统一推理',
          '支持 DBNet 多边形检测、AngleNet 方向校正与 CTC 解码',
          'Invoice #INV-2026-0892   Date: 2026-10-26',
          'Total Amount: \$1,280.00 USD (Paid Offline)',
        ];
    }
  }
}
