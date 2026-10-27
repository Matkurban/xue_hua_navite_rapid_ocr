#!/usr/bin/env bash
# Build the plugin shared library and place ONNX Runtime beside it for dlopen.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build/native"
mkdir -p "$BUILD"

if command -v cmake >/dev/null 2>&1; then
  cmake -S "$ROOT/src" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release
  cmake --build "$BUILD" --parallel
else
  echo "cmake not found; building with system C++ compiler"
  case "$(uname -s)" in
    Darwin)
      out="$BUILD/libxue_hua_navite_rapid_ocr.dylib"
      clang++ -std=c++17 -O2 -fPIC -shared \
        -o "$out" \
        "$ROOT/src/xue_hua_navite_rapid_ocr_c_api.cpp" \
        -I"$ROOT/src" \
        -install_name @rpath/libxue_hua_navite_rapid_ocr.dylib
      ;;
    Linux)
      out="$BUILD/libxue_hua_navite_rapid_ocr.so"
      c++ -std=c++17 -O2 -fPIC -shared \
        -o "$out" \
        "$ROOT/src/xue_hua_navite_rapid_ocr_c_api.cpp" \
        -I"$ROOT/src" \
        -ldl
      ;;
    *)
      echo "No cmake and no compiler recipe for $(uname -s). Install cmake." >&2
      exit 1
      ;;
  esac
  echo "Built $out"
fi

shopt -s nullglob
copied=0
for lib in \
  "$ROOT"/third_party/onnxruntime/*/libonnxruntime.so.1 \
  "$ROOT"/third_party/onnxruntime/*/libonnxruntime.dylib \
  "$ROOT"/third_party/onnxruntime/*/onnxruntime.dll
do
  dest="$BUILD/$(basename "$lib")"
  cp -L "$lib" "$dest"
  if [[ "$(uname -s)" == "Darwin" && "$dest" == *.dylib ]]; then
    install_name_tool -id @rpath/libonnxruntime.dylib "$dest" 2>/dev/null || true
    codesign --force --sign - "$dest" 2>/dev/null || true
  fi
  copied=1
  echo "Copied $(basename "$lib") -> $BUILD"
done
if [[ "$copied" -eq 0 ]]; then
  echo "ONNX Runtime library not found under third_party/onnxruntime." >&2
  echo "Run scripts/download_onnxruntime.sh before expecting real OCR text." >&2
fi
