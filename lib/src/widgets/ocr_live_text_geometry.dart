import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import '../models/ocr_text_line.dart';
import 'ocr_image_coordinate_transform.dart';

/// Shared geometry for Live Text highlights: junk filtering, corner order,
/// near-upright snap, stroke outset, and hit testing.
///
/// Corner order is RapidOCR `[topLeft, topRight, bottomRight, bottomLeft]`.
class OcrLiveTextGeometry {
  const OcrLiveTextGeometry._();

  /// Drops empty transcriptions, ~0 scores, and degenerate or off-image quads.
  ///
  /// Thresholds stay low on purpose. The recognizer already applied
  /// [OcrRecognizeOptions.minConfidence] and `boxScoreThresh`; this only
  /// removes highlights that would draw as empty or zero-area boxes.
  static bool isDisplayable(
    OcrTextLine line, {
    required double imageWidth,
    required double imageHeight,
    required double minConfidence,
    required double minBoxScore,
  }) {
    if (line.text.trim().isEmpty) return false;
    if (!line.confidence.isFinite || line.confidence < minConfidence) {
      return false;
    }
    if (!line.boxScore.isFinite || line.boxScore < minBoxScore) {
      return false;
    }
    if (line.cornerPoints.length < 4) return false;
    final Rect bounds = polygonBounds(line.cornerPoints);
    if (bounds.width < 1 || bounds.height < 1) return false;
    if (polygonArea(line.cornerPoints).abs() < 4) return false;
    final Rect image = Rect.fromLTWH(0, 0, imageWidth, imageHeight);
    if (!bounds.overlaps(image.inflate(1))) return false;
    return true;
  }

  /// Orders corners and replaces near-upright shears with a tight AABB.
  ///
  /// Quads whose top and bottom edges are within [axisSnapDegrees] of
  /// horizontal are snapped. The default style uses 6°, which covers the
  /// few-degree centroid noise of upright UI text. A 12° line stays oriented.
  static OcrTextLine sanitize(
    OcrTextLine line, {
    required double axisSnapDegrees,
  }) {
    final List<Offset> ordered = orderCorners(line.cornerPoints);
    final Rect box = polygonBounds(ordered);
    if (box.width <= 0 || box.height <= 0) {
      return line.copyWith(cornerPoints: ordered, boundingBox: box);
    }

    final double topDeg = _edgeDegrees(ordered[1] - ordered[0]);
    final double bottomDeg = _edgeDegrees(ordered[2] - ordered[3]);
    final bool upright =
        topDeg.abs() <= axisSnapDegrees && bottomDeg.abs() <= axisSnapDegrees;
    if (!upright) {
      return line.copyWith(cornerPoints: ordered, boundingBox: box);
    }

    return line.copyWith(
      cornerPoints: <Offset>[
        box.topLeft,
        box.topRight,
        box.bottomRight,
        box.bottomLeft,
      ],
      boundingBox: box,
      angle: 0,
    );
  }

  /// `[TL, TR, BR, BL]`, or the AABB when the four indices collapse.
  static List<Offset> orderCorners(List<Offset> points) {
    if (points.length != 4) {
      final Rect box = polygonBounds(points);
      return <Offset>[
        box.topLeft,
        box.topRight,
        box.bottomRight,
        box.bottomLeft,
      ];
    }
    int tl = 0;
    int tr = 0;
    int br = 0;
    int bl = 0;
    double minSum = double.infinity;
    double maxSum = -double.infinity;
    double maxDiff = -double.infinity;
    double minDiff = double.infinity;
    for (int i = 0; i < 4; i++) {
      final double sum = points[i].dx + points[i].dy;
      final double diff = points[i].dx - points[i].dy;
      if (sum < minSum) {
        minSum = sum;
        tl = i;
      }
      if (sum > maxSum) {
        maxSum = sum;
        br = i;
      }
      if (diff > maxDiff) {
        maxDiff = diff;
        tr = i;
      }
      if (diff < minDiff) {
        minDiff = diff;
        bl = i;
      }
    }
    if (<int>{tl, tr, br, bl}.length < 4) {
      final Rect box = polygonBounds(points);
      return <Offset>[
        box.topLeft,
        box.topRight,
        box.bottomRight,
        box.bottomLeft,
      ];
    }
    return <Offset>[points[tl], points[tr], points[br], points[bl]];
  }

