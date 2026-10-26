import 'dart:ui' show Offset, Rect;

import 'ocr_text_line.dart';

/// A spatially clustered paragraph block composed of adjacent [OcrTextLine]s with similar line heights.
class OcrTextBlock {
  const OcrTextBlock({
    required this.lines,
    required this.boundingBox,
    required this.cornerPoints,
  });

  /// Ordered text lines belonging to this paragraph block.
  final List<OcrTextLine> lines;

  /// Enclosing axis-aligned bounding rectangle of the entire paragraph block.
  final Rect boundingBox;

  /// 4 clockwise vertices of the paragraph block (`[TL, TR, BR, BL]`).
  final List<Offset> cornerPoints;

  /// Concatenated paragraph text.
  String get text => lines.map((OcrTextLine l) => l.text).join('\n');

  /// Average recognition confidence across all lines in this paragraph block.
  double get averageConfidence {
    if (lines.isEmpty) return 0.0;
    final double sum = lines.fold<double>(
      0.0,
      (double acc, OcrTextLine l) => acc + l.confidence,
    );
    return sum / lines.length;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'text': text,
    'averageConfidence': double.parse(averageConfidence.toStringAsFixed(4)),
    'boundingBox': <String, double>{
      'left': boundingBox.left,
      'top': boundingBox.top,
      'width': boundingBox.width,
      'height': boundingBox.height,
    },
    'lines': lines.map((OcrTextLine l) => l.toJson()).toList(growable: false),
  };
}
