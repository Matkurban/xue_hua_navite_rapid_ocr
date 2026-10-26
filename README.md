# xue_hua_navite_rapid_ocr

English | [简体中文](./README_ZH.md)

[![pub package](https://img.shields.io/badge/pub-v1.0.0-blue.svg)](https://github.com/Matkurban/xue_hua_navite_rapid_ocr)
[![Platform](https://img.shields.io/badge/platforms-Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20Web-brightgreen.svg)](https://github.com/Matkurban/xue_hua_navite_rapid_ocr)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

A production-grade, **6-platform offline OCR plugin for Flutter** (`Android`, `iOS`, `macOS`, `Windows`, `Linux`, and `Web`) built on the **RapidOCR (PP-OCRv4 / PP-OCRv5 ONNX Runtime)** pipeline with an interactive **Live Text Overlay (`OcrLiveTextOverlay`)**.

- **Author**: Matkurban (`3496354336@qq.com`)
- **Repository**: [https://github.com/Matkurban/xue_hua_navite_rapid_ocr](https://github.com/Matkurban/xue_hua_navite_rapid_ocr)
- **Related Ecosystem**: Check out `xue_hua_navite_share` — a full-featured 6-platform native share plugin for Flutter!

## Architecture Highlights

1. **True 6-Platform Unified API with Compile-Time Isolation**:
   - Uses Dart conditional exports (`if (dart.library.ffi)` vs `if (dart.library.js_interop)`) so `flutter build web` and `flutter build web --wasm` never fail due to transitive `dart:ffi` or `dart:io` imports.
2. **Native Engine (`Android` / `iOS` / `macOS` / `Windows` / `Linux`)**:
   - Powered by **C++17 (`RapidOcrOnnx`) + `dart:ffi` + dedicated background `Worker Isolate`** with `TransferableTypedData` zero-copy memory transfer.
   - Native **Swift Package Manager (`Package.swift`)** support for iOS & macOS (sharing the same C++17 core) and **CMake (`CMakeLists.txt`)** for Android (16 KB page-size aligned for Android 15+), Windows, and Linux.
   - Built-in JPEG APP1 **EXIF Orientation (`1..8`) automatic parser & rotator**, plus multi-format raw pixel conversion (`RGBA8888`, `BGRA8888`, `NV21`).
3. **Web Engine (`Browser WASM SIMD` / `WebGPU`)**:
   - Powered by modern **`dart:js_interop` + `dart:js_interop_unsafe`** (zero `dart:html` or `dart:js` legacy dependencies).
   - Runs `DBNet` detection (with Vatti polygon unclip expansion), `AngleNet` 180° classification, and `CrnnNet`/`SVTR` CTC greedy decoding inside a dedicated **Web Worker** using `OffscreenCanvas` and `onnxruntime-web`.
   - Automatically caches `.onnx` models and `keys.txt` in browser **`CacheStorage`** (`xue_hua_rapid_ocr_onnx_cache_v1`) so reloads do not re-download model weights.
4. **Spatial Layout Analysis & Paragraph Clustering (`OcrParagraphClusterer`)**:
   - Pure Dart layout engine shared across Native and Web that sorts recognized text lines (`OcrTextLine`) in natural reading order and groups spatially adjacent lines with matching line heights into paragraph blocks (`OcrTextBlock`), exposing `fullText`, `toMarkdown()`, and `toJson()`.
5. **Interactive Live Text Widget (`OcrLiveTextOverlay`)**:
   - Renders rotated 4-vertex quadrilateral highlights directly over the image (`CustomPainter`), supporting single-tap selection, touch/mouse lasso & rectangular multi-line drag selection, automatic desktop/Web `SystemMouseCursors.text` hover cursor, and a customizable floating action bar.

## Directory Structure

```text
xue_hua_navite_rapid_ocr/
├── pubspec.yaml
├── CHANGELOG.md
├── LICENSE
├── README.md
├── README_ZH.md
├── ffigen.yaml
├── src/
│   ├── CMakeLists.txt
│   ├── xue_hua_navite_rapid_ocr_c_api.h
│   └── xue_hua_navite_rapid_ocr_c_api.cpp
├── ios/
│   ├── xue_hua_navite_rapid_ocr.podspec
│   ├── Classes/
│   │   └── xue_hua_navite_rapid_ocr_c_api.cpp
│   └── xue_hua_navite_rapid_ocr/
│       ├── Package.swift
│       └── Sources/xue_hua_navite_rapid_ocr/
│           ├── include/xue_hua_navite_rapid_ocr_c_api.h
│           └── xue_hua_navite_rapid_ocr_c_api.cpp
├── macos/
│   ├── xue_hua_navite_rapid_ocr.podspec
│   ├── Classes/
│   │   └── xue_hua_navite_rapid_ocr_c_api.cpp
│   └── xue_hua_navite_rapid_ocr/
│       ├── Package.swift
│       └── Sources/xue_hua_navite_rapid_ocr/
│           ├── include/xue_hua_navite_rapid_ocr_c_api.h
│           └── xue_hua_navite_rapid_ocr_c_api.cpp
├── android/
│   └── build.gradle
├── windows/
│   └── CMakeLists.txt
├── linux/
│   └── CMakeLists.txt
├── lib/
│   ├── xue_hua_navite_rapid_ocr.dart
│   ├── xue_hua_navite_rapid_ocr_web.dart
│   └── src/
│       ├── engine/
│       │   ├── ocr_engine_interface.dart
│       │   ├── ocr_engine_stub.dart
│       │   ├── ffi_bindings.dart
│       │   ├── ocr_engine_ffi.dart
│       │   ├── ocr_engine_web.dart
│       │   └── rapid_ocr_worker_script.dart
│       ├── models/
│       │   ├── ocr_models.dart
│       │   └── paragraph_clusterer.dart
│       └── widgets/
│           └── ocr_live_text_overlay.dart
├── skills/
│   └── xue-hua-navite-rapid-ocr/
│       └── SKILL.md
├── test/
│   └── xue_hua_navite_rapid_ocr_test.dart
└── example/
    └── lib/
        └── main.dart
```

## Installation & Platform Setup

Add `xue_hua_navite_rapid_ocr` to your `pubspec.yaml`:

```yaml
dependencies:
  xue_hua_navite_rapid_ocr: ^1.0.0
```

### Bundling PP-OCRv4 / PP-OCRv5 ONNX Models

Declare your `.onnx` model files and dictionary in your app's `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/models/ch_PP-OCRv4_det_infer.onnx
    - assets/models/ch_ppocr_mobile_v2.0_cls_infer.onnx
    - assets/models/ch_PP-OCRv4_rec_infer.onnx
    - assets/models/ppocr_keys_v1.txt
```

### Platform Notes

| Platform | Build System | Hardware Acceleration (`OcrExecutionProvider`) | Notes |
| :--- | :--- | :--- | :--- |
| **Android** | CMake + NDK (`minSdk 24`) | `nnapi` / `cpu` | Configured with `-Wl,-z,max-page-size=16384` for Android 15+ 16 KB page alignment. |
| **iOS** | Swift Package Manager (`Package.swift`) & CocoaPods (`iOS 15.0+`) | `coreML` / `cpu` | Shares C++17 source directly via `Package.swift`. |
| **macOS** | Swift Package Manager (`Package.swift`) & CocoaPods (`macOS 11.0+`) | `coreML` / `cpu` | Shares C++17 source directly via `Package.swift`. |
| **Windows** | CMake (`Visual Studio 2022 C++17`) | `directML` / `cpu` | Compiles `xue_hua_navite_rapid_ocr.dll`. |
| **Linux** | CMake (`clang++` / `g++` C++17) | `cpu` | Compiles `libxue_hua_navite_rapid_ocr.so`. |
| **Web** | `dart:js_interop` + Web Worker | `webGpu` / `wasm` | Compatible with `flutter build web --wasm`. Uses `CacheStorage` for model caching. |

## Quick Start & Full Usage

### 1. Initialize the Engine

```dart
import 'package:xue_hua_navite_rapid_ocr/xue_hua_navite_rapid_ocr.dart';

final ocr = XueHuaNaviteRapidOcr.instance;

await ocr.initialize(
  const OcrModelConfig(
    language: OcrLanguage.chineseAndEnglish, // or OcrLanguage.multilingual
    executionProvider: OcrExecutionProvider.auto,
    detModelPathOrUrl: 'assets/models/ch_PP-OCRv4_det_infer.onnx',
    clsModelPathOrUrl: 'assets/models/ch_ppocr_mobile_v2.0_cls_infer.onnx',
    recModelPathOrUrl: 'assets/models/ch_PP-OCRv4_rec_infer.onnx',
    keysPathOrUrl: 'assets/models/ppocr_keys_v1.txt',
    numThreads: 4,
    enableHardwareAcceleration: true,
    enableWebModelCache: true,
  ),
);
```

### 2. Three Ways to Recognize Images

```dart
// A. From local file path (Native) or Blob / Data / HTTP / Asset URL (Web)
final OcrResult fileResult = await ocr.recognizeFile(
  '/path/to/invoice.jpg',
  options: const OcrRecognizeOptions(
    maxSideLen: 960,
    boxThresh: 0.5,
    boxScoreThresh: 0.6,
    unclipRatio: 1.6,
    doAngle: true,
    mostAngle: true,
    minConfidence: 0.3,
  ),
);

// B. From in-memory encoded bytes (PNG / JPEG / WebP / BMP across all 6 platforms)
final OcrResult bytesResult = await ocr.recognizeBytes(encodedPngOrJpegBytes);

// C. From raw camera / ui.Image pixel buffers (RGBA8888 / BGRA8888 / NV21)
final OcrResult pixelResult = await ocr.recognizeRawPixels(
  pixels: rawRgbaBytes,
  width: 1920,
  height: 1080,
  format: OcrPixelFormat.rgba8888,
  rowStride: 1920 * 4,
);

// Inspect paragraphs, plain text, Markdown, and JSON
print(bytesResult.fullText);
print(bytesResult.toMarkdown());
print(bytesResult.toJson());
```

### 3. Interactive Live Text Overlay (`OcrLiveTextOverlay`)

```dart
OcrLiveTextOverlay(
  image: MemoryImage(encodedPngBytes),
  ocrResult: bytesResult,
  fit: BoxFit.contain,
  onSelectionChanged: (String selectedText, List<OcrTextLine> selectedLines) {
    debugPrint('Selected: $selectedText');
  },
  onTextCopied: (String copiedText) {
    debugPrint('Copied to clipboard: $copiedText');
  },
  customActions: [
    OcrLiveTextCustomAction(
      label: 'Share',
      icon: Icons.share_rounded,
      onPressed: (selectedText, selectedLines) {
        // Trigger share or custom workflow
      },
    ),
  ],
)
```

### 4. Dispose Engine When Done

```dart
await ocr.dispose();
```

## AI Coding Agent Skills (`package:skills`)

This package ships with an official AI Agent Skill under [`skills/xue-hua-navite-rapid-ocr/SKILL.md`](./skills/xue-hua-navite-rapid-ocr/SKILL.md) following the [Dart Package Skills specification](https://dart.dev/tools/pub/package-skills). Consumers can install it into their workspace via:

```bash
dart run skills@ get
```

## Important Notes & Best Practices

1. **Zero UI Jank**: All Native C++ decoding/inference runs inside a persistent background `Worker Isolate`, and all Web decoding/inference runs inside a dedicated `Web Worker`.
2. **Automatic EXIF Orientation**: Smartphone camera photos frequently contain EXIF Orientation metadata (`1..8`). Both the Native C++ decoder and Web Worker normalize orientation automatically before detection, returning `result.imageWidth` and `result.imageHeight` in upright display coordinates.
3. **Always Call `dispose()`**: When shutting down a dedicated OCR controller, call `await ocr.dispose()` to free native ONNX sessions or terminate the browser Web Worker.

## License

MIT License © 2026 Matkurban (`3496354336@qq.com`)
