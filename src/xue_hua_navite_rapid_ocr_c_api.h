#ifndef XUE_HUA_NAVITE_RAPID_OCR_C_API_H_
#define XUE_HUA_NAVITE_RAPID_OCR_C_API_H_

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle representing an initialized RapidOCR engine instance.
typedef void* OcrEngineHandle;

/// Execution provider hardware acceleration types.
typedef enum OcrExecutionProviderType {
  OCR_EP_AUTO = 0,
  OCR_EP_CPU = 1,
  OCR_EP_COREML = 2,
  OCR_EP_NNAPI = 3,
  OCR_EP_DIRECTML = 4,
  OCR_EP_WEBGPU = 5,
  OCR_EP_WASM = 6
} OcrExecutionProviderType;

/// Raw pixel buffer memory layout formats.
typedef enum OcrPixelFormatType {
  OCR_PIXEL_FORMAT_RGBA8888 = 0,
  OCR_PIXEL_FORMAT_BGRA8888 = 1,
  OCR_PIXEL_FORMAT_NV21 = 2
} OcrPixelFormatType;

/// Configuration for initializing a RapidOCR engine instance.
/// Supports both filesystem paths and in-memory asset buffers for det/cls/rec models and dictionary keys.
typedef struct OcrInitConfig {
  /// Filesystem path to DBNet detection ONNX model (`det.onnx`), or NULL if using buffer.
  const char* det_model_path;
  const uint8_t* det_model_bytes;
  size_t det_model_length;

  /// Filesystem path to AngleNet orientation classifier ONNX model (`cls.onnx`), or NULL if using buffer.
  const char* cls_model_path;
  const uint8_t* cls_model_bytes;
  size_t cls_model_length;

  /// Filesystem path to CrnnNet/SVTR recognition ONNX model (`rec.onnx`), or NULL if using buffer.
  const char* rec_model_path;
  const uint8_t* rec_model_bytes;
  size_t rec_model_length;

  /// Filesystem path to character dictionary (`keys.txt`), or NULL if using in-memory UTF-8 text.
  const char* keys_path;
  const char* keys_utf8_text;
  size_t keys_length;

  /// Number of CPU intra-op threads (default: 4).
  int32_t num_threads;

  /// Hardware execution provider preference (0 = Auto, 1 = CPU, 2 = CoreML, 3 = NNAPI, 4 = DirectML).
  int32_t execution_provider;

  /// Enable hardware acceleration when supported by the target OS.
  bool enable_hardware_acceleration;
} OcrInitConfig;

/// Fine-grained inference parameters for DBNet detection, AngleNet classification, and CrnnNet recognition.
typedef struct OcrDetectOption {
  /// Maximum image side length before DBNet detection downscaling (default: 960).
  int32_t max_side_len;

  /// Binary map threshold for DBNet probability map (default: 0.5f).
  float box_thresh;

  /// Minimum polygon score threshold for detected text boxes (default: 0.6f).
  float box_score_thresh;

  /// Polygon Vatti unclip expansion ratio (default: 1.6f).
  float unclip_ratio;

  /// Whether to run the 180-degree text angle classification stage (default: true).
  bool do_angle;

  /// Whether to vote for the dominant angle across all text lines (default: true).
  bool most_angle;

  /// Minimum character recognition confidence filter (default: 0.3f).
  float min_confidence;
} OcrDetectOption;

/// 2D floating-point coordinate in corrected image pixel space.
typedef struct C_OcrPoint {
  float x;
  float y;
} C_OcrPoint;

/// Axis-aligned bounding rectangle in corrected image pixel space.
typedef struct C_OcrRect {
  float left;
  float top;
  float width;
  float height;
} C_OcrRect;

