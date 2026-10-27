import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_navite_rapid_ocr/xue_hua_navite_rapid_ocr.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OcrImageCoordinateTransform', () {
    test('contain letterboxes and cover crops with center alignment', () {
      final OcrImageCoordinateTransform contain =
          OcrImageCoordinateTransform.compute(
            containerSize: const Size(100, 100),
            imageWidth: 200,
            imageHeight: 100,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            imageScale: 1,
          );
      expect(contain.imageToLocal(Offset.zero), const Offset(0, 25));
      expect(
        contain.imageToLocal(const Offset(200, 100)),
        const Offset(100, 75),
      );
      expect(contain.imageToLocal(const Offset(100, 50)), const Offset(50, 50));

      final OcrImageCoordinateTransform containTopLeft =
          OcrImageCoordinateTransform.compute(
            containerSize: const Size(100, 100),
            imageWidth: 200,
            imageHeight: 100,
            fit: BoxFit.contain,
            alignment: Alignment.topLeft,
            imageScale: 1,
          );
      expect(containTopLeft.imageToLocal(Offset.zero), Offset.zero);
      expect(
        containTopLeft.imageToLocal(const Offset(200, 100)),
        const Offset(100, 50),
      );

      final OcrImageCoordinateTransform wideContain =
          OcrImageCoordinateTransform.compute(
            containerSize: const Size(300, 100),
            imageWidth: 200,
            imageHeight: 100,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            imageScale: 1,
          );
      expect(
        wideContain.imageToLocal(const Offset(100, 50)),
        const Offset(150, 50),
      );
      expect(
        wideContain.containsImagePoint(
          wideContain.localToImage(const Offset(10, 50)),
        ),
        isFalse,
      );
      final Offset roundTrip = wideContain.imageToLocal(
        wideContain.localToImage(const Offset(150, 50)),
      );
      expect(roundTrip.dx, closeTo(150, 0.001));
      expect(roundTrip.dy, closeTo(50, 0.001));

      final OcrImageCoordinateTransform cover =
          OcrImageCoordinateTransform.compute(
            containerSize: const Size(100, 100),
            imageWidth: 200,
            imageHeight: 100,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            imageScale: 1,
          );
      expect(cover.imageToLocal(const Offset(50, 0)), Offset.zero);
      expect(
        cover.imageToLocal(const Offset(150, 100)),
        const Offset(100, 100),
      );
      expect(cover.imageToLocal(const Offset(100, 50)), const Offset(50, 50));
      expect(cover.imageToLocal(Offset.zero), const Offset(-50, 0));
      expect(cover.containsImagePoint(const Offset(100, 50)), isTrue);
      expect(cover.containsImagePoint(Offset.zero), isFalse);

      final OcrImageCoordinateTransform fill =
          OcrImageCoordinateTransform.compute(
            containerSize: const Size(100, 80),
            imageWidth: 200,
            imageHeight: 100,
            fit: BoxFit.fill,
            alignment: Alignment.center,
            imageScale: 1,
          );
      expect(fill.imageToLocal(const Offset(200, 100)), const Offset(100, 80));
      expect(fill.imageToLocal(const Offset(100, 50)), const Offset(50, 40));
    });

    test('BoxFit.none honors ImageInfo.scale', () {
      final OcrImageCoordinateTransform none =
          OcrImageCoordinateTransform.compute(
            containerSize: const Size(100, 100),
            imageWidth: 200,
            imageHeight: 100,
            fit: BoxFit.none,
            alignment: Alignment.center,
            imageScale: 2,
          );
      expect(none.imageToLocal(Offset.zero), const Offset(0, 25));
      expect(none.imageToLocal(const Offset(200, 100)), const Offset(100, 75));
      expect(none.imageToLocal(const Offset(100, 50)), const Offset(50, 50));
    });
  });

  group('EXIF and displayed image space', () {
    test('orientations 1..8 round-trip continuous coordinates', () {
      const int rawW = 100;
      const int rawH = 80;
      const List<Offset> samples = <Offset>[
        Offset(0, 0),
        Offset(10, 20),
        Offset(100, 80),
        Offset(37.5, 12.25),
      ];
      for (int orientation = 1; orientation <= 8; orientation++) {
        final bool swap = orientation >= 5;
        final int correctedW = swap ? rawH : rawW;
        final int correctedH = swap ? rawW : rawH;
        expect(
          OcrExifCoordinateMapper.rawSize(
            correctedWidth: correctedW,
            correctedHeight: correctedH,
            orientation: orientation,
          ),
          const Size(100, 80),
        );
        for (final Offset raw in samples) {
          final Offset corrected = OcrExifCoordinateMapper.rawToCorrected(
            raw,
            rawWidth: rawW,
            rawHeight: rawH,
            orientation: orientation,
          );
          final Offset back = OcrExifCoordinateMapper.correctedToRaw(
            corrected,
            correctedWidth: correctedW,
            correctedHeight: correctedH,
            orientation: orientation,
          );
          expect(back.dx, closeTo(raw.dx, 1e-6), reason: 'orient $orientation');
          expect(back.dy, closeTo(raw.dy, 1e-6), reason: 'orient $orientation');
        }
      }
    });

    test('resolve keeps matching sizes and maps EXIF or uniform scale', () {
      final OcrDisplayedImageSpace same = OcrDisplayedImageSpace.resolve(
        correctedWidth: 200,
        correctedHeight: 100,
        exifOrientation: 1,
        decodedPixelSize: const Size(200, 100),
      );
      expect(same.toDisplay(const Offset(10, 20)), const Offset(10, 20));

      final OcrDisplayedImageSpace swapped = OcrDisplayedImageSpace.resolve(
        correctedWidth: 200,
        correctedHeight: 100,
        exifOrientation: 6,
        decodedPixelSize: const Size(100, 200),
      );
      expect(swapped.imageWidth, 100);
      expect(swapped.imageHeight, 200);
      expect(swapped.toDisplay(const Offset(40, 10)), const Offset(10, 160));

      final OcrDisplayedImageSpace scaled = OcrDisplayedImageSpace.resolve(
        correctedWidth: 200,
        correctedHeight: 100,
        exifOrientation: 1,
        decodedPixelSize: const Size(400, 200),
      );
      expect(scaled.toDisplay(const Offset(10, 20)), const Offset(20, 40));

      final OcrDisplayedImageSpace stretched = OcrDisplayedImageSpace.resolve(
        correctedWidth: 200,
        correctedHeight: 100,
        exifOrientation: 1,
        decodedPixelSize: const Size(300, 100),
      );
      expect(stretched.imageWidth, 300);
      expect(stretched.imageHeight, 100);
      expect(stretched.toDisplay(const Offset(10, 20)), const Offset(15, 20));

      final OcrDisplayedImageSpace tiny = OcrDisplayedImageSpace.resolve(
        correctedWidth: 200,
        correctedHeight: 100,
        exifOrientation: 1,
        decodedPixelSize: const Size(1, 1),
      );
      expect(tiny.imageWidth, 1);
      expect(tiny.imageHeight, 1);
      expect(tiny.toDisplay(const Offset(100, 50)), const Offset(0.5, 0.5));

      final OcrDisplayedImageSpace pending = OcrDisplayedImageSpace.resolve(
        correctedWidth: 200,
        correctedHeight: 100,
        exifOrientation: 6,
        decodedPixelSize: null,
      );
      expect(pending.imageWidth, 200);
      expect(pending.toDisplay(const Offset(10, 20)), const Offset(10, 20));
    });
  });

  group('OcrLiveTextGeometry', () {
    OcrTextLine line({
      String text = 'Treasury',
      double confidence = 0.9,
      double boxScore = 0.8,
      List<Offset>? corners,
    }) {
      final List<Offset> points =
          corners ??
          const <Offset>[
            Offset(10, 20),
            Offset(110, 20),
            Offset(110, 40),
            Offset(10, 40),
          ];
      return OcrTextLine(
        text: text,
        confidence: confidence,
        cornerPoints: points,
        boundingBox: OcrLiveTextGeometry.polygonBounds(points),
        boxScore: boxScore,
      );
    }

    test('drops empty, low-score, and degenerate boxes', () {
      expect(
        OcrLiveTextGeometry.isDisplayable(
          line(text: '   '),
          imageWidth: 200,
          imageHeight: 100,
          minConfidence: 0.05,
          minBoxScore: 0.05,
        ),
        isFalse,
      );
      expect(
        OcrLiveTextGeometry.isDisplayable(
          line(confidence: 0.01),
          imageWidth: 200,
          imageHeight: 100,
          minConfidence: 0.05,
          minBoxScore: 0.05,
        ),
        isFalse,
      );
      expect(
        OcrLiveTextGeometry.isDisplayable(
          line(boxScore: 0),
          imageWidth: 200,
          imageHeight: 100,
          minConfidence: 0.05,
          minBoxScore: 0.05,
        ),
        isFalse,
      );
      expect(
        OcrLiveTextGeometry.isDisplayable(
          line(
            corners: const <Offset>[
              Offset(1, 1),
              Offset(1.2, 1),
              Offset(1.2, 1.2),
              Offset(1, 1.2),
            ],
          ),
          imageWidth: 200,
          imageHeight: 100,
          minConfidence: 0.05,
          minBoxScore: 0.05,
        ),
        isFalse,
      );
      expect(
        OcrLiveTextGeometry.isDisplayable(
          line(),
          imageWidth: 200,
          imageHeight: 100,
          minConfidence: 0.05,
          minBoxScore: 0.05,
        ),
        isTrue,
      );
    });

    test('snaps a 1.5 degree shear and keeps a 12 degree quad ordered', () {
      const double rise = 5.236;
      final OcrTextLine sheared = line(
        corners: const <Offset>[
          Offset(10, 20 - rise / 2),
          Offset(210, 20 + rise / 2),
          Offset(210, 40 + rise / 2),
          Offset(10, 40 - rise / 2),
        ],
      );
      final OcrTextLine snapped = OcrLiveTextGeometry.sanitize(
        sheared,
        axisSnapDegrees: 4,
      );
      expect(snapped.angle, 0);
      expect(
        snapped.cornerPoints[0].dy,
        closeTo(snapped.cornerPoints[1].dy, 1e-6),
      );
      expect(
        snapped.cornerPoints[3].dy,
        closeTo(snapped.cornerPoints[2].dy, 1e-6),
      );
      expect(snapped.cornerPoints[0].dx, closeTo(10, 0.01));
      expect(snapped.cornerPoints[1].dx, closeTo(210, 0.01));

      final List<Offset> rotated = _rotatedQuad(
        center: const Offset(100, 50),
        halfWidth: 80,
        halfHeight: 10,
        degrees: 12,
      );
      final OcrTextLine kept = OcrLiveTextGeometry.sanitize(
        line(corners: <Offset>[rotated[2], rotated[0], rotated[3], rotated[1]])
            .copyWith(angle: 12),
        axisSnapDegrees: 4,
      );
      expect(kept.angle, 12);
      expect(
        kept.cornerPoints[0].dx + kept.cornerPoints[0].dy,
        lessThan(kept.cornerPoints[2].dx + kept.cornerPoints[2].dy),
      );
      final double topDeg = _edgeDegrees(
        kept.cornerPoints[1] - kept.cornerPoints[0],
      );
      expect(topDeg.abs(), greaterThan(8));
      expect(topDeg.abs(), lessThan(16));
    });

    test('hit testing uses the outset quad', () {
      final OcrImageCoordinateTransform transform =
          OcrImageCoordinateTransform.compute(
            containerSize: const Size(200, 100),
            imageWidth: 200,
            imageHeight: 100,
            fit: BoxFit.fill,
            alignment: Alignment.center,
            imageScale: 1,
          );
      final List<Offset> quad = OcrLiveTextGeometry.paintedQuad(
        imageCorners: line().cornerPoints,
        transform: transform,
        outset: 1.25,
      );
      expect(
        OcrLiveTextGeometry.containsPoint(const Offset(60, 30), quad),
        isTrue,
      );
      expect(
        OcrLiveTextGeometry.containsPoint(const Offset(1, 1), quad),
        isFalse,
      );
      expect(
        OcrLiveTextGeometry.quadIntersectsRect(
          quad,
          const Rect.fromLTWH(100, 20, 20, 10),
        ),
        isTrue,
      );
    });
  });

  group('OcrInkLineLocalizer', () {
    test('hugs upright stroke runs and ignores chrome', () {
      const int width = 320;
      const int height = 160;
      final Uint8List rgba = Uint8List(width * height * 4);
      _fill(rgba, const Color(0xFFF4F5F8));
      _strokeRun(rgba, width, x0: 24, x1: 200, y0: 30, y1: 48);
      _strokeRun(rgba, width, x0: 24, x1: 160, y0: 80, y1: 96);
      _fillRect(rgba, width, 230, 30, 300, 70, const Color(0xFF1B1B1F));
      _fillRect(rgba, width, 4, 0, 6, height, const Color(0xFF1B1B1F));
      _fillRect(rgba, width, 10, 140, 300, 142, const Color(0xFF1B1B1F));

      final List<OcrLocalizedInkLine> found = OcrInkLineLocalizer.localize(
        rgba: rgba,
        width: width,
        height: height,
      );
      expect(found, isNotEmpty);
      expect(found.length, lessThanOrEqualTo(3));
      for (final OcrLocalizedInkLine line in found) {
        expect(line.angle.abs(), lessThan(1.5));
        expect(line.boundingBox.height, lessThan(40));
        expect(line.boundingBox.left, greaterThan(10));
        expect(line.boundingBox.right, lessThan(220));
        expect(line.cornerPoints[0].dy, closeTo(line.cornerPoints[1].dy, 0.01));
        final double cy = line.boundingBox.center.dy;
        expect(
          (cy - 39).abs() < 14 || (cy - 88).abs() < 14,
          isTrue,
          reason: 'center y $cy',
        );
        expect(
          line.boundingBox.center.dx > 230 && line.boundingBox.center.dx < 300,
          isFalse,
        );
      }

      final List<OcrTextLine> labeled = OcrInkLineLocalizer.toTextLines(
        lines: found,
        imageWidth: width,
        imageHeight: height,
      );
      expect(labeled, isNotEmpty);
      expect(
        labeled.every((OcrTextLine line) => line.text == '\u2026'),
        isTrue,
      );
      expect(
        labeled.every((OcrTextLine line) => line.text.trim().isNotEmpty),
        isTrue,
      );
    });

    test('blank and chrome-only bitmaps produce no lines', () {
      final Uint8List blank = Uint8List(80 * 80 * 4);
      _fill(blank, const Color(0xFFFFFFFF));
      expect(
        OcrInkLineLocalizer.localize(rgba: blank, width: 80, height: 80),
        isEmpty,
      );

      const int width = 200;
      const int height = 120;
      final Uint8List chrome = Uint8List(width * height * 4);
      _fill(chrome, const Color(0xFFFFFFFF));
      _fillRect(chrome, width, 20, 20, 160, 80, const Color(0xFF222222));
      _fillRect(chrome, width, 2, 0, 4, height, const Color(0xFF222222));
      _fillRect(chrome, width, 8, 100, 190, 102, const Color(0xFF222222));
      expect(
        OcrInkLineLocalizer.localize(
          rgba: chrome,
          width: width,
          height: height,
        ),
        isEmpty,
      );
    });

    test('undecoded demo sheet is axis-aligned', () {
      final List<OcrTextLine> demo = OcrInkLineLocalizer.undecodedDemoLines(
        width: 960,
        height: 640,
      );
      expect(demo.length, 6);
      for (final OcrTextLine line in demo) {
        expect(line.angle, 0);
        expect(line.text.trim(), isNotEmpty);
        expect(line.cornerPoints[0].dy, line.cornerPoints[1].dy);
        expect(line.cornerPoints[0].dx, line.cornerPoints[3].dx);
      }
    });
  });

  group('OcrLiveTextOverlay alignment', () {
    testWidgets('contain letterbox hits the glyph and misses the margin', (
      WidgetTester tester,
    ) async {
      final Uint8List png = _solidPng(200, 100);
      final OcrTextLine line = OcrTextLine(
        text: 'Confidential Treasury',
        confidence: 0.97,
        cornerPoints: const <Offset>[
          Offset(40, 30),
          Offset(160, 30),
          Offset(160, 70),
          Offset(40, 70),
        ],
        boundingBox: const Rect.fromLTWH(40, 30, 120, 40),
      );
      final OcrTextLine empty = OcrTextLine(
        text: '',
        confidence: 0.99,
        cornerPoints: const <Offset>[
          Offset(20, 5),
          Offset(180, 5),
          Offset(180, 20),
          Offset(20, 20),
        ],
        boundingBox: const Rect.fromLTWH(20, 5, 160, 15),
        boxScore: 0.9,
      );
      final OcrResult result = OcrResult(
        lines: <OcrTextLine>[empty, line],
        blocks: const <OcrTextBlock>[],
        imageWidth: 200,
        imageHeight: 100,
        totalTimeMs: 1,
      );
      final OcrLiveTextController controller = OcrLiveTextController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 100,
              child: OcrLiveTextOverlay(
                image: MemoryImage(png),
                ocrResult: result,
                controller: controller,
                layout: const OcrLiveTextLayout(
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final Rect overlay = tester.getRect(find.byType(OcrLiveTextOverlay));
      await tester.tapAt(overlay.topLeft + const Offset(10, 50));
      await tester.pump();
      expect(controller.selectedIndices, isEmpty);

      await tester.tapAt(overlay.center);
      await tester.pump();
      expect(controller.selectedIndices, <int>{1});
    });
  });
}

List<Offset> _rotatedQuad({
  required Offset center,
  required double halfWidth,
  required double halfHeight,
  required double degrees,
}) {
  final double rad = degrees * math.pi / 180;
  final double c = math.cos(rad);
  final double s = math.sin(rad);
  Offset rot(double x, double y) {
    return Offset(center.dx + x * c - y * s, center.dy + x * s + y * c);
  }

  return <Offset>[
    rot(-halfWidth, -halfHeight),
    rot(halfWidth, -halfHeight),
    rot(halfWidth, halfHeight),
    rot(-halfWidth, halfHeight),
  ];
}

double _edgeDegrees(Offset edge) {
  return math.atan2(edge.dy, edge.dx) * 180 / math.pi;
}

void _fill(Uint8List rgba, Color color) {
  final int r = (color.r * 255).round();
  final int g = (color.g * 255).round();
  final int b = (color.b * 255).round();
  final int a = (color.a * 255).round();
  for (int i = 0; i < rgba.length; i += 4) {
    rgba[i] = r;
    rgba[i + 1] = g;
    rgba[i + 2] = b;
    rgba[i + 3] = a;
  }
}

void _fillRect(
  Uint8List rgba,
  int width,
  int x0,
  int y0,
  int x1,
  int y1,
  Color color,
) {
  final int r = (color.r * 255).round();
  final int g = (color.g * 255).round();
  final int b = (color.b * 255).round();
  final int a = (color.a * 255).round();
  final int height = rgba.length ~/ (width * 4);
  final int left = x0.clamp(0, width);
  final int right = x1.clamp(0, width);
  final int top = y0.clamp(0, height);
  final int bottom = y1.clamp(0, height);
  for (int y = top; y < bottom; y++) {
    for (int x = left; x < right; x++) {
      final int i = (y * width + x) * 4;
      rgba[i] = r;
      rgba[i + 1] = g;
      rgba[i + 2] = b;
      rgba[i + 3] = a;
    }
  }
}

void _strokeRun(
  Uint8List rgba,
  int width, {
  required int x0,
  required int x1,
  required int y0,
  required int y1,
}) {
  for (int x = x0; x < x1; x += 5) {
    _fillRect(rgba, width, x, y0, x + 2, y1, const Color(0xFF1A1A1A));
  }
}

/// Uncompressed-scanline PNG. Built without `dart:ui` so widget tests do not
/// wait on a picture `toImage` call that the test zone never completes.
Uint8List _solidPng(int width, int height) {
  final BytesBuilder raw = BytesBuilder(copy: false);
  final Uint8List row = Uint8List(1 + width * 4);
  for (int x = 0; x < width; x++) {
    row[1 + x * 4] = 255;
    row[2 + x * 4] = 255;
    row[3 + x * 4] = 255;
    row[4 + x * 4] = 255;
  }
  for (int y = 0; y < height; y++) {
    raw.add(row);
  }
  final List<int> idat = ZLibEncoder().convert(raw.takeBytes());
  final BytesBuilder png = BytesBuilder(copy: false);
  png.add(const <int>[137, 80, 78, 71, 13, 10, 26, 10]);
  final ByteData ihdr = ByteData(13);
  ihdr.setUint32(0, width);
  ihdr.setUint32(4, height);
  ihdr.setUint8(8, 8);
  ihdr.setUint8(9, 6);
  _pngChunk(png, 'IHDR', ihdr.buffer.asUint8List());
  _pngChunk(png, 'IDAT', idat);
  _pngChunk(png, 'IEND', const <int>[]);
  return png.toBytes();
}

void _pngChunk(BytesBuilder out, String type, List<int> data) {
  final Uint8List typeBytes = ascii.encode(type);
  final ByteData header = ByteData(8);
  header.setUint32(0, data.length);
  out.add(header.buffer.asUint8List(0, 4));
  out.add(typeBytes);
  out.add(data);
  final BytesBuilder crcInput = BytesBuilder(copy: false);
  crcInput.add(typeBytes);
  crcInput.add(data);
  header.setUint32(4, _crc32(crcInput.toBytes()));
  out.add(header.buffer.asUint8List(4, 4));
}

int _crc32(List<int> data) {
  int crc = 0xFFFFFFFF;
  for (final int byte in data) {
    crc ^= byte;
    for (int i = 0; i < 8; i++) {
      if ((crc & 1) != 0) {
        crc = (crc >> 1) ^ 0xEDB88320;
      } else {
        crc >>= 1;
      }
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