  /// Pushes a clockwise quad outward by [pad] logical pixels.
  ///
  /// Axis-aligned quads use [Rect.inflate]. Rotated quads move each edge
  /// along its outward normal so the stroke stays off the glyphs and hit
  /// testing matches the painted shape.
  static List<Offset> outsetQuad(List<Offset> corners, double pad) {
    if (corners.length < 4 || pad == 0) {
      return List<Offset>.from(corners);
    }
    if (_isAxisAligned(corners)) {
      final Rect inflated = polygonBounds(corners).inflate(pad);
      return <Offset>[
        inflated.topLeft,
        inflated.topRight,
        inflated.bottomRight,
        inflated.bottomLeft,
      ];
    }

    final Offset centroid = polygonBounds(corners).center;
    final List<Offset> normals = List<Offset>.generate(4, (int i) {
      return _outwardNormal(corners[i], corners[(i + 1) % 4], centroid);
    });
    return List<Offset>.generate(4, (int i) {
      final Offset n1 = normals[(i + 3) % 4];
      final Offset n2 = normals[i];
      Offset miter = n1 + n2;
      final double len = miter.distance;
      if (len < 1e-6) return corners[i];
      miter = miter / len;
      final double cosHalf = (n1.dx * miter.dx + n1.dy * miter.dy).clamp(
        0.25,
        1.0,
      );
      return corners[i] + miter * (pad / cosHalf);
    });
  }

  /// Local quad actually stroked by [OcrLiveTextPainter].
  static List<Offset> paintedQuad({
    required List<Offset> imageCorners,
    required OcrImageCoordinateTransform transform,
    required double outset,
  }) {
    final List<Offset> local = imageCorners
        .map(transform.imageToLocal)
        .toList(growable: false);
    return outsetQuad(local, outset);
  }

  static bool containsPoint(Offset point, List<Offset> polygon) {
    if (polygon.length < 3) return false;
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final double xi = polygon[i].dx;
      final double yi = polygon[i].dy;
      final double xj = polygon[j].dx;
      final double yj = polygon[j].dy;
      final bool intersect =
          ((yi > point.dy) != (yj > point.dy)) &&
          (point.dx <
              (xj - xi) *
                      (point.dy - yi) /
                      ((yj - yi) == 0 ? 1e-7 : (yj - yi)) +
                  xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  /// True when the quad and [rect] touch, including edge crossings.
  static bool quadIntersectsRect(List<Offset> quad, Rect rect) {
    if (quad.length < 4 || rect.isEmpty) return false;
    for (final Offset p in quad) {
      if (rect.contains(p)) return true;
    }
    final List<Offset> rectPts = <Offset>[
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ];
    for (final Offset p in rectPts) {
      if (containsPoint(p, quad)) return true;
    }
    for (int i = 0; i < 4; i++) {
      final Offset a = quad[i];
      final Offset b = quad[(i + 1) % 4];
      for (int j = 0; j < 4; j++) {
        if (_segmentsIntersect(a, b, rectPts[j], rectPts[(j + 1) % 4])) {
          return true;
        }
      }
    }
    return false;
  }

  static Rect polygonBounds(List<Offset> points) {
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

  static double polygonArea(List<Offset> points) {
    if (points.length < 3) return 0;
    double sum = 0;
    for (int i = 0; i < points.length; i++) {
      final Offset a = points[i];
      final Offset b = points[(i + 1) % points.length];
      sum += a.dx * b.dy - b.dx * a.dy;
    }
    return sum * 0.5;
  }

  static double _edgeDegrees(Offset edge) {
    return math.atan2(edge.dy, edge.dx) * 180.0 / math.pi;
  }

  static bool _isAxisAligned(List<Offset> corners) {
    final Rect box = polygonBounds(corners);
    const double eps = 0.75;
    bool near(Offset a, Offset b) => (a - b).distance <= eps;
    return near(corners[0], box.topLeft) &&
        near(corners[1], box.topRight) &&
        near(corners[2], box.bottomRight) &&
        near(corners[3], box.bottomLeft);
  }

  static Offset _outwardNormal(Offset a, Offset b, Offset centroid) {
    final Offset d = b - a;
    Offset n = Offset(d.dy, -d.dx);
    final double len = n.distance;
    if (len < 1e-6) return Offset.zero;
    n = n / len;
    final Offset mid = Offset((a.dx + b.dx) * 0.5, (a.dy + b.dy) * 0.5);
    final Offset toward = centroid - mid;
    if (n.dx * toward.dx + n.dy * toward.dy > 0) {
      n = -n;
    }
    return n;
  }

  static bool _segmentsIntersect(Offset a, Offset b, Offset c, Offset d) {
    double cross(Offset p, Offset q, Offset r) {
      return (q.dx - p.dx) * (r.dy - p.dy) - (q.dy - p.dy) * (r.dx - p.dx);
    }

    final double d1 = cross(c, d, a);
    final double d2 = cross(c, d, b);
    final double d3 = cross(a, b, c);
    final double d4 = cross(a, b, d);
    return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
  }
}
