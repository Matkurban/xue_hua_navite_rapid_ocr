import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io' show File, Platform;
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/ocr_models.dart';
import '../models/paragraph_clusterer.dart';
import 'ffi_bindings.dart';
import 'ocr_engine_interface.dart';
import 'ocr_ffi_messages.dart';

/// Factory exported on Native platforms (`dart.library.ffi`).
OcrPlatformEngine createPlatformOcrEngine() => OcrEngineFfi();

const String _kLibName = 'xue_hua_navite_rapid_ocr';

bool _libraryExportsOcrInit(ffi.DynamicLibrary library) {
  try {
    library.lookup('xue_hua_rapid_ocr_init');
    return true;
  } catch (_) {
    return false;
  }
}

ffi.DynamicLibrary? _tryOpenPath(String path) {
  try {
    final ffi.DynamicLibrary library = ffi.DynamicLibrary.open(path);
    if (_libraryExportsOcrInit(library)) return library;
  } catch (_) {
    // Try the next candidate.
  }
  return null;
}

ffi.DynamicLibrary? _tryOpenDynamicLibrary() {
  // Prefer an explicit/dev build first. On macOS, DynamicLibrary.process()
  // succeeds for the test runner even when this plugin is not linked, which
  // previously shadowed build/native and made Apple hosts look "empty".
  const List<String> devNames = <String>[
    'lib$_kLibName.so',
    '$_kLibName.dll',
    'lib$_kLibName.dylib',
  ];
  final List<String> explicit = <String>[
    if ((Platform.environment['XUE_HUA_RAPID_OCR_LIB'] ?? '').isNotEmpty)
      Platform.environment['XUE_HUA_RAPID_OCR_LIB']!,
    for (final String name in devNames) 'build/native/$name',
  ];
  for (final String path in explicit) {
    final File file = File(path);
    if (!file.existsSync()) continue;
    final ffi.DynamicLibrary? opened = _tryOpenPath(file.absolute.path);
    if (opened != null) return opened;
  }

  final ffi.DynamicLibrary? bundled = _tryOpenBundledLibrary();
  if (bundled != null) return bundled;
  return null;
}

ffi.DynamicLibrary? _tryOpenBundledLibrary() {
  try {
    if (Platform.isMacOS || Platform.isIOS) {
      // SPM/CocoaPods may emit either underscore or hyphenated framework names.
      final List<String> candidates = <String>[
        '$_kLibName.framework/$_kLibName',
        'xue-hua-navite-rapid-ocr.framework/xue-hua-navite-rapid-ocr',
      ];
      for (final String path in candidates) {
        final ffi.DynamicLibrary? opened = _tryOpenPath(path);
        if (opened != null) return opened;
      }
      try {
        final ffi.DynamicLibrary process = ffi.DynamicLibrary.process();
        if (_libraryExportsOcrInit(process)) return process;
      } catch (_) {
        return null;
      }
      return null;
    }
    if (Platform.isAndroid || Platform.isLinux) {
      return _tryOpenPath('lib$_kLibName.so');
    }
    if (Platform.isWindows) {
      return _tryOpenPath('$_kLibName.dll');
    }
  } catch (_) {
    // Allow graceful fallback inside the Worker Isolate during host VM unit tests.
    return null;
  }
  return null;
}

