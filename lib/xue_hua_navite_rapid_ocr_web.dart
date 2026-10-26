import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Web plugin registration entry point for `xue_hua_navite_rapid_ocr`.
///
/// The actual OCR execution on Web is handled directly via `OcrEngineWeb`
/// (`dart:js_interop` + `Web Worker` + `onnxruntime-web`) selected through
/// conditional exports in `lib/xue_hua_navite_rapid_ocr.dart`.
class XueHuaNaviteRapidOcrWebPlugin {
  static void registerWith(Registrar registrar) {
    // Registered for Flutter Web plugin discovery compatibility.
  }
}
