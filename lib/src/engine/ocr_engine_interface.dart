import 'dart:typed_data';

import '../models/ocr_models.dart';

/// Platform-agnostic OCR engine contract implemented by Native FFI (`ocr_engine_ffi.dart`)
/// and Web JS Interop (`ocr_engine_web.dart`).
abstract interface class OcrPlatformEngine {
  /// Returns `true` if [initialize] has completed and the engine has not been disposed.
  bool get isInitialized;

  /// Initializes the underlying native C++ ONNX session (via Worker Isolate)
  /// or Web Worker ONNX Runtime Web session.
  Future<void> initialize(OcrModelConfig config);

  /// Recognizes text from a local file path (Native) or Blob/Data/HTTP/Asset URL (Web).
  Future<OcrResult> recognizeFile(
    String filePathOrUrl, {
    OcrRecognizeOptions? options,
  });

  /// Recognizes text from in-memory encoded image bytes (PNG, JPEG, WebP, BMP).
  Future<OcrResult> recognizeBytes(
    Uint8List encodedBytes, {
    OcrRecognizeOptions? options,
  });

  /// Recognizes text from raw uncompressed pixel buffers (`RGBA8888`, `BGRA8888`, `NV21`).
  Future<OcrResult> recognizeRawPixels({
    required Uint8List pixels,
    required int width,
    required int height,
    required OcrPixelFormat format,
    int? rowStride,
    OcrRecognizeOptions? options,
  });

  /// Releases all native C++ models / Worker Isolates or terminates the Web Worker.
  Future<void> dispose();
}
