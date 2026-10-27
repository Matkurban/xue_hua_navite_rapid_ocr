import '../models/ocr_enums.dart';
import 'ocr_runtime_assets.dart';

/// A downloadable RapidOCR character dictionary pack for end-user apps.
///
/// Dictionaries are **not** shipped as mandatory plugin assets. Consuming apps
/// let users pick which language packs to download at runtime, then pass the
/// cached path via [OcrModelConfig.keysPathOrUrl] or the UTF-8 text via
/// [OcrModelConfig.keysUtf8Text].
class OcrDictionaryPack {
  const OcrDictionaryPack({
    required this.id,
    required this.fileName,
    required this.displayName,
    required this.relativeUrl,
    this.language,
    this.sha256,
  });

  /// Stable pack id (e.g. `ppocr_keys_v1`, `japan_dict`).
  final String id;

  /// On-disk / cache file name.
  final String fileName;

  /// Human-readable label for UI pickers.
  final String displayName;

  /// Path under [kRapidOcrModelScopeBase].
  final String relativeUrl;

  /// Preset language this dictionary pairs with, when applicable.
  final OcrLanguage? language;

  /// Optional SHA-256 of the upstream file (null when RapidOCR leaves it unpinned).
  final String? sha256;

  /// Absolute ModelScope download URL.
  String get downloadUrl => '$kRapidOcrModelScopeBase/$relativeUrl';
}

/// Catalog of language dictionary packs aligned with RapidOCR v3.10.0.
abstract final class OcrDictionaryCatalog {
  static const List<OcrDictionaryPack> packs = <OcrDictionaryPack>[
    OcrDictionaryPack(
      id: 'ppocr_keys_v1',
      fileName: 'ppocr_keys_v1.txt',
      displayName: 'Chinese & English (ppocr_keys_v1)',
      relativeUrl:
          'paddle/PP-OCRv4/rec/ch_PP-OCRv4_rec_mobile/ppocr_keys_v1.txt',
      language: OcrLanguage.chineseAndEnglish,
    ),
    OcrDictionaryPack(
      id: 'en_dict',
      fileName: 'en_dict.txt',
      displayName: 'English (en_dict)',
      relativeUrl: 'paddle/PP-OCRv4/rec/en_PP-OCRv4_rec_mobile/en_dict.txt',
      language: OcrLanguage.english,
    ),
    OcrDictionaryPack(
      id: 'japan_dict',
      fileName: 'japan_dict.txt',
      displayName: 'Japanese (japan_dict)',
      relativeUrl:
          'paddle/PP-OCRv4/rec/japan_PP-OCRv4_rec_mobile/japan_dict.txt',
      language: OcrLanguage.japanese,
    ),
    OcrDictionaryPack(
      id: 'korean_dict',
      fileName: 'korean_dict.txt',
      displayName: 'Korean (korean_dict)',
      relativeUrl:
          'paddle/PP-OCRv4/rec/korean_PP-OCRv4_rec_mobile/korean_dict.txt',
      language: OcrLanguage.korean,
    ),
    OcrDictionaryPack(
      id: 'latin_dict',
      fileName: 'latin_dict.txt',
      displayName: 'Latin scripts (latin_dict)',
      relativeUrl:
          'paddle/PP-OCRv4/rec/latin_PP-OCRv3_rec_mobile/latin_dict.txt',
      language: OcrLanguage.latin,
    ),
    OcrDictionaryPack(
      id: 'cyrillic_dict',
      fileName: 'cyrillic_dict.txt',
      displayName: 'Cyrillic (cyrillic_dict)',
      relativeUrl:
          'paddle/PP-OCRv4/rec/cyrillic_PP-OCRv3_rec_mobile/cyrillic_dict.txt',
      language: OcrLanguage.cyrillic,
    ),
    OcrDictionaryPack(
      id: 'arabic_dict',
      fileName: 'arabic_dict.txt',
      displayName: 'Arabic (arabic_dict)',
      relativeUrl:
          'paddle/PP-OCRv4/rec/arabic_PP-OCRv4_rec_mobile/arabic_dict.txt',
      language: OcrLanguage.arabic,
    ),
    OcrDictionaryPack(
      id: 'ppocrv5_dict',
      fileName: 'ppocrv5_dict.txt',
      displayName: 'Chinese PP-OCRv5 (ppocrv5_dict)',
      relativeUrl:
          'paddle/PP-OCRv5/rec/ch_PP-OCRv5_rec_mobile/ppocrv5_dict.txt',
    ),
  ];

  /// All packs suitable for an in-app language picker.
  static List<OcrDictionaryPack> listPacks() =>
      List<OcrDictionaryPack>.unmodifiable(packs);

  /// Pack for a preset [OcrLanguage], or null for `multilingual` / unknown.
  static OcrDictionaryPack? packForLanguage(OcrLanguage language) {
    for (final OcrDictionaryPack pack in packs) {
      if (pack.language == language) {
        return pack;
      }
    }
    // multilingual reuses the Chinese keys by default.
    if (language == OcrLanguage.multilingual) {
      return packForLanguage(OcrLanguage.chineseAndEnglish);
    }
    return null;
  }

  static OcrDictionaryPack? packById(String id) {
    for (final OcrDictionaryPack pack in packs) {
      if (pack.id == id) {
        return pack;
      }
    }
    return null;
  }
}
