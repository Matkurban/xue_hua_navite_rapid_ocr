import 'ocr_engine_interface.dart';

/// Fallback stub factory used only if neither `dart.library.ffi` nor `dart.library.js_interop`
/// is available in the compilation environment.
OcrPlatformEngine createPlatformOcrEngine() {
  throw UnsupportedError(
    'Cannot create OcrPlatformEngine without dart:ffi (Native) or dart:js_interop (Web).',
  );
}
