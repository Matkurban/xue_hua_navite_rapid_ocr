#!/usr/bin/env bash
# Download ONNX Runtime 1.20.1 (the version this plugin dlopens) for the host.
# RapidOCR weights stay in scripts/download_models.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="1.20.1"
BASE="https://github.com/microsoft/onnxruntime/releases/download/v${VERSION}"

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)
    asset="onnxruntime-linux-x64-${VERSION}.tgz"
    dest_name="linux-x64"
    packed_lib="lib/libonnxruntime.so.${VERSION}"
    out_name="libonnxruntime.so.1"
    expect_sha="67db4dc1561f1e3fd42e619575c82c601ef89849afc7ea85a003abbac1a1a105"
    ;;
  Darwin-arm64)
    asset="onnxruntime-osx-arm64-${VERSION}.tgz"
    dest_name="macos-arm64"
    packed_lib="lib/libonnxruntime.${VERSION}.dylib"
    out_name="libonnxruntime.dylib"
    expect_sha=""
    ;;
  Darwin-x86_64)
    asset="onnxruntime-osx-x86_64-${VERSION}.tgz"
    dest_name="macos-x64"
    packed_lib="lib/libonnxruntime.${VERSION}.dylib"
    out_name="libonnxruntime.dylib"
    expect_sha=""
    ;;
  MINGW*|MSYS*|CYGWIN*)
    asset="onnxruntime-win-x64-${VERSION}.zip"
    dest_name="win-x64"
    packed_lib="lib/onnxruntime.dll"
    out_name="onnxruntime.dll"
    expect_sha=""
    ;;
  *)
    echo "Unsupported host $(uname -s)-$(uname -m)." >&2
    echo "Place ONNX Runtime ${VERSION} manually under third_party/onnxruntime/<platform>/." >&2
    exit 1
    ;;
esac

dest="$ROOT/third_party/onnxruntime/$dest_name"
work="$ROOT/third_party/.onnxruntime-download"
mkdir -p "$dest" "$work"
archive="$work/$asset"

download() {
  if [[ -f "$archive" ]]; then
    echo "Using cached $archive"
  else
    echo "GET $asset"
    curl -L --fail --retry 3 --connect-timeout 30 -o "$archive.partial" "$BASE/$asset"
    mv "$archive.partial" "$archive"
  fi
  if [[ -n "$expect_sha" ]]; then
    local got
    got="$(shasum -a 256 "$archive" | awk '{print $1}')"
    if [[ "$got" != "$expect_sha" ]]; then
      echo "SHA256 FAIL $asset expected=$expect_sha got=$got" >&2
      rm -f "$archive"
      exit 1
    fi
    echo "SHA256 OK $asset"
  else
    echo "SHA256 (unpinned host): $(shasum -a 256 "$archive" | awk '{print $1}')"
  fi
}

download

extract="$work/extract"
rm -rf "$extract"
mkdir -p "$extract"
case "$archive" in
  *.zip) unzip -q "$archive" -d "$extract" ;;
  *) tar -xzf "$archive" -C "$extract" ;;
esac

src_lib="$(find "$extract" -path "*/$packed_lib" -print -quit)"
if [[ -z "$src_lib" || ! -f "$src_lib" ]]; then
  echo "Missing $packed_lib inside $asset" >&2
  exit 1
fi
# Materialize a regular file. A symlink would break once the extract directory is removed.
cp -L "$src_lib" "$dest/$out_name"
chmod +x "$dest/$out_name"
rm -rf "$extract"
echo "OK $dest/$out_name"
ls -lh "$dest/$out_name"
