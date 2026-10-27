# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "xue_hua_navite_rapid_ocr")
project(${PROJECT_NAME} LANGUAGES CXX)

# Auto-fetch ONNX Runtime on the developer machine when dart is available.
find_program(DART_EXECUTABLE dart)
set(_xue_hua_ort_dll "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/onnxruntime/win-x64/onnxruntime.dll")
if(DART_EXECUTABLE AND NOT EXISTS "${_xue_hua_ort_dll}")
  execute_process(
    COMMAND "${DART_EXECUTABLE}" run bin/fetch_runtime.dart --ort
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/.."
    RESULT_VARIABLE _xue_hua_fetch_rc
  )
  if(NOT _xue_hua_fetch_rc EQUAL 0)
    message(WARNING "fetch_runtime --ort failed (rc=${_xue_hua_fetch_rc}). "
      "Run: dart run xue_hua_navite_rapid_ocr:fetch_runtime --ort")
  endif()
endif()

# Invoke the build for native code shared with the other target platforms.
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")

set(_xue_hua_bundled_libraries
  $<TARGET_FILE:xue_hua_navite_rapid_ocr>
)
if(EXISTS "${_xue_hua_ort_dll}")
  list(APPEND _xue_hua_bundled_libraries "${_xue_hua_ort_dll}")
endif()
set(xue_hua_navite_rapid_ocr_bundled_libraries
  ${_xue_hua_bundled_libraries}
  PARENT_SCOPE
)
