import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_navite_rapid_ocr/xue_hua_navite_rapid_ocr.dart';

/// Owner screenshot of the XueHua vault UI with the skewed highlight quads
/// already painted into the pixels. This file is the original attachment
/// (638636 bytes, 822×1666), not a synthetic stand-in.
const String _kComplaintPng = 'example/ocr_overlay_complaint.png';

void main() {
  final AutomatedTestWidgetsFlutterBinding binding =
      AutomatedTestWidgetsFlutterBinding.ensureInitialized();

  test('complaint screenshot keeps horizontal UI runs untilted', () async {
    final File file = File(_kComplaintPng);
    expect(file.existsSync(), isTrue, reason: 'missing $_kComplaintPng');
    expect(file.lengthSync(), 638636, reason: 'fixture must be the owner PNG');
    final ({int width, int height, Uint8List rgba}) image = await _decodePng(
      binding,
      file.readAsBytesSync(),
    );
    expect(image.width, 822);
    expect(image.height, 1666);
    final List<OcrTextLine> lines = _recognize(
      image.rgba,
      image.width,
      image.height,
    );
    final List<OcrTextLine> tilted = lines
        .where((OcrTextLine line) => line.angle.abs() > 4)
        .toList();
    expect(
      tilted,
      isEmpty,
      reason:
          'tilted=${tilted.length} '
          'angles=${tilted.map((OcrTextLine l) => l.angle.toStringAsFixed(2)).toList()}',
    );
    expect(lines.length, greaterThanOrEqualTo(15));
    for (final OcrTextLine line in lines) {
      expect(line.angle.abs(), lessThanOrEqualTo(4));
      expect(
        (line.cornerPoints[0].dy - line.cornerPoints[1].dy).abs(),
        lessThan(0.6),
      );
      expect(line.text.trim(), isNotEmpty);
    }
  });

  test('a real 12 degree stroke run stays tilted and hairlines do not', () {
    const int width = 400;
    const int height = 200;
    final Uint8List tilted = _blank(width, height);
    for (int x = 30; x < 280; x += 5) {
      final int y = 40 + ((x - 30) * 0.2126).round();
      _stroke(tilted, width, x, y, y + 16);
    }
    final List<OcrTextLine> rotated = _recognize(tilted, width, height);
    expect(rotated, hasLength(1));
    expect(rotated.single.angle.abs(), inInclusiveRange(8, 16));

    final Uint8List edges = _blank(width, height);
    for (int x = 40; x < 140; x++) {
      final int y = 50 + ((x - 40) * 0.276).round();
      _stroke(edges, width, x, y, y + 2);
    }
    for (int x = 180; x < 280; x++) {
      final int y = 90 - ((x - 180) * 0.276).round();
      _stroke(edges, width, x, y, y + 3);
    }
    final List<OcrTextLine> junk = _recognize(edges, width, height);
    expect(junk.where((OcrTextLine line) => line.angle.abs() > 4), isEmpty);
  });
}

List<OcrTextLine> _recognize(Uint8List rgba, int width, int height) {
  return OcrInkLineLocalizer.toTextLines(
    lines: OcrInkLineLocalizer.localize(
      rgba: rgba,
      width: width,
      height: height,
    ),
    imageWidth: width,
    imageHeight: height,
  );
}

Future<({int width, int height, Uint8List rgba})> _decodePng(
  AutomatedTestWidgetsFlutterBinding binding,
  Uint8List bytes,
) async {
  late ui.Image image;
  late ByteData rgba;
  await binding.runAsync(() async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    image = frame.image;
    rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  });
  return (
    width: image.width,
    height: image.height,
    rgba: rgba.buffer.asUint8List(),
  );
}

Uint8List _blank(int width, int height) {
  final Uint8List px = Uint8List(width * height * 4);
  for (int i = 0; i < px.length; i += 4) {
    px[i] = 255;
    px[i + 1] = 255;
    px[i + 2] = 255;
    px[i + 3] = 255;
  }
  return px;
}

void _stroke(Uint8List px, int width, int x, int y0, int y1) {
  final int height = px.length ~/ (width * 4);
  for (int y = y0; y < y1; y++) {
    if (y < 0 || y >= height) continue;
    for (int dx = 0; dx < 2; dx++) {
      final int xx = x + dx;
      if (xx < 0 || xx >= width) continue;
      final int i = (y * width + xx) * 4;
      px[i] = 20;
      px[i + 1] = 20;
      px[i + 2] = 20;
    }
  }
}
