import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../models/ocr_models.dart';
import '../models/paragraph_clusterer.dart';
import 'ocr_engine_interface.dart';
import 'ocr_web_interop_bindings.dart';
import 'rapid_ocr_worker_script.dart';

/// Factory exported on Web platforms (`dart.library.js_interop`).
OcrPlatformEngine createPlatformOcrEngine() => OcrEngineWeb();

/// Web implementation of [OcrPlatformEngine] powered by `dart:js_interop`,
/// `onnxruntime-web` (WebGPU / WASM SIMD), `OffscreenCanvas`, `CacheStorage` / `IndexedDB`,
/// and a dedicated background Web Worker.
///
/// Strictly avoids deprecated `dart:html` and `dart:js`, making it 100% compatible
/// with `flutter build web --wasm`.
class OcrEngineWeb implements OcrPlatformEngine {
  OcrJSWorker? _worker;
  String? _workerBlobUrl;
  bool _initialized = false;
  int _nextRequestId = 1;
  final Map<int, Completer<Map<String, dynamic>>> _pendingRequests =
      <int, Completer<Map<String, dynamic>>>{};

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize(OcrModelConfig config) async {
    if (_initialized) {
      await dispose();
    }

    // Create a self-contained Web Worker from our bundled RapidOCR ONNX Runtime Web script
    final JSObject blobOptions = JSObject()
      ..['type'] = 'application/javascript'.toJS;
    final OcrJSBlob workerBlob = OcrJSBlob(
      <JSAny?>[kRapidOcrWebWorkerScript.toJS].toJS,
      blobOptions,
    );
    final JSString blobUrl = createOcrObjectUrl(workerBlob);
    _workerBlobUrl = blobUrl.toDart;

    final OcrJSWorker worker = OcrJSWorker(blobUrl);
    _worker = worker;

    worker.onmessage = ((OcrJSMessageEvent event) {
      final JSAny? rawData = event.data;
      if (rawData == null || !rawData.isA<JSObject>()) return;
      final JSObject obj = rawData as JSObject;
      final JSAny? idVal = obj['requestId'];
      if (idVal == null || !idVal.isA<JSNumber>()) return;
      final int requestId = (idVal as JSNumber).toDartInt;

      final Completer<Map<String, dynamic>>? completer = _pendingRequests
          .remove(requestId);
      if (completer == null || completer.isCompleted) return;

      final JSAny? errVal = obj['error'];
      if (errVal != null && errVal.isA<JSString>()) {
        completer.completeError(
          XueHuaOcrException((errVal as JSString).toDart),
        );
        return;
      }

      final JSAny? payloadJsonVal = obj['payloadJson'];
      if (payloadJsonVal != null && payloadJsonVal.isA<JSString>()) {
        final String jsonStr = (payloadJsonVal as JSString).toDart;
        final Map<String, dynamic> decoded =
            jsonDecode(jsonStr) as Map<String, dynamic>;
        completer.complete(decoded);
      } else {
        completer.complete(<String, dynamic>{});
      }
    }).toJS;

    worker.onerror = ((JSObject errorEvent) {
      final JSAny? msg = errorEvent['message'];
      final String errStr = msg != null && msg.isA<JSString>()
          ? (msg as JSString).toDart
          : 'Unknown Web Worker runtime error';
      for (final Completer<Map<String, dynamic>> c in _pendingRequests.values) {
        if (!c.isCompleted) {
          c.completeError(XueHuaOcrException(errStr));
        }
      }
      _pendingRequests.clear();
    }).toJS;

    final JSObject initPayload = JSObject()
      ..['language'] = config.language.name.toJS
      ..['executionProvider'] = config.executionProvider.wireName.toJS
      ..['numThreads'] = config.numThreads.toJS
      ..['enableHardwareAcceleration'] = config.enableHardwareAcceleration.toJS
      ..['enableWebModelCache'] = config.enableWebModelCache.toJS
      ..['webCacheName'] = config.webCacheName.toJS
      ..['webOrtScriptUrl'] = config.webOrtScriptUrl.toJS;

    final Uint8List? detBytes =
        config.detModelBytes ?? await _loadAssetBytes(config.detModelPathOrUrl);
    final Uint8List? clsBytes =
        config.clsModelBytes ?? await _loadAssetBytes(config.clsModelPathOrUrl);
    final Uint8List? recBytes =
        config.recModelBytes ?? await _loadAssetBytes(config.recModelPathOrUrl);
    final String? keysText =
        config.keysUtf8Text ?? await _loadAssetString(config.keysPathOrUrl);

    final List<JSObject> transferList = <JSObject>[];
    _putModel(
      initPayload,
      transferList,
      urlKey: 'detModelUrl',
      bytesKey: 'detModelBytes',
      path: config.detModelPathOrUrl,
      bytes: detBytes,
    );
    _putModel(
      initPayload,
      transferList,
      urlKey: 'clsModelUrl',
      bytesKey: 'clsModelBytes',
      path: config.clsModelPathOrUrl,
      bytes: clsBytes,
    );
    _putModel(
      initPayload,
      transferList,
      urlKey: 'recModelUrl',
      bytesKey: 'recModelBytes',
      path: config.recModelPathOrUrl,
      bytes: recBytes,
    );
    if (config.keysPathOrUrl != null &&
        (keysText == null || _isRemoteUrl(config.keysPathOrUrl!))) {
      initPayload['keysUrl'] = config.keysPathOrUrl!.toJS;
    }
    if (keysText != null) {
      initPayload['keysText'] = keysText.toJS;
    }

    await _postWorkerCommand(
      type: 'init',
      payload: initPayload,
      transfer: transferList,
    );
    _initialized = true;
  }

