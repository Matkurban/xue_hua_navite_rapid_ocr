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

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17'
  }
  s.swift_version = '5.9'
end
