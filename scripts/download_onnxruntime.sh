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

# Apple Flutter hosts build the plugin via SwiftPM; copy beside the C++ sources
# so Package.swift can `.copy` the dylib into the framework Resources.
if [[ "$(uname -s)" == "Darwin" ]]; then
  spm_vendor="$ROOT/macos/xue_hua_navite_rapid_ocr/Sources/xue_hua_navite_rapid_ocr/Vendor"
  mkdir -p "$spm_vendor" "$ROOT/macos/Libraries"
  cp -L "$dest/$out_name" "$spm_vendor/libonnxruntime.dylib"
  cp -L "$dest/$out_name" "$ROOT/macos/Libraries/libonnxruntime.dylib"
  install_name_tool -id @rpath/libonnxruntime.dylib "$spm_vendor/libonnxruntime.dylib" 2>/dev/null || true
  install_name_tool -id @rpath/libonnxruntime.dylib "$ROOT/macos/Libraries/libonnxruntime.dylib" 2>/dev/null || true
  codesign --force --sign - "$spm_vendor/libonnxruntime.dylib" 2>/dev/null || true
  codesign --force --sign - "$ROOT/macos/Libraries/libonnxruntime.dylib" 2>/dev/null || true
  echo "Prepared SPM Vendor + CocoaPods Libraries copies"
fi

# iOS / simulator: Microsoft ships a static onnxruntime.xcframework via the
# CocoaPods pod-archive (GitHub release assets omit iOS). Use 1.20.0 — same
# ORT_API_VERSION 20 as the 1.20.1 desktop dylibs this plugin dlopens.
if [[ "$(uname -s)" == "Darwin" ]]; then
  IOS_VERSION="1.20.0"
  IOS_ASSET="pod-archive-onnxruntime-c-${IOS_VERSION}.zip"
  IOS_URL="https://download.onnxruntime.ai/${IOS_ASSET}"
  ios_dest="$ROOT/third_party/onnxruntime/ios"
  ios_archive="$work/$IOS_ASSET"
  mkdir -p "$ios_dest" "$work"
  if [[ ! -d "$ios_dest/onnxruntime.xcframework" ]]; then
    if [[ ! -f "$ios_archive" ]]; then
      echo "GET $IOS_ASSET"
      curl -L --fail --retry 5 --connect-timeout 30 -C - -o "$ios_archive.partial" "$IOS_URL"
      mv "$ios_archive.partial" "$ios_archive"
    else
      echo "Using cached $ios_archive"
    fi
    ios_extract="$work/extract-ios"
    rm -rf "$ios_extract"
    mkdir -p "$ios_extract"
    unzip -q "$ios_archive" -d "$ios_extract"
    if [[ ! -d "$ios_extract/onnxruntime.xcframework" ]]; then
      echo "Missing onnxruntime.xcframework inside $IOS_ASSET" >&2
      exit 1
    fi
    rm -rf "$ios_dest/onnxruntime.xcframework"
    mkdir -p "$ios_dest"
    cp -R "$ios_extract/onnxruntime.xcframework" "$ios_dest/"
    rm -rf "$ios_extract"
    echo "OK $ios_dest/onnxruntime.xcframework"
  else
    echo "Using existing $ios_dest/onnxruntime.xcframework"
  fi
  # CocoaPods prepare_command + SwiftPM binaryTarget copies
  mkdir -p "$ROOT/ios/Frameworks"
  rm -rf "$ROOT/ios/Frameworks/onnxruntime.xcframework"
  cp -R "$ios_dest/onnxruntime.xcframework" "$ROOT/ios/Frameworks/"
  spm_ios="$ROOT/ios/xue_hua_navite_rapid_ocr/OnnxRuntime"
  mkdir -p "$spm_ios"
  rm -rf "$spm_ios/onnxruntime.xcframework"
  cp -R "$ios_dest/onnxruntime.xcframework" "$spm_ios/"
  echo "Prepared iOS Frameworks + SPM OnnxRuntime xcframework copies"
fi

