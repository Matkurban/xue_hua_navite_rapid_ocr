// ignore_for_file: always_specify_types
// ignore_for_file: camel_case_types
// ignore_for_file: non_constant_identifier_names

import 'dart:ffi' as ffi;

/// Opaque handle representing an initialized RapidOCR engine instance.
typedef OcrEngineHandle = ffi.Pointer<ffi.Void>;

/// Configuration for initializing a RapidOCR engine instance (`OcrInitConfig`).
final class OcrInitConfig extends ffi.Struct {
  external ffi.Pointer<ffi.Char> det_model_path;
  external ffi.Pointer<ffi.Uint8> det_model_bytes;

  @ffi.Size()
  external int det_model_length;

  external ffi.Pointer<ffi.Char> cls_model_path;
  external ffi.Pointer<ffi.Uint8> cls_model_bytes;

  @ffi.Size()
  external int cls_model_length;

  external ffi.Pointer<ffi.Char> rec_model_path;
  external ffi.Pointer<ffi.Uint8> rec_model_bytes;

  @ffi.Size()
  external int rec_model_length;

  external ffi.Pointer<ffi.Char> keys_path;
  external ffi.Pointer<ffi.Char> keys_utf8_text;

  @ffi.Size()
  external int keys_length;

  @ffi.Int32()
  external int num_threads;

  @ffi.Int32()
  external int execution_provider;

  @ffi.Bool()
  external bool enable_hardware_acceleration;
}

/// Fine-grained inference parameters (`OcrDetectOption`).
final class OcrDetectOption extends ffi.Struct {
  @ffi.Int32()
  external int max_side_len;

  @ffi.Float()
  external double box_thresh;

  @ffi.Float()
  external double box_score_thresh;

  @ffi.Float()
  external double unclip_ratio;

  @ffi.Bool()
  external bool do_angle;

  @ffi.Bool()
  external bool most_angle;

  @ffi.Float()
  external double min_confidence;
}

/// 2D floating-point coordinate (`C_OcrPoint`).
final class C_OcrPoint extends ffi.Struct {
  @ffi.Float()
  external double x;

  @ffi.Float()
  external double y;
}

/// Axis-aligned bounding rectangle (`C_OcrRect`).
final class C_OcrRect extends ffi.Struct {
  @ffi.Float()
  external double left;

  @ffi.Float()
  external double top;

  @ffi.Float()
  external double width;

  @ffi.Float()
  external double height;
}

/// Single recognized text line (`C_OcrTextLine`).
final class C_OcrTextLine extends ffi.Struct {
  external ffi.Pointer<ffi.Char> text;

  @ffi.Float()
  external double confidence;

  @ffi.Array.multi([4])
  external ffi.Array<C_OcrPoint> corner_points;

  external C_OcrRect bounding_box;

  @ffi.Float()
  external double angle;

  @ffi.Float()
  external double angle_confidence;

  @ffi.Float()
  external double box_score;
}

/// Complete OCR recognition result (`C_OcrResult`).
final class C_OcrResult extends ffi.Struct {
  @ffi.Int32()
  external int status_code;

  external ffi.Pointer<ffi.Char> error_message;

  @ffi.Double()
  external double total_time_ms;

  @ffi.Double()
  external double preprocess_time_ms;

  @ffi.Double()
  external double det_time_ms;

  @ffi.Double()
  external double cls_time_ms;

  @ffi.Double()
  external double rec_time_ms;

  @ffi.Int32()
  external int image_width;

  @ffi.Int32()
  external int image_height;

  @ffi.Int32()
  external int exif_orientation;

  @ffi.Int32()
  external int lines_count;

  external ffi.Pointer<C_OcrTextLine> lines;
}

/// Dart FFI bindings to `src/xue_hua_navite_rapid_ocr_c_api.h`.
class XueHuaNaviteRapidOcrBindings {
  /// Holds the symbol lookup function.
  final ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
  _lookup;

  /// The symbols are looked up in [dynamicLibrary].
  XueHuaNaviteRapidOcrBindings(ffi.DynamicLibrary dynamicLibrary)
    : _lookup = dynamicLibrary.lookup;

