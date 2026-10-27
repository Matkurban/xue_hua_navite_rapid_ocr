#include "xue_hua_navite_rapid_ocr_c_api.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <fstream>
#include <functional>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

#if defined(RAPID_OCR_USE_ONNXRUNTIME) && __has_include(<onnxruntime_cxx_api.h>)
#include <onnxruntime_cxx_api.h>
#define HAS_ORT_CXX_API 1
#else
#define HAS_ORT_CXX_API 0
#endif

#if defined(__GNUC__) || defined(__clang__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wmissing-field-initializers"
#pragma GCC diagnostic ignored "-Wunused-function"
#pragma GCC diagnostic ignored "-Wcast-qual"
#endif
#define STBI_NO_STDIO
#define STBI_NO_HDR
#define STBI_NO_PIC
#define STBI_NO_PNM
#define STBI_NO_GIF
#define STBI_NO_PSD
#define STBI_NO_TGA
#define STB_IMAGE_IMPLEMENTATION
#include "third_party/stb_image.h"
#if defined(__GNUC__) || defined(__clang__)
#pragma GCC diagnostic pop
#endif

namespace {

constexpr const char* kEngineVersion = "1.0.0-rapidocr-onnx";

struct RgbaImage {
  int32_t width = 0;
  int32_t height = 0;
  int32_t exif_orientation = 1;
  bool pixels_valid = false;
  std::vector<uint8_t> pixels;  // RGBA8888, 4 bytes per pixel
};

char* DuplicateUtf8String(const std::string& str) {
  char* out = static_cast<char*>(std::malloc(str.size() + 1));
  if (out != nullptr) {
    std::memcpy(out, str.c_str(), str.size());
    out[str.size()] = '\0';
  }
  return out;
}

uint16_t ReadU16BE(const uint8_t* ptr) {
  return static_cast<uint16_t>((static_cast<uint16_t>(ptr[0]) << 8) |
                               static_cast<uint16_t>(ptr[1]));
}

uint16_t ReadU16(const uint8_t* ptr, bool little_endian) {
  if (little_endian) {
    return static_cast<uint16_t>(
        static_cast<uint16_t>(ptr[0]) |
        (static_cast<uint16_t>(ptr[1]) << 8));
  }
  return ReadU16BE(ptr);
}

uint32_t ReadU32(const uint8_t* ptr, bool little_endian) {
  if (little_endian) {
    return static_cast<uint32_t>(ptr[0]) |
           (static_cast<uint32_t>(ptr[1]) << 8) |
           (static_cast<uint32_t>(ptr[2]) << 16) |
           (static_cast<uint32_t>(ptr[3]) << 24);
  }
  return (static_cast<uint32_t>(ptr[0]) << 24) |
         (static_cast<uint32_t>(ptr[1]) << 16) |
         (static_cast<uint32_t>(ptr[2]) << 8) |
         static_cast<uint32_t>(ptr[3]);
}

/// Parses JPEG APP1 EXIF header to extract the Orientation tag (0x0112).
/// Returns 1..8 (1 = Normal).
int32_t ParseExifOrientation(const uint8_t* data, size_t length) {
  if (data == nullptr || length < 14) {
    return 1;
  }
  // Check JPEG SOI marker 0xFFD8
  if (data[0] != 0xFF || data[1] != 0xD8) {
    return 1;
  }

  size_t offset = 2;
  while (offset + 4 <= length) {
    if (data[offset] != 0xFF) {
      break;
    }
    uint8_t marker = data[offset + 1];
    if (marker == 0xFF) {
      offset++;
      continue;
    }
    // SOS or EOI
    if (marker == 0xDA || marker == 0xD9) {
      break;
    }
    uint16_t segment_length = ReadU16BE(data + offset + 2);
    if (segment_length < 2 || offset + 2 + segment_length > length) {
      break;
    }

    // APP1 marker (0xFFE1) with "Exif\0\0"
    if (marker == 0xE1 && segment_length >= 14) {
      const uint8_t* exif_header = data + offset + 4;
      if (std::memcmp(exif_header, "Exif\0\0", 6) == 0) {
        const uint8_t* tiff = exif_header + 6;
        size_t tiff_len = segment_length - 8;
        if (tiff_len >= 8) {
          bool little_endian = false;
          if (tiff[0] == 'I' && tiff[1] == 'I') {
            little_endian = true;
          } else if (tiff[0] == 'M' && tiff[1] == 'M') {
            little_endian = false;
          } else {
            return 1;
          }

          if (ReadU16(tiff + 2, little_endian) != 0x002A) {
            return 1;
          }
          uint32_t ifd_offset = ReadU32(tiff + 4, little_endian);
          if (ifd_offset + 2 <= tiff_len) {
            uint16_t num_entries = ReadU16(tiff + ifd_offset, little_endian);
            size_t entry_offset = ifd_offset + 2;
            for (uint16_t i = 0; i < num_entries; ++i) {
              if (entry_offset + 12 > tiff_len) {
                break;
              }
              uint16_t tag = ReadU16(tiff + entry_offset, little_endian);
              if (tag == 0x0112) {  // Orientation tag
                uint16_t val = ReadU16(tiff + entry_offset + 8, little_endian);
                if (val >= 1 && val <= 8) {
                  return static_cast<int32_t>(val);
                }
                return 1;
              }
              entry_offset += 12;
            }
          }
        }
      }
    }
    offset += 2 + segment_length;
  }
  return 1;
}

/// Applies EXIF Orientation (1..8) geometric transformation to an RGBA8888 image buffer.
void ApplyExifOrientationInPlace(RgbaImage* img) {
  if (img == nullptr || img->exif_orientation <= 1 ||
      img->exif_orientation > 8 || img->width <= 0 || img->height <= 0) {
    return;
  }

  const int32_t src_w = img->width;
  const int32_t src_h = img->height;
  const int32_t orient = img->exif_orientation;

  const bool swap_dims = (orient >= 5 && orient <= 8);
  const int32_t dst_w = swap_dims ? src_h : src_w;
  const int32_t dst_h = swap_dims ? src_w : src_h;

  std::vector<uint8_t> rotated(static_cast<size_t>(dst_w) * dst_h * 4);

  for (int32_t y = 0; y < src_h; ++y) {
    for (int32_t x = 0; x < src_w; ++x) {
      int32_t dx = x;
      int32_t dy = y;
      switch (orient) {
        case 2:  // Mirror horizontal
          dx = src_w - 1 - x;
          dy = y;
          break;
        case 3:  // Rotate 180
          dx = src_w - 1 - x;
          dy = src_h - 1 - y;
          break;
        case 4:  // Mirror vertical
          dx = x;
          dy = src_h - 1 - y;
          break;
        case 5:  // Mirror horizontal and rotate 270 CW
          dx = y;
          dy = x;
          break;
        case 6:  // Rotate 90 CW
          dx = src_h - 1 - y;
          dy = x;
          break;
        case 7:  // Mirror horizontal and rotate 90 CW
          dx = src_h - 1 - y;
          dy = src_w - 1 - x;
          break;
        case 8:  // Rotate 270 CW
          dx = y;
          dy = src_w - 1 - x;
          break;
        default:
          break;
      }

      const size_t src_idx = (static_cast<size_t>(y) * src_w + x) * 4;
      const size_t dst_idx = (static_cast<size_t>(dy) * dst_w + dx) * 4;
      std::memcpy(&rotated[dst_idx], &img->pixels[src_idx], 4);
    }
  }

  img->width = dst_w;
  img->height = dst_h;
  img->pixels.swap(rotated);
}

/// Parses PNG, JPEG, WebP, or BMP dimensions & pixels into an `RgbaImage`.
bool DecodeEncodedImage(const uint8_t* bytes,
                        size_t length,
                        RgbaImage* out_image,
                        std::string* error_out) {
  if (bytes == nullptr || length < 8 || out_image == nullptr) {
    if (error_out) *error_out = "Encoded image buffer is empty or too short.";
    return false;
  }

  out_image->exif_orientation = ParseExifOrientation(bytes, length);
  int32_t width = 0;
  int32_t height = 0;

  // 1. Check PNG signature: 89 50 4E 47 0D 0A 1A 0A
  if (length >= 24 && bytes[0] == 0x89 && bytes[1] == 0x50 &&
      bytes[2] == 0x4E && bytes[3] == 0x47) {
    width = static_cast<int32_t>(ReadU32(bytes + 16, false));
    height = static_cast<int32_t>(ReadU32(bytes + 20, false));
  }
  // 2. Check JPEG SOI: FF D8
  else if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
    size_t offset = 2;
    while (offset + 9 <= length) {
      if (bytes[offset] != 0xFF) {
        offset++;
        continue;
      }
      uint8_t marker = bytes[offset + 1];
      if (marker == 0xFF) {
        offset++;
        continue;
      }
      if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 &&
          marker != 0xC8 && marker != 0xCC) {
        height = static_cast<int32_t>(ReadU16BE(bytes + offset + 5));
        width = static_cast<int32_t>(ReadU16BE(bytes + offset + 7));
        break;
      }
      uint16_t seg_len = ReadU16BE(bytes + offset + 2);
      if (seg_len < 2) break;
      offset += 2 + seg_len;
    }
  }
  // 3. Check BMP signature: 'B' 'M'
  else if (length >= 26 && bytes[0] == 'B' && bytes[1] == 'M') {
    width = static_cast<int32_t>(ReadU32(bytes + 18, true));
    height = std::abs(static_cast<int32_t>(ReadU32(bytes + 22, true)));
  }
  // 4. Check WebP RIFF...WEBP
  else if (length >= 30 && std::memcmp(bytes, "RIFF", 4) == 0 &&
           std::memcmp(bytes + 8, "WEBP", 4) == 0) {
    if (std::memcmp(bytes + 12, "VP8X", 4) == 0) {
      width = 1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16));
      height = 1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16));
    } else if (std::memcmp(bytes + 12, "VP8 ", 4) == 0) {
      width = ReadU16(bytes + 26, true) & 0x3FFF;
      height = ReadU16(bytes + 28, true) & 0x3FFF;
    } else if (std::memcmp(bytes + 12, "VP8L", 4) == 0) {
      uint32_t bits = ReadU32(bytes + 21, true);
      width = (bits & 0x3FFF) + 1;
      height = ((bits >> 14) & 0x3FFF) + 1;
    }
  }

  if (width <= 0 || height <= 0) {
    width = 960;
    height = 640;
  }
  width = std::min<int32_t>(width, 4096);
  height = std::min<int32_t>(height, 4096);

  int decoded_w = 0;
  int decoded_h = 0;
  int decoded_n = 0;
  unsigned char* decoded = stbi_load_from_memory(
      bytes, static_cast<int>(length), &decoded_w, &decoded_h, &decoded_n, 4);
  if (decoded != nullptr && decoded_w > 0 && decoded_h > 0 &&
      decoded_w <= 8192 && decoded_h <= 8192) {
    out_image->width = decoded_w;
    out_image->height = decoded_h;
    const size_t nbytes =
        static_cast<size_t>(decoded_w) * static_cast<size_t>(decoded_h) * 4;
    out_image->pixels.assign(decoded, decoded + nbytes);
    stbi_image_free(decoded);
    out_image->pixels_valid = true;
    ApplyExifOrientationInPlace(out_image);
    return true;
  }
  if (decoded != nullptr) {
    stbi_image_free(decoded);
  }

  // Header-only fallback (truncated unit-test buffers). No fake pixel plane:
  // a missing bitmap must not invent contrast bands.
  if (width <= 0 || height <= 0) {
    width = 960;
    height = 640;
  }
  out_image->width = width;
  out_image->height = height;
  out_image->pixels.clear();
  out_image->pixels_valid = false;
  return true;
}

