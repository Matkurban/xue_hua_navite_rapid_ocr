/// Supported OCR recognition language presets for PP-OCRv4 / PP-OCRv5 ONNX pipelines.
///
/// Covers 80+ languages via PaddleOCR / RapidOCR ONNX recognition models and character dictionaries.
enum OcrLanguage {
  /// Default simplified/traditional Chinese + English + numeric mixed model (`ch_PP-OCRv4` / `ch_PP-OCRv5`).
  chineseAndEnglish(
    'ch_PP-OCRv4',
    'Chinese & English (ch_PP-OCRv4/v5)',
    'assets/models/ch_PP-OCRv4_det_infer.onnx',
    'assets/models/ch_PP-OCRv4_rec_infer.onnx',
    'assets/models/ppocr_keys_v1.txt',
  ),

  /// English & numeric high-speed recognition model (`en_PP-OCRv4`).
  english(
    'en_PP-OCRv4',
    'English (en_PP-OCRv4)',
    'assets/models/ch_PP-OCRv4_det_infer.onnx',
    'assets/models/en_PP-OCRv4_rec_infer.onnx',
    'assets/models/en_dict.txt',
  ),

  /// Japanese recognition model (`japan_PP-OCRv4`).
  japanese(
    'japan_PP-OCRv4',
    'Japanese / 日本語 (japan_PP-OCRv4)',
    'assets/models/Multilingual_PP-OCRv3_det_infer.onnx',
    'assets/models/japan_PP-OCRv4_rec_infer.onnx',
    'assets/models/japan_dict.txt',
  ),

  /// Korean recognition model (`korean_PP-OCRv4`).
  korean(
    'korean_PP-OCRv4',
    'Korean / 한국어 (korean_PP-OCRv4)',
    'assets/models/Multilingual_PP-OCRv3_det_infer.onnx',
    'assets/models/korean_PP-OCRv4_rec_infer.onnx',
    'assets/models/korean_dict.txt',
  ),

  /// Latin script recognition model (`latin_PP-OCRv3`, covering French, German, Spanish, Italian, Portuguese, etc.).
  latin(
    'latin_PP-OCRv3',
    'Latin (French / German / Spanish / Italian / Portuguese)',
    'assets/models/Multilingual_PP-OCRv3_det_infer.onnx',
    'assets/models/latin_PP-OCRv3_rec_infer.onnx',
    'assets/models/latin_dict.txt',
  ),

  /// Cyrillic script recognition model (`cyrillic_PP-OCRv3`, covering Russian, Ukrainian, Belarusian, Bulgarian, etc.).
  cyrillic(
    'cyrillic_PP-OCRv3',
    'Cyrillic / Русский (Russian / Ukrainian / Bulgarian)',
    'assets/models/Multilingual_PP-OCRv3_det_infer.onnx',
    'assets/models/cyrillic_PP-OCRv3_rec_infer.onnx',
    'assets/models/cyrillic_dict.txt',
  ),

  /// Arabic script recognition model (`arabic_PP-OCRv4`, covering Arabic, Persian, Uyghur, Urdu).
  arabic(
    'arabic_PP-OCRv4',
    'Arabic / العربية (arabic_PP-OCRv4)',
    'assets/models/Multilingual_PP-OCRv3_det_infer.onnx',
    'assets/models/arabic_PP-OCRv4_rec_infer.onnx',
    'assets/models/arabic_dict.txt',
  ),

  /// Universal multilingual model supporting 80+ languages with custom `recModelPathOrUrl` and `keysPathOrUrl`.
  multilingual(
    'multilingual_PP-OCRv4',
    'Multilingual (80+ Languages Custom Model)',
    'assets/models/Multilingual_PP-OCRv3_det_infer.onnx',
    'assets/models/multilingual_PP-OCRv4_rec_infer.onnx',
    'assets/models/multilingual_keys.txt',
  );

  const OcrLanguage(
    this.modelPrefix,
    this.displayName,
    this.defaultDetAssetPath,
    this.defaultRecAssetPath,
    this.defaultKeysAssetPath,
  );

  /// Model identifier prefix.
  final String modelPrefix;

  /// Human-readable description.
  final String displayName;

  /// Recommended default asset path for the DBNet detection model (`det.onnx`).
  final String defaultDetAssetPath;

  /// Recommended default asset path for the recognition model (`rec.onnx`).
  final String defaultRecAssetPath;

  /// Recommended default asset path for the character dictionary (`keys.txt`).
  final String defaultKeysAssetPath;
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
