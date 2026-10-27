/// Developer-machine runtime assets for RapidOCR v3.10.0 + ONNX Runtime.
///
/// Desktop / host ORT is **1.31.1** (`ORT_API_VERSION` 31). iOS uses the newest
/// CocoaPods `pod-archive-onnxruntime-c` that still publishes (**1.30.0**,
/// `ORT_API_VERSION` 30) — GitHub ORT releases omit iOS, and 1.31.x pod
/// archives are not available yet.
///
/// Consumed by `dart run xue_hua_navite_rapid_ocr:fetch_runtime` (and optionally
/// by CocoaPods / CMake prepare steps). Large binaries stay gitignored.
library;

/// ModelScope resolve base aligned with RapidOCR v3.10.0.
const String kRapidOcrModelScopeBase =
    'https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/v3.10.0';

/// Desktop / Android / macOS (arm64) / Windows host ORT version this plugin dlopens.
const String kOnnxRuntimeVersion = '1.31.1';

/// iOS CocoaPods ORT archive (newest available; ORT_API_VERSION 30).
///
/// Linked iOS builds must call `GetApi(30)`, not the vendored header's 31.
const String kOnnxRuntimeIosVersion = '1.30.0';

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
  sha256: 'c849e36a1ef3e22d4ff217b9d1ce4a3cf5b9467b975610913ae959ad5b16bdc9',
);

const OcrOrtHostArtifact kOrtMacosArm64 = OcrOrtHostArtifact(
  platformKey: 'macos-arm64',
  assetName: 'onnxruntime-osx-arm64-$kOnnxRuntimeVersion.tgz',
  packedLibRelativePath: 'lib/libonnxruntime.$kOnnxRuntimeVersion.dylib',
  outFileName: 'libonnxruntime.dylib',
  sha256: '2e1344a1926ee50eb25b38153cb6992c3567515aef0e677a1a520a1798896d6f',
);

/// ORT 1.31.x GitHub releases no longer ship `osx-x86_64`. Kept for error messaging only.
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
  sha256: '5869e26bb25314375f2d5ef1877e3ea06b1543d6c710e6e4a1ec2f7177ab4b2c',
);

const String kOrtIosPodArchiveUrl =
    'https://download.onnxruntime.ai/pod-archive-onnxruntime-c-$kOnnxRuntimeIosVersion.zip';

/// SHA-256 of the iOS CocoaPods ORT 1.30.0 archive.
const String kOrtIosPodArchiveSha256 =
    'e6f1670c14406fd9f082bb400ab197a9b0a9646058ca6366e440642e2b54a2ea';
