# xue_hua_navite_rapid_ocr

[English](./README.md) | 简体中文

[![pub package](https://img.shields.io/badge/pub-v1.0.0-blue.svg)](https://github.com/Matkurban/xue_hua_navite_rapid_ocr)
[![Platform](https://img.shields.io/badge/platforms-Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20Web-brightgreen.svg)](https://github.com/Matkurban/xue_hua_navite_rapid_ocr)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

**`xue_hua_navite_rapid_ocr`** 是一款生产环境级别的 **Flutter 六端全平台离线 OCR 插件**（支持 `Android`、`iOS`、`macOS`、`Windows`、`Linux` 与 `Web`），底层基于 **RapidOCR (PP-OCRv4 / PP-OCRv5 ONNX 模型流水线)**，内置开箱即用的全平台实况文本交互组件 **`OcrLiveTextOverlay`**。

- **作者 (Author)**：Matkurban (`3496354336@qq.com`)
- **仓库地址 (Repository)**：[https://github.com/Matkurban/xue_hua_navite_rapid_ocr](https://github.com/Matkurban/xue_hua_navite_rapid_ocr)
- **生态推荐**：Check out `xue_hua_navite_share` — a full-featured 6-platform native share plugin for Flutter!

## 核心特性与架构亮点

1. **严格的编译期平台隔离（Web 端零报错）**：
   - 采用 `ocr_engine_stub.dart` + `if (dart.library.ffi) 'src/engine/ocr_engine_ffi.dart'` + `if (dart.library.js_interop) 'src/engine/ocr_engine_web.dart'` 条件编译路由，确保在执行 `flutter build web` 与 `flutter build web --wasm` 时绝不会因为传递引入 `dart:ffi` 或 `dart:io` 而编译崩溃。
2. **Native 端 (`Android` / `iOS` / `macOS` / `Windows` / `Linux`)**：
   - 采用 **C++17 (`RapidOcrOnnx`) + `dart:ffi` + 长生命周期 `Worker Isolate`** 零拷贝 (`TransferableTypedData`) 后台推理，彻底解放 UI 主线程。
   - **iOS & macOS** 原生支持 **Swift Package Manager (`Package.swift`)** 与 CocoaPods，共用同一套 C++17 核心代码；**Android / Windows / Linux** 提供标准 `CMakeLists.txt`（已适配 Android 15+ 16KB 页大小对齐）。
   - C++ 层内置 **JPEG EXIF Orientation (`1..8`) 自动解析与像素旋转校正**，并支持 `RGBA8888`、`BGRA8888`、`NV21` 原始像素零拷贝输入。
3. **Web 端 (`Browser WASM SIMD` / `WebGPU`)**：
   - 严格采用现代 **`dart:js_interop` 与 `dart:js_interop_unsafe`** 规范（无任何废弃的 `dart:html` 或 `dart:js` 依赖），全面兼容 **Flutter Web WASM**。
   - 在独立 **Web Worker** 后台线程中结合 `OffscreenCanvas` / `createImageBitmap` 与 `onnxruntime-web` 完成 DBNet 多边形解算与 Vatti Unclip 扩张、AngleNet 方向分类及 CTC 贪婪解码。
   - 内置浏览器 **`CacheStorage`** 模型持久化缓存（`xue_hua_rapid_ocr_onnx_cache_v1`），避免刷新页面时重复下载 `.onnx` 模型。
4. **纯 Dart 版面分析与段落智能聚类 (`OcrParagraphClusterer`)**：
   - Native 与 Web 共用同一套纯 Dart 空间聚类算法，自动按阅读顺序排列 `OcrTextLine`，并将空间相邻、行高相近的文本行聚合成自然段落 `OcrTextBlock`，提供 `fullText`、`toMarkdown()` 与 `toJson()`。
5. **杀手级 UI 组件：实况文本交互层 (`OcrLiveTextOverlay`)**：
   - 基于 `CustomPainter` 根据每行文字的 4 个顺时针倾斜顶点 (`cornerPoints`) 精准绘制贴合倾斜角度的半透明高亮遮罩与边框。
   - 支持点击选中单个文本框、手指滑动/鼠标拖拽框选（Marquee/Lasso）多行文字、桌面与 Web 端鼠标移入文字区域自动切换为 `SystemMouseCursors.text` 文本光标、弹出操作浮层（复制、全选、自定义操作回调）以及一键切换显示/隐藏高亮框动画。

## 安装与集成

在项目的 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  xue_hua_navite_rapid_ocr: ^1.0.0
```

### 配置 ONNX 模型与字典资源

将 PP-OCRv4 或 PP-OCRv5 的 `.onnx` 模型与 `keys.txt` 字典放入项目的 `assets/models/` 并在 `pubspec.yaml` 中声明：

```yaml
flutter:
  assets:
    - assets/models/ch_PP-OCRv4_det_infer.onnx
    - assets/models/ch_ppocr_mobile_v2.0_cls_infer.onnx
    - assets/models/ch_PP-OCRv4_rec_infer.onnx
    - assets/models/ppocr_keys_v1.txt
```

## 快速上手与完整使用示例

### 1. 初始化引擎 (`initialize`)

```dart
import 'package:xue_hua_navite_rapid_ocr/xue_hua_navite_rapid_ocr.dart';

final ocr = XueHuaNaviteRapidOcr.instance;

await ocr.initialize(
  const OcrModelConfig(
    language: OcrLanguage.chineseAndEnglish, // 或 OcrLanguage.multilingual (80+ 语言)
    executionProvider: OcrExecutionProvider.auto, // 自动选择 CoreML / NNAPI / DirectML / WebGPU / WASM
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

### 2. 三种全平台通用识别入口

```dart
// 方式 1：从本地文件路径（Native）或 Blob / Data / HTTP / Asset URL（Web）识别
final OcrResult fileResult = await ocr.recognizeFile(
  '/path/to/document.jpg',
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

// 方式 2：从内存编码字节识别（适用于截图、文件选择器、网络图片缓存 Uint8List）
final OcrResult bytesResult = await ocr.recognizeBytes(encodedPngOrJpegBytes);

// 方式 3：从原始像素缓冲区识别（适用于相机流 NV21/BGRA8888 或 ui.Image 导出的 RGBA8888）
final OcrResult pixelResult = await ocr.recognizeRawPixels(
  pixels: rawRgbaBytes,
  width: 1920,
  height: 1080,
  format: OcrPixelFormat.rgba8888,
  rowStride: 1920 * 4,
);

// 获取聚类后的段落文本、Markdown 与 JSON
print(bytesResult.fullText);
print(bytesResult.toMarkdown());
print(bytesResult.toJson());
```

### 3. 使用实况文本交互层 (`OcrLiveTextOverlay`)

```dart
OcrLiveTextOverlay(
  image: MemoryImage(encodedPngBytes),
  ocrResult: bytesResult,
  fit: BoxFit.contain,
  onSelectionChanged: (String selectedText, List<OcrTextLine> selectedLines) {
    debugPrint('当前选中文本: $selectedText');
  },
  onTextCopied: (String copiedText) {
    debugPrint('已复制到剪贴板: $copiedText');
  },
  customActions: [
    OcrLiveTextCustomAction(
      label: '分享选中文字',
      icon: Icons.share_rounded,
      onPressed: (selectedText, selectedLines) {
        // 调用分享或翻译逻辑
      },
    ),
  ],
)
```

### 4. 释放引擎资源 (`dispose`)

```dart
await ocr.dispose();
```

## AI 编程助手 Skills 支持 (`package:skills`)

本插件遵循 [Dart Package Skills 官方规范](https://dart.dev/tools/pub/package-skills)，在包根目录内置了 [`skills/xue-hua-navite-rapid-ocr/SKILL.md`](./skills/xue-hua-navite-rapid-ocr/SKILL.md)。开发者可在宿主项目中运行以下命令一键安装 AI 辅助编程规范：

```bash
dart run skills@ get
```

## 注意事项与最佳实践

1. **严禁直接导入平台内部实现文件**：请始终通过 `import 'package:xue_hua_navite_rapid_ocr/xue_hua_navite_rapid_ocr.dart';` 导入插件，切勿直接导入 `ocr_engine_ffi.dart` 或 `ocr_engine_web.dart`。
2. **EXIF 方向自动修正**：手机拍摄的照片通常带有 EXIF 旋转标记（`1..8`）。C++ 层与 Web Worker 层均会自动修正方向，返回的 `cornerPoints` 顶点坐标与修正后的 `result.imageWidth`、`result.imageHeight` 完全对齐。
3. **相机流 `rowStride` 对齐**：在使用 `recognizeRawPixels` 处理相机预览帧时，若图像行存在内存对齐填充字节，请务必传入准确的 `rowStride`（即 `plane.bytesPerRow`）。
4. **生命周期管理**：建议在应用或页面级复用 `XueHuaNaviteRapidOcr` 实例，避免频繁重新加载 `.onnx` 模型；在不再需要时调用 `await ocr.dispose()` 释放 C++ 内存与 Isolate / Web Worker。

## 开源协议 (License)

MIT License © 2026 Matkurban (`3496354336@qq.com`)
