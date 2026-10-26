import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'ocr_models.dart';

/// Pure Dart spatial layout analysis and paragraph clustering engine shared by Native and Web.
///
/// Sorts raw [OcrTextLine]s in natural reading order (top-to-bottom, left-to-right) and
/// merges spatially adjacent lines with compatible line heights and horizontal alignment
/// into cohesive [OcrTextBlock] paragraphs.
class OcrParagraphClusterer {
  const OcrParagraphClusterer._();

  /// Sorts [rawLines] in reading order and clusters them into [OcrTextBlock]s.
  static ({List<OcrTextLine> sortedLines, List<OcrTextBlock> blocks})
  clusterLines(
    List<OcrTextLine> rawLines, {
    double maxVerticalGapMultiplier = 1.35,
    double maxLineHeightRatio = 1.45,
    double minHorizontalOverlapRatio = 0.15,
  }) {
    if (rawLines.isEmpty) {
      return (
        sortedLines: const <OcrTextLine>[],
        blocks: const <OcrTextBlock>[],
      );
    }

    // 1. Sort lines in natural reading order: top-to-bottom, breaking ties left-to-right
    final List<OcrTextLine> sorted = List<OcrTextLine>.from(rawLines)
      ..sort((OcrTextLine a, OcrTextLine b) {
        final double avgHeight =
            (a.estimatedLineHeight + b.estimatedLineHeight) * 0.5;
        final double verticalDiff = (a.boundingBox.top - b.boundingBox.top)
            .abs();
        // If two segments are on the same horizontal line (within 0.45 * lineHeight), sort left-to-right
        if (verticalDiff <= avgHeight * 0.45) {
          return a.boundingBox.left.compareTo(b.boundingBox.left);
        }
        return a.boundingBox.top.compareTo(b.boundingBox.top);
      });

    // 2. Group adjacent compatible lines into paragraph clusters
    final List<List<OcrTextLine>> rawBlocks = <List<OcrTextLine>>[];
    for (final OcrTextLine line in sorted) {
      bool merged = false;
      for (int i = rawBlocks.length - 1; i >= 0; i--) {
        final List<OcrTextLine> candidateCluster = rawBlocks[i];
        final OcrTextLine prevLine = candidateCluster.last;
        if (_shouldMergeIntoBlock(
          prevLine,
          line,
          maxVerticalGapMultiplier: maxVerticalGapMultiplier,
          maxLineHeightRatio: maxLineHeightRatio,
          minHorizontalOverlapRatio: minHorizontalOverlapRatio,
        )) {
          candidateCluster.add(line);
          merged = true;
          break;
        }
      }
      if (!merged) {
        rawBlocks.add(<OcrTextLine>[line]);
      }
    }

    // 3. Build OcrTextBlock objects with enclosing bounding boxes and 4 clockwise vertices
    final List<OcrTextBlock> blocks = rawBlocks
        .map((List<OcrTextLine> cluster) {
          double minX = cluster.first.boundingBox.left;
          double minY = cluster.first.boundingBox.top;
          double maxX = cluster.first.boundingBox.right;
          double maxY = cluster.first.boundingBox.bottom;

          for (final OcrTextLine l in cluster) {
            minX = math.min(minX, l.boundingBox.left);
            minY = math.min(minY, l.boundingBox.top);
            maxX = math.max(maxX, l.boundingBox.right);
            maxY = math.max(maxY, l.boundingBox.bottom);
          }

          final Rect rect = Rect.fromLTRB(minX, minY, maxX, maxY);
          return OcrTextBlock(
            lines: List<OcrTextLine>.unmodifiable(cluster),
            boundingBox: rect,
            cornerPoints: <Offset>[
              rect.topLeft,
              rect.topRight,
              rect.bottomRight,
              rect.bottomLeft,
            ],
          );
        })
        .toList(growable: false);

    return (
      sortedLines: List<OcrTextLine>.unmodifiable(sorted),
      blocks: List<OcrTextBlock>.unmodifiable(blocks),
    );
  }

  static bool _shouldMergeIntoBlock(
    OcrTextLine upper,
    OcrTextLine lower, {
    required double maxVerticalGapMultiplier,
    required double maxLineHeightRatio,
    required double minHorizontalOverlapRatio,
  }) {
    final double h1 = math.max(1.0, upper.estimatedLineHeight);
    final double h2 = math.max(1.0, lower.estimatedLineHeight);
    final double heightRatio = math.max(h1, h2) / math.min(h1, h2);
    if (heightRatio > maxLineHeightRatio) {
      return false;
    }

    final double avgHeight = (h1 + h2) * 0.5;
    // Allow either same-row horizontal segments or next-row vertical paragraphs
    final double verticalGap = lower.boundingBox.top - upper.boundingBox.bottom;
    if (verticalGap < -avgHeight * 0.65 ||
        verticalGap > avgHeight * maxVerticalGapMultiplier) {
      return false;
    }

    // Check angle consistency (within 8 degrees)
    if ((upper.angle - lower.angle).abs() > 8.0) {
      return false;
    }

    // Check horizontal alignment (left-edge alignment or horizontal overlap)
    final double leftEdgeDelta =
        (upper.boundingBox.left - lower.boundingBox.left).abs();
    final bool leftAligned = leftEdgeDelta <= avgHeight * 2.2;

    final double overlapLeft = math.max(
      upper.boundingBox.left,
      lower.boundingBox.left,
    );
    final double overlapRight = math.min(
      upper.boundingBox.right,
      lower.boundingBox.right,
    );
    final double overlapWidth = math.max(0.0, overlapRight - overlapLeft);
    final double minWidth = math.max(
      1.0,
      math.min(upper.boundingBox.width, lower.boundingBox.width),
    );
    final bool hasOverlap =
        (overlapWidth / minWidth) >= minHorizontalOverlapRatio;

    return leftAligned || hasOverlap;
  }
}
