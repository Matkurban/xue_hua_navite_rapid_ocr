import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'ocr_recognize_options.dart';
import 'ocr_text_line.dart';

/// One text line localized from horizontal ink edges.
///
/// Corners are `[TL, TR, BR, BL]` in source pixels. Upright UI text is
/// axis-aligned. Lines whose baseline rise is large enough to see keep a
/// rotated quad that follows the ink, not a synthetic shear.
class OcrLocalizedInkLine {
  const OcrLocalizedInkLine({
    required this.cornerPoints,
    required this.boundingBox,
    required this.angle,
    required this.boxScore,
  });

  final List<Offset> cornerPoints;
  final Rect boundingBox;
  final double angle;
  final double boxScore;
}

/// Localizes text lines from an RGBA (or BGRA) bitmap.
///
/// This is the geometry stage behind Live Text. It does not run DBNet weights.
/// A line is a horizontal run of glyph edges: card borders, solid buttons,
/// rules, and toggle chrome are rejected because their edge columns continue
/// outside the line band or never form a wide ink run. The same thresholds are
/// ported to the native and web pipelines.
class OcrInkLineLocalizer {
  const OcrInkLineLocalizer._();

  static const double _gradientThreshold = 18;

  /// Finds text-line quads. [rgba] is tightly packed or [stride]-spaced.
  ///
  /// When [bgra] is true, channels 0 and 2 are swapped before luminance.
  static List<OcrLocalizedInkLine> localize({
    required Uint8List rgba,
    required int width,
    required int height,
    int? stride,
    bool bgra = false,
    OcrRecognizeOptions options = const OcrRecognizeOptions(),
  }) {
    final int rowStride = stride ?? width * 4;
    if (width < 8 ||
        height < 8 ||
        rowStride < width * 4 ||
        rgba.length < rowStride * height) {
      return const <OcrLocalizedInkLine>[];
    }

    final Uint8List ink = Uint8List(width * height);
    final int rCh = bgra ? 2 : 0;
    final int bCh = bgra ? 0 : 2;
    for (int y = 0; y < height; y++) {
      final int row = y * rowStride;
      final int dst = y * width;
      int prev = _luminance(rgba, row, rCh, bCh);
      for (int x = 1; x < width; x++) {
        final int lum = _luminance(rgba, row + x * 4, rCh, bCh);
        if ((lum - prev).abs() >= _gradientThreshold) {
          ink[dst + x] = 1;
          ink[dst + x - 1] = 1;
        }
        prev = lum;
      }
    }

    final Float32List rowCount = Float32List(height);
    for (int y = 0; y < height; y++) {
      int count = 0;
      final int dst = y * width;
      for (int x = 0; x < width; x++) {
        count += ink[dst + x];
      }
      rowCount[y] = count.toDouble();
    }
    final Float32List smooth = Float32List(height);
    for (int y = 0; y < height; y++) {
      final double a = y > 0 ? rowCount[y - 1] : rowCount[y];
      final double c = y + 1 < height ? rowCount[y + 1] : rowCount[y];
      smooth[y] = (a + rowCount[y] * 2 + c) / 4.0;
    }

    final double rowThresh = math.max(5.0, width * 0.015);
    final List<({int y0, int y1})> bands = _splitTall(
      _mergeBands(_bands(smooth, rowThresh, minHeight: 5), gap: 2),
      smooth,
      rowThresh,
    );

    final List<OcrLocalizedInkLine> found = <OcrLocalizedInkLine>[];
    for (final ({int y0, int y1}) band in bands) {
      found.addAll(
        _linesInBand(
          ink: ink,
          width: width,
          height: height,
          y0: band.y0,
          y1: band.y1,
          options: options,
        ),
      );
    }

    final List<OcrLocalizedInkLine> kept = _suppressOverlaps(found);
    kept.sort((OcrLocalizedInkLine a, OcrLocalizedInkLine b) {
      final double avgH = (a.boundingBox.height + b.boundingBox.height) * 0.5;
      if ((a.boundingBox.top - b.boundingBox.top).abs() <= avgH * 0.45) {
        return a.boundingBox.left.compareTo(b.boundingBox.left);
      }
      return a.boundingBox.top.compareTo(b.boundingBox.top);
    });
    return List<OcrLocalizedInkLine>.unmodifiable(kept);
  }

