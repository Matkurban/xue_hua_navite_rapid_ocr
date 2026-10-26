import 'dart:ui' show Offset, Rect;

import 'ocr_text_block.dart';
import 'ocr_text_line.dart';

/// Complete OCR recognition result shared across all 6 platforms (Native FFI & Web).
class OcrResult {
  const OcrResult({
    required this.lines,
    required this.blocks,
    required this.imageWidth,
    required this.imageHeight,
    required this.totalTimeMs,
    this.preprocessTimeMs = 0.0,
    this.detTimeMs = 0.0,
    this.clsTimeMs = 0.0,
    this.recTimeMs = 0.0,
    this.exifOrientation = 1,
    this.executionProviderUsed = 'cpu',
  });

  /// Individual recognized text lines sorted in reading order (top-to-bottom, left-to-right).
  final List<OcrTextLine> lines;

  /// Spatially clustered paragraph blocks produced by `OcrParagraphClusterer`.
  final List<OcrTextBlock> blocks;

  /// Corrected image width in pixels (after EXIF orientation normalization).
  final int imageWidth;

  /// Corrected image height in pixels (after EXIF orientation normalization).
  final int imageHeight;

  /// Total end-to-end OCR pipeline duration in milliseconds.
  final double totalTimeMs;

  /// Image decode & EXIF orientation normalization time in milliseconds.
  final double preprocessTimeMs;

  /// DBNet detection stage duration in milliseconds.
  final double detTimeMs;

  /// AngleNet direction classification stage duration in milliseconds.
  final double clsTimeMs;

  /// CrnnNet/SVTR recognition stage duration in milliseconds.
  final double recTimeMs;

  /// Original EXIF orientation tag (`1..8`, where `1` is normal).
  final int exifOrientation;

  /// Actual Execution Provider used (`cpu`, `coreml`, `nnapi`, `directml`, `webgpu`, `wasm`).
  final String executionProviderUsed;

  /// Returns `true` when no text lines were detected.
  bool get isEmpty => lines.isEmpty;

  /// Returns `true` when at least one text line was detected.
  bool get isNotEmpty => lines.isNotEmpty;

  /// Full plain text reconstructed from paragraph [blocks] (or [lines] if blocks is empty).
  String get fullText {
    if (blocks.isNotEmpty) {
      return blocks.map((OcrTextBlock b) => b.text).join('\n\n');
    }
    return lines.map((OcrTextLine l) => l.text).join('\n');
  }

  /// Exports the recognized document layout into structured Markdown.
  ///
  /// Automatically formats large prominent top lines as headings and preserves paragraph blocks.
  String toMarkdown() {
    if (blocks.isEmpty && lines.isEmpty) {
      return '';
    }
    final List<OcrTextBlock> targetBlocks = blocks.isNotEmpty
        ? blocks
        : <OcrTextBlock>[
            OcrTextBlock(
              lines: lines,
              boundingBox: Rect.fromLTWH(
                0,
                0,
                imageWidth.toDouble(),
                imageHeight.toDouble(),
              ),
              cornerPoints: <Offset>[
                Offset.zero,
                Offset(imageWidth.toDouble(), 0),
                Offset(imageWidth.toDouble(), imageHeight.toDouble()),
                Offset(0, imageHeight.toDouble()),
              ],
            ),
          ];

    final double medianHeight = _computeMedianLineHeight(lines);
    final StringBuffer buffer = StringBuffer();

    for (int i = 0; i < targetBlocks.length; i++) {
      final OcrTextBlock block = targetBlocks[i];
      if (block.lines.length == 1 &&
          medianHeight > 0 &&
          block.lines.first.estimatedLineHeight >= medianHeight * 1.35) {
        buffer.writeln('## ${block.lines.first.text.trim()}');
      } else {
        buffer.writeln(block.text.trim());
      }
      if (i < targetBlocks.length - 1) {
        buffer.writeln();
      }
    }
    return buffer.toString().trimRight();
  }

  /// Serializes the entire [OcrResult] including timing breakdown, lines, and paragraph blocks to JSON.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'imageWidth': imageWidth,
    'imageHeight': imageHeight,
    'exifOrientation': exifOrientation,
    'executionProviderUsed': executionProviderUsed,
    'totalTimeMs': double.parse(totalTimeMs.toStringAsFixed(2)),
    'preprocessTimeMs': double.parse(preprocessTimeMs.toStringAsFixed(2)),
    'detTimeMs': double.parse(detTimeMs.toStringAsFixed(2)),
    'clsTimeMs': double.parse(clsTimeMs.toStringAsFixed(2)),
    'recTimeMs': double.parse(recTimeMs.toStringAsFixed(2)),
    'fullText': fullText,
    'lines': lines.map((OcrTextLine l) => l.toJson()).toList(growable: false),
    'blocks': blocks
        .map((OcrTextBlock b) => b.toJson())
        .toList(growable: false),
  };

  static double _computeMedianLineHeight(List<OcrTextLine> lines) {
    if (lines.isEmpty) return 0.0;
    final List<double> heights =
        lines.map((OcrTextLine l) => l.estimatedLineHeight).toList()..sort();
    return heights[heights.length ~/ 2];
  }
}
