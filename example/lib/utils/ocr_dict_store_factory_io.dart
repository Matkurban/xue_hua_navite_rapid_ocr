import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:xue_hua_navite_rapid_ocr/xue_hua_navite_rapid_ocr.dart';

Future<OcrDictionaryStore> createDemoDictionaryStore() async {
  final Directory docs = await getApplicationDocumentsDirectory();
  return OcrDictionaryStore(Directory('${docs.path}/ocr_dicts'));
}
