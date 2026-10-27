/// Developer-machine runtime assets for RapidOCR v3.10.0 + ONNX Runtime 1.20.x.
///
/// Consumed by `dart run xue_hua_navite_rapid_ocr:fetch_runtime` (and optionally
/// by CocoaPods / CMake prepare steps). Large binaries stay gitignored.
library;

/// ModelScope resolve base aligned with RapidOCR v3.10.0.
const String kRapidOcrModelScopeBase =
    'https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/v3.10.0';

/// Desktop / Android host ORT version this plugin dlopens.
const String kOnnxRuntimeVersion = '1.20.1';

/// iOS CocoaPods ORT archive (same ORT_API_VERSION 20 as 1.20.1 desktop).
const String kOnnxRuntimeIosVersion = '1.20.0';

/// One downloadable `.onnx` weight (no character dictionaries).
class OcrOnnxModelAsset {
  const OcrOnnxModelAsset({
    required this.fileName,
    required this.relativeUrl,
    required this.sha256,
  });

  final String fileName;
  final String relativeUrl;
  final String sha256;

  String get url => '$kRapidOcrModelScopeBase/$relativeUrl';
}

/// Default PP-OCRv4 (+ optional v5) ONNX weights fetched on the developer machine.
const List<OcrOnnxModelAsset> kDefaultOnnxModelAssets = <OcrOnnxModelAsset>[
  OcrOnnxModelAsset(
    fileName: 'ch_ppocr_mobile_v2.0_cls_mobile.onnx',
    relativeUrl: 'onnx/PP-OCRv4/cls/ch_ppocr_mobile_v2.0_cls_mobile.onnx',
    sha256:
        'e47acedf663230f8863ff1ab0e64dd2d82b838fceb5957146dab185a89d6215c',
  ),
  OcrOnnxModelAsset(
    fileName: 'ch_PP-OCRv4_det_mobile.onnx',
    relativeUrl: 'onnx/PP-OCRv4/det/ch_PP-OCRv4_det_mobile.onnx',
    sha256:
        'd2a7720d45a54257208b1e13e36a8479894cb74155a5efe29462512d42f49da9',
  ),
  OcrOnnxModelAsset(
    fileName: 'multi_PP-OCRv3_det_mobile.onnx',
    relativeUrl: 'onnx/PP-OCRv4/det/multi_PP-OCRv3_det_mobile.onnx',
    sha256:
        '5582933662898cd2b4c2eae8a7e5e4fbdff84773711f29db00a1cbd185059001',
  ),
  OcrOnnxModelAsset(
    fileName: 'ch_PP-OCRv4_rec_mobile.onnx',
    relativeUrl: 'onnx/PP-OCRv4/rec/ch_PP-OCRv4_rec_mobile.onnx',
    sha256:
        '48fc40f24f6d2a207a2b1091d3437eb3cc3eb6b676dc3ef9c37384005483683b',
  ),
  OcrOnnxModelAsset(
    fileName: 'en_PP-OCRv4_rec_mobile.onnx',
    relativeUrl: 'onnx/PP-OCRv4/rec/en_PP-OCRv4_rec_mobile.onnx',
    sha256:
        'e8770c967605983d1570cdf5352041dfb68fa0c21664f49f47b155abd3e0e318',
  ),
  OcrOnnxModelAsset(
    fileName: 'japan_PP-OCRv4_rec_mobile.onnx',
    relativeUrl: 'onnx/PP-OCRv4/rec/japan_PP-OCRv4_rec_mobile.onnx',
    sha256:
        'e1075a67dba758ecfc7ebc78a10ae61c95ac8fb66a9c86fab5541e33f085cb7a',
  ),
  OcrOnnxModelAsset(
    fileName: 'korean_PP-OCRv4_rec_mobile.onnx',
    relativeUrl: 'onnx/PP-OCRv4/rec/korean_PP-OCRv4_rec_mobile.onnx',
    sha256:
        'ab151ba9065eccd98f884cf4d927db091be86137276392072edd4f9d43ad7426',
  ),
  OcrOnnxModelAsset(
    fileName: 'latin_PP-OCRv3_rec_mobile.onnx',
    relativeUrl: 'onnx/PP-OCRv4/rec/latin_PP-OCRv3_rec_mobile.onnx',
    sha256:
        'e9d7a33667e8aaa702862975186adf2012e3f390cc0f9422865957125f8071cf',
  ),
  OcrOnnxModelAsset(
    fileName: 'cyrillic_PP-OCRv3_rec_mobile.onnx',
    relativeUrl: 'onnx/PP-OCRv4/rec/cyrillic_PP-OCRv3_rec_mobile.onnx',
    sha256:
        '1efb65bdc460af1c0e8733d005b20952b17ca5aac10ddb56c968333791c5eaa3',
  ),
  OcrOnnxModelAsset(
    fileName: 'arabic_PP-OCRv4_rec_mobile.onnx',
    relativeUrl: 'onnx/PP-OCRv4/rec/arabic_PP-OCRv4_rec_mobile.onnx',
    sha256:
        '4a9011bef71687bb84288dc86ad2471bd5d37b717ddf672dd156f9e7a5601bac',
  ),
];

