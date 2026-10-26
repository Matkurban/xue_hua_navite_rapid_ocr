library xue_hua_navite_rapid_ocr;

import 'dart:typed_data';

import 'src/engine/ocr_engine_interface.dart';
import 'src/engine/ocr_engine_stub.dart'
    if (dart.library.ffi) 'src/engine/ocr_engine_ffi.dart'
    if (dart.library.js_interop) 'src/engine/ocr_engine_web.dart';
import 'src/models/ocr_models.dart';

export 'src/engine/ocr_engine_interface.dart' show OcrPlatformEngine;
export 'src/models/ocr_models.dart';
export 'src/models/paragraph_clusterer.dart' show OcrParagraphClusterer;
export 'src/widgets/ocr_live_text_overlay.dart';

/// Unified 6-platform offline RapidOCR (PP-OCRv4 / PP-OCRv5 ONNX) engine for Flutter.
///
/// Uses compile-time conditional exports (`dart.library.ffi` vs `dart.library.js_interop`)
/// to automatically dispatch between:
/// - **Native (Android / iOS / macOS / Windows / Linux)**: `RapidOcrOnnx C++17` + `dart:ffi`
///   + background `Worker Isolate` with zero-copy `TransferableTypedData`.
/// - **Web (Browser WASM / WebGPU)**: `dart:js_interop` + `onnxruntime-web` (WebGPU / WASM SIMD)
///   + `OffscreenCanvas` + `CacheStorage` / `IndexedDB` inside a dedicated `Web Worker`.
class XueHuaNaviteRapidOcr {
  /// Creates a new [XueHuaNaviteRapidOcr] instance backed by the platform's native FFI Isolate
  /// or Web Worker engine, or a custom [engine] for testing.
  XueHuaNaviteRapidOcr({OcrPlatformEngine? engine})
    : _engine = engine ?? createPlatformOcrEngine();

  /// Shared singleton convenience instance.
  static final XueHuaNaviteRapidOcr instance = XueHuaNaviteRapidOcr();

  final OcrPlatformEngine _engine;

  /// Returns `true` if [initialize] has completed and the engine is ready for inference.
  bool get isInitialized => _engine.isInitialized;

  /// Initializes the OCR engine (automatically launching the Native FFI Worker Isolate
  /// or Web Worker session for the current platform).
  Future<void> initialize(OcrModelConfig config) => _engine.initialize(config);

  /// 1. Recognizes text from a local file path (Native) or Blob / Data / HTTP / Asset URL (Web).
  Future<OcrResult> recognizeFile(
    String filePathOrUrl, {
    OcrRecognizeOptions? options,
  }) => _engine.recognizeFile(filePathOrUrl, options: options);

  /// 2. Recognizes text from in-memory encoded image bytes (PNG, JPEG, WebP, BMP).
  ///
  /// Works identically across all 6 platforms for clipboard screenshots, file picker bytes,
  /// and cached network image [Uint8List] buffers.
  Future<OcrResult> recognizeBytes(
    Uint8List encodedBytes, {
    OcrRecognizeOptions? options,
  }) => _engine.recognizeBytes(encodedBytes, options: options);

  /// 3. Recognizes text from raw uncompressed pixel buffers (`RGBA8888`, `BGRA8888`, `NV21`).
  ///
  /// Ideal for live camera preview streams or `ui.Image.toByteData(format: ui.ImageByteFormat.rawRgba)`.
  Future<OcrResult> recognizeRawPixels({
    required Uint8List pixels,
    required int width,
    required int height,
    required OcrPixelFormat format,
    int? rowStride,
    OcrRecognizeOptions? options,
  }) => _engine.recognizeRawPixels(
    pixels: pixels,
    width: width,
    height: height,
    format: format,
    rowStride: rowStride,
    options: options,
  );

  /// Releases the underlying C++ engine / Worker Isolate or terminates the Web Worker session.
  Future<void> dispose() => _engine.dispose();
}
