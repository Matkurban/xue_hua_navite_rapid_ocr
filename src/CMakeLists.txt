# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(xue_hua_navite_rapid_ocr_library VERSION 1.0.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

add_library(xue_hua_navite_rapid_ocr SHARED
  "xue_hua_navite_rapid_ocr_c_api.cpp"
)

set_target_properties(xue_hua_navite_rapid_ocr PROPERTIES
  PUBLIC_HEADER xue_hua_navite_rapid_ocr_c_api.h
  OUTPUT_NAME "xue_hua_navite_rapid_ocr"
)

target_include_directories(xue_hua_navite_rapid_ocr PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}"
)

target_compile_definitions(xue_hua_navite_rapid_ocr PUBLIC DART_SHARED_LIB)

# Optional external ONNX Runtime / RapidOcrOnnx linking when ONNXRUNTIME_ROOTDIR is provided
if (DEFINED ONNXRUNTIME_ROOTDIR AND EXISTS "${ONNXRUNTIME_ROOTDIR}")
  target_include_directories(xue_hua_navite_rapid_ocr PRIVATE "${ONNXRUNTIME_ROOTDIR}/include")
  target_compile_definitions(xue_hua_navite_rapid_ocr PRIVATE RAPID_OCR_USE_ONNXRUNTIME=1)
endif()

if (ANDROID)
  # Support Android 15+ 16 KB page size alignment
  target_link_options(xue_hua_navite_rapid_ocr PRIVATE "-Wl,-z,max-page-size=16384")
  find_library(log-lib log)
  if (log-lib)
    target_link_libraries(xue_hua_navite_rapid_ocr PRIVATE ${log-lib})
  endif()
endif()