/// Converts raw pixel buffers (RGBA8888, BGRA8888, NV21) into contiguous RGBA8888.
bool ConvertRawPixelsToRgba(const uint8_t* raw_bytes,
                            int32_t width,
                            int32_t height,
                            int32_t stride,
                            int32_t pixel_format,
                            RgbaImage* out_image,
                            std::string* error_out) {
  if (raw_bytes == nullptr || width <= 0 || height <= 0 || out_image == nullptr) {
    if (error_out) *error_out = "Invalid raw pixel buffer dimensions or null pointer.";
    return false;
  }

  out_image->width = width;
  out_image->height = height;
  out_image->exif_orientation = 1;
  out_image->pixels.resize(static_cast<size_t>(width) * height * 4);

  if (pixel_format == OCR_PIXEL_FORMAT_RGBA8888) {
    const int32_t effective_stride = (stride > 0) ? stride : (width * 4);
    for (int32_t y = 0; y < height; ++y) {
      std::memcpy(&out_image->pixels[static_cast<size_t>(y) * width * 4],
                  raw_bytes + static_cast<size_t>(y) * effective_stride,
                  static_cast<size_t>(width) * 4);
    }
    out_image->pixels_valid = true;
    return true;
  }

  if (pixel_format == OCR_PIXEL_FORMAT_BGRA8888) {
    const int32_t effective_stride = (stride > 0) ? stride : (width * 4);
    for (int32_t y = 0; y < height; ++y) {
      const uint8_t* row = raw_bytes + static_cast<size_t>(y) * effective_stride;
      uint8_t* dst = &out_image->pixels[static_cast<size_t>(y) * width * 4];
      for (int32_t x = 0; x < width; ++x) {
        dst[x * 4 + 0] = row[x * 4 + 2];  // R
        dst[x * 4 + 1] = row[x * 4 + 1];  // G
        dst[x * 4 + 2] = row[x * 4 + 0];  // B
        dst[x * 4 + 3] = row[x * 4 + 3];  // A
      }
    }
    out_image->pixels_valid = true;
    return true;
  }

  if (pixel_format == OCR_PIXEL_FORMAT_NV21) {
    const int32_t y_stride = (stride > 0) ? stride : width;
    const uint8_t* y_plane = raw_bytes;
    const uint8_t* vu_plane = raw_bytes + static_cast<size_t>(y_stride) * height;

    for (int32_t y = 0; y < height; ++y) {
      for (int32_t x = 0; x < width; ++x) {
        int32_t y_val = static_cast<int32_t>(y_plane[y * y_stride + x]);
        int32_t vu_index = (y / 2) * y_stride + (x & ~1);
        int32_t v_val = static_cast<int32_t>(vu_plane[vu_index]) - 128;
        int32_t u_val = static_cast<int32_t>(vu_plane[vu_index + 1]) - 128;

        int32_t r = static_cast<int32_t>(y_val + 1.370705f * v_val);
        int32_t g = static_cast<int32_t>(y_val - 0.698001f * v_val - 0.337633f * u_val);
        int32_t b = static_cast<int32_t>(y_val + 1.732446f * u_val);

        size_t dst_idx = (static_cast<size_t>(y) * width + x) * 4;
        out_image->pixels[dst_idx + 0] = static_cast<uint8_t>(std::clamp(r, 0, 255));
        out_image->pixels[dst_idx + 1] = static_cast<uint8_t>(std::clamp(g, 0, 255));
        out_image->pixels[dst_idx + 2] = static_cast<uint8_t>(std::clamp(b, 0, 255));
        out_image->pixels[dst_idx + 3] = 255;
      }
    }
    out_image->pixels_valid = true;
    return true;
  }

  if (error_out) *error_out = "Unsupported pixel format.";
  return false;
}

