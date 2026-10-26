import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

/// Supported OCR recognition language presets for PP-OCRv4 / PP-OCRv5 ONNX pipelines.
enum OcrLanguage {
  /// Default simplified/traditional Chinese + English + numeric mixed model (`ch_PP-OCRv4` / `ch_PP-OCRv5`).
  chineseAndEnglish('ch_PP-OCRv4', 'Chinese & English (ch_PP-OCRv4/v5)'),

  /// Multilingual model supporting 80+ languages including Japanese, Korean, French,
  /// German, Russian, Arabic, Spanish, Portuguese, and Latin scripts.
  multilingual('multilingual_PP-OCRv4', 'Multilingual (80+ Languages)');

  const OcrLanguage(this.modelPrefix, this.displayName);

  /// Model identifier prefix.
  final String modelPrefix;

  /// Human-readable description.
  final String displayName;
}

/// Hardware execution provider preference across Native (FFI) and Web (ONNX Runtime Web).
enum OcrExecutionProvider {
  /// Automatically selects the optimal execution provider for the current platform
  /// (CoreML on iOS/macOS, NNAPI on Android, DirectML on Windows, WebGPU/WASM on Web, CPU fallback).
  auto(0, 'auto'),

  /// Standard multi-threaded CPU execution provider (all platforms).
  cpu(1, 'cpu'),

  /// Apple CoreML / Neural Engine hardware acceleration (iOS & macOS).
  coreML(2, 'coreml'),

  /// Android Neural Networks API hardware acceleration (Android).
  nnapi(3, 'nnapi'),

  /// Microsoft DirectX 12 DirectML GPU acceleration (Windows).
  directML(4, 'directml'),

  /// Browser WebGPU hardware acceleration (Web).
  webGpu(5, 'webgpu'),

  /// Browser WebAssembly SIMD + multi-threading execution provider (Web).
  wasm(6, 'wasm');

  const OcrExecutionProvider(this.nativeValue, this.wireName);

  /// Integer enum value passed across the C FFI boundary.
  final int nativeValue;

  /// String identifier used by `onnxruntime-web` and JSON serialization.
  final String wireName;
}

/// Pixel buffer memory layout format for `recognizeRawPixels`.
enum OcrPixelFormat {
  /// 32-bit RGBA format (8 bits per channel: Red, Green, Blue, Alpha).
  /// Matches `ui.ImageByteFormat.rawRgba` and HTML5 Canvas `ImageData`.
  rgba8888(0),

  /// 32-bit BGRA format (8 bits per channel: Blue, Green, Red, Alpha).
  /// Common on iOS/macOS CoreVideo `kCVPixelFormatType_32BGRA` and Windows bitmaps.
  bgra8888(1),

  /// YUV420SP NV21 camera preview plane format (common on Android Camera2/CameraX).
  nv21(2);

  const OcrPixelFormat(this.nativeValue);

  /// Integer enum value passed across the C FFI boundary.
  final int nativeValue;
}

/// Model configuration for initializing [XueHuaNaviteRapidOcr].
///
/// Supports loading `.onnx` models (`det.onnx`, `cls.onnx`, `rec.onnx`) and `keys.txt`
/// from local filesystem paths, Flutter asset keys (`assets/...`), remote/CDN URLs (Web),
/// or preloaded in-memory [Uint8List] buffers.
class OcrModelConfig {
  const OcrModelConfig({
    this.language = OcrLanguage.chineseAndEnglish,
    this.executionProvider = OcrExecutionProvider.auto,
    this.detModelPathOrUrl,
    this.clsModelPathOrUrl,
    this.recModelPathOrUrl,
    this.keysPathOrUrl,
    this.detModelBytes,
    this.clsModelBytes,
    this.recModelBytes,
    this.keysUtf8Text,
    this.numThreads = 4,
    this.enableHardwareAcceleration = true,
    this.enableWebModelCache = true,
    this.webCacheName = 'xue_hua_rapid_ocr_onnx_cache_v1',
    this.webOrtScriptUrl =
        'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.20.1/dist/ort.min.js',
  });

  /// Preset language configuration (`chineseAndEnglish` or `multilingual`).
  final OcrLanguage language;

  /// Preferred hardware acceleration Execution Provider.
  final OcrExecutionProvider executionProvider;

  /// Path, Flutter asset key, or URL to the DBNet text detection model (`det.onnx`).
  final String? detModelPathOrUrl;

  /// Path, Flutter asset key, or URL to the AngleNet direction classifier model (`cls.onnx`).
  final String? clsModelPathOrUrl;

  /// Path, Flutter asset key, or URL to the CrnnNet/SVTR text recognition model (`rec.onnx`).
  final String? recModelPathOrUrl;

  /// Path, Flutter asset key, or URL to the character dictionary (`keys.txt`).
  final String? keysPathOrUrl;

  /// Optional in-memory bytes for `det.onnx`.
  final Uint8List? detModelBytes;

  /// Optional in-memory bytes for `cls.onnx`.
  final Uint8List? clsModelBytes;

  /// Optional in-memory bytes for `rec.onnx`.
  final Uint8List? recModelBytes;

  /// Optional in-memory UTF-8 content for `keys.txt`.
  final String? keysUtf8Text;

  /// Number of CPU intra-op threads for ONNX Runtime (default: `4`).
  final int numThreads;

  /// Whether to enable OS/browser hardware acceleration (CoreML/NNAPI/DirectML/WebGPU).
  final bool enableHardwareAcceleration;

  /// On Web, whether to persist downloaded `.onnx` and `keys.txt` files in browser
  /// `CacheStorage` / `IndexedDB` so subsequent page reloads do not re-download models.
  final bool enableWebModelCache;

  /// Browser CacheStorage / IndexedDB store name on Web.
  final String webCacheName;

  /// Optional CDN URL for loading `onnxruntime-web` inside the Web Worker if not pre-loaded.
  final String webOrtScriptUrl;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'language': language.name,
    'executionProvider': executionProvider.wireName,
    'detModelPathOrUrl': detModelPathOrUrl,
    'clsModelPathOrUrl': clsModelPathOrUrl,
    'recModelPathOrUrl': recModelPathOrUrl,
    'keysPathOrUrl': keysPathOrUrl,
    'numThreads': numThreads,
    'enableHardwareAcceleration': enableHardwareAcceleration,
    'enableWebModelCache': enableWebModelCache,
    'webCacheName': webCacheName,
    'webOrtScriptUrl': webOrtScriptUrl,
  };
}

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

  /// Concatenated paragraph text, automatically joining CJK lines without extra spaces
  /// and Latin/numeric lines with spaces or newlines.
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

  /// Spatially clustered paragraph blocks produced by [OcrParagraphClusterer].
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

/// Exception thrown by [XueHuaNaviteRapidOcr] when initialization or inference fails.
class XueHuaOcrException implements Exception {
  const XueHuaOcrException(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() =>
      'XueHuaOcrException(${code != null ? 'code: $code, ' : ''}message: $message)';
}
