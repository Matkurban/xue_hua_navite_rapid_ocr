/// Fine-grained inference options for a single OCR recognition call.
class OcrRecognizeOptions {
  const OcrRecognizeOptions({
    this.maxSideLen = 960,
    this.boxThresh = 0.5,
    this.boxScoreThresh = 0.6,
    this.unclipRatio = 1.6,
    this.doAngle = true,
    this.mostAngle = true,
    this.minConfidence = 0.3,
  }) : assert(maxSideLen >= 64, 'maxSideLen must be >= 64'),
       assert(boxThresh >= 0.0 && boxThresh <= 1.0),
       assert(boxScoreThresh >= 0.0 && boxScoreThresh <= 1.0),
       assert(unclipRatio > 0.1),
       assert(minConfidence >= 0.0 && minConfidence <= 1.0);

  /// Maximum image side length before DBNet detection downscaling (default: `960`).
  final int maxSideLen;

  /// DBNet probability map binarization threshold (default: `0.5`).
  final double boxThresh;

  /// Minimum polygon score threshold for detected text boxes (default: `0.6`).
  final double boxScoreThresh;

  /// Vatti polygon unclip expansion ratio (default: `1.6`).
  final double unclipRatio;

  /// Whether to run 180-degree AngleNet orientation classification (default: `true`).
  final bool doAngle;

  /// Whether to use majority voting across all text lines for angle classification (default: `true`).
  final bool mostAngle;

  /// Minimum recognition confidence score required to keep a text line (default: `0.3`).
  final double minConfidence;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'maxSideLen': maxSideLen,
    'boxThresh': boxThresh,
    'boxScoreThresh': boxScoreThresh,
    'unclipRatio': unclipRatio,
    'doAngle': doAngle,
    'mostAngle': mostAngle,
    'minConfidence': minConfidence,
  };
}