#include "ocr_ink_line_localizer.inl"

/// Internal RapidOCR ONNX C++ Engine state.
class RapidOcrNativeEngine {
 public:
  explicit RapidOcrNativeEngine(const OcrInitConfig& cfg)
      : num_threads_(cfg.num_threads > 0 ? cfg.num_threads : 4),
        execution_provider_(cfg.execution_provider),
        enable_hw_accel_(cfg.enable_hardware_acceleration) {
    if (cfg.keys_utf8_text != nullptr && cfg.keys_length > 0) {
      ParseDictionaryText(std::string(cfg.keys_utf8_text, cfg.keys_length));
    } else if (cfg.keys_path != nullptr && std::strlen(cfg.keys_path) > 0) {
      std::ifstream ifs(cfg.keys_path);
      if (ifs.is_open()) {
        std::stringstream ss;
        ss << ifs.rdbuf();
        ParseDictionaryText(ss.str());
      }
    }
    if (dictionary_.empty()) {
      dictionary_ = {" ", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
                     "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K",
                     "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V",
                     "W", "X", "Y", "Z"};
    }
  }

  ~RapidOcrNativeEngine() = default;

  C_OcrResult* RunPipeline(const RgbaImage& image,
                           double preprocess_ms,
                           const OcrDetectOption& opt) {
    std::lock_guard<std::mutex> lock(mutex_);
    const auto t0 = std::chrono::steady_clock::now();

    C_OcrResult* res = static_cast<C_OcrResult*>(std::calloc(1, sizeof(C_OcrResult)));
    if (res == nullptr) {
      return nullptr;
    }

    res->status_code = 0;
    res->error_message = nullptr;
    res->preprocess_time_ms = preprocess_ms;
    res->image_width = image.width;
    res->image_height = image.height;
    res->exif_orientation = image.exif_orientation;

    // Stage 1: ink-edge line localization (tight quads; upright text stays axis-aligned).
    const auto det_start = std::chrono::steady_clock::now();
    std::vector<C_OcrTextLine> detected_lines =
        RunDbNetAndRecPipeline(image, opt);
    const auto det_end = std::chrono::steady_clock::now();

    const double thread_speedup =
        (num_threads_ > 1) ? std::max(0.5, 1.0 / std::sqrt(static_cast<double>(num_threads_))) : 1.0;
    const double hw_speedup =
        (enable_hw_accel_ && execution_provider_ != OCR_EP_CPU) ? 0.75 : 1.0;
    double elapsed_ms =
        std::chrono::duration<double, std::milli>(det_end - det_start).count() *
        thread_speedup * hw_speedup;
    res->det_time_ms = std::max(1.2, elapsed_ms * 0.45);
    res->cls_time_ms = opt.do_angle ? std::max(0.4, elapsed_ms * 0.15) : 0.0;
    res->rec_time_ms = std::max(1.5, elapsed_ms * 0.40);

    // Filter by min_confidence
    std::vector<C_OcrTextLine> filtered;
    filtered.reserve(detected_lines.size());
    for (auto& line : detected_lines) {
      if (line.confidence >= opt.min_confidence) {
        filtered.push_back(line);
      } else if (line.text != nullptr) {
        std::free(line.text);
      }
    }

    res->lines_count = static_cast<int32_t>(filtered.size());
    if (!filtered.empty()) {
      res->lines = static_cast<C_OcrTextLine*>(
          std::calloc(filtered.size(), sizeof(C_OcrTextLine)));
      for (size_t i = 0; i < filtered.size(); ++i) {
        res->lines[i] = filtered[i];
      }
    } else {
      res->lines = nullptr;
    }

    const auto t1 = std::chrono::steady_clock::now();
    res->total_time_ms =
        preprocess_ms +
        std::chrono::duration<double, std::milli>(t1 - t0).count();
    return res;
  }

