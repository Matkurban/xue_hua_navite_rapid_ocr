import 'package:flutter/painting.dart' show Color;

/// Highlight appearance and the rules that decide which quads are drawn.
///
/// Thresholds are properties of this style, not optional arguments kept so an
/// older widget constructor would still compile.
class OcrLiveTextStyle {
  const OcrLiveTextStyle({
    this.highlightOutset = 1.25,
    this.minConfidence = 0.05,
    this.minBoxScore = 0.05,
    this.axisSnapDegrees = 6.0,
    this.highlightFillColor = const Color(0x282196F3),
    this.highlightBorderColor = const Color(0x992196F3),
    this.selectedFillColor = const Color(0x4D1976D2),
    this.selectedBorderColor = const Color(0xFF1565C0),
    this.hoveredFillColor = const Color(0x3842A5F5),
    this.marqueeFillColor = const Color(0x261E88E5),
    this.marqueeBorderColor = const Color(0xCC1E88E5),
  });

  /// Logical pixels the stroke sits outside the glyph quad.
  final double highlightOutset;

  /// Lines below this recognition confidence are not drawn or hit-tested.
  final double minConfidence;

  /// Lines below this detection score are not drawn or hit-tested.
  final double minBoxScore;

  /// Top and bottom edges within this many degrees of horizontal snap to an
  /// axis-aligned box. Upright UI noise is inside 6°. A real ~12° line stays
  /// oriented.
  final double axisSnapDegrees;

  final Color highlightFillColor;
  final Color highlightBorderColor;
  final Color selectedFillColor;
  final Color selectedBorderColor;
  final Color hoveredFillColor;
  final Color marqueeFillColor;
  final Color marqueeBorderColor;
}
