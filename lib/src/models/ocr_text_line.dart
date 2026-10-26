import 'dart:ui' show Offset, Rect;

/// A single recognized text line with 4 clockwise rotated vertices and confidence metrics.
class OcrTextLine {
  const OcrTextLine({
    required this.text,
    required this.confidence,
    required this.cornerPoints,
    required this.boundingBox,
    this.angle = 0.0,
    this.angleConfidence = 1.0,
    this.boxScore = 1.0,
  }) : assert(
         cornerPoints.length == 4,
         'cornerPoints must contain exactly 4 clockwise vertices: [TL, TR, BR, BL].',
       );

  /// Recognized UTF-8 text string.
  final String text;

  /// Recognition confidence score (`0.0` to `1.0`).
  final double confidence;

  /// 4 clockwise rotated corner points in corrected image coordinates:
  /// `[topLeft, topRight, bottomRight, bottomLeft]`.
  final List<Offset> cornerPoints;

  /// Axis-aligned bounding rectangle enclosing [cornerPoints].
  final Rect boundingBox;

  /// Text line tilt or orientation angle in degrees.
  final double angle;

  /// Confidence of the AngleNet orientation classification (`0.0` to `1.0`).
  final double angleConfidence;

  /// DBNet detection polygon score (`0.0` to `1.0`).
  final double boxScore;

  /// Estimated line height based on the average left and right edge heights of the quadrilateral.
  double get estimatedLineHeight {
    final double leftEdge = (cornerPoints[3] - cornerPoints[0]).distance;
    final double rightEdge = (cornerPoints[2] - cornerPoints[1]).distance;
    final double avg = (leftEdge + rightEdge) * 0.5;
    return avg > 0 ? avg : boundingBox.height;
  }

  /// Center point of the text line in image coordinates.
  Offset get center => boundingBox.center;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'text': text,
    'confidence': double.parse(confidence.toStringAsFixed(4)),
    'angle': double.parse(angle.toStringAsFixed(2)),
    'angleConfidence': double.parse(angleConfidence.toStringAsFixed(4)),
    'boxScore': double.parse(boxScore.toStringAsFixed(4)),
    'boundingBox': <String, double>{
      'left': boundingBox.left,
      'top': boundingBox.top,
      'width': boundingBox.width,
      'height': boundingBox.height,
    },
    'cornerPoints': cornerPoints
        .map((Offset p) => <String, double>{'x': p.dx, 'y': p.dy})
        .toList(growable: false),
  };

  factory OcrTextLine.fromJson(Map<String, dynamic> json) {
    final List<dynamic> pts =
        json['cornerPoints'] as List<dynamic>? ?? <dynamic>[];
    final List<Offset> corners = pts
        .map((dynamic e) {
          final Map<String, dynamic> m = Map<String, dynamic>.from(e as Map);
          return Offset((m['x'] as num).toDouble(), (m['y'] as num).toDouble());
        })
        .toList(growable: false);

    final Map<String, dynamic>? rectMap = json['boundingBox'] != null
        ? Map<String, dynamic>.from(json['boundingBox'] as Map)
        : null;
    final Rect box = rectMap != null
        ? Rect.fromLTWH(
            (rectMap['left'] as num).toDouble(),
            (rectMap['top'] as num).toDouble(),
            (rectMap['width'] as num).toDouble(),
            (rectMap['height'] as num).toDouble(),
          )
        : _computeBounds(corners);

    return OcrTextLine(
      text: json['text'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      cornerPoints: corners.length == 4
          ? corners
          : <Offset>[
              box.topLeft,
              box.topRight,
              box.bottomRight,
              box.bottomLeft,
            ],
      boundingBox: box,
      angle: (json['angle'] as num?)?.toDouble() ?? 0.0,
      angleConfidence: (json['angleConfidence'] as num?)?.toDouble() ?? 1.0,
      boxScore: (json['boxScore'] as num?)?.toDouble() ?? 1.0,
    );
  }

  static Rect _computeBounds(List<Offset> points) {
    if (points.isEmpty) return Rect.zero;
    double minX = points.first.dx;
    double maxX = points.first.dx;
    double minY = points.first.dy;
    double maxY = points.first.dy;
    for (final Offset p in points.skip(1)) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}
