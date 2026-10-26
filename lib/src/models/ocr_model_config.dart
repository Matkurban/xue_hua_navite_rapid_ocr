import 'dart:typed_data';

import 'ocr_enums.dart';

/// Model configuration for initializing `XueHuaNaviteRapidOcr`.
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

  /// Convenience factory that populates default asset paths for a specific [OcrLanguage].
  factory OcrModelConfig.forLanguage(
    OcrLanguage language, {
    OcrExecutionProvider executionProvider = OcrExecutionProvider.auto,
    String? detModelPathOrUrl,
    String? clsModelPathOrUrl =
        'assets/models/ch_ppocr_mobile_v2.0_cls_infer.onnx',
    String? recModelPathOrUrl,
    String? keysPathOrUrl,
    int numThreads = 4,
    bool enableHardwareAcceleration = true,
    bool enableWebModelCache = true,
  }) {
    return OcrModelConfig(
      language: language,
      executionProvider: executionProvider,
      detModelPathOrUrl: detModelPathOrUrl ?? language.defaultDetAssetPath,
      clsModelPathOrUrl: clsModelPathOrUrl,
      recModelPathOrUrl: recModelPathOrUrl ?? language.defaultRecAssetPath,
      keysPathOrUrl: keysPathOrUrl ?? language.defaultKeysAssetPath,
      numThreads: numThreads,
      enableHardwareAcceleration: enableHardwareAcceleration,
      enableWebModelCache: enableWebModelCache,
    );
  }

  /// Preset language configuration (`chineseAndEnglish`, `english`, `japanese`, `korean`, `latin`, `cyrillic`, `arabic`, or `multilingual`).
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
