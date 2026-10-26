---
name: xue-hua-navite-rapid-ocr
description: >-
  Use when the user is working with xue_hua_navite_rapid_ocr APIs (XueHuaNaviteRapidOcr, OcrLiveTextOverlay) to implement 6-platform offline OCR (PP-OCRv4/PP-OCRv5 ONNX), zero-copy FFI Worker Isolate inference, WebGPU/WASM Web Worker OCR, EXIF orientation normalization, spatial paragraph clustering, or interactive Live Text selection across Android, iOS, macOS, Windows, Linux, and Web.
---

# xue-hua-navite-rapid-ocr

Provide idiomatic integration patterns, 6-platform setup rules, zero-copy memory guidelines, and Live Text UI best practices for the `xue_hua_navite_rapid_ocr` Flutter plugin (`v1.0.0+`) across Android, iOS, macOS, Windows, Linux, and Web.

## When to Use

- Initializing offline PP-OCRv4 / PP-OCRv5 ONNX pipelines (`XueHuaNaviteRapidOcr`, `OcrModelConfig`, `OcrLanguage`, `OcrExecutionProvider`)
- Recognizing text from local files or Web Blob/Data/HTTP URLs (`recognizeFile`)
- Recognizing text from in-memory encoded image bytes such as screenshots, clipboard images, or network buffers (`recognizeBytes`)
- Recognizing text from camera preview frames or `ui.Image` raw pixel buffers in `RGBA8888`, `BGRA8888`, or `NV21` formats (`recognizeRawPixels`)
- Extracting structured paragraph blocks, plain text, Markdown, or JSON from OCR results (`OcrResult.blocks`, `fullText`, `toMarkdown()`, `toJson()`)
- Rendering interactive rotated quadrilateral text highlights with touch/mouse lasso selection and floating copy toolbars (`OcrLiveTextOverlay`, `OcrLiveTextController`)

## Guidelines

1. Always call `await ocr.initialize(OcrModelConfig(...))` before calling `recognizeFile`, `recognizeBytes`, or `recognizeRawPixels`.
2. Reuse a single `XueHuaNaviteRapidOcr` instance (or `XueHuaNaviteRapidOcr.instance`) across multiple recognition calls so the underlying Native Worker Isolate or Web Worker and ONNX sessions remain warm in memory. Call `await ocr.dispose()` only when the feature or screen is permanently torn down.
3. Never import `src/engine/ocr_engine_ffi.dart` or `src/engine/ocr_engine_web.dart` directly in application code. Always import `package:xue_hua_navite_rapid_ocr/xue_hua_navite_rapid_ocr.dart` so Dart's conditional exports (`if (dart.library.ffi)` vs `if (dart.library.js_interop)`) keep `flutter build web` and `flutter build web --wasm` free of `dart:ffi` / `dart:io` compilation errors.
4. Use `OcrExecutionProvider.auto` by default so the engine automatically selects `coreML` on iOS/macOS, `nnapi` on Android, `directML` on Windows, and `webGpu` (with `wasm` SIMD fallback) on Web.
5. Keep `enableWebModelCache: true` in `OcrModelConfig` on Web targets so `.onnx` models and `keys.txt` dictionaries are cached in the browser's `CacheStorage` (`xue_hua_rapid_ocr_onnx_cache_v1`) instead of re-downloading on every page reload.
6. When displaying recognized text over an image, pass the exact same `BoxFit` (for example, `BoxFit.contain`) to `OcrLiveTextOverlay` so the 4 clockwise rotated vertices (`line.cornerPoints`) align with the rendered image.

## Examples

### Initialize Engine and Recognize Image Bytes / Raw Pixels

```dart
import 'dart:typed_data';
import 'package:xue_hua_navite_rapid_ocr/xue_hua_navite_rapid_ocr.dart';

final ocr = XueHuaNaviteRapidOcr.instance;

Future<void> runOcrPipeline(Uint8List pngOrJpegBytes) async {
  // 1. Initialize once (spawns Native FFI Worker Isolate or Web Worker)
  await ocr.initialize(
    const OcrModelConfig(
      language: OcrLanguage.chineseAndEnglish,
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

  // 2. Run zero-copy recognition with fine-grained DBNet & CTC options
  final OcrResult result = await ocr.recognizeBytes(
    pngOrJpegBytes,
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

  // 3. Access spatially clustered paragraphs, Markdown, or JSON
  print('Total time: ${result.totalTimeMs} ms (${result.blocks.length} blocks)');
  print(result.toMarkdown());
}
```

### Interactive Live Text Overlay (`OcrLiveTextOverlay`)

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
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

- **Web Compilation (`dart:ffi` / `dart:io` Leak)**: Never import `dart:ffi` or `dart:io` in files shared with Web when passing data to `XueHuaNaviteRapidOcr`. Use `recognizeBytes(Uint8List)` or `recognizeFile(blobOrDataUrl)` on Web.
- **EXIF Orientation**: Camera photos on iOS and Android often store a 90°/180°/270° EXIF orientation tag (`1..8`). Both the Native C++ decoder and Web `createImageBitmap(..., { imageOrientation: 'from-image' })` normalize orientation before DBNet inference so returned `cornerPoints` always match the upright displayed image (`result.imageWidth` x `result.imageHeight`).
- **Camera Frame Stride (`recognizeRawPixels`)**: When passing `RGBA8888`, `BGRA8888`, or `NV21` planes from camera streams, always pass `rowStride` (`plane.bytesPerRow`) if rows contain hardware alignment padding bytes.
