# ONNX Runtime for macOS

This folder is filled by `xue_hua_navite_rapid_ocr.podspec` `prepare_command` from
`third_party/onnxruntime/macos-arm64|macos-x64/libonnxruntime.dylib`.

Run from the repo root:

```bash
scripts/download_onnxruntime.sh
```

Then `cd example && flutter build macos` (pod install embeds the dylib).
