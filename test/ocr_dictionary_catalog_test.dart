import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_navite_rapid_ocr/xue_hua_navite_rapid_ocr.dart';

void main() {
  test('catalog lists packs and maps languages', () {
    final List<OcrDictionaryPack> packs = OcrDictionaryCatalog.listPacks();
    expect(packs, isNotEmpty);
    expect(
      packs.map((OcrDictionaryPack p) => p.fileName),
      contains('ppocr_keys_v1.txt'),
    );
    expect(
      OcrDictionaryCatalog.packForLanguage(OcrLanguage.japanese)?.id,
      'japan_dict',
    );
    expect(
      OcrDictionaryCatalog.packForLanguage(OcrLanguage.multilingual)?.fileName,
      'ppocr_keys_v1.txt',
    );
    expect(
      OcrDictionaryCatalog.packById('arabic_dict')?.downloadUrl,
      contains('arabic_dict.txt'),
    );
  });
}