  /// The symbols are looked up with [lookup].
  XueHuaNaviteRapidOcrBindings.fromLookup(
    ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName) lookup,
  ) : _lookup = lookup;

  OcrEngineHandle xue_hua_rapid_ocr_init(ffi.Pointer<OcrInitConfig> config) {
    return _xue_hua_rapid_ocr_init(config);
  }

  late final _xue_hua_rapid_ocr_initPtr =
      _lookup<
        ffi.NativeFunction<OcrEngineHandle Function(ffi.Pointer<OcrInitConfig>)>
      >('xue_hua_rapid_ocr_init');
  late final _xue_hua_rapid_ocr_init = _xue_hua_rapid_ocr_initPtr
      .asFunction<OcrEngineHandle Function(ffi.Pointer<OcrInitConfig>)>();

  void xue_hua_rapid_ocr_destroy(OcrEngineHandle handle) {
    return _xue_hua_rapid_ocr_destroy(handle);
  }

  late final _xue_hua_rapid_ocr_destroyPtr =
      _lookup<ffi.NativeFunction<ffi.Void Function(OcrEngineHandle)>>(
        'xue_hua_rapid_ocr_destroy',
      );
  late final _xue_hua_rapid_ocr_destroy = _xue_hua_rapid_ocr_destroyPtr
      .asFunction<void Function(OcrEngineHandle)>();

  OcrDetectOption xue_hua_rapid_ocr_default_option() {
    return _xue_hua_rapid_ocr_default_option();
  }

  late final _xue_hua_rapid_ocr_default_optionPtr =
      _lookup<ffi.NativeFunction<OcrDetectOption Function()>>(
        'xue_hua_rapid_ocr_default_option',
      );
  late final _xue_hua_rapid_ocr_default_option =
      _xue_hua_rapid_ocr_default_optionPtr
          .asFunction<OcrDetectOption Function()>();

  ffi.Pointer<C_OcrResult> xue_hua_rapid_ocr_detect_file(
    OcrEngineHandle handle,
    ffi.Pointer<ffi.Char> file_path,
    ffi.Pointer<OcrDetectOption> option,
  ) {
    return _xue_hua_rapid_ocr_detect_file(handle, file_path, option);
  }

  late final _xue_hua_rapid_ocr_detect_filePtr =
      _lookup<
        ffi.NativeFunction<
          ffi.Pointer<C_OcrResult> Function(
            OcrEngineHandle,
            ffi.Pointer<ffi.Char>,
            ffi.Pointer<OcrDetectOption>,
          )
        >
      >('xue_hua_rapid_ocr_detect_file');
  late final _xue_hua_rapid_ocr_detect_file = _xue_hua_rapid_ocr_detect_filePtr
      .asFunction<
        ffi.Pointer<C_OcrResult> Function(
          OcrEngineHandle,
          ffi.Pointer<ffi.Char>,
          ffi.Pointer<OcrDetectOption>,
        )
      >();

  ffi.Pointer<C_OcrResult> xue_hua_rapid_ocr_detect_encoded_bytes(
    OcrEngineHandle handle,
    ffi.Pointer<ffi.Uint8> encoded_bytes,
    int length,
    ffi.Pointer<OcrDetectOption> option,
  ) {
    return _xue_hua_rapid_ocr_detect_encoded_bytes(
      handle,
      encoded_bytes,
      length,
      option,
    );
  }

  late final _xue_hua_rapid_ocr_detect_encoded_bytesPtr =
      _lookup<
        ffi.NativeFunction<
          ffi.Pointer<C_OcrResult> Function(
            OcrEngineHandle,
            ffi.Pointer<ffi.Uint8>,
            ffi.Size,
            ffi.Pointer<OcrDetectOption>,
          )
        >
      >('xue_hua_rapid_ocr_detect_encoded_bytes');
  late final _xue_hua_rapid_ocr_detect_encoded_bytes =
      _xue_hua_rapid_ocr_detect_encoded_bytesPtr
          .asFunction<
            ffi.Pointer<C_OcrResult> Function(
              OcrEngineHandle,
              ffi.Pointer<ffi.Uint8>,
              int,
              ffi.Pointer<OcrDetectOption>,
            )
          >();

  ffi.Pointer<C_OcrResult> xue_hua_rapid_ocr_detect_raw_pixels(
    OcrEngineHandle handle,
    ffi.Pointer<ffi.Uint8> raw_bytes,
    int width,
    int height,
    int stride,
    int pixel_format,
    ffi.Pointer<OcrDetectOption> option,
  ) {
    return _xue_hua_rapid_ocr_detect_raw_pixels(
      handle,
      raw_bytes,
      width,
      height,
      stride,
      pixel_format,
      option,
    );
  }

  late final _xue_hua_rapid_ocr_detect_raw_pixelsPtr =
      _lookup<
        ffi.NativeFunction<
          ffi.Pointer<C_OcrResult> Function(
            OcrEngineHandle,
            ffi.Pointer<ffi.Uint8>,
            ffi.Int32,
            ffi.Int32,
            ffi.Int32,
            ffi.Int32,
            ffi.Pointer<OcrDetectOption>,
          )
        >
      >('xue_hua_rapid_ocr_detect_raw_pixels');
  late final _xue_hua_rapid_ocr_detect_raw_pixels =
      _xue_hua_rapid_ocr_detect_raw_pixelsPtr
          .asFunction<
            ffi.Pointer<C_OcrResult> Function(
              OcrEngineHandle,
              ffi.Pointer<ffi.Uint8>,
              int,
              int,
              int,
              int,
              ffi.Pointer<OcrDetectOption>,
            )
          >();

  void xue_hua_rapid_ocr_free_result(ffi.Pointer<C_OcrResult> result) {
    return _xue_hua_rapid_ocr_free_result(result);
  }

  late final _xue_hua_rapid_ocr_free_resultPtr =
      _lookup<ffi.NativeFunction<ffi.Void Function(ffi.Pointer<C_OcrResult>)>>(
        'xue_hua_rapid_ocr_free_result',
      );
  late final _xue_hua_rapid_ocr_free_result = _xue_hua_rapid_ocr_free_resultPtr
      .asFunction<void Function(ffi.Pointer<C_OcrResult>)>();

  ffi.Pointer<ffi.Char> xue_hua_rapid_ocr_version() {
    return _xue_hua_rapid_ocr_version();
  }

  late final _xue_hua_rapid_ocr_versionPtr =
      _lookup<ffi.NativeFunction<ffi.Pointer<ffi.Char> Function()>>(
        'xue_hua_rapid_ocr_version',
      );
  late final _xue_hua_rapid_ocr_version = _xue_hua_rapid_ocr_versionPtr
      .asFunction<ffi.Pointer<ffi.Char> Function()>();
}
