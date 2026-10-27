## Unreleased

* Horizontal UI text no longer gets a rotated quad from a thin edge or a few degrees of centroid noise. Glyph runs thinner than 6px per column (skewed overlay edges, borders) are dropped. Baseline tilt within 6° snaps to an axis-aligned box. A short sliver rotates only when its baseline climbs by more than its own column height, so the owner vault screenshot's 20×15 edge (about −20° over a 7px rise) stays flat. A coherent ~12° glyph run, which climbs several times its stroke height, stays rotated. `OcrLiveTextStyle.axisSnapDegrees` defaults to 6. The complaint fixture is that screenshot (`example/ocr_overlay_complaint.png`, 822×1666).
* **Pre-release breaking API cleanup.** This package has not been published to pub.dev, so compatibility shims were removed. `OcrLiveTextOverlay` takes `OcrLiveTextLayout` (`BoxFit`, `Alignment`, filter quality) and `OcrLiveTextStyle` (colors, outset, score floors, axis snap) instead of optional widget parameters kept so older call sites would compile. `OcrImageCoordinateTransform.compute` requires alignment and image scale; scale and offset are derived from the source and destination rects. The painter requires highlight outset and source line indices. Corner mapping has one path: EXIF when the decoded bitmap is still pre-orientation, otherwise per-axis scale into the decoded pixels, then `BoxFit`. The fallback that ignored a mismatched decode and painted in OCR pixel space is gone.
* Live Text highlights follow Flutter `paintImage` / `applyBoxFit` (contain, cover, fill, alignment, and image scale), including letterboxing and EXIF orientation. Near-upright quads snap to a tight axis-aligned box; empty and near-zero-score detections are not drawn. Decoded bitmaps are localized from glyph edges instead of a fixed sheared demo sheet. Arbitrary screenshots still use a placeholder transcription until ONNX weights run.
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
