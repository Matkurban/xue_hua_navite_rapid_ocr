import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../models/ocr_text_line.dart';
import 'ocr_image_coordinate_transform.dart';

/// High-performance `CustomPainter` for `OcrLiveTextOverlay` driven directly by
/// `repaint` listenables ([selectedIndicesListenable], [hoveredIndexListenable],
/// [dragMarqueeListenable], and [highlightOpacityListenable]) so pointer hover,
/// marquee dragging, and selection changes repaint ONLY the canvas layer without
/// rebuilding the widget tree via `setState`.
class OcrLiveTextPainter extends CustomPainter {
  OcrLiveTextPainter({
    required this.lines,
    required this.transform,
    required this.selectedIndicesListenable,
    required this.hoveredIndexListenable,
    required this.highlightOpacityListenable,
    required this.dragMarqueeListenable,
    required this.highlightFillColor,
    required this.highlightBorderColor,
    required this.selectedFillColor,
    required this.selectedBorderColor,
    required this.hoveredFillColor,
    required this.marqueeFillColor,
    required this.marqueeBorderColor,
  }) : super(
         repaint: Listenable.merge(<Listenable>[
           selectedIndicesListenable,
           hoveredIndexListenable,
           highlightOpacityListenable,
           dragMarqueeListenable,
         ]),
       );

  final List<OcrTextLine> lines;
  final OcrImageCoordinateTransform transform;
  final ValueListenable<Set<int>> selectedIndicesListenable;
  final ValueListenable<int?> hoveredIndexListenable;
  final ValueListenable<double> highlightOpacityListenable;
  final ValueListenable<Rect?> dragMarqueeListenable;
  final Color highlightFillColor;
  final Color highlightBorderColor;
  final Color selectedFillColor;
  final Color selectedBorderColor;
  final Color hoveredFillColor;
  final Color marqueeFillColor;
  final Color marqueeBorderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Set<int> selectedIndices = selectedIndicesListenable.value;
    final int? hoveredIndex = hoveredIndexListenable.value;
    final double highlightOpacity = highlightOpacityListenable.value;
    final Rect? dragMarqueeRect = dragMarqueeListenable.value;

    for (int i = 0; i < lines.length; i++) {
      final OcrTextLine line = lines[i];
      if (line.cornerPoints.length < 4) continue;

      final bool isSelected = selectedIndices.contains(i);
      final bool isHovered = hoveredIndex == i;

      if (!isSelected && !isHovered && highlightOpacity <= 0.01) {
        continue;
      }

      final List<Offset> pts = line.cornerPoints
          .map(transform.imageToLocal)
          .toList(growable: false);

      final Path polyPath = Path()
        ..moveTo(pts[0].dx, pts[0].dy)
        ..lineTo(pts[1].dx, pts[1].dy)
        ..lineTo(pts[2].dx, pts[2].dy)
        ..lineTo(pts[3].dx, pts[3].dy)
        ..close();

      final Color baseFill = isSelected
          ? selectedFillColor
          : (isHovered ? hoveredFillColor : highlightFillColor);
      final Color baseBorder = isSelected
          ? selectedBorderColor
          : highlightBorderColor;

      final double effectiveOpacity = (isSelected || isHovered)
          ? 1.0
          : highlightOpacity;

      final Paint fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = baseFill.withValues(
          alpha: (baseFill.a * effectiveOpacity).clamp(0.0, 1.0),
        );

      final Paint borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2.2 : 1.3
        ..strokeJoin = StrokeJoin.round
        ..color = baseBorder.withValues(
          alpha: (baseBorder.a * effectiveOpacity).clamp(0.0, 1.0),
        );

      canvas.drawPath(polyPath, fillPaint);
      canvas.drawPath(polyPath, borderPaint);
    }

    // Draw interactive drag selection marquee rectangle if active
    if (dragMarqueeRect != null) {
      final Paint marqueeFill = Paint()
        ..style = PaintingStyle.fill
        ..color = marqueeFillColor;
      final Paint marqueeStroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = marqueeBorderColor;
      canvas.drawRect(dragMarqueeRect, marqueeFill);
      canvas.drawRect(dragMarqueeRect, marqueeStroke);
    }
  }

  @override
  bool shouldRepaint(covariant OcrLiveTextPainter oldDelegate) {
    return oldDelegate.lines != lines ||
        oldDelegate.transform.scaleX != transform.scaleX ||
        oldDelegate.transform.scaleY != transform.scaleY ||
        oldDelegate.transform.offsetX != transform.offsetX ||
        oldDelegate.transform.offsetY != transform.offsetY ||
        oldDelegate.highlightFillColor != highlightFillColor ||
        oldDelegate.selectedFillColor != selectedFillColor;
  }
}