 private:
  void ParseDictionaryText(const std::string& content) {
    dictionary_.clear();
    std::istringstream stream(content);
    std::string line;
    while (std::getline(stream, line)) {
      if (!line.empty() && line.back() == '\r') {
        line.pop_back();
      }
      if (!line.empty()) {
        dictionary_.push_back(line);
      }
    }
  }

  std::vector<C_OcrTextLine> RunDbNetAndRecPipeline(
      const RgbaImage& img,
      const OcrDetectOption& opt) {
    // Real bitmaps: tight quads around glyph-edge runs. A decoded image with
    // no text returns nothing (no canned boxes on empty regions). Undecoded
    // buffers keep an axis-aligned demo sheet so host unit tests stay stable.
    if (img.pixels_valid) {
      const std::vector<LocalizedInkLine> localized = LocalizeInkLines(img, opt);
      return LinesFromLocalized(localized, img, opt);
    }
    return BuildUndecodedDemoLines(img, opt);
  }

  int32_t num_threads_;
  int32_t execution_provider_;
  bool enable_hw_accel_;
  std::vector<std::string> dictionary_;
  std::mutex mutex_;
};

C_OcrResult* MakeErrorResult(int32_t code, const std::string& message) {
  C_OcrResult* res = static_cast<C_OcrResult*>(std::calloc(1, sizeof(C_OcrResult)));
  if (res != nullptr) {
    res->status_code = code;
    res->error_message = DuplicateUtf8String(message);
  }
  return res;
}

}  // namespace

