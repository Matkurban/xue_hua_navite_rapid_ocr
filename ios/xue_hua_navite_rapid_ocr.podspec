Pod::Spec.new do |s|
  s.name             = 'xue_hua_navite_rapid_ocr'
  s.version          = '1.0.0'
  s.summary          = 'Full-featured 6-platform offline RapidOCR ONNX plugin for Flutter.'
  s.description      = <<-DESC
Check out xue_hua_navite_rapid_ocr — a full-featured 6-platform native & Web offline RapidOCR (PP-OCRv4/PP-OCRv5 ONNX) plugin for Flutter!
                       DESC
  s.homepage         = 'https://github.com/Matkurban/xue_hua_navite_rapid_ocr'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Matkurban' => '3496354336@qq.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.libraries = 'c++'
  s.weak_frameworks = 'CoreML'
  s.preserve_paths = 'Frameworks/**/*'
  s.vendored_frameworks = 'Frameworks/onnxruntime.xcframework'

  # Embed ONNX Runtime (static xcframework) for RapidOCR.
  # Developers: `dart run xue_hua_navite_rapid_ocr:fetch_runtime --ort`
  # Official GitHub releases omit iOS; newest pod-archive is 1.30.0 (ORT_API_VERSION 30).
  # Desktop vendors 1.31.1 (API 31); linked iOS must call GetApi(30).
  s.prepare_command = <<-CMD
    set -e
    ROOT="$(cd .. && pwd)"
    mkdir -p Frameworks
    if command -v dart >/dev/null 2>&1; then
      (cd "$ROOT" && dart run bin/fetch_runtime.dart --ort) || true
    fi
    ORT=""
    if [ -d "../third_party/onnxruntime/ios/onnxruntime.xcframework" ]; then
      ORT="../third_party/onnxruntime/ios/onnxruntime.xcframework"
    elif [ -d "xue_hua_navite_rapid_ocr/OnnxRuntime/onnxruntime.xcframework" ]; then
      ORT="xue_hua_navite_rapid_ocr/OnnxRuntime/onnxruntime.xcframework"
    fi
    if [ -z "$ORT" ]; then
      echo "ERROR: onnxruntime.xcframework missing. Run: dart run xue_hua_navite_rapid_ocr:fetch_runtime --ort" >&2
      exit 1
    fi
    rm -rf Frameworks/onnxruntime.xcframework
    cp -R "$ORT" Frameworks/onnxruntime.xcframework
    echo "Embedded $ORT -> Frameworks/onnxruntime.xcframework"
  CMD

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) XUE_HUA_ORT_LINKED=1',
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -DXUE_HUA_ORT_LINKED=1',
    'OTHER_CFLAGS' => '$(inherited) -DXUE_HUA_ORT_LINKED=1'
  }
  s.swift_version = '5.9'
end