/// Optional PP-OCRv5 Chinese mobile upgrade pack.
const List<OcrOnnxModelAsset> kOptionalPpocrv5OnnxModelAssets =
    <OcrOnnxModelAsset>[
  OcrOnnxModelAsset(
    fileName: 'ch_PP-OCRv5_det_mobile.onnx',
    relativeUrl: 'onnx/PP-OCRv5/det/ch_PP-OCRv5_det_mobile.onnx',
    sha256:
        '4d97c44a20d30a81aad087d6a396b08f786c4635742afc391f6621f5c6ae78ae',
  ),
  OcrOnnxModelAsset(
    fileName: 'ch_PP-OCRv5_rec_mobile.onnx',
    relativeUrl: 'onnx/PP-OCRv5/rec/ch_PP-OCRv5_rec_mobile.onnx',
    sha256:
        '5825fc7ebf84ae7a412be049820b4d86d77620f204a041697b0494669b1742c5',
  ),
  OcrOnnxModelAsset(
    fileName: 'ch_PP-LCNet_x0_25_textline_ori_cls_mobile.onnx',
    relativeUrl:
        'onnx/PP-OCRv5/cls/ch_PP-LCNet_x0_25_textline_ori_cls_mobile.onnx',
    sha256:
        '54379ae5174d026780215fc748a7f31910dee36818e63d49e17dc598ecc82df7',
  ),
];

/// Host ONNX Runtime release asset metadata.
class OcrOrtHostArtifact {
  const OcrOrtHostArtifact({
    required this.platformKey,
    required this.assetName,
    required this.packedLibRelativePath,
    required this.outFileName,
    this.sha256,
  });

  final String platformKey;
  final String assetName;
  final String packedLibRelativePath;
  final String outFileName;
  final String? sha256;

  String get url =>
      'https://github.com/microsoft/onnxruntime/releases/download/v$kOnnxRuntimeVersion/$assetName';
}

const OcrOrtHostArtifact kOrtLinuxX64 = OcrOrtHostArtifact(
  platformKey: 'linux-x64',
  assetName: 'onnxruntime-linux-x64-$kOnnxRuntimeVersion.tgz',
  packedLibRelativePath: 'lib/libonnxruntime.so.$kOnnxRuntimeVersion',
  outFileName: 'libonnxruntime.so.1',
  sha256: '67db4dc1561f1e3fd42e619575c82c601ef89849afc7ea85a003abbac1a1a105',
);

const OcrOrtHostArtifact kOrtMacosArm64 = OcrOrtHostArtifact(
  platformKey: 'macos-arm64',
  assetName: 'onnxruntime-osx-arm64-$kOnnxRuntimeVersion.tgz',
  packedLibRelativePath: 'lib/libonnxruntime.$kOnnxRuntimeVersion.dylib',
  outFileName: 'libonnxruntime.dylib',
);

const OcrOrtHostArtifact kOrtMacosX64 = OcrOrtHostArtifact(
  platformKey: 'macos-x64',
  assetName: 'onnxruntime-osx-x86_64-$kOnnxRuntimeVersion.tgz',
  packedLibRelativePath: 'lib/libonnxruntime.$kOnnxRuntimeVersion.dylib',
  outFileName: 'libonnxruntime.dylib',
);

const OcrOrtHostArtifact kOrtWinX64 = OcrOrtHostArtifact(
  platformKey: 'win-x64',
  assetName: 'onnxruntime-win-x64-$kOnnxRuntimeVersion.zip',
  packedLibRelativePath: 'lib/onnxruntime.dll',
  outFileName: 'onnxruntime.dll',
);

const String kOrtIosPodArchiveUrl =
    'https://download.onnxruntime.ai/pod-archive-onnxruntime-c-$kOnnxRuntimeIosVersion.zip';
