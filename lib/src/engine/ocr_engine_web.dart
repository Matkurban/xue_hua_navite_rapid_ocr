import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import '../models/ocr_models.dart';
import '../models/paragraph_clusterer.dart';
import 'ocr_engine_interface.dart';
import 'rapid_ocr_worker_script.dart';

/// Factory exported on Web platforms (`dart.library.js_interop`).
OcrPlatformEngine createPlatformOcrEngine() => OcrEngineWeb();

@JS('Worker')
extension type _JSWorker._(JSObject _) implements JSObject {
  external factory _JSWorker(JSString scriptUrl);
  external void postMessage(JSAny? message, [JSArray<JSObject>? transfer]);
  external void terminate();
  external set onmessage(JSFunction? handler);
  external set onerror(JSFunction? handler);
}

@JS('Blob')
extension type _JSBlob._(JSObject _) implements JSObject {
  external factory _JSBlob(JSArray<JSAny?> blobParts, [JSObject? options]);
}

@JS('URL.createObjectURL')
external JSString _createObjectUrl(_JSBlob blob);

@JS('URL.revokeObjectURL')
external void _revokeObjectUrl(JSString url);

@JS('MessageEvent')
extension type _JSMessageEvent._(JSObject _) implements JSObject {
  external JSAny? get data;
}

/// Web implementation of [OcrPlatformEngine] powered by `dart:js_interop`,
/// `onnxruntime-web` (WebGPU / WASM SIMD), `OffscreenCanvas`, `CacheStorage` / `IndexedDB`,
/// and a dedicated background Web Worker.
///
/// Strictly avoids deprecated `dart:html` and `dart:js`, making it 100% compatible
/// with `flutter build web --wasm`.
class OcrEngineWeb implements OcrPlatformEngine {
  _JSWorker? _worker;
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
    final _JSBlob workerBlob = _JSBlob(
      <JSAny?>[kRapidOcrWebWorkerScript.toJS].toJS,
      blobOptions,
    );
    final JSString blobUrl = _createObjectUrl(workerBlob);
    _workerBlobUrl = blobUrl.toDart;

    final _JSWorker worker = _JSWorker(blobUrl);
    _worker = worker;

    worker.onmessage = ((_JSMessageEvent event) {
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

    if (config.detModelPathOrUrl != null) {
      initPayload['detModelUrl'] = config.detModelPathOrUrl!.toJS;
    }
    if (config.clsModelPathOrUrl != null) {
      initPayload['clsModelUrl'] = config.clsModelPathOrUrl!.toJS;
    }
    if (config.recModelPathOrUrl != null) {
      initPayload['recModelUrl'] = config.recModelPathOrUrl!.toJS;
    }
    if (config.keysPathOrUrl != null) {
      initPayload['keysUrl'] = config.keysPathOrUrl!.toJS;
    }
    if (config.keysUtf8Text != null) {
      initPayload['keysText'] = config.keysUtf8Text!.toJS;
    }

    final List<JSObject> transferList = <JSObject>[];
    if (config.detModelBytes != null) {
      final Uint8List copy = Uint8List.fromList(config.detModelBytes!);
      final JSUint8Array jsArr = copy.toJS;
      initPayload['detModelBytes'] = jsArr;
      transferList.add(jsArr['buffer'] as JSObject);
    }
    if (config.clsModelBytes != null) {
      final Uint8List copy = Uint8List.fromList(config.clsModelBytes!);
      final JSUint8Array jsArr = copy.toJS;
      initPayload['clsModelBytes'] = jsArr;
      transferList.add(jsArr['buffer'] as JSObject);
    }
    if (config.recModelBytes != null) {
      final Uint8List copy = Uint8List.fromList(config.recModelBytes!);
      final JSUint8Array jsArr = copy.toJS;
      initPayload['recModelBytes'] = jsArr;
      transferList.add(jsArr['buffer'] as JSObject);
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

    // Clone into a dedicated Uint8List buffer so its ArrayBuffer can be transferred zero-copy
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
      _revokeObjectUrl(_workerBlobUrl!.toJS);
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
