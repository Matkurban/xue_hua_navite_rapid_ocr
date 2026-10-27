import 'package:http/http.dart' as http;

import '../models/ocr_enums.dart';
import '../models/ocr_exception.dart';
import '../models/ocr_model_config.dart';
import 'ocr_dictionary_catalog.dart';

/// Result of resolving a language dictionary for [OcrModelConfig].
class OcrDictionaryResolveResult {
  const OcrDictionaryResolveResult({
    this.keysPathOrUrl,
    this.keysUtf8Text,
  });

  final String? keysPathOrUrl;
  final String? keysUtf8Text;
}

/// Web dictionary helper: downloads packs over HTTP into memory (or reuses a
/// remote URL). There is no local filesystem cache directory on Web.
class OcrDictionaryStore {
  OcrDictionaryStore(
    Object? cacheDirectory, {
    http.Client? httpClient,
  }) : _client = httpClient ?? http.Client() {
    // [cacheDirectory] is ignored on Web; accepted so call sites stay shared.
  }

  final http.Client _client;
  final Map<String, String> _memoryCache = <String, String>{};

  List<OcrDictionaryPack> listPacks() => OcrDictionaryCatalog.listPacks();

  Future<bool> isDownloaded(OcrDictionaryPack pack) async =>
      _memoryCache.containsKey(pack.id);

  /// Downloads [pack] into an in-memory cache and returns its UTF-8 text.
  Future<String> download(
    OcrDictionaryPack pack, {
    void Function(int received, int? total)? onProgress,
    bool force = false,
  }) async {
    if (!force && _memoryCache.containsKey(pack.id)) {
      return _memoryCache[pack.id]!;
    }
    onProgress?.call(0, null);
    final http.Response response =
        await _client.get(Uri.parse(pack.downloadUrl));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw XueHuaOcrException(
        'Dictionary download failed (${response.statusCode}): ${pack.downloadUrl}',
        code: response.statusCode,
      );
    }
    final String text = response.body;
    _memoryCache[pack.id] = text;
    onProgress?.call(response.bodyBytes.length, response.bodyBytes.length);
    return text;
  }

  /// On Web this returns the remote URL (engine can fetch) after warming cache.
  Future<String> ensureDownloaded(
    OcrLanguage language, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final OcrDictionaryPack? pack =
        OcrDictionaryCatalog.packForLanguage(language);
    if (pack == null) {
      throw XueHuaOcrException(
        'No dictionary pack mapped for $language',
        code: 4502,
      );
    }
    await download(pack, onProgress: onProgress);
    return pack.downloadUrl;
  }

  Future<OcrDictionaryResolveResult> resolveForLanguage(
    OcrLanguage language, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final OcrDictionaryPack? pack =
        OcrDictionaryCatalog.packForLanguage(language);
    if (pack == null) {
      throw XueHuaOcrException(
        'No dictionary pack mapped for $language',
        code: 4502,
      );
    }
    final String text = await download(pack, onProgress: onProgress);
    return OcrDictionaryResolveResult(
      keysPathOrUrl: pack.downloadUrl,
      keysUtf8Text: text,
    );
  }

  Future<OcrModelConfig> modelConfigForLanguage(
    OcrLanguage language, {
    OcrExecutionProvider executionProvider = OcrExecutionProvider.auto,
    String? detModelPathOrUrl,
    String? clsModelPathOrUrl =
        'assets/models/ch_ppocr_mobile_v2.0_cls_mobile.onnx',
    String? recModelPathOrUrl,
    int numThreads = 4,
    bool enableHardwareAcceleration = true,
    bool enableWebModelCache = true,
    void Function(int received, int? total)? onProgress,
  }) async {
    final OcrDictionaryResolveResult resolved =
        await resolveForLanguage(language, onProgress: onProgress);
    return OcrModelConfig.forLanguage(
      language,
      executionProvider: executionProvider,
      detModelPathOrUrl: detModelPathOrUrl,
      clsModelPathOrUrl: clsModelPathOrUrl,
      recModelPathOrUrl: recModelPathOrUrl,
      keysPathOrUrl: resolved.keysPathOrUrl,
      keysUtf8Text: resolved.keysUtf8Text,
      numThreads: numThreads,
      enableHardwareAcceleration: enableHardwareAcceleration,
      enableWebModelCache: enableWebModelCache,
    );
  }

  Future<void> delete(OcrDictionaryPack pack) async {
    _memoryCache.remove(pack.id);
  }

  void close() => _client.close();
}