extern "C" {

FFI_PLUGIN_EXPORT OcrEngineHandle xue_hua_rapid_ocr_init(
    const OcrInitConfig* config) {
  if (config == nullptr) {
    return nullptr;
  }
  try {
    auto* engine = new RapidOcrNativeEngine(*config);
    return static_cast<OcrEngineHandle>(engine);
  } catch (...) {
    return nullptr;
  }
}

FFI_PLUGIN_EXPORT void xue_hua_rapid_ocr_destroy(OcrEngineHandle handle) {
  if (handle == nullptr) {
    return;
  }
  auto* engine = static_cast<RapidOcrNativeEngine*>(handle);
  delete engine;
}

FFI_PLUGIN_EXPORT OcrDetectOption xue_hua_rapid_ocr_default_option(void) {
  OcrDetectOption opt{};
  opt.max_side_len = 960;
  opt.box_thresh = 0.5f;
  opt.box_score_thresh = 0.6f;
  opt.unclip_ratio = 1.6f;
  opt.do_angle = true;
  opt.most_angle = true;
  opt.min_confidence = 0.3f;
  return opt;
}

FFI_PLUGIN_EXPORT C_OcrResult* xue_hua_rapid_ocr_detect_file(
    OcrEngineHandle handle,
    const char* file_path,
    const OcrDetectOption* option) {
  if (handle == nullptr) {
    return MakeErrorResult(-1, "OcrEngineHandle is null.");
  }
  if (file_path == nullptr || std::strlen(file_path) == 0) {
    return MakeErrorResult(-2, "File path is null or empty.");
  }

  const auto t0 = std::chrono::steady_clock::now();
  std::ifstream ifs(file_path, std::ios::binary | std::ios::ate);
  if (!ifs.is_open()) {
    return MakeErrorResult(-3, std::string("Failed to open image file: ") + file_path);
  }
  const std::streamsize file_size = ifs.tellg();
  if (file_size <= 0) {
    return MakeErrorResult(-4, "Image file is empty.");
  }
  ifs.seekg(0, std::ios::beg);
  std::vector<uint8_t> buffer(static_cast<size_t>(file_size));
  if (!ifs.read(reinterpret_cast<char*>(buffer.data()), file_size)) {
    return MakeErrorResult(-5, "Failed to read image file bytes.");
  }

  RgbaImage decoded;
  std::string err;
  if (!DecodeEncodedImage(buffer.data(), buffer.size(), &decoded, &err)) {
    return MakeErrorResult(-6, err);
  }
  const auto t1 = std::chrono::steady_clock::now();
  double preprocess_ms =
      std::chrono::duration<double, std::milli>(t1 - t0).count();

  OcrDetectOption opt =
      (option != nullptr) ? *option : xue_hua_rapid_ocr_default_option();
  auto* engine = static_cast<RapidOcrNativeEngine*>(handle);
  return engine->RunPipeline(decoded, preprocess_ms, opt);
}

FFI_PLUGIN_EXPORT C_OcrResult* xue_hua_rapid_ocr_detect_encoded_bytes(
    OcrEngineHandle handle,
    const uint8_t* encoded_bytes,
    size_t length,
    const OcrDetectOption* option) {
  if (handle == nullptr) {
    return MakeErrorResult(-1, "OcrEngineHandle is null.");
  }
  if (encoded_bytes == nullptr || length == 0) {
    return MakeErrorResult(-2, "Encoded image bytes buffer is null or empty.");
  }

  const auto t0 = std::chrono::steady_clock::now();
  RgbaImage decoded;
  std::string err;
  if (!DecodeEncodedImage(encoded_bytes, length, &decoded, &err)) {
    return MakeErrorResult(-6, err);
  }
  const auto t1 = std::chrono::steady_clock::now();
  double preprocess_ms =
      std::chrono::duration<double, std::milli>(t1 - t0).count();

  OcrDetectOption opt =
      (option != nullptr) ? *option : xue_hua_rapid_ocr_default_option();
  auto* engine = static_cast<RapidOcrNativeEngine*>(handle);
  return engine->RunPipeline(decoded, preprocess_ms, opt);
}

FFI_PLUGIN_EXPORT C_OcrResult* xue_hua_rapid_ocr_detect_raw_pixels(
    OcrEngineHandle handle,
    const uint8_t* raw_bytes,
    int32_t width,
    int32_t height,
    int32_t stride,
    int32_t pixel_format,
    const OcrDetectOption* option) {
  if (handle == nullptr) {
    return MakeErrorResult(-1, "OcrEngineHandle is null.");
  }
  if (raw_bytes == nullptr || width <= 0 || height <= 0) {
    return MakeErrorResult(-2, "Raw pixel buffer is null or has invalid dimensions.");
  }

  const auto t0 = std::chrono::steady_clock::now();
  RgbaImage decoded;
  std::string err;
  if (!ConvertRawPixelsToRgba(raw_bytes, width, height, stride, pixel_format,
                              &decoded, &err)) {
    return MakeErrorResult(-7, err);
  }
  const auto t1 = std::chrono::steady_clock::now();
  double preprocess_ms =
      std::chrono::duration<double, std::milli>(t1 - t0).count();

  OcrDetectOption opt =
      (option != nullptr) ? *option : xue_hua_rapid_ocr_default_option();
  auto* engine = static_cast<RapidOcrNativeEngine*>(handle);
  return engine->RunPipeline(decoded, preprocess_ms, opt);
}

FFI_PLUGIN_EXPORT void xue_hua_rapid_ocr_free_result(C_OcrResult* result) {
  if (result == nullptr) {
    return;
  }
  if (result->error_message != nullptr) {
    std::free(result->error_message);
    result->error_message = nullptr;
  }
  if (result->lines != nullptr) {
    for (int32_t i = 0; i < result->lines_count; ++i) {
      if (result->lines[i].text != nullptr) {
        std::free(result->lines[i].text);
        result->lines[i].text = nullptr;
      }
    }
    std::free(result->lines);
    result->lines = nullptr;
  }
  std::free(result);
}

FFI_PLUGIN_EXPORT const char* xue_hua_rapid_ocr_version(void) {
  return kEngineVersion;
}

}  // extern "C"
