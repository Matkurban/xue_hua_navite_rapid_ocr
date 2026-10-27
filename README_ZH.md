# xue_hua_navite_rapid_ocr

[English](./README.md) | 简体中文

[![pub package](https://img.shields.io/badge/pub-v1.0.0-blue.svg)](https://github.com/Matkurban/xue_hua_navite_rapid_ocr)
[![Platform](https://img.shields.io/badge/platforms-Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20Web-brightgreen.svg)](https://github.com/Matkurban/xue_hua_navite_rapid_ocr)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

**`xue_hua_navite_rapid_ocr`** 是一款生产环境级别的 **Flutter 六端全平台离线 OCR 插件**（支持 `Android`、`iOS`、`macOS`、`Windows`、`Linux` 与 `Web`），底层基于 **RapidOCR **v3.10.0** (PP-OCRv4 / PP-OCRv5 ONNX 模型流水线)**，全面采用 **`package:material_ui/material_ui.dart`** 构建，内置支持国际化定制与局部精准重绘的实况文本交互组件 **`OcrLiveTextOverlay`**。

- **作者 (Author)**：Matkurban (`3496354336@qq.com`)
- **仓库地址 (Repository)**：[https://github.com/Matkurban/xue_hua_navite_rapid_ocr](https://github.com/Matkurban/xue_hua_navite_rapid_ocr)
- **生态推荐**：Check out `xue_hua_navite_share` — a full-featured 6-platform native share plugin for Flutter!

## 核心特性与架构亮点

1. **严格的编译期平台隔离（Web 端零报错）与模块化分文件设计**：
   - 采用 `ocr_engine_stub.dart` + `if (dart.library.ffi) 'engine/ocr_engine_ffi.dart'` + `if (dart.library.js_interop) 'engine/ocr_engine_web.dart'` 条件编译路由，确保在执行 `flutter build web` 与 `flutter build web --wasm` 时绝不会因为传递引入 `dart:ffi` 或 `dart:io` 而编译崩溃。
   - 所有模型、引擎消息、Web 互操作绑定、绘制器与控制器均按单一职责拆分为独立文件，且统一使用 [`package:material_ui/material_ui.dart`](https://pub.dev/packages/material_ui)（不使用 `package:flutter/material.dart`）。
2. **Native 端 (`Android` / `iOS` / `macOS` / `Windows` / `Linux`)**：
   - 采用 **C++17 (`RapidOcrOnnx`) + `dart:ffi` + 长生命周期 `Worker Isolate`** 零拷贝 (`TransferableTypedData`) 后台推理，彻底解放 UI 主线程。
   - **iOS & macOS** 原生支持 **Swift Package Manager (`Package.swift`)** 与 CocoaPods，共用同一套 C++17 核心代码；**Android / Windows / Linux** 提供标准 `CMakeLists.txt`（已适配 Android 15+ 16KB 页大小对齐）。
   - C++ 层内置 **JPEG EXIF Orientation (`1..8`) 自动解析与像素旋转校正**，并支持 `RGBA8888`、`BGRA8888`、`NV21` 原始像素零拷贝输入。
3. **Web 端 (`Browser WASM SIMD` / `WebGPU`)**：
   - 严格采用现代 **`dart:js_interop` 与 `dart:js_interop_unsafe`** 规范（无任何废弃的 `dart:html` 或 `dart:js` 依赖），全面兼容 **Flutter Web WASM**。
   - 在独立 **Web Worker** 后台线程中结合 `OffscreenCanvas` / `createImageBitmap` 与 `onnxruntime-web` 完成 DBNet 多边形解算与 Vatti Unclip 扩张、AngleNet 方向分类及 CTC 贪婪解码。
   - 内置浏览器 **`CacheStorage`** 模型持久化缓存（`xue_hua_rapid_ocr_onnx_cache_v1`），避免刷新页面时重复下载 `.onnx` 模型。
4. **实况文本交互层 (`OcrLiveTextOverlay`)：零 `setState` 局部重绘 + `OcrLiveTextStrings` 国际化配置**：
   - 内部完全剔除粗粒度 `setState`，通过 `ValueNotifier`、`ValueListenableBuilder` 以及 `CustomPainter(repaint: Listenable.merge(...))` 精确控制刷新粒度：鼠标悬停、拖拽选框、点击选中仅触发 Canvas 画布或顶部浮动工具栏局部更新，底层原图绝不重绘。
   - 提供 **`OcrLiveTextStrings`** 对象统一接收所有 UI 文案（内置英文默认、`OcrLiveTextStrings.zhCN()` 简体中文、`OcrLiveTextStrings.jaJP()` 日文预设，以及自定义格式化回调），无缝对接多语言国际化系统。

## 安装与集成

在项目的 `pubspec.yaml` 中添加依赖（示例项目同时集成了 `xue_hua_file_operations: ^1.5.2` 实现六端选图识别）：

```yaml
dependencies:
  flutter:
    sdk: flutter
  material_ui: ^1.8.0
  xue_hua_file_operations: ^1.5.2
  xue_hua_navite_rapid_ocr: ^1.0.0
```

## 多语言（80+ 语种）集成完整指南 (`OcrLanguage` & `OcrModelConfig`)

> 模型文件名与下载地址对齐 **RapidOCR v3.10.0**（`ModelScope resolve/v3.10.0`，见 `dart run xue_hua_navite_rapid_ocr:fetch_runtime --models` 与 [default_models.yaml](https://github.com/RapidAI/RapidOCR/blob/v3.10.0/python/rapidocr/default_models.yaml)）。桌面 / Android 宿主使用 **ONNX Runtime 1.31.1**（先运行 `dart run xue_hua_navite_rapid_ocr:fetch_runtime --ort`，再运行 `dart run xue_hua_navite_rapid_ocr:fetch_runtime --build-native`）。**iOS** 嵌入目前仍可下载的最新 CocoaPods `pod-archive-onnxruntime-c`——**1.30.0**（`ORT_API_VERSION` 30）；1.31.x 的 iOS 归档尚未发布，因此链接态 iOS 调用 `GetApi(30)`，而仓库内 C 头文件跟随桌面 1.31.1（`ORT_API_VERSION` 31）。Linux 与 Windows 会在 `third_party/onnxruntime/` 中存在对应动态库时一并打包。macOS（arm64）上 Flutter 通过 SwiftPM 构建本插件：`dart run xue_hua_navite_rapid_ocr:fetch_runtime --ort` 会把 dylib 拷进 SPM 的 `Vendor/`，由 `Package.swift` 打进 framework 的 Resources（CocoaPods 的 `Libraries/` 仍兼容旧 pod 安装）。ORT 1.31.x 的 GitHub Release 已不再提供 `osx-x86_64`。macOS 沙盒宿主还需 `com.apple.security.cs.disable-library-validation`（便于 RapidOCR `dlopen` ORT），若应用在运行时通过 HTTPS 下载字典或模型，还需 `com.apple.security.network.client`——example 的 entitlements 均已包含。

`xue_hua_navite_rapid_ocr` 支持通过切换 PP-OCRv4 / PP-OCRv5 的识别模型（`rec.onnx`）与对应字符字典（`keys.txt`）实现 80+ 语言离线识别。

### 1. 多语言枚举与推荐模型对照表

| `OcrLanguage` 枚举值 | 支持语言范围 | 推荐检测模型 (`det.onnx`) | 推荐识别模型 (`rec.onnx`) | 推荐字典文件 (`keys.txt`) |
| :--- | :--- | :--- | :--- | :--- |
| `OcrLanguage.chineseAndEnglish` | 简体中文、繁体中文、英文、数字（默认） | `ch_PP-OCRv4_det_mobile.onnx` | `ch_PP-OCRv4_rec_mobile.onnx` | `ppocr_keys_v1.txt` |
| `OcrLanguage.english` | 纯英文、数字、符号高速识别 | `ch_PP-OCRv4_det_mobile.onnx` | `en_PP-OCRv4_rec_mobile.onnx` | `en_dict.txt` |
| `OcrLanguage.japanese` | 日语（汉字、平假名、片假名）、英文 | `multi_PP-OCRv3_det_mobile.onnx` | `japan_PP-OCRv4_rec_mobile.onnx` | `japan_dict.txt` |
| `OcrLanguage.korean` | 韩语（谚文）、英文 | `multi_PP-OCRv3_det_mobile.onnx` | `korean_PP-OCRv4_rec_mobile.onnx` | `korean_dict.txt` |
| `OcrLanguage.latin` | 法语、德语、西班牙语、意大利语、葡萄牙语等拉丁语系 | `multi_PP-OCRv3_det_mobile.onnx` | `latin_PP-OCRv3_rec_mobile.onnx` | `latin_dict.txt` |
| `OcrLanguage.cyrillic` | 俄语、乌克兰语、白俄罗斯语、保加利亚语等西里尔字母 | `multi_PP-OCRv3_det_mobile.onnx` | `cyrillic_PP-OCRv3_rec_mobile.onnx` | `cyrillic_dict.txt` |
| `OcrLanguage.arabic` | 阿拉伯语、波斯语、维吾尔语、乌尔都语 | `multi_PP-OCRv3_det_mobile.onnx` | `arabic_PP-OCRv4_rec_mobile.onnx` | `arabic_dict.txt` |
| `OcrLanguage.multilingual` | 自定义 80+ 语种模型 | 自定义 `det.onnx` 路径或 URL | 自定义 `rec.onnx` 路径或 URL | 自定义 `keys.txt` 路径或 URL |

### 2. 开发者机器：自动拉取 ONNX Runtime 与 `.onnx` 权重（禁止 `.sh`）

在插件根目录（或依赖本包的应用中）：

```bash
dart run xue_hua_navite_rapid_ocr:fetch_runtime          # ORT + 模型
dart run xue_hua_navite_rapid_ocr:fetch_runtime --ort     # 仅 ONNX Runtime
dart run xue_hua_navite_rapid_ocr:fetch_runtime --models  # 仅 .onnx 权重
```

CocoaPods `prepare_command` 与 Linux/Windows CMake 在检测到 `dart` 时会调用同一工具。大文件仍 gitignore（`third_party/onnxruntime/`、`assets/models/*.onnx`）。

应用 `pubspec.yaml` 只声明 **模型** 资源（字典不再作为插件必选 asset）：

```yaml
flutter:
  assets:
    - assets/models/ch_ppocr_mobile_v2.0_cls_mobile.onnx
    - assets/models/ch_PP-OCRv4_det_mobile.onnx
    - assets/models/ch_PP-OCRv4_rec_mobile.onnx
    - assets/models/multi_PP-OCRv3_det_mobile.onnx
    - assets/models/japan_PP-OCRv4_rec_mobile.onnx
    # …按需声明其他语种 .onnx
```

### 3. 终端应用：让用户选择并下载字典

字符字典由 `OcrDictionaryCatalog` 列出，经 `OcrDictionaryStore` 缓存到应用文档目录，再写入 `OcrModelConfig.keysPathOrUrl` / `keysUtf8Text`：

```dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:xue_hua_navite_rapid_ocr/xue_hua_navite_rapid_ocr.dart';

final docs = await getApplicationDocumentsDirectory();
final store = OcrDictionaryStore(Directory('${docs.path}/ocr_dicts'));

// 可用 OcrDictionaryCatalog.listPacks() 做语言包选择 UI
final config = await store.modelConfigForLanguage(
  OcrLanguage.japanese,
  executionProvider: OcrExecutionProvider.auto,
);
store.close();

await XueHuaNaviteRapidOcr.instance.initialize(config);
```

在 **macOS App Sandbox** 下，出站 HTTPS 需要宿主 entitlements 开启 `com.apple.security.network.client`（缺少时下载 ModelScope 字典会报 `SocketException: Operation not permitted`）。example 已配置；自行集成且运行时下载语言包的应用也需加上该项。

## 结合 `xue_hua_file_operations` 选图识别与 `OcrLiveTextOverlay` 国际化示例

```dart
import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_file_operations/xue_hua_file_operations.dart';
import 'package:xue_hua_navite_rapid_ocr/xue_hua_navite_rapid_ocr.dart';

class OcrScannerDemo extends StatefulWidget {
  const OcrScannerDemo({super.key});

  @override
  State<OcrScannerDemo> createState() => _OcrScannerDemoState();
}

class _OcrScannerDemoState extends State<OcrScannerDemo> {
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

  Future<void> _pickImageAndRecognize() async {
    // 使用 xue_hua_file_operations 跨六端选择图片
    final PlatformFile? file = await _fileOps.pickFile(
      type: FileType.image,
      withData: true,
    );
    if (file == null || file.bytes == null) return;

    final OcrResult result = await _ocr.recognizeBytes(file.bytes!);
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
        title: const Text('选图 OCR 识别'),
        actions: <Widget>[
          FilledButton(
            onPressed: _pickImageAndRecognize,
            child: const Text('选择图片并识别'),
          ),
        ],
      ),
      body: _pickedFile?.bytes != null && _ocrResult != null
          ? OcrLiveTextOverlay(
              image: MemoryImage(_pickedFile!.bytes!),
              ocrResult: _ocrResult!,
              controller: _liveTextController,
              layout: const OcrLiveTextLayout.contain(),
              // 使用 OcrLiveTextStrings.zhCN() 或自定义所有国际化文案
              strings: OcrLiveTextStrings(
                copyButtonLabel: '复制选中',
                selectAllButtonLabel: '全选文字',
                clearSelectionTooltip: '清除选区',
                hideHighlightsTooltip: '隐藏实况文本高亮框',
                showHighlightsTooltip: '显示实况文本高亮框',
                selectedCountBuilder: (int count) => '已选 $count 行',
                copiedSnackBarMessageBuilder: (int count) =>
                    '已成功复制 $count 行文字到剪贴板',
              ),
              onSelectionChanged: (String selectedText, List<OcrTextLine> lines) {
                debugPrint('当前选中文本: $selectedText');
              },
            )
          : const Center(child: Text('请点击右上角选择图片进行 OCR 识别')),
    );
  }
}
```

## AI 编程助手 Skills 支持 (`package:skills`)

本插件遵循 [Dart Package Skills 官方规范](https://dart.dev/tools/pub/package-skills)，在包根目录内置了 [`skills/xue-hua-navite-rapid-ocr/SKILL.md`](./skills/xue-hua-navite-rapid-ocr/SKILL.md)。开发者可在宿主项目中运行以下命令一键安装 AI 辅助编程规范：

```bash
dart run skills@ get
```

## 注意事项与最佳实践

1. **统一使用 `package:material_ui/material_ui.dart`**：本插件与示例项目全面迁移至 Flutter 官方解耦的 `material_ui` 包，严禁混用旧版 `package:flutter/material.dart`。
2. **局部精准刷新（零 `setState`）**：`OcrLiveTextOverlay` 内部通过 `ValueNotifier` 与 `CustomPainter(repaint: ...)` 局部刷新画布与工具栏，不会重绘底层图片。
3. **EXIF 方向自动修正**：手机拍摄的照片常带有 EXIF 旋转标记（`1..8`）。C++ 层与 Web Worker 层均会自动修正方向，返回的 `cornerPoints` 顶点坐标与修正后的 `result.imageWidth`、`result.imageHeight` 完全对齐。

## 开源协议 (License)

MIT License © 2026 Matkurban (`3496354336@qq.com`)