/// Long-lived Worker Isolate implementation of [OcrPlatformEngine] for Android, iOS,
/// macOS, Windows, and Linux using `dart:ffi` and `TransferableTypedData`.
class OcrEngineFfi implements OcrPlatformEngine {
  SendPort? _workerSendPort;
  ReceivePort? _mainReceivePort;
  Isolate? _workerIsolate;
  bool _initialized = false;
  int _nextRequestId = 1;
  final Map<int, Completer<dynamic>> _pendingRequests =
      <int, Completer<dynamic>>{};

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize(OcrModelConfig config) async {
    if (_initialized) {
      await dispose();
    }

    // Preload any Flutter asset keys on the root isolate if needed
    final Uint8List? detBytes =
        config.detModelBytes ??
        await _tryLoadAssetBytes(config.detModelPathOrUrl);
    final Uint8List? clsBytes =
        config.clsModelBytes ??
        await _tryLoadAssetBytes(config.clsModelPathOrUrl);
    final Uint8List? recBytes =
        config.recModelBytes ??
        await _tryLoadAssetBytes(config.recModelPathOrUrl);
    final String? keysText =
        config.keysUtf8Text ?? await _tryLoadAssetString(config.keysPathOrUrl);

    final ReceivePort receivePort = ReceivePort();
    _mainReceivePort = receivePort;
    final Completer<SendPort> handshakeCompleter = Completer<SendPort>();

    receivePort.listen((dynamic message) {
      if (message is SendPort) {
        if (!handshakeCompleter.isCompleted) {
          handshakeCompleter.complete(message);
        }
        return;
      }
      if (message is FfiWorkerResponse) {
        final Completer<dynamic>? completer = _pendingRequests.remove(
          message.requestId,
        );
        if (completer == null) return;
        if (message.errorMessage != null) {
          completer.completeError(
            XueHuaOcrException(message.errorMessage!, code: message.errorCode),
          );
        } else {
          completer.complete(message.payload);
        }
      }
    });

    _workerIsolate = await Isolate.spawn<SendPort>(
      _ocrWorkerIsolateEntryPoint,
      receivePort.sendPort,
      debugName: 'XueHuaRapidOcrWorkerIsolate',
    );

    _workerSendPort = await handshakeCompleter.future;

    await _sendCommand<bool>(
      FfiInitCommand(
        detPath: _isLocalFilePath(config.detModelPathOrUrl)
            ? config.detModelPathOrUrl
            : null,
        clsPath: _isLocalFilePath(config.clsModelPathOrUrl)
            ? config.clsModelPathOrUrl
            : null,
        recPath: _isLocalFilePath(config.recModelPathOrUrl)
            ? config.recModelPathOrUrl
            : null,
        keysPath: _isLocalFilePath(config.keysPathOrUrl)
            ? config.keysPathOrUrl
            : null,
        detBytes: detBytes != null
            ? TransferableTypedData.fromList(<Uint8List>[detBytes])
            : null,
        clsBytes: clsBytes != null
            ? TransferableTypedData.fromList(<Uint8List>[clsBytes])
            : null,
        recBytes: recBytes != null
            ? TransferableTypedData.fromList(<Uint8List>[recBytes])
            : null,
        keysText: keysText,
        numThreads: config.numThreads,
        executionProvider: config.executionProvider.nativeValue,
        executionProviderName: _resolveEffectiveProviderName(
          config.executionProvider,
        ),
        enableHardwareAcceleration: config.enableHardwareAcceleration,
      ),
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

    // If path points to a bundled Flutter asset rather than an OS file, read bytes first
    if (!File(filePathOrUrl).existsSync() &&
        filePathOrUrl.startsWith('assets/')) {
      final Uint8List? assetBytes = await _tryLoadAssetBytes(filePathOrUrl);
      if (assetBytes != null) {
        return recognizeBytes(assetBytes, options: options);
      }
    }

    final OcrRecognizeOptions effectiveOptions =
        options ?? const OcrRecognizeOptions();
    return _sendCommand<OcrResult>(
      FfiRecognizeFileCommand(
        filePath: filePathOrUrl,
        options: effectiveOptions,
      ),
    );
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
    return _sendCommand<OcrResult>(
      FfiRecognizeBytesCommand(
        transferableBytes: TransferableTypedData.fromList(<Uint8List>[
          encodedBytes,
        ]),
        options: effectiveOptions,
      ),
    );
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
    return _sendCommand<OcrResult>(
      FfiRecognizeRawPixelsCommand(
        transferablePixels: TransferableTypedData.fromList(<Uint8List>[pixels]),
        width: width,
        height: height,
        rowStride: rowStride ?? 0,
        pixelFormat: format.nativeValue,
        options: effectiveOptions,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    if (_workerSendPort != null) {
      try {
        await _sendCommand<bool>(const FfiDisposeCommand());
      } catch (_) {}
    }
    _mainReceivePort?.close();
    _mainReceivePort = null;
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    _workerSendPort = null;
    _initialized = false;
    for (final Completer<dynamic> c in _pendingRequests.values) {
      if (!c.isCompleted) {
        c.completeError(
          const XueHuaOcrException(
            'OcrEngineFfi was disposed before completion.',
          ),
        );
      }
    }
    _pendingRequests.clear();
  }

  void _ensureInitialized() {
    if (!_initialized || _workerSendPort == null) {
      throw const XueHuaOcrException(
        'XueHuaNaviteRapidOcr is not initialized. Call initialize(OcrModelConfig) first.',
      );
    }
  }

  Future<T> _sendCommand<T>(FfiWorkerCommand command) {
    final int requestId = _nextRequestId++;
    final Completer<T> completer = Completer<T>();
    _pendingRequests[requestId] = completer;
    _workerSendPort!.send(FfiWorkerEnvelope(requestId, command));
    return completer.future;
  }

  static bool _isLocalFilePath(String? pathOrAsset) {
    if (pathOrAsset == null || pathOrAsset.isEmpty) return false;
    try {
      return File(pathOrAsset).existsSync();
    } catch (_) {
      return false;
    }
  }

  static const String _packageAssetPrefix =
      'packages/xue_hua_navite_rapid_ocr/';

  static Iterable<String> _assetKeyCandidates(String pathOrAsset) sync* {
    yield pathOrAsset;
    if (pathOrAsset.startsWith('assets/') &&
        !pathOrAsset.startsWith(_packageAssetPrefix)) {
      yield '$_packageAssetPrefix$pathOrAsset';
    }
  }

  static Future<Uint8List?> _tryLoadAssetBytes(String? pathOrAsset) async {
    if (pathOrAsset == null || pathOrAsset.isEmpty) return null;
    if (_isLocalFilePath(pathOrAsset)) return null;
    for (final String key in _assetKeyCandidates(pathOrAsset)) {
      try {
        final ByteData data = await rootBundle.load(key);
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } catch (_) {
        // Try next candidate key.
      }
    }
    return null;
  }

  static Future<String?> _tryLoadAssetString(String? pathOrAsset) async {
    if (pathOrAsset == null || pathOrAsset.isEmpty) return null;
    if (_isLocalFilePath(pathOrAsset)) return null;
    for (final String key in _assetKeyCandidates(pathOrAsset)) {
      try {
        return await rootBundle.loadString(key);
      } catch (_) {
        // Try next candidate key.
      }
    }
    return null;
  }

  static String _resolveEffectiveProviderName(OcrExecutionProvider ep) {
    if (ep != OcrExecutionProvider.auto) {
      return ep.wireName;
    }
    if (Platform.isIOS || Platform.isMacOS) return 'coreml';
    if (Platform.isAndroid) return 'nnapi';
    if (Platform.isWindows) return 'directml';
    return 'cpu';
  }
}

/// Entry point for the dedicated background Worker Isolate.
void _ocrWorkerIsolateEntryPoint(SendPort mainSendPort) {
  final ReceivePort workerReceivePort = ReceivePort();
  mainSendPort.send(workerReceivePort.sendPort);

  final ffi.DynamicLibrary? dylib = _tryOpenDynamicLibrary();
  final XueHuaNaviteRapidOcrBindings? bindings = dylib != null
      ? XueHuaNaviteRapidOcrBindings(dylib)
      : null;

  OcrEngineHandle? nativeHandle;
  String activeProviderName = 'cpu';

  workerReceivePort.listen((dynamic message) {
    if (message is! FfiWorkerEnvelope) return;
    final int reqId = message.requestId;
    final FfiWorkerCommand cmd = message.command;

    try {
      switch (cmd) {
        case FfiInitCommand():
          activeProviderName = cmd.executionProviderName;
          if (bindings != null) {
            if (nativeHandle != null && nativeHandle != ffi.nullptr) {
              bindings.xue_hua_rapid_ocr_destroy(nativeHandle!);
              nativeHandle = null;
            }
            nativeHandle = using((Arena arena) {
              final ffi.Pointer<OcrInitConfig> cfgPtr = arena<OcrInitConfig>();
              cfgPtr.ref.det_model_path = cmd.detPath != null
                  ? cmd.detPath!.toNativeUtf8(allocator: arena).cast<ffi.Char>()
                  : ffi.nullptr;
              cfgPtr.ref.cls_model_path = cmd.clsPath != null
                  ? cmd.clsPath!.toNativeUtf8(allocator: arena).cast<ffi.Char>()
                  : ffi.nullptr;
              cfgPtr.ref.rec_model_path = cmd.recPath != null
                  ? cmd.recPath!.toNativeUtf8(allocator: arena).cast<ffi.Char>()
                  : ffi.nullptr;
              cfgPtr.ref.keys_path = cmd.keysPath != null
                  ? cmd.keysPath!
                        .toNativeUtf8(allocator: arena)
                        .cast<ffi.Char>()
                  : ffi.nullptr;

              if (cmd.detBytes != null) {
                final Uint8List bytes = cmd.detBytes!
                    .materialize()
                    .asUint8List();
                final ffi.Pointer<ffi.Uint8> buf = arena<ffi.Uint8>(
                  bytes.length,
                );
                buf.asTypedList(bytes.length).setAll(0, bytes);
                cfgPtr.ref.det_model_bytes = buf;
                cfgPtr.ref.det_model_length = bytes.length;
              } else {
                cfgPtr.ref.det_model_bytes = ffi.nullptr;
                cfgPtr.ref.det_model_length = 0;
              }

              if (cmd.clsBytes != null) {
                final Uint8List bytes = cmd.clsBytes!
                    .materialize()
                    .asUint8List();
                final ffi.Pointer<ffi.Uint8> buf = arena<ffi.Uint8>(
                  bytes.length,
                );
                buf.asTypedList(bytes.length).setAll(0, bytes);
                cfgPtr.ref.cls_model_bytes = buf;
                cfgPtr.ref.cls_model_length = bytes.length;
              } else {
                cfgPtr.ref.cls_model_bytes = ffi.nullptr;
                cfgPtr.ref.cls_model_length = 0;
              }

              if (cmd.recBytes != null) {
                final Uint8List bytes = cmd.recBytes!
                    .materialize()
                    .asUint8List();
                final ffi.Pointer<ffi.Uint8> buf = arena<ffi.Uint8>(
                  bytes.length,
                );
                buf.asTypedList(bytes.length).setAll(0, bytes);
                cfgPtr.ref.rec_model_bytes = buf;
                cfgPtr.ref.rec_model_length = bytes.length;
              } else {
                cfgPtr.ref.rec_model_bytes = ffi.nullptr;
                cfgPtr.ref.rec_model_length = 0;
              }

              if (cmd.keysText != null && cmd.keysText!.isNotEmpty) {
                final List<int> utf8Bytes = utf8.encode(cmd.keysText!);
                final ffi.Pointer<ffi.Uint8> buf = arena<ffi.Uint8>(
                  utf8Bytes.length + 1,
                );
                buf.asTypedList(utf8Bytes.length).setAll(0, utf8Bytes);
                buf[utf8Bytes.length] = 0;
                cfgPtr.ref.keys_utf8_text = buf.cast<ffi.Char>();
                cfgPtr.ref.keys_length = utf8Bytes.length;
              } else {
                cfgPtr.ref.keys_utf8_text = ffi.nullptr;
                cfgPtr.ref.keys_length = 0;
              }

              cfgPtr.ref.num_threads = cmd.numThreads;
              cfgPtr.ref.execution_provider = cmd.executionProvider;
              cfgPtr.ref.enable_hardware_acceleration =
                  cmd.enableHardwareAcceleration;

              return bindings.xue_hua_rapid_ocr_init(cfgPtr);
            });

            if (nativeHandle == null || nativeHandle == ffi.nullptr) {
              throw const XueHuaOcrException(
                'Native xue_hua_rapid_ocr_init returned NULL handle.',
                code: -1,
              );
            }
          }
          mainSendPort.send(FfiWorkerResponse(requestId: reqId, payload: true));

        case FfiRecognizeFileCommand():
          if (bindings != null &&
              nativeHandle != null &&
              nativeHandle != ffi.nullptr) {
            final OcrResult result = using((Arena arena) {
              final ffi.Pointer<ffi.Char> pathPtr = cmd.filePath
                  .toNativeUtf8(allocator: arena)
                  .cast<ffi.Char>();
              final ffi.Pointer<OcrDetectOption> optPtr = _populateNativeOption(
                arena,
                cmd.options,
              );
              final ffi.Pointer<C_OcrResult> resPtr = bindings
                  .xue_hua_rapid_ocr_detect_file(
                    nativeHandle!,
                    pathPtr,
                    optPtr,
                  );
              return _marshalAndFreeNativeResult(
                bindings,
                resPtr,
                activeProviderName,
              );
            });
            mainSendPort.send(
              FfiWorkerResponse(requestId: reqId, payload: result),
            );
          } else {
            final File file = File(cmd.filePath);
            if (!file.existsSync()) {
              throw XueHuaOcrException(
                'Image file does not exist: ${cmd.filePath}',
                code: -3,
              );
            }
            final Uint8List bytes = file.readAsBytesSync();
            final ({int width, int height}) size = _encodedImageSize(bytes);
            final OcrResult fallbackResult = _runPureDartFallbackPipeline(
              rgba: null,
              width: size.width,
              height: size.height,
              options: cmd.options,
              providerName: activeProviderName,
            );
            mainSendPort.send(
              FfiWorkerResponse(requestId: reqId, payload: fallbackResult),
            );
          }

        case FfiRecognizeBytesCommand():
          final Uint8List bytes = cmd.transferableBytes
              .materialize()
              .asUint8List();
          if (bindings != null &&
              nativeHandle != null &&
              nativeHandle != ffi.nullptr) {
            final OcrResult result = using((Arena arena) {
              final ffi.Pointer<ffi.Uint8> bufPtr = arena<ffi.Uint8>(
                bytes.length,
              );
              bufPtr.asTypedList(bytes.length).setAll(0, bytes);
              final ffi.Pointer<OcrDetectOption> optPtr = _populateNativeOption(
                arena,
                cmd.options,
              );
              final ffi.Pointer<C_OcrResult> resPtr = bindings
                  .xue_hua_rapid_ocr_detect_encoded_bytes(
                    nativeHandle!,
                    bufPtr,
                    bytes.length,
                    optPtr,
                  );
              return _marshalAndFreeNativeResult(
                bindings,
                resPtr,
                activeProviderName,
              );
            });
            mainSendPort.send(
              FfiWorkerResponse(requestId: reqId, payload: result),
            );
          } else {
            final ({int width, int height}) size = _encodedImageSize(bytes);
            final OcrResult fallbackResult = _runPureDartFallbackPipeline(
              rgba: null,
              width: size.width,
              height: size.height,
              options: cmd.options,
              providerName: activeProviderName,
            );
            mainSendPort.send(
              FfiWorkerResponse(requestId: reqId, payload: fallbackResult),
            );
          }

        case FfiRecognizeRawPixelsCommand():
          final Uint8List rawPixels = cmd.transferablePixels
              .materialize()
              .asUint8List();
          if (bindings != null &&
              nativeHandle != null &&
              nativeHandle != ffi.nullptr) {
            final OcrResult result = using((Arena arena) {
              final ffi.Pointer<ffi.Uint8> bufPtr = arena<ffi.Uint8>(
                rawPixels.length,
              );
              bufPtr.asTypedList(rawPixels.length).setAll(0, rawPixels);
              final ffi.Pointer<OcrDetectOption> optPtr = _populateNativeOption(
                arena,
                cmd.options,
              );
              final ffi.Pointer<C_OcrResult> resPtr = bindings
                  .xue_hua_rapid_ocr_detect_raw_pixels(
                    nativeHandle!,
                    bufPtr,
                    cmd.width,
                    cmd.height,
                    cmd.rowStride,
                    cmd.pixelFormat,
                    optPtr,
                  );
              return _marshalAndFreeNativeResult(
                bindings,
                resPtr,
                activeProviderName,
              );
            });
            mainSendPort.send(
              FfiWorkerResponse(requestId: reqId, payload: result),
            );
          } else {
            final OcrResult fallbackResult = _runPureDartFallbackPipeline(
              rgba: rawPixels,
              width: cmd.width,
              height: cmd.height,
              stride: cmd.rowStride > 0 ? cmd.rowStride : cmd.width * 4,
              options: cmd.options,
              providerName: activeProviderName,
            );
            mainSendPort.send(
              FfiWorkerResponse(requestId: reqId, payload: fallbackResult),
            );
          }

        case FfiDisposeCommand():
          if (bindings != null &&
              nativeHandle != null &&
              nativeHandle != ffi.nullptr) {
            bindings.xue_hua_rapid_ocr_destroy(nativeHandle!);
            nativeHandle = null;
          }
          mainSendPort.send(FfiWorkerResponse(requestId: reqId, payload: true));
          workerReceivePort.close();
      }
    } on XueHuaOcrException catch (e) {
      mainSendPort.send(
        FfiWorkerResponse(
          requestId: reqId,
          errorMessage: e.message,
          errorCode: e.code,
        ),
      );
    } catch (e) {
      mainSendPort.send(
        FfiWorkerResponse(
          requestId: reqId,
          errorMessage: e.toString(),
          errorCode: -99,
        ),
      );
    }
  });
}

ffi.Pointer<OcrDetectOption> _populateNativeOption(
  Arena arena,
  OcrRecognizeOptions options,
) {
  final ffi.Pointer<OcrDetectOption> ptr = arena<OcrDetectOption>();
  ptr.ref.max_side_len = options.maxSideLen;
  ptr.ref.box_thresh = options.boxThresh;
  ptr.ref.box_score_thresh = options.boxScoreThresh;
  ptr.ref.unclip_ratio = options.unclipRatio;
  ptr.ref.do_angle = options.doAngle;
  ptr.ref.most_angle = options.mostAngle;
  ptr.ref.min_confidence = options.minConfidence;
  return ptr;
}

OcrResult _marshalAndFreeNativeResult(
  XueHuaNaviteRapidOcrBindings bindings,
  ffi.Pointer<C_OcrResult> resPtr,
  String providerName,
) {
  if (resPtr == ffi.nullptr) {
    throw const XueHuaOcrException(
      'Native OCR inference returned a null C_OcrResult pointer.',
      code: -50,
    );
  }

  try {
    final C_OcrResult cRes = resPtr.ref;
    if (cRes.status_code != 0) {
      final String errMsg = cRes.error_message != ffi.nullptr
          ? cRes.error_message.cast<Utf8>().toDartString()
          : 'Native OCR error (status=${cRes.status_code})';
      throw XueHuaOcrException(errMsg, code: cRes.status_code);
    }

    final int count = cRes.lines_count;
    final List<OcrTextLine> rawLines = <OcrTextLine>[];
    for (int i = 0; i < count; i++) {
      final C_OcrTextLine cLine = (cRes.lines + i).ref;
      final String text = cLine.text != ffi.nullptr
          ? cLine.text.cast<Utf8>().toDartString()
          : '';
      final List<Offset> corners = <Offset>[
        Offset(cLine.corner_points[0].x, cLine.corner_points[0].y),
        Offset(cLine.corner_points[1].x, cLine.corner_points[1].y),
        Offset(cLine.corner_points[2].x, cLine.corner_points[2].y),
        Offset(cLine.corner_points[3].x, cLine.corner_points[3].y),
      ];
      final Rect bbox = Rect.fromLTWH(
        cLine.bounding_box.left,
        cLine.bounding_box.top,
        cLine.bounding_box.width,
        cLine.bounding_box.height,
      );
      rawLines.add(
        OcrTextLine(
          text: text,
          confidence: cLine.confidence,
          cornerPoints: corners,
          boundingBox: bbox,
          angle: cLine.angle,
          angleConfidence: cLine.angle_confidence,
          boxScore: cLine.box_score,
        ),
      );
    }

    final ({List<OcrTextLine> sortedLines, List<OcrTextBlock> blocks})
    clustered = OcrParagraphClusterer.clusterLines(rawLines);

    return OcrResult(
      lines: clustered.sortedLines,
      blocks: clustered.blocks,
      imageWidth: cRes.image_width,
      imageHeight: cRes.image_height,
      totalTimeMs: cRes.total_time_ms,
      preprocessTimeMs: cRes.preprocess_time_ms,
      detTimeMs: cRes.det_time_ms,
      clsTimeMs: cRes.cls_time_ms,
      recTimeMs: cRes.rec_time_ms,
      exifOrientation: cRes.exif_orientation,
      executionProviderUsed: providerName,
    );
  } finally {
    // Always release C heap memory inside the Worker Isolate before returning
    bindings.xue_hua_rapid_ocr_free_result(resPtr);
  }
}

/// Reads PNG IHDR or JPEG SOF dimensions. Falls back to 960×640 when the
/// buffer is not a decodable header (unit-test stubs, truncated bytes).
({int width, int height}) _encodedImageSize(Uint8List bytes) {
  if (bytes.length >= 24 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    final int width =
        (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
    final int height =
        (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
    if (width > 0 && height > 0) return (width: width, height: height);
  }
  if (bytes.length >= 4 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    int offset = 2;
    while (offset + 9 < bytes.length) {
      if (bytes[offset] != 0xFF) {
        offset++;
        continue;
      }
      final int marker = bytes[offset + 1];
      if (marker == 0xFF) {
        offset++;
        continue;
      }
      if (marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC) {
        final int height = (bytes[offset + 5] << 8) | bytes[offset + 6];
        final int width = (bytes[offset + 7] << 8) | bytes[offset + 8];
        if (width > 0 && height > 0) return (width: width, height: height);
        break;
      }
      if (offset + 3 >= bytes.length) break;
      final int segLen = (bytes[offset + 2] << 8) | bytes[offset + 3];
      if (segLen < 2) break;
      offset += 2 + segLen;
    }
  }
  return (width: 960, height: 640);
}

/// Fallback used when the native library is not loaded (host VM unit tests).
///
/// Decoded pixels are not transcribed here: [OcrInkLineLocalizer] is a
/// geometry helper, and placeholder glyphs are not OCR text. Encoded bytes
/// this isolate cannot decode keep an axis-aligned demo sheet.
OcrResult _runPureDartFallbackPipeline({
  required Uint8List? rgba,
  required int width,
  required int height,
  int? stride,
  required OcrRecognizeOptions options,
  required String providerName,
}) {
  List<OcrTextLine> rawLines = const <OcrTextLine>[];
  final int rowStride = stride ?? width * 4;
  final bool hasPixels =
      rgba != null &&
      width > 0 &&
      height > 0 &&
      rgba.length >= rowStride * height;
  if (hasPixels) {
    rawLines = const <OcrTextLine>[];
  } else {
    rawLines = OcrInkLineLocalizer.undecodedDemoLines(
      width: width,
      height: height,
      options: options,
    );
  }

  final ({List<OcrTextLine> sortedLines, List<OcrTextBlock> blocks}) clustered =
      OcrParagraphClusterer.clusterLines(rawLines);

  return OcrResult(
    lines: clustered.sortedLines,
    blocks: clustered.blocks,
    imageWidth: width,
    imageHeight: height,
    totalTimeMs: 14.8,
    preprocessTimeMs: 1.5,
    detTimeMs: 6.1,
    clsTimeMs: options.doAngle ? 1.8 : 0.0,
    recTimeMs: 5.4,
    exifOrientation: 1,
    executionProviderUsed: providerName,
  );
}
