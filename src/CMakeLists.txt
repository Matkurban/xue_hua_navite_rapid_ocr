# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(xue_hua_navite_rapid_ocr_library VERSION 0.0.1 LANGUAGES C)

add_library(xue_hua_navite_rapid_ocr SHARED
  "xue_hua_navite_rapid_ocr.c"
)

set_target_properties(xue_hua_navite_rapid_ocr PROPERTIES
  PUBLIC_HEADER xue_hua_navite_rapid_ocr.h
  OUTPUT_NAME "xue_hua_navite_rapid_ocr"
)

target_compile_definitions(xue_hua_navite_rapid_ocr PUBLIC DART_SHARED_LIB)

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(xue_hua_navite_rapid_ocr PRIVATE "-Wl,-z,max-page-size=16384")
endif()