  @override
  Future<OcrResult> recognizeFile(
    String filePathOrUrl, {
    OcrRecognizeOptions? options,
  }) async {
    _ensureInitialized();
    if (filePathOrUrl.trim().isEmpty) {
      throw const XueHuaOcrException('filePathOrUrl cannot be empty.');
    }
    final OcrRecognizeOptions effectiveOptions =
        options ?? const OcrRecognizeOptions();

    final JSObject payload = JSObject()
      ..['url'] = filePathOrUrl.toJS
      ..['options'] = _optionsToJsObject(effectiveOptions);

    final Map<String, dynamic> rawMap = await _postWorkerCommand(
      type: 'recognizeUrl',
      payload: payload,
    );
    return _parseWorkerResult(rawMap);
  }

  @override
  Future<OcrResult> recognizeBytes(
    Uint8List encodedBytes, {
    OcrRecognizeOptions? options,
  }) async {
    _ensureInitialized();
    if (encodedBytes.isEmpty) {
      throw const XueHuaOcrException('encodedBytes cannot be empty.');
    }
    final OcrRecognizeOptions effectiveOptions =
        options ?? const OcrRecognizeOptions();

    final Uint8List transferableCopy = Uint8List.fromList(encodedBytes);
    final JSUint8Array jsBytes = transferableCopy.toJS;
    final JSObject arrayBuffer = jsBytes['buffer'] as JSObject;

    final JSObject payload = JSObject()
      ..['encodedBytes'] = jsBytes
      ..['options'] = _optionsToJsObject(effectiveOptions);

    final Map<String, dynamic> rawMap = await _postWorkerCommand(
      type: 'recognizeBytes',
      payload: payload,
      transfer: <JSObject>[arrayBuffer],
    );
    return _parseWorkerResult(rawMap);
  }

  @override
  Future<OcrResult> recognizeRawPixels({
    required Uint8List pixels,
    required int width,
    required int height,
    required OcrPixelFormat format,
    int? rowStride,
    OcrRecognizeOptions? options,
  }) async {
    _ensureInitialized();
    if (pixels.isEmpty || width <= 0 || height <= 0) {
      throw const XueHuaOcrException(
        'Invalid raw pixel buffer or non-positive width/height.',
      );
    }
    final OcrRecognizeOptions effectiveOptions =
        options ?? const OcrRecognizeOptions();

    final Uint8List transferableCopy = Uint8List.fromList(pixels);
    final JSUint8Array jsPixels = transferableCopy.toJS;
    final JSObject arrayBuffer = jsPixels['buffer'] as JSObject;

    final JSObject payload = JSObject()
      ..['pixels'] = jsPixels
      ..['width'] = width.toJS
      ..['height'] = height.toJS
      ..['rowStride'] = (rowStride ?? 0).toJS
      ..['pixelFormat'] = format.nativeValue.toJS
      ..['options'] = _optionsToJsObject(effectiveOptions);

    final Map<String, dynamic> rawMap = await _postWorkerCommand(
      type: 'recognizeRawPixels',
      payload: payload,
      transfer: <JSObject>[arrayBuffer],
    );
    return _parseWorkerResult(rawMap);
  }

  @override
  Future<void> dispose() async {
    if (_worker != null) {
      try {
        await _postWorkerCommand(type: 'dispose', payload: JSObject());
      } catch (_) {}
      _worker!.terminate();
      _worker = null;
    }
    if (_workerBlobUrl != null) {
      revokeOcrObjectUrl(_workerBlobUrl!.toJS);
      _workerBlobUrl = null;
    }
    _initialized = false;
    for (final Completer<Map<String, dynamic>> c in _pendingRequests.values) {
      if (!c.isCompleted) {
        c.completeError(
          const XueHuaOcrException(
            'OcrEngineWeb was disposed before completion.',
          ),
        );
      }
    }
    _pendingRequests.clear();
  }

  static const String _packageAssetPrefix =
      'packages/xue_hua_navite_rapid_ocr/';

  static bool _isRemoteUrl(String value) {
    final String lower = value.toLowerCase();
    return lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('blob:') ||
        lower.startsWith('data:');
  }

  static Iterable<String> _assetKeyCandidates(String pathOrAsset) sync* {
    yield pathOrAsset;
    if (pathOrAsset.startsWith('assets/') &&
        !pathOrAsset.startsWith(_packageAssetPrefix)) {
      yield '$_packageAssetPrefix$pathOrAsset';
    }
  }

