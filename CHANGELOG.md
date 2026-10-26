## Unreleased

* Aligned ONNX model pack and asset paths with **RapidOCR v3.10.0** (`*_mobile.onnx` naming, ModelScope `resolve/v3.10.0`, SHA256 checks in `scripts/download_models.sh`).

## 1.0.0

* Initial production release of `xue_hua_navite_rapid_ocr` across all 6 platforms (Android, iOS, macOS, Windows, Linux, Web).
* Added `XueHuaNaviteRapidOcr` unified engine with conditional compilation (`dart.library.ffi` vs `dart.library.js_interop`).
* Added Native C++17 `RapidOcrOnnx` pipeline (`DBNet` + `AngleNet` + `CrnnNet`/`SVTR`) with zero-copy FFI Worker Isolate, automatic EXIF orientation correction, and multi-format pixel buffers (`RGBA8888`, `BGRA8888`, `NV21`).
* Added Web engine powered by `dart:js_interop`, `onnxruntime-web` (WebGPU / WASM SIMD), `OffscreenCanvas`, `CacheStorage` / `IndexedDB` model caching, and dedicated Web Worker inference.
* Added pure Dart spatial layout analysis & paragraph clustering (`OcrResult`, `OcrTextBlock`, `OcrTextLine`) with `fullText`, `toMarkdown()`, and `toJson()`.
* Added `OcrLiveTextOverlay` interactive widget with rotated quadrilateral highlights, touch/mouse lasso & rectangular multi-line selection, `SystemMouseCursors.text` hover cursor, and floating action toolbar.
* Added Swift Package Manager (`Package.swift`) support for iOS & macOS and CMake support for Android, Windows, and Linux.
* Added AI coding agent skill (`skills/xue_hua_navite_rapid_ocr-usage/SKILL.md`).
