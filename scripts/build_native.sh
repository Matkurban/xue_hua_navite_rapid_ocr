#!/usr/bin/env bash
# Build the plugin shared library and place ONNX Runtime beside it for dlopen.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build/native"
cmake -S "$ROOT/src" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD" --parallel

shopt -s nullglob
copied=0
for lib in \
  "$ROOT"/third_party/onnxruntime/*/libonnxruntime.so.1 \
  "$ROOT"/third_party/onnxruntime/*/libonnxruntime.dylib \
  "$ROOT"/third_party/onnxruntime/*/onnxruntime.dll
do
  cp -L "$lib" "$BUILD/$(basename "$lib")"
  copied=1
  echo "Copied $(basename "$lib") -> $BUILD"
done
if [[ "$copied" -eq 0 ]]; then
  echo "ONNX Runtime library not found under third_party/onnxruntime." >&2
  echo "Run scripts/download_onnxruntime.sh before expecting real OCR text." >&2
fi