/// Single recognized text line with rotated quadrilateral geometry and timing metrics.
typedef struct C_OcrTextLine {
  /// UTF-8 null-terminated recognized string.
  char* text;

  /// Recognition confidence score in [0.0, 1.0].
  float confidence;

  /// 4 clockwise rotated vertices: [top-left, top-right, bottom-right, bottom-left].
  C_OcrPoint corner_points[4];

  /// Axis-aligned bounding rectangle enclosing the 4 corner points.
  C_OcrRect bounding_box;

  /// Rotation angle in degrees (e.g., 0.0, 180.0, or geometric tilt angle).
  float angle;

  /// Angle classification confidence score in [0.0, 1.0].
  float angle_confidence;

  /// Detection box score in [0.0, 1.0].
  float box_score;
} C_OcrTextLine;

/// Complete OCR recognition result returned by the C++ engine.
typedef struct C_OcrResult {
  /// Status code (0 = success, non-zero = error code).
  int32_t status_code;

  /// Optional UTF-8 error message if status_code != 0 (NULL on success).
  char* error_message;

  /// Total pipeline elapsed time in milliseconds.
  double total_time_ms;

  /// Image decoding and EXIF orientation correction time in milliseconds.
  double preprocess_time_ms;

  /// DBNet text detection stage elapsed time in milliseconds.
  double det_time_ms;

  /// AngleNet direction classification stage elapsed time in milliseconds.
  double cls_time_ms;

  /// CrnnNet/SVTR recognition stage elapsed time in milliseconds.
  double rec_time_ms;

  /// Image width after EXIF orientation normalization.
  int32_t image_width;

  /// Image height after EXIF orientation normalization.
  int32_t image_height;

  /// Detected EXIF orientation tag (1..8, default 1 = Normal).
  int32_t exif_orientation;

  /// Number of recognized text lines.
  int32_t lines_count;

  /// Heap-allocated array of recognized text lines (`lines_count` elements).
  C_OcrTextLine* lines;
} C_OcrResult;

/// Initializes a new thread-safe RapidOCR engine instance.
/// Returns NULL if initialization fails.
FFI_PLUGIN_EXPORT OcrEngineHandle xue_hua_rapid_ocr_init(
    const OcrInitConfig* config);

/// Destroys a RapidOCR engine instance and releases all associated ONNX sessions and memory.
FFI_PLUGIN_EXPORT void xue_hua_rapid_ocr_destroy(OcrEngineHandle handle);

/// Returns the default `OcrDetectOption` values.
FFI_PLUGIN_EXPORT OcrDetectOption xue_hua_rapid_ocr_default_option(void);

/// Runs OCR on a local image file path (PNG/JPEG/WebP/BMP), automatically applying EXIF orientation correction.
FFI_PLUGIN_EXPORT C_OcrResult* xue_hua_rapid_ocr_detect_file(
    OcrEngineHandle handle,
    const char* file_path,
    const OcrDetectOption* option);

/// Runs OCR on in-memory encoded image bytes (PNG/JPEG/WebP/BMP), automatically applying EXIF orientation correction.
FFI_PLUGIN_EXPORT C_OcrResult* xue_hua_rapid_ocr_detect_encoded_bytes(
    OcrEngineHandle handle,
    const uint8_t* encoded_bytes,
    size_t length,
    const OcrDetectOption* option);

/// Runs OCR on a zero-copy raw pixel buffer (RGBA8888, BGRA8888, or NV21).
FFI_PLUGIN_EXPORT C_OcrResult* xue_hua_rapid_ocr_detect_raw_pixels(
    OcrEngineHandle handle,
    const uint8_t* raw_bytes,
    int32_t width,
    int32_t height,
    int32_t stride,
    int32_t pixel_format,
    const OcrDetectOption* option);

/// Frees a `C_OcrResult` structure and all nested heap allocations (`lines`, `text`, `error_message`).
FFI_PLUGIN_EXPORT void xue_hua_rapid_ocr_free_result(C_OcrResult* result);

/// Returns the native engine version string.
FFI_PLUGIN_EXPORT const char* xue_hua_rapid_ocr_version(void);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // XUE_HUA_NAVITE_RAPID_OCR_C_API_H_
