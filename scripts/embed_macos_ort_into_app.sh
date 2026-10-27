#!/usr/bin/env bash
# Copy ONNX Runtime next to the plugin framework binary inside a built .app
# so RapidOCR can dlopen it via SiblingCandidates (Flutter SwiftPM places the
# dylib in a resource bundle that is awkward for dlopen search).
set -euo pipefail
APP="${1:-}"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "usage: $0 /path/to/Your.app" >&2
  exit 1
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORT=""
for cand in \
  "$ROOT/macos/xue_hua_navite_rapid_ocr/Sources/xue_hua_navite_rapid_ocr/Vendor/libonnxruntime.dylib" \
  "$ROOT/macos/Libraries/libonnxruntime.dylib" \
  "$ROOT/third_party/onnxruntime/macos-arm64/libonnxruntime.dylib" \
  "$ROOT/third_party/onnxruntime/macos-x64/libonnxruntime.dylib"
do
  if [[ -f "$cand" ]]; then ORT="$cand"; break; fi
done
if [[ -z "$ORT" ]]; then
  # Fall back to the SwiftPM resource bundle already inside the app.
  ORT="$(find "$APP/Contents/Resources" -name 'libonnxruntime.dylib' 2>/dev/null | head -1 || true)"
fi
if [[ -z "$ORT" || ! -f "$ORT" ]]; then
  echo "ERROR: libonnxruntime.dylib not found (run scripts/download_onnxruntime.sh)" >&2
  exit 1
fi

FRAMEWORKS="$APP/Contents/Frameworks"
mkdir -p "$FRAMEWORKS"
cp -L "$ORT" "$FRAMEWORKS/libonnxruntime.dylib"
install_name_tool -id @rpath/libonnxruntime.dylib "$FRAMEWORKS/libonnxruntime.dylib" 2>/dev/null || true
codesign --force --sign - "$FRAMEWORKS/libonnxruntime.dylib" 2>/dev/null || true

# Also place a copy beside the plugin binary for the tightest SiblingCandidates hit.
PLUGIN_BIN="$(find "$FRAMEWORKS" -name 'xue-hua-navite-rapid-ocr' -type f 2>/dev/null | head -1 || true)"
if [[ -n "$PLUGIN_BIN" ]]; then
  cp -L "$FRAMEWORKS/libonnxruntime.dylib" "$(dirname "$PLUGIN_BIN")/libonnxruntime.dylib"
  codesign --force --sign - "$(dirname "$PLUGIN_BIN")/libonnxruntime.dylib" 2>/dev/null || true
fi
echo "Embedded ORT into $FRAMEWORKS/libonnxruntime.dylib"
