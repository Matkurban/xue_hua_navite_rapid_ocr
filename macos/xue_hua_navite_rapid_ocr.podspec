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
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '11.0'
  s.libraries = 'c++'
  s.preserve_paths = 'Libraries/**/*'
  s.vendored_libraries = 'Libraries/libonnxruntime.dylib'

  # Embed ONNX Runtime 1.20.1 for RapidOCR dlopen. Hosts: scripts/download_onnxruntime.sh
  s.prepare_command = <<-CMD
    set -e
    mkdir -p Libraries
    ORT=""
    ARCH="$(uname -m)"
    if [ "$ARCH" = "arm64" ] && [ -f "../third_party/onnxruntime/macos-arm64/libonnxruntime.dylib" ]; then
      ORT="../third_party/onnxruntime/macos-arm64/libonnxruntime.dylib"
    elif [ "$ARCH" = "x86_64" ] && [ -f "../third_party/onnxruntime/macos-x64/libonnxruntime.dylib" ]; then
      ORT="../third_party/onnxruntime/macos-x64/libonnxruntime.dylib"
    elif [ -f "../third_party/onnxruntime/macos-arm64/libonnxruntime.dylib" ]; then
      ORT="../third_party/onnxruntime/macos-arm64/libonnxruntime.dylib"
    elif [ -f "../third_party/onnxruntime/macos-x64/libonnxruntime.dylib" ]; then
      ORT="../third_party/onnxruntime/macos-x64/libonnxruntime.dylib"
    fi
    if [ -z "$ORT" ]; then
      echo "ERROR: ONNX Runtime dylib missing. Run: scripts/download_onnxruntime.sh" >&2
      exit 1
    fi
    cp -L "$ORT" Libraries/libonnxruntime.dylib
    install_name_tool -id @rpath/libonnxruntime.dylib Libraries/libonnxruntime.dylib 2>/dev/null || true
    codesign --force --sign - Libraries/libonnxruntime.dylib 2>/dev/null || true
    echo "Embedded $ORT -> Libraries/libonnxruntime.dylib"
  CMD

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/../src"',
    'LD_RUNPATH_SEARCH_PATHS' => '$(inherited) @loader_path @loader_path/../Frameworks @executable_path/../Frameworks',
    'OTHER_LDFLAGS' => '$(inherited) -Wl,-rpath,@loader_path'
  }
  s.swift_version = '5.9'
end
