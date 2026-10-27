import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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

  /// Absolute filesystem path (preferred on native) or remote URL.
  final String? keysPathOrUrl;

  /// In-memory UTF-8 dictionary (preferred on Web).
  final String? keysUtf8Text;
}

/// Downloads and caches character dictionaries under an app-owned directory
/// (typically `getApplicationDocumentsDirectory()/ocr_dicts`).
///
/// Example:
/// ```dart
/// final docs = await getApplicationDocumentsDirectory();
/// final store = OcrDictionaryStore(Directory('${docs.path}/ocr_dicts'));
/// final keysPath = await store.ensureDownloaded(OcrLanguage.japanese);
/// await ocr.initialize(OcrModelConfig.forLanguage(
///   OcrLanguage.japanese,
///   keysPathOrUrl: keysPath,
/// ));
/// ```
class OcrDictionaryStore {
  OcrDictionaryStore(
    Object? cacheDirectory, {
    http.Client? httpClient,
  })  : cacheDirectory = cacheDirectory is Directory
            ? cacheDirectory
            : Directory(
                cacheDirectory?.toString() ??
                    '${Directory.systemTemp.path}/ocr_dicts',
              ),
        _client = httpClient ?? http.Client();

  /// Root directory that holds `*.txt` dictionary files.
  final Directory cacheDirectory;

  final http.Client _client;

  /// Lists every catalog pack (installed or not).
  List<OcrDictionaryPack> listPacks() => OcrDictionaryCatalog.listPacks();

  File fileFor(OcrDictionaryPack pack) =>
      File('${cacheDirectory.path}/${pack.fileName}');

  Future<bool> isDownloaded(OcrDictionaryPack pack) async {
    final File file = fileFor(pack);
    if (!await file.exists()) {
      return false;
    }
    final int length = await file.length();
    return length > 0;
  }

  /// Downloads [pack] into [cacheDirectory], verifying SHA-256 when provided.
  Future<File> download(
    OcrDictionaryPack pack, {
    void Function(int received, int? total)? onProgress,
    bool force = false,
  }) async {
    await cacheDirectory.create(recursive: true);
    final File out = fileFor(pack);
    if (!force && await isDownloaded(pack)) {
      if (pack.sha256 != null) {
        final String got = await _sha256File(out);
        if (got == pack.sha256) {
          return out;
        }
      } else {
        return out;
      }
    }

    final http.Request request = http.Request('GET', Uri.parse(pack.downloadUrl));
    final http.StreamedResponse response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw XueHuaOcrException(
        'Dictionary download failed (${response.statusCode}): ${pack.downloadUrl}',
        code: response.statusCode,
      );
    }

    final int? total = response.contentLength;
    final BytesBuilder builder = BytesBuilder(copy: false);
    int received = 0;
    await for (final List<int> chunk in response.stream) {
      builder.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }
    final Uint8List bytes = builder.takeBytes();
    if (pack.sha256 != null) {
      final String got = sha256.convert(bytes).toString();
      if (got != pack.sha256) {
        throw XueHuaOcrException(
          'Dictionary SHA-256 mismatch for ${pack.fileName}: expected ${pack.sha256}, got $got',
          code: 4501,
        );
      }
    }

    final File tmp = File('${out.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    if (await out.exists()) {
      await out.delete();
    }
    await tmp.rename(out.path);
    return out;
  }

  /// Ensures the dictionary for [language] is on disk; returns its absolute path.
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
    final File file = await download(pack, onProgress: onProgress);
    return file.absolute.path;
  }

  /// Downloads (if needed) and returns both a path and UTF-8 text for [language].
  Future<OcrDictionaryResolveResult> resolveForLanguage(
    OcrLanguage language, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final String path =
        await ensureDownloaded(language, onProgress: onProgress);
    final String text = await File(path).readAsString();
    return OcrDictionaryResolveResult(
      keysPathOrUrl: path,
      keysUtf8Text: text,
    );
  }

  /// Builds an [OcrModelConfig] with a downloaded dictionary for [language].
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
    final File file = fileFor(pack);
    if (await file.exists()) {
      await file.delete();
    }
  }

  void close() => _client.close();

  static Future<String> _sha256File(File file) async {
    final Digest digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}
