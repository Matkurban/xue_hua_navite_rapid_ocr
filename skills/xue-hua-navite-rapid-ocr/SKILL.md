---
name: xue-hua-navite-rapid-ocr
description: >-
  Use when the user is working with xue_hua_navite_rapid_ocr APIs (XueHuaNaviteRapidOcr, OcrLiveTextOverlay, OcrLiveTextStrings, OcrModelConfig.forLanguage) to implement 6-platform offline OCR (PP-OCRv4/PP-OCRv5 ONNX), 80+ language multilingual recognition, zero-copy FFI Worker Isolate inference, WebGPU/WASM Web Worker OCR, EXIF orientation normalization, spatial paragraph clustering, or interactive Live Text selection across Android, iOS, macOS, Windows, Linux, and Web.
---

# xue-hua-navite-rapid-ocr

Provide idiomatic integration patterns, 6-platform setup rules, multilingual model configuration, zero-copy memory guidelines, and Live Text UI best practices for the `xue_hua_navite_rapid_ocr` Flutter plugin (`v1.0.0+`) across Android, iOS, macOS, Windows, Linux, and Web.

## When to Use

- Initializing offline PP-OCRv4 / PP-OCRv5 ONNX pipelines or configuring 80+ language models (`XueHuaNaviteRapidOcr`, `OcrModelConfig.forLanguage`, `OcrLanguage`, `OcrExecutionProvider`)
- Picking images with `xue_hua_file_operations` (`^1.5.2`) and running OCR (`recognizeBytes`, `recognizeFile`)
- Recognizing text from camera preview frames or `ui.Image` raw pixel buffers in `RGBA8888`, `BGRA8888`, or `NV21` formats (`recognizeRawPixels`)
- Extracting structured paragraph blocks, plain text, Markdown, or JSON from OCR results (`OcrResult.blocks`, `fullText`, `toMarkdown()`, `toJson()`)
- Rendering interactive rotated quadrilateral text highlights with fine-grained `ValueNotifier` repaints and customizable i18n strings (`OcrLiveTextOverlay`, `OcrLiveTextController`, `OcrLiveTextStrings`)

## Guidelines

1. Always import `package:material_ui/material_ui.dart` instead of `package:flutter/material.dart` when building UI alongside `xue_hua_navite_rapid_ocr`.
2. Call `await ocr.initialize(OcrModelConfig.forLanguage(OcrLanguage.chineseAndEnglish))` (or another `OcrLanguage` such as `japanese`, `korean`, `latin`, `cyrillic`, `arabic`, `multilingual`) before calling `recognizeFile`, `recognizeBytes`, or `recognizeRawPixels`.
3. Reuse a single `XueHuaNaviteRapidOcr` instance (or `XueHuaNaviteRapidOcr.instance`) across recognition calls so the Native Worker Isolate or Web Worker remains warm in memory. Call `await ocr.dispose()` only when tearing down the feature.
4. Never import `src/engine/ocr_engine_ffi.dart` or `src/engine/ocr_engine_web.dart` directly. Always import `package:xue_hua_navite_rapid_ocr/xue_hua_navite_rapid_ocr.dart` so Dart's conditional exports (`if (dart.library.ffi)` vs `if (dart.library.js_interop)`) keep `flutter build web` and `flutter build web --wasm` free of `dart:ffi` / `dart:io` errors.
5. Pass an `OcrLiveTextStrings` instance (`OcrLiveTextStrings()`, `OcrLiveTextStrings.zhCN()`, `OcrLiveTextStrings.jaJP()`, or custom builders) to `OcrLiveTextOverlay.strings` to localize all buttons, tooltips, selection counters, and SnackBar notifications.
6. Listen to `OcrLiveTextController.selectedIndicesListenable` and `showHighlightBoxesListenable` for granular UI updates rather than wrapping `OcrLiveTextOverlay` in full-page `setState` calls.

## Examples

### Multilingual Initialization and Image Picking with `xue_hua_file_operations`

```dart
import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_file_operations/xue_hua_file_operations.dart';
import 'package:xue_hua_navite_rapid_ocr/xue_hua_navite_rapid_ocr.dart';

final ocr = XueHuaNaviteRapidOcr.instance;
final fileOps = XueHuaFileOperations.instance;

Future<OcrResult?> pickAndRecognizeMultilingual(OcrLanguage language) async {
  // 1. Initialize or switch language model (Chinese/English, Japanese, Korean, Latin, Cyrillic, Arabic)
  await ocr.initialize(
    OcrModelConfig.forLanguage(
      language,
      executionProvider: OcrExecutionProvider.auto,
      numThreads: 4,
      enableHardwareAcceleration: true,
      enableWebModelCache: true,
    ),
  );

  // 2. Pick an image across all 6 platforms using xue_hua_file_operations
  final PlatformFile? file = await fileOps.pickFile(
    type: FileType.image,
    withData: true,
  );
  if (file == null || file.bytes == null) return null;

  // 3. Run zero-copy recognition
  return ocr.recognizeBytes(
    file.bytes!,
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
}
```

### Interactive Live Text Overlay (`OcrLiveTextOverlay`) with Custom i18n Strings

```dart
import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_navite_rapid_ocr/xue_hua_navite_rapid_ocr.dart';

class DocumentLiveTextView extends StatefulWidget {
  const DocumentLiveTextView({
    super.key,
    required this.imageBytes,
    required this.ocrResult,
  });

  final Uint8List imageBytes;
  final OcrResult ocrResult;

  @override
  State<DocumentLiveTextView> createState() => _DocumentLiveTextViewState();
}

class _DocumentLiveTextViewState extends State<DocumentLiveTextView> {
  final OcrLiveTextController _controller = OcrLiveTextController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OcrLiveTextOverlay(
      image: MemoryImage(widget.imageBytes),
      ocrResult: widget.ocrResult,
      controller: _controller,
      strings: OcrLiveTextStrings.zhCN(),
      fit: BoxFit.contain,
      onSelectionChanged: (String selectedText, List<OcrTextLine> lines) {
        debugPrint('Selected ${lines.length} lines: $selectedText');
      },
      customActions: <OcrLiveTextCustomAction>[
        OcrLiveTextCustomAction(
          label: 'Translate',
          icon: Icons.translate_rounded,
          onPressed: (String selectedText, List<OcrTextLine> lines) {
            // Handle custom action on selected text
          },
        ),
      ],
    );
  }
}
```

## Gotchas

- **Use `package:material_ui/material_ui.dart`**: Do not import `package:flutter/material.dart`.
- **Web Compilation (`dart:ffi` / `dart:io` Leak)**: Never import `dart:ffi` or `dart:io` in files shared with Web. Always pass `file.bytes!` from `XueHuaFileOperations.instance.pickFile(withData: true)` to `recognizeBytes(Uint8List)` on Web.
- **EXIF Orientation**: Both the Native C++ decoder and Web `createImageBitmap(..., { imageOrientation: 'from-image' })` normalize EXIF orientation (`1..8`) before DBNet inference so returned `cornerPoints` always match the upright displayed image (`result.imageWidth` x `result.imageHeight`).
