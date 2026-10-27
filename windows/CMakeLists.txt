# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "xue_hua_navite_rapid_ocr")
project(${PROJECT_NAME} LANGUAGES CXX)

# Invoke the build for native code shared with the other target platforms.
# This can be changed to accommodate different builds.
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(_xue_hua_bundled_libraries
  $<TARGET_FILE:xue_hua_navite_rapid_ocr>
)
set(_xue_hua_ort_dll "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/onnxruntime/win-x64/onnxruntime.dll")
if(EXISTS "${_xue_hua_ort_dll}")
  list(APPEND _xue_hua_bundled_libraries "${_xue_hua_ort_dll}")
endif()
set(xue_hua_navite_rapid_ocr_bundled_libraries
  ${_xue_hua_bundled_libraries}
  PARENT_SCOPE
)
