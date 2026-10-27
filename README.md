# xue_hua_navite_rapid_ocr

English | [简体中文](./README_ZH.md)

[![pub package](https://img.shields.io/badge/pub-v1.0.0-blue.svg)](https://github.com/Matkurban/xue_hua_navite_rapid_ocr)
[![Platform](https://img.shields.io/badge/platforms-Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20Web-brightgreen.svg)](https://github.com/Matkurban/xue_hua_navite_rapid_ocr)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

A production-grade, **6-platform offline OCR plugin for Flutter** (`Android`, `iOS`, `macOS`, `Windows`, `Linux`, and `Web`) built on the **RapidOCR **v3.10.0** (PP-OCRv4 / PP-OCRv5 ONNX Runtime)** pipeline with an interactive **Live Text Overlay (`OcrLiveTextOverlay`)** using **`package:material_ui/material_ui.dart`**.

- **Author**: Matkurban (`3496354336@qq.com`)
- **Repository**: [https://github.com/Matkurban/xue_hua_navite_rapid_ocr](https://github.com/Matkurban/xue_hua_navite_rapid_ocr)
- **Related Ecosystem**: Check out `xue_hua_navite_share` — a full-featured 6-platform native share plugin for Flutter!

## Architecture Highlights

1. **True 6-Platform Unified API with Compile-Time Isolation**:
   - Uses Dart conditional exports (`if (dart.library.ffi)` vs `if (dart.library.js_interop)`) so `flutter build web` and `flutter build web --wasm` never fail due to transitive `dart:ffi` or `dart:io` imports.
   - Built with Flutter's decoupled Material Design library [`package:material_ui/material_ui.dart`](https://pub.dev/packages/material_ui) across all UI components, tests, and examples.
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
5. **Interactive Live Text Widget (`OcrLiveTextOverlay`) with Zero `setState` Overhead & Full i18n (`OcrLiveTextStrings`)**:
   - Driven by granular `ValueNotifier`s, `ValueListenableBuilder`s, and `CustomPainter(repaint: Listenable.merge(...))` so mouse hover, marquee dragging, and selection updates only repaint the affected layer without rebuilding the entire widget tree.
   - Accepts an `OcrLiveTextStrings` object (`OcrLiveTextStrings()`, `OcrLiveTextStrings.zhCN()`, `OcrLiveTextStrings.jaJP()`, or custom builders) to localize every button, tooltip, selection counter, and SnackBar notification.

## Modular Directory Structure

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
│   ├── Classes/xue_hua_navite_rapid_ocr_c_api.cpp
│   └── xue_hua_navite_rapid_ocr/
│       ├── Package.swift
│       └── Sources/xue_hua_navite_rapid_ocr/
│           ├── include/xue_hua_navite_rapid_ocr_c_api.h
│           └── xue_hua_navite_rapid_ocr_c_api.cpp
├── macos/
│   ├── xue_hua_navite_rapid_ocr.podspec
│   ├── Classes/xue_hua_navite_rapid_ocr_c_api.cpp
│   └── xue_hua_navite_rapid_ocr/
│       ├── Package.swift
│       └── Sources/xue_hua_navite_rapid_ocr/
│           ├── include/xue_hua_navite_rapid_ocr_c_api.h
│           └── xue_hua_navite_rapid_ocr_c_api.cpp
├── android/build.gradle
├── windows/CMakeLists.txt
├── linux/CMakeLists.txt
├── lib/
│   ├── xue_hua_navite_rapid_ocr.dart
│   ├── xue_hua_navite_rapid_ocr_web.dart
│   └── src/
│       ├── xue_hua_navite_rapid_ocr_client.dart
│       ├── engine/
│       │   ├── ocr_engine_interface.dart
│       │   ├── ocr_engine_stub.dart
│       │   ├── ffi_bindings.dart
│       │   ├── ocr_ffi_messages.dart
│       │   ├── ocr_engine_ffi.dart
│       │   ├── ocr_web_interop_bindings.dart
│       │   ├── ocr_engine_web.dart
│       │   └── rapid_ocr_worker_script.dart
│       ├── models/
│       │   ├── ocr_models.dart
│       │   ├── ocr_enums.dart
│       │   ├── ocr_model_config.dart
│       │   ├── ocr_recognize_options.dart
│       │   ├── ocr_text_line.dart
│       │   ├── ocr_text_block.dart
│       │   ├── ocr_result.dart
│       │   ├── ocr_exception.dart
│       │   └── paragraph_clusterer.dart
│       └── widgets/
│           ├── ocr_image_coordinate_transform.dart
│           ├── ocr_live_text_controller.dart
│           ├── ocr_live_text_custom_action.dart
│           ├── ocr_live_text_painter.dart
│           ├── ocr_live_text_strings.dart
│           └── ocr_live_text_overlay.dart
├── skills/
│   └── xue-hua-navite-rapid-ocr/
│       └── SKILL.md
├── test/
│   └── xue_hua_navite_rapid_ocr_test.dart
└── example/
    └── lib/
        ├── main.dart
        ├── pages/ocr_demo_home_page.dart
        ├── utils/sample_image_generator.dart
        └── widgets/
            ├── live_text_preview_tab.dart
            ├── paragraph_blocks_tab.dart
            ├── markdown_json_tab.dart
            └── engine_config_tab.dart
```

## Installation

Add `xue_hua_navite_rapid_ocr` and `material_ui` (plus `xue_hua_file_operations: ^1.5.2` if you need cross-platform image picking) to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  material_ui: ^1.8.0
  xue_hua_file_operations: ^1.5.2
  xue_hua_navite_rapid_ocr: ^1.0.0
```

## Multilingual OCR Integration Guide (80+ Languages)

> Model filenames and download URLs are aligned with **RapidOCR v3.10.0** (`ModelScope resolve/v3.10.0`, see `scripts/download_models.sh` and [default_models.yaml](https://github.com/RapidAI/RapidOCR/blob/v3.10.0/python/rapidocr/default_models.yaml)). Native recognition loads those weights through ONNX Runtime 1.20.1 (`scripts/download_onnxruntime.sh`, then `scripts/build_native.sh`). Linux and Windows bundle `libonnxruntime` / `onnxruntime.dll` when that download is present under `third_party/onnxruntime/`. macOS CocoaPods embeds `Libraries/libonnxruntime.dylib` via the plugin podspec `prepare_command` (same download). Sandboxed host apps need `com.apple.security.cs.disable-library-validation` (the example entitlements already set it) so RapidOCR can `dlopen` that dylib.

`xue_hua_navite_rapid_ocr` supports 80+ languages by pairing a universal DBNet text detector (`det.onnx`), the 180° orientation classifier (`cls.onnx`), and a language-specific CrnnNet/SVTR recognition model (`rec.onnx`) + character dictionary (`keys.txt`).

### 1. Preset Languages & Recommended ONNX Model Files

| `OcrLanguage` Enum | Supported Scripts / Languages | Recommended Detection Model (`det.onnx`) | Recommended Recognition Model (`rec.onnx`) | Dictionary (`keys.txt`) |
| :--- | :--- | :--- | :--- | :--- |
| `OcrLanguage.chineseAndEnglish` | Simplified/Traditional Chinese, English, Numbers | `ch_PP-OCRv4_det_mobile.onnx` | `ch_PP-OCRv4_rec_mobile.onnx` | `ppocr_keys_v1.txt` |
| `OcrLanguage.english` | English, Numbers, Symbols | `ch_PP-OCRv4_det_mobile.onnx` | `en_PP-OCRv4_rec_mobile.onnx` | `en_dict.txt` |
| `OcrLanguage.japanese` | Japanese (Kanji, Hiragana, Katakana), English | `multi_PP-OCRv3_det_mobile.onnx` | `japan_PP-OCRv4_rec_mobile.onnx` | `japan_dict.txt` |
| `OcrLanguage.korean` | Korean (Hangul), English | `multi_PP-OCRv3_det_mobile.onnx` | `korean_PP-OCRv4_rec_mobile.onnx` | `korean_dict.txt` |
| `OcrLanguage.latin` | French, German, Spanish, Italian, Portuguese, etc. | `multi_PP-OCRv3_det_mobile.onnx` | `latin_PP-OCRv3_rec_mobile.onnx` | `latin_dict.txt` |
| `OcrLanguage.cyrillic` | Russian, Ukrainian, Belarusian, Bulgarian, etc. | `multi_PP-OCRv3_det_mobile.onnx` | `cyrillic_PP-OCRv3_rec_mobile.onnx` | `cyrillic_dict.txt` |
| `OcrLanguage.arabic` | Arabic, Persian, Uyghur, Urdu | `multi_PP-OCRv3_det_mobile.onnx` | `arabic_PP-OCRv4_rec_mobile.onnx` | `arabic_dict.txt` |
| `OcrLanguage.multilingual` | Any custom PP-OCRv4/v5 language model | Custom `det.onnx` path/URL | Custom `rec.onnx` path/URL | Custom `keys.txt` path/URL |

### 2. Declare Multilingual Model Assets in `pubspec.yaml`

```yaml
flutter:
  assets:
    # Shared angle classifier (RapidOCR v3.10.0)
    - assets/models/ch_ppocr_mobile_v2.0_cls_mobile.onnx
    # Chinese & English (default)
    - assets/models/ch_PP-OCRv4_det_mobile.onnx
    - assets/models/ch_PP-OCRv4_rec_mobile.onnx
    - assets/models/ppocr_keys_v1.txt
    # Multilingual detection + Japanese / Korean / Latin / Cyrillic / Arabic
    - assets/models/multi_PP-OCRv3_det_mobile.onnx
    - assets/models/japan_PP-OCRv4_rec_mobile.onnx
    - assets/models/japan_dict.txt
    - assets/models/korean_PP-OCRv4_rec_mobile.onnx
    - assets/models/korean_dict.txt
    - assets/models/latin_PP-OCRv3_rec_mobile.onnx
    - assets/models/latin_dict.txt
```

### 3. Initialize & Dynamically Switch Languages at Runtime

Use `OcrModelConfig.forLanguage(...)` to automatically bind the default asset paths for any `OcrLanguage`, or override `detModelPathOrUrl`, `recModelPathOrUrl`, and `keysPathOrUrl` with custom paths or CDN URLs:

```dart
import 'package:xue_hua_navite_rapid_ocr/xue_hua_navite_rapid_ocr.dart';

final ocr = XueHuaNaviteRapidOcr.instance;

// Initialize with Japanese PP-OCRv4 model
await ocr.initialize(
  OcrModelConfig.forLanguage(
    OcrLanguage.japanese,
    executionProvider: OcrExecutionProvider.auto,
    numThreads: 4,
    enableHardwareAcceleration: true,
    enableWebModelCache: true,
  ),
);

// Switch to Korean or Latin on demand (safely re-initializes the Worker Isolate / Web Worker)
await ocr.initialize(
  OcrModelConfig.forLanguage(OcrLanguage.korean),
);
```

## Full Usage Example with `xue_hua_file_operations` & `OcrLiveTextOverlay`

```dart
import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_file_operations/xue_hua_file_operations.dart';
import 'package:xue_hua_navite_rapid_ocr/xue_hua_navite_rapid_ocr.dart';

class DocumentScannerView extends StatefulWidget {
  const DocumentScannerView({super.key});

  @override
  State<DocumentScannerView> createState() => _DocumentScannerViewState();
}

class _DocumentScannerViewState extends State<DocumentScannerView> {
  final XueHuaNaviteRapidOcr _ocr = XueHuaNaviteRapidOcr();
  final XueHuaFileOperations _fileOps = XueHuaFileOperations.instance;
  final OcrLiveTextController _liveTextController = OcrLiveTextController();

  PlatformFile? _pickedFile;
  OcrResult? _ocrResult;

  @override
  void initState() {
    super.initState();
    _ocr.initialize(
      OcrModelConfig.forLanguage(OcrLanguage.chineseAndEnglish),
    );
  }

  Future<void> _pickImageAndRunOcr() async {
    // 1. Pick an image across Android, iOS, macOS, Windows, Linux, and Web
    final PlatformFile? file = await _fileOps.pickFile(
      type: FileType.image,
      withData: true,
    );
    if (file == null || file.bytes == null) return;

    // 2. Run zero-copy OCR recognition
    final OcrResult result = await _ocr.recognizeBytes(
      file.bytes!,
      options: const OcrRecognizeOptions(
        maxSideLen: 960,
        boxThresh: 0.5,
        boxScoreThresh: 0.6,
        unclipRatio: 1.6,
        doAngle: true,
        minConfidence: 0.3,
      ),
    );

    setState(() {
      _pickedFile = file;
      _ocrResult = result;
    });
  }

  @override
  void dispose() {
    _liveTextController.dispose();
    _ocr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RapidOCR + File Operations'),
        actions: <Widget>[
          FilledButton.icon(
            onPressed: _pickImageAndRunOcr,
            icon: const Icon(Icons.add_photo_alternate_rounded),
            label: const Text('Pick Image & OCR'),
          ),
        ],
      ),
      body: _pickedFile?.bytes != null && _ocrResult != null
          ? OcrLiveTextOverlay(
              image: MemoryImage(_pickedFile!.bytes!),
              ocrResult: _ocrResult!,
              controller: _liveTextController,
              layout: const OcrLiveTextLayout.contain(),
              // Pass localized strings via OcrLiveTextStrings
              strings: OcrLiveTextStrings(
                copyButtonLabel: 'Copy',
                selectAllButtonLabel: 'Select All',
                clearSelectionTooltip: 'Clear selection',
                hideHighlightsTooltip: 'Hide Live Text Highlights',
                showHighlightsTooltip: 'Show Live Text Highlights',
                selectedCountBuilder: (int count) => '$count lines selected',
                copiedSnackBarMessageBuilder: (int count) =>
                    'Copied $count line(s) to clipboard',
              ),
              onSelectionChanged: (String text, List<OcrTextLine> lines) {
                debugPrint('Selected: $text');
              },
            )
          : const Center(child: Text('Tap "Pick Image & OCR" to begin.')),
    );
  }
}
```

## AI Coding Agent Skills (`package:skills`)

This package ships with an official AI Agent Skill under [`skills/xue-hua-navite-rapid-ocr/SKILL.md`](./skills/xue-hua-navite-rapid-ocr/SKILL.md) following the [Dart Package Skills specification](https://dart.dev/tools/pub/package-skills). Consumers can install it into their workspace via:

```bash
dart run skills@ get
```

## Important Notes & Best Practices

1. **Always Use `package:material_ui/material_ui.dart`**: This plugin and its example use Flutter's standalone `material_ui` package rather than legacy `package:flutter/material.dart`.
2. **Fine-Grained Repaints in `OcrLiveTextOverlay`**: `OcrLiveTextOverlay` uses `ValueNotifier` and `Listenable.merge` inside `OcrLiveTextPainter` instead of `setState`. You can also listen to `controller.selectedIndicesListenable` and `controller.showHighlightBoxesListenable` directly.
3. **Automatic EXIF Orientation**: Smartphone camera photos frequently contain EXIF Orientation metadata (`1..8`). Both the Native C++ decoder and Web Worker normalize orientation automatically before detection, returning `result.imageWidth` and `result.imageHeight` in upright display coordinates.

## License

MIT License © 2026 Matkurban (`3496354336@qq.com`)