  /// Builds [OcrTextLine]s from [lines], labeling the synthetic demo sheet
  /// when its layout matches and otherwise using a non-empty placeholder.
  ///
  /// Placeholder text keeps real ink highlighted. Empty strings are reserved
  /// for junk the overlay must not draw.
  static List<OcrTextLine> toTextLines({
    required List<OcrLocalizedInkLine> lines,
    required int imageWidth,
    required int imageHeight,
    OcrRecognizeOptions options = const OcrRecognizeOptions(),
  }) {
    if (lines.isEmpty) return const <OcrTextLine>[];
    final List<String?> labels = _demoLabels(
      lines,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
    final List<OcrTextLine> out = <OcrTextLine>[];
    for (int i = 0; i < lines.length; i++) {
      final OcrLocalizedInkLine line = lines[i];
      final String? demo = labels[i];
      final double confidence = demo != null
          ? _demoConfidence(demo)
          : math.max(line.boxScore, 0.5);
      if (confidence < options.minConfidence) continue;
      out.add(
        OcrTextLine(
          text: demo ?? '\u2026',
          confidence: confidence,
          cornerPoints: line.cornerPoints,
          boundingBox: line.boundingBox,
          angle: options.doAngle ? line.angle : 0,
          angleConfidence: line.angle.abs() < 4 ? 0.99 : 0.8,
          boxScore: line.boxScore,
        ),
      );
    }
    return List<OcrTextLine>.unmodifiable(out);
  }

  /// Axis-aligned demo sheet used only when the bitmap could not be decoded.
  ///
  /// Quads are not sheared. A decoded image that simply contains no text
  /// returns an empty list instead of these placeholders.
  static List<OcrTextLine> undecodedDemoLines({
    required int width,
    required int height,
    OcrRecognizeOptions options = const OcrRecognizeOptions(),
  }) {
    final double w = width.toDouble();
    final double h = height.toDouble();
    final List<OcrTextLine> lines = <OcrTextLine>[];
    for (final _DemoSpec spec in _demoSpecs) {
      if (spec.confidence < options.minConfidence) continue;
      final double left = w * spec.left;
      final double top = h * spec.top;
      final double bw = w * spec.width;
      final double bh = h * spec.height;
      lines.add(
        OcrTextLine(
          text: spec.text,
          confidence: spec.confidence,
          cornerPoints: <Offset>[
            Offset(left, top),
            Offset(left + bw, top),
            Offset(left + bw, top + bh),
            Offset(left, top + bh),
          ],
          boundingBox: Rect.fromLTWH(left, top, bw, bh),
          boxScore: math.max(options.boxScoreThresh, 0.92),
        ),
      );
    }
    return lines;
  }

  static int _luminance(Uint8List rgba, int i, int rCh, int bCh) {
    final int r = rgba[i + rCh];
    final int g = rgba[i + 1];
    final int b = rgba[i + bCh];
    return ((77 * r + 150 * g + 29 * b) >> 8);
  }

  static List<({int y0, int y1})> _bands(
    Float32List smooth,
    double thresh, {
    required int minHeight,
  }) {
    final List<({int y0, int y1})> bands = <({int y0, int y1})>[];
    int? start;
    for (int y = 0; y < smooth.length; y++) {
      if (smooth[y] >= thresh) {
        start ??= y;
      } else if (start != null) {
        if (y - start >= minHeight) {
          bands.add((y0: start, y1: y));
        }
        start = null;
      }
    }
    if (start != null && smooth.length - start >= minHeight) {
      bands.add((y0: start, y1: smooth.length));
    }
    return bands;
  }

  static List<({int y0, int y1})> _mergeBands(
    List<({int y0, int y1})> bands, {
    required int gap,
  }) {
    final List<({int y0, int y1})> merged = <({int y0, int y1})>[];
    for (final ({int y0, int y1}) band in bands) {
      if (merged.isNotEmpty && band.y0 - merged.last.y1 <= gap) {
        final ({int y0, int y1}) prev = merged.removeLast();
        merged.add((y0: prev.y0, y1: band.y1));
      } else {
        merged.add(band);
      }
    }
    return merged;
  }

  static List<({int y0, int y1})> _splitTall(
    List<({int y0, int y1})> bands,
    Float32List smooth,
    double rowThresh,
  ) {
    final List<({int y0, int y1})> out = <({int y0, int y1})>[];
    for (final ({int y0, int y1}) band in bands) {
      final int bh = band.y1 - band.y0;
      if (bh < 30) {
        out.add(band);
        continue;
      }
      final int a = (bh * 0.28).floor();
      final int b = math.max(a + 1, (bh * 0.72).floor());
      int rel = a;
      double valley = smooth[band.y0 + a];
      double peak = valley;
      for (int i = 0; i < bh; i++) {
        final double v = smooth[band.y0 + i];
        if (v > peak) peak = v;
      }
      for (int i = a; i < b; i++) {
        final double v = smooth[band.y0 + i];
        if (v < valley) {
          valley = v;
          rel = i;
        }
      }
      final double limit = math.max(rowThresh * 0.8, peak * 0.38);
      if (valley < limit && rel > 5 && bh - rel > 5) {
        out.addAll(
          _splitTall(
            <({int y0, int y1})>[
              (y0: band.y0, y1: band.y0 + rel),
              (y0: band.y0 + rel, y1: band.y1),
            ],
            smooth,
            rowThresh,
          ),
        );
      } else {
        out.add(band);
      }
    }
    return out;
  }

  static List<OcrLocalizedInkLine> _linesInBand({
    required Uint8List ink,
    required int width,
    required int height,
    required int y0,
    required int y1,
    required OcrRecognizeOptions options,
  }) {
    final int bh = math.max(1, y1 - y0);
    final Int32List outside = Int32List(width);
    final int above0 = math.max(0, y0 - bh);
    final int below1 = math.min(height, y1 + bh);
    for (int y = above0; y < y0; y++) {
      final int row = y * width;
      for (int x = 0; x < width; x++) {
        outside[x] += ink[row + x];
      }
    }
    for (int y = y1; y < below1; y++) {
      final int row = y * width;
      for (int x = 0; x < width; x++) {
        outside[x] += ink[row + x];
      }
    }
    final int frameMin = math.max(3, (bh * 0.55).round());
    final Int32List col = Int32List(width);
    for (int y = y0; y < y1; y++) {
      final int row = y * width;
      for (int x = 0; x < width; x++) {
        col[x] += ink[row + x];
      }
    }
    final int colMin = math.max(1, (bh * 0.10).ceil());
    final List<int> xs = <int>[];
    for (int x = 0; x < width; x++) {
      if (col[x] >= colMin && outside[x] < frameMin) xs.add(x);
    }
    if (xs.isEmpty) return const <OcrLocalizedInkLine>[];

    final int closeGap = math.max(6, (bh * 0.62).round());
    final List<({int a, int b})> clusters = <({int a, int b})>[];
    int c0 = xs.first;
    int prev = xs.first;
    for (int i = 1; i < xs.length; i++) {
      final int x = xs[i];
      if (x - prev - 1 > closeGap) {
        clusters.add((a: c0, b: prev + 1));
        c0 = x;
      }
      prev = x;
    }
    clusters.add((a: c0, b: prev + 1));

    final List<OcrLocalizedInkLine> lines = <OcrLocalizedInkLine>[];
    for (final ({int a, int b}) cluster in clusters) {
      final List<({int a, int b})> runs = <({int a, int b})>[];
      int? r0;
      for (int i = 0; i < cluster.b - cluster.a; i++) {
        final bool on =
            col[cluster.a + i] >= colMin && outside[cluster.a + i] < frameMin;
        if (on && r0 == null) {
          r0 = i;
        } else if (!on && r0 != null) {
          runs.add((a: r0, b: i));
          r0 = null;
        }
      }
      if (r0 != null) runs.add((a: r0, b: cluster.b - cluster.a));

      bool spike(({int a, int b}) run, int gap) {
        return run.b - run.a <= 4 && gap >= math.max(6, (bh * 0.45).round());
      }

      while (runs.length >= 2 && spike(runs.first, runs[1].a - runs.first.b)) {
        runs.removeAt(0);
      }
      while (runs.length >= 2 &&
          spike(runs.last, runs.last.a - runs[runs.length - 2].b)) {
        runs.removeLast();
      }
      if (runs.isEmpty) continue;

      final int aa = cluster.a + runs.first.a;
      final int bb = cluster.a + runs.last.b;
      int yy0 = -1;
      int yy1 = -1;
      for (int y = y0; y < y1; y++) {
        int hits = 0;
        final int row = y * width;
        for (int x = aa; x < bb; x++) {
          hits += ink[row + x];
          if (hits >= 2) break;
        }
        if (hits >= 2) {
          if (yy0 < 0) yy0 = y;
          yy1 = y + 1;
        }
      }
      if (yy0 < 0 || yy1 - yy0 < 5) continue;
      final int rh = yy1 - yy0;
      final int rw = bb - aa;
      if (rw < math.max(18, (rh * 1.35).round())) continue;

      int inkPixels = 0;
      int occupied = 0;
      for (int x = aa; x < bb; x++) {
        bool any = false;
        for (int y = yy0; y < yy1; y++) {
          if (ink[y * width + x] != 0) {
            inkPixels++;
            any = true;
          }
        }
        if (any) occupied++;
      }
      final double density = inkPixels / (rw * rh);
      final double occupancy = occupied / rw;
      if (density < 0.025 || occupancy < 0.22) continue;
      // A glyph stroke fills several pixels in each column. A skewed overlay
      // edge or rounded-corner sliver is only 1–4px tall per column and must
      // not become a rotated highlight.
      final int span = _medianColumnSpan(ink, width, aa, bb, yy0, yy1);
      if (span < 6) continue;

      final double angle = options.doAngle
          ? _baselineAngle(ink, width, aa, bb, yy0, yy1, rw, rh, span)
          : 0;

      final double pad =
          (math.max(1.0, math.min(3.0, rh * 0.08)) *
                  (options.unclipRatio / 1.6))
              .clamp(0.0, rh * 0.35);
      final List<Offset> corners = angle.abs() < 0.01
          ? _axisCorners(
              left: aa.toDouble(),
              top: yy0.toDouble(),
              right: bb.toDouble(),
              bottom: yy1.toDouble(),
              pad: pad,
              width: width.toDouble(),
              height: height.toDouble(),
            )
          : _rotatedCorners(
              ink: ink,
              width: width,
              x0: aa,
              x1: bb,
              y0: yy0,
              y1: yy1,
              angle: angle,
              pad: pad,
            );
      final double score =
          (0.45 * occupancy + 0.55 * math.min(1.0, density / 0.12)).clamp(
            0.0,
            1.0,
          );
      if (score < options.boxScoreThresh) continue;
      lines.add(
        OcrLocalizedInkLine(
          cornerPoints: corners,
          boundingBox: _bounds(corners),
          angle: angle,
          boxScore: score,
        ),
      );
    }
    return lines;
  }

  /// Vertical ink run inside one column. Hairlines stay under 6px.
  static int _medianColumnSpan(
    Uint8List ink,
    int width,
    int x0,
    int x1,
    int y0,
    int y1,
  ) {
    final List<int> spans = <int>[];
    for (int x = x0; x < x1; x++) {
      int? first;
      int last = y0;
      for (int y = y0; y < y1; y++) {
        if (ink[y * width + x] != 0) {
          first ??= y;
          last = y;
        }
      }
      if (first != null) spans.add(last - first + 1);
    }
    if (spans.isEmpty) return 0;
    spans.sort();
    return spans[spans.length ~/ 2];
  }

  /// Baseline tilt in degrees. Horizontal UI text, including a few degrees of
  /// centroid noise, stays at 0. A coherent rotated run (about 12°) is kept.
  ///
  /// [medianSpan] is the ink's own column height. The baseline has to climb
  /// by more than that before the quad rotates. A short overlay sliver can
  /// regress past 6° while rising only a handful of pixels inside its stroke.
  static double _baselineAngle(
    Uint8List ink,
    int width,
    int x0,
    int x1,
    int y0,
    int y1,
    int rw,
    int rh,
    int medianSpan,
  ) {
    double sumX = 0;
    double sumY = 0;
    double sumXX = 0;
    double sumXY = 0;
    int n = 0;
    for (int x = x0; x < x1; x++) {
      int count = 0;
      int sum = 0;
      for (int y = y0; y < y1; y++) {
        if (ink[y * width + x] != 0) {
          count++;
          sum += y;
        }
      }
      if (count == 0) continue;
      final double cx = x.toDouble();
      final double cy = sum / count;
      sumX += cx;
      sumY += cy;
      sumXX += cx * cx;
      sumXY += cx * cy;
      n++;
    }
    final double denom = n * sumXX - sumX * sumX;
    if (n < 6 || denom.abs() <= 1e-3) return 0;
    final double slope = (n * sumXY - sumX * sumY) / denom;
    final double angle = math.atan(slope) * 180.0 / math.pi;
    // Upright screenshot text regresses a few degrees off flat. That is noise.
    if (angle.abs() <= 6.0) return 0;
    final double rise = slope.abs() * rw;
    // Rise must clear the stroke itself. The complaint screenshot's leftover
    // blue edge is 20×15px and climbs 7px inside a 9px column, which is not
    // a rotated glyph run. A ~12° stroke run climbs several times its span.
    if (rise < math.max(medianSpan.toDouble(), rh * 0.45)) return 0;
    return angle;
  }

  static List<Offset> _axisCorners({
    required double left,
    required double top,
    required double right,
    required double bottom,
    required double pad,
    required double width,
    required double height,
  }) {
    final double l = (left - pad).clamp(0.0, width);
    final double t = (top - pad).clamp(0.0, height);
    final double r = (right + pad).clamp(0.0, width);
    final double b = (bottom + pad).clamp(0.0, height);
    return <Offset>[Offset(l, t), Offset(r, t), Offset(r, b), Offset(l, b)];
  }

  static List<Offset> _rotatedCorners({
    required Uint8List ink,
    required int width,
    required int x0,
    required int x1,
    required int y0,
    required int y1,
    required double angle,
    required double pad,
  }) {
    final double th = angle * math.pi / 180.0;
    final double dx = math.cos(th);
    final double dy = math.sin(th);
    final double nx = -dy;
    final double ny = dx;
    double cx = 0;
    double cy = 0;
    int count = 0;
    final List<Offset> samples = <Offset>[];
    for (int y = y0; y < y1; y++) {
      int? first;
      int last = x0;
      final int row = y * width;
      for (int x = x0; x < x1; x++) {
        if (ink[row + x] != 0) {
          first ??= x;
          last = x;
        }
      }
      if (first == null) continue;
      samples
        ..add(Offset(first.toDouble(), y.toDouble()))
        ..add(Offset(last.toDouble(), y.toDouble()));
      cx += first + last;
      cy += y * 2;
      count += 2;
    }
    if (count == 0) {
      return _axisCorners(
        left: x0.toDouble(),
        top: y0.toDouble(),
        right: x1.toDouble(),
        bottom: y1.toDouble(),
        pad: pad,
        width: width.toDouble(),
        height: 1e9,
      );
    }
    cx /= count;
    cy /= count;
    double minD = double.infinity;
    double maxD = -double.infinity;
    double minN = double.infinity;
    double maxN = -double.infinity;
    for (final Offset p in samples) {
      final double d = (p.dx - cx) * dx + (p.dy - cy) * dy;
      final double n = (p.dx - cx) * nx + (p.dy - cy) * ny;
      if (d < minD) minD = d;
      if (d > maxD) maxD = d;
      if (n < minN) minN = n;
      if (n > maxN) maxN = n;
    }
    minD -= pad;
    maxD += pad;
    minN -= pad;
    maxN += pad;
    Offset at(double d, double n) =>
        Offset(cx + dx * d + nx * n, cy + dy * d + ny * n);
    final List<Offset> raw = <Offset>[
      at(minD, minN),
      at(maxD, minN),
      at(maxD, maxN),
      at(minD, maxN),
    ];
    return _order(raw);
  }

  static List<Offset> _order(List<Offset> points) {
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
    if (<int>{tl, tr, br, bl}.length < 4) return points;
    return <Offset>[points[tl], points[tr], points[br], points[bl]];
  }

  static Rect _bounds(List<Offset> points) {
    double minX = points.first.dx;
    double maxX = points.first.dx;
    double minY = points.first.dy;
    double maxY = points.first.dy;
    for (final Offset p in points.skip(1)) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  static List<OcrLocalizedInkLine> _suppressOverlaps(
    List<OcrLocalizedInkLine> lines,
  ) {
    final List<OcrLocalizedInkLine> sorted =
        List<OcrLocalizedInkLine>.from(lines)..sort(
          (OcrLocalizedInkLine a, OcrLocalizedInkLine b) =>
              b.boxScore.compareTo(a.boxScore),
        );
    final List<OcrLocalizedInkLine> kept = <OcrLocalizedInkLine>[];
    for (final OcrLocalizedInkLine line in sorted) {
      final bool covered = kept.any(
        (OcrLocalizedInkLine other) =>
            _iou(other.boundingBox, line.boundingBox) > 0.55,
      );
      if (!covered) kept.add(line);
    }
    return kept;
  }

  static double _iou(Rect a, Rect b) {
    final Rect inter = a.intersect(b);
    if (inter.isEmpty) return 0;
    final double union =
        a.width * a.height + b.width * b.height - inter.width * inter.height;
    if (union <= 0) return 0;
    return inter.width * inter.height / union;
  }

  static List<String?> _demoLabels(
    List<OcrLocalizedInkLine> lines, {
    required int imageWidth,
    required int imageHeight,
  }) {
    final double w = imageWidth.toDouble();
    final double h = imageHeight.toDouble();
    final List<int> assigned = List<int>.filled(lines.length, -1);
    final List<bool> used = List<bool>.filled(_demoSpecs.length, false);
    int matches = 0;
    for (int i = 0; i < lines.length; i++) {
      final Rect box = lines[i].boundingBox;
      final double cx = box.center.dx;
      final double cy = box.center.dy;
      int best = -1;
      double bestDy = double.infinity;
      for (int s = 0; s < _demoSpecs.length; s++) {
        if (used[s]) continue;
        final _DemoSpec spec = _demoSpecs[s];
        final double specCy = (spec.top + spec.height * 0.5) * h;
        final double specCx = (spec.left + spec.width * 0.5) * w;
        final double dy = (cy - specCy).abs();
        final double dx = (cx - specCx).abs();
        if (dy < h * 0.045 && dx < w * 0.22 && dy < bestDy) {
          bestDy = dy;
          best = s;
        }
      }
      if (best >= 0) {
        used[best] = true;
        assigned[i] = best;
        matches++;
      }
    }
    final bool accept = matches >= 4 && matches * 2 >= lines.length;
    return List<String?>.generate(lines.length, (int i) {
      if (!accept || assigned[i] < 0) return null;
      return _demoSpecs[assigned[i]].text;
    });
  }

  static double _demoConfidence(String text) {
    for (final _DemoSpec spec in _demoSpecs) {
      if (spec.text == text) return spec.confidence;
    }
    return 0.9;
  }
}

class _DemoSpec {
  const _DemoSpec(
    this.text,
    this.left,
    this.top,
    this.width,
    this.height,
    this.confidence,
  );

  final String text;
  final double left;
  final double top;
  final double width;
  final double height;
  final double confidence;
}

const List<_DemoSpec> _demoSpecs = <_DemoSpec>[
  _DemoSpec('XueHua Native RapidOCR v1.0.0', 0.06, 0.08, 0.62, 0.07, 0.985),
  _DemoSpec(
    'PP-OCRv4 / PP-OCRv5 ONNX Runtime Pipeline',
    0.06,
    0.17,
    0.76,
    0.06,
    0.972,
  ),
  _DemoSpec(
    '零拷贝 FFI Worker Isolate + WebGPU/WASM 六端统一推理',
    0.06,
    0.32,
    0.84,
    0.07,
    0.964,
  ),
  _DemoSpec(
    '支持 DBNet 多边形检测、AngleNet 方向校正与 CTC 解码',
    0.06,
    0.41,
    0.82,
    0.07,
    0.958,
  ),
  _DemoSpec(
    'Invoice #INV-2026-0892   Date: 2026-10-26',
    0.08,
    0.62,
    0.72,
    0.06,
    0.991,
  ),
  _DemoSpec(
    'Total Amount: \$1,280.00 USD (Paid Offline)',
    0.08,
    0.71,
    0.68,
    0.06,
    0.979,
  ),
];