  static Future<Uint8List?> _loadAssetBytes(String? pathOrAsset) async {
    if (pathOrAsset == null ||
        pathOrAsset.isEmpty ||
        _isRemoteUrl(pathOrAsset)) {
      return null;
    }
    for (final String key in _assetKeyCandidates(pathOrAsset)) {
      try {
        final ByteData data = await rootBundle.load(key);
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } catch (_) {
        // Try the package-prefixed asset key next.
      }
    }
    return null;
  }

  static Future<String?> _loadAssetString(String? pathOrAsset) async {
    if (pathOrAsset == null ||
        pathOrAsset.isEmpty ||
        _isRemoteUrl(pathOrAsset)) {
      return null;
    }
    for (final String key in _assetKeyCandidates(pathOrAsset)) {
      try {
        return await rootBundle.loadString(key);
      } catch (_) {
        // Try the package-prefixed asset key next.
      }
    }
    return null;
  }

  static void _putModel(
    JSObject payload,
    List<JSObject> transfer, {
    required String urlKey,
    required String bytesKey,
    required String? path,
    required Uint8List? bytes,
  }) {
    if (bytes != null && bytes.isNotEmpty) {
      final Uint8List copy = Uint8List.fromList(bytes);
      final JSUint8Array jsArr = copy.toJS;
      payload[bytesKey] = jsArr;
      transfer.add(jsArr['buffer'] as JSObject);
    }
    if (path != null &&
        path.isNotEmpty &&
        (bytes == null || bytes.isEmpty || _isRemoteUrl(path))) {
      payload[urlKey] = path.toJS;
    }
  }

  void _ensureInitialized() {
    if (!_initialized || _worker == null) {
      throw const XueHuaOcrException(
        'XueHuaNaviteRapidOcr is not initialized on Web. Call initialize(OcrModelConfig) first.',
      );
    }
  }

  JSObject _optionsToJsObject(OcrRecognizeOptions options) {
    return JSObject()
      ..['maxSideLen'] = options.maxSideLen.toJS
      ..['boxThresh'] = options.boxThresh.toJS
      ..['boxScoreThresh'] = options.boxScoreThresh.toJS
      ..['unclipRatio'] = options.unclipRatio.toJS
      ..['doAngle'] = options.doAngle.toJS
      ..['mostAngle'] = options.mostAngle.toJS
      ..['minConfidence'] = options.minConfidence.toJS;
  }

  Future<Map<String, dynamic>> _postWorkerCommand({
    required String type,
    required JSObject payload,
    List<JSObject>? transfer,
  }) {
    final int requestId = _nextRequestId++;
    final Completer<Map<String, dynamic>> completer =
        Completer<Map<String, dynamic>>();
    _pendingRequests[requestId] = completer;

    final JSObject envelope = JSObject()
      ..['requestId'] = requestId.toJS
      ..['type'] = type.toJS
      ..['payload'] = payload;

    if (transfer != null && transfer.isNotEmpty) {
      _worker!.postMessage(envelope, transfer.toJS);
    } else {
      _worker!.postMessage(envelope);
    }
    return completer.future;
  }

  OcrResult _parseWorkerResult(Map<String, dynamic> map) {
    final int imageWidth = (map['imageWidth'] as num?)?.toInt() ?? 960;
    final int imageHeight = (map['imageHeight'] as num?)?.toInt() ?? 640;
    final int exifOrientation = (map['exifOrientation'] as num?)?.toInt() ?? 1;
    final String epUsed = map['executionProviderUsed'] as String? ?? 'wasm';
    final double totalTimeMs = (map['totalTimeMs'] as num?)?.toDouble() ?? 0.0;
    final double preprocessTimeMs =
        (map['preprocessTimeMs'] as num?)?.toDouble() ?? 0.0;
    final double detTimeMs = (map['detTimeMs'] as num?)?.toDouble() ?? 0.0;
    final double clsTimeMs = (map['clsTimeMs'] as num?)?.toDouble() ?? 0.0;
    final double recTimeMs = (map['recTimeMs'] as num?)?.toDouble() ?? 0.0;

    final List<dynamic> rawLineMaps =
        map['lines'] as List<dynamic>? ?? <dynamic>[];
    final List<OcrTextLine> rawLines = rawLineMaps
        .map((dynamic item) {
          return OcrTextLine.fromJson(Map<String, dynamic>.from(item as Map));
        })
        .toList(growable: false);

    // Run identical pure Dart spatial layout & paragraph clustering algorithm
    final ({List<OcrTextLine> sortedLines, List<OcrTextBlock> blocks})
    clustered = OcrParagraphClusterer.clusterLines(rawLines);

    return OcrResult(
      lines: clustered.sortedLines,
      blocks: clustered.blocks,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      totalTimeMs: totalTimeMs,
      preprocessTimeMs: preprocessTimeMs,
      detTimeMs: detTimeMs,
      clsTimeMs: clsTimeMs,
      recTimeMs: recTimeMs,
      exifOrientation: exifOrientation,
      executionProviderUsed: epUsed,
    );
  }
}
