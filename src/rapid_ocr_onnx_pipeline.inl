// RapidOCR v3.10.0 PP-OCRv4 mobile pipeline: DBNet det -> AngleNet cls -> CTC rec.
// Included inside the engine translation unit. ONNX Runtime is loaded at runtime.

struct Vec2 {
  float x = 0;
  float y = 0;
};

struct RotatedRect {
  float cx = 0;
  float cy = 0;
  float width = 0;
  float height = 0;
  float angle_deg = 0;
  Vec2 corners[4]{};
  bool ok = false;
};

float Cross(Vec2 o, Vec2 a, Vec2 b) {
  return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
}

float Dist(Vec2 a, Vec2 b) {
  const float dx = a.x - b.x;
  const float dy = a.y - b.y;
  return std::sqrt(dx * dx + dy * dy);
}

std::vector<Vec2> ConvexHull(std::vector<Vec2> points) {
  std::sort(points.begin(), points.end(), [](Vec2 a, Vec2 b) {
    if (a.x != b.x) return a.x < b.x;
    return a.y < b.y;
  });
  points.erase(std::unique(points.begin(), points.end(),
                            [](Vec2 a, Vec2 b) {
                              return a.x == b.x && a.y == b.y;
                            }),
               points.end());
  const int n = static_cast<int>(points.size());
  if (n < 3) return points;
  std::vector<Vec2> hull(static_cast<size_t>(n * 2));
  int k = 0;
  for (int i = 0; i < n; ++i) {
    while (k >= 2 && Cross(hull[k - 2], hull[k - 1], points[i]) <= 0) k--;
    hull[k++] = points[i];
  }
  for (int i = n - 2, t = k + 1; i >= 0; --i) {
    while (k >= t && Cross(hull[k - 2], hull[k - 1], points[i]) <= 0) k--;
    hull[k++] = points[i];
  }
  hull.resize(static_cast<size_t>(k - 1));
  return hull;
}

RotatedRect MinAreaRect(const std::vector<Vec2>& hull) {
  RotatedRect best;
  if (hull.size() < 3) return best;
  float best_area = 1e30f;
  const int n = static_cast<int>(hull.size());
  for (int i = 0; i < n; ++i) {
    const Vec2 a = hull[i];
    const Vec2 b = hull[(i + 1) % n];
    const float dx = b.x - a.x;
    const float dy = b.y - a.y;
    const float len = std::sqrt(dx * dx + dy * dy);
    if (len < 1e-3f) continue;
    const float cos_t = dx / len;
    const float sin_t = dy / len;
    float min_x = 1e30f, max_x = -1e30f, min_y = 1e30f, max_y = -1e30f;
    for (const Vec2& p : hull) {
      const float rx = p.x * cos_t + p.y * sin_t;
      const float ry = -p.x * sin_t + p.y * cos_t;
      min_x = std::min(min_x, rx);
      max_x = std::max(max_x, rx);
      min_y = std::min(min_y, ry);
      max_y = std::max(max_y, ry);
    }
    const float rw = max_x - min_x;
    const float rh = max_y - min_y;
    const float area = rw * rh;
    if (area >= best_area || rw < 1.f || rh < 1.f) continue;
    best_area = area;
    const float cx = (min_x + max_x) * 0.5f;
    const float cy = (min_y + max_y) * 0.5f;
    // Inverse rotation: [cos, -sin; sin, cos] applied to (rx, ry).
    auto unrot = [&](float rx, float ry) {
      return Vec2{rx * cos_t - ry * sin_t, rx * sin_t + ry * cos_t};
    };
    best.cx = unrot(cx, cy).x;
    best.cy = unrot(cx, cy).y;
    best.width = rw;
    best.height = rh;
    best.angle_deg = std::atan2(sin_t, cos_t) * 180.f / 3.14159265f;
    const Vec2 local[4] = {
        {min_x, min_y}, {max_x, min_y}, {max_x, max_y}, {min_x, max_y}};
    for (int k = 0; k < 4; ++k) best.corners[k] = unrot(local[k].x, local[k].y);
    best.ok = true;
  }
  return best;
}

void OrderQuad(Vec2 pts[4]) {
  std::sort(pts, pts + 4, [](Vec2 a, Vec2 b) {
    if (a.x != b.x) return a.x < b.x;
    return a.y < b.y;
  });
  Vec2 left[2] = {pts[0], pts[1]};
  Vec2 right[2] = {pts[2], pts[3]};
  if (left[0].y > left[1].y) std::swap(left[0], left[1]);
  if (right[0].y > right[1].y) std::swap(right[0], right[1]);
  pts[0] = left[0];
  pts[1] = right[0];
  pts[2] = right[1];
  pts[3] = left[1];
}

float PolygonMean(const float* bitmap, int width, int height, const Vec2 quad[4]) {
  float min_x = quad[0].x, max_x = quad[0].x, min_y = quad[0].y, max_y = quad[0].y;
  for (int i = 1; i < 4; ++i) {
    min_x = std::min(min_x, quad[i].x);
    max_x = std::max(max_x, quad[i].x);
    min_y = std::min(min_y, quad[i].y);
    max_y = std::max(max_y, quad[i].y);
  }
  const int x0 = std::max(0, static_cast<int>(std::floor(min_x)));
  const int x1 = std::min(width - 1, static_cast<int>(std::ceil(max_x)));
  const int y0 = std::max(0, static_cast<int>(std::floor(min_y)));
  const int y1 = std::min(height - 1, static_cast<int>(std::ceil(max_y)));
  if (x1 < x0 || y1 < y0) return 0.f;
  double sum = 0;
  int count = 0;
  for (int y = y0; y <= y1; ++y) {
    const float fy = static_cast<float>(y) + 0.5f;
    float xs[4];
    int hits = 0;
    for (int e = 0; e < 4; ++e) {
      const Vec2 a = quad[e];
      const Vec2 b = quad[(e + 1) % 4];
      const float y_min = std::min(a.y, b.y);
      const float y_max = std::max(a.y, b.y);
      if (fy < y_min || fy >= y_max || std::fabs(b.y - a.y) < 1e-4f) continue;
      const float t = (fy - a.y) / (b.y - a.y);
      xs[hits++] = a.x + t * (b.x - a.x);
    }
    if (hits < 2) continue;
    std::sort(xs, xs + hits);
    const int xa = std::max(x0, static_cast<int>(std::floor(xs[0])));
    const int xb = std::min(x1, static_cast<int>(std::ceil(xs[hits - 1])));
    for (int x = xa; x <= xb; ++x) {
      sum += bitmap[y * width + x];
      count++;
    }
  }
  if (count == 0) return 0.f;
  return static_cast<float>(sum / count);
}

bool SolveLinear(double m[8][9], double out[8]) {
  for (int col = 0; col < 8; ++col) {
    int pivot = col;
    double best = std::fabs(m[col][col]);
    for (int row = col + 1; row < 8; ++row) {
      const double v = std::fabs(m[row][col]);
      if (v > best) {
        best = v;
        pivot = row;
      }
    }
    if (best < 1e-12) return false;
    if (pivot != col) {
      for (int c = col; c < 9; ++c) std::swap(m[col][c], m[pivot][c]);
    }
    const double div = m[col][col];
    for (int c = col; c < 9; ++c) m[col][c] /= div;
    for (int row = 0; row < 8; ++row) {
      if (row == col) continue;
      const double factor = m[row][col];
      if (factor == 0) continue;
      for (int c = col; c < 9; ++c) m[row][c] -= factor * m[col][c];
    }
  }
  for (int i = 0; i < 8; ++i) out[i] = m[i][8];
  return true;
}

bool HomographyDestToSrc(const Vec2 src[4], int dest_w, int dest_h, double h[9]) {
  const Vec2 dest[4] = {
      {0.f, 0.f},
      {static_cast<float>(dest_w), 0.f},
      {static_cast<float>(dest_w), static_cast<float>(dest_h)},
      {0.f, static_cast<float>(dest_h)},
  };
  double m[8][9] = {};
  for (int i = 0; i < 4; ++i) {
    const double x = dest[i].x;
    const double y = dest[i].y;
    const double u = src[i].x;
    const double v = src[i].y;
    m[i * 2][0] = x;
    m[i * 2][1] = y;
    m[i * 2][2] = 1;
    m[i * 2][6] = -u * x;
    m[i * 2][7] = -u * y;
    m[i * 2][8] = u;
    m[i * 2 + 1][3] = x;
    m[i * 2 + 1][4] = y;
    m[i * 2 + 1][5] = 1;
    m[i * 2 + 1][6] = -v * x;
    m[i * 2 + 1][7] = -v * y;
    m[i * 2 + 1][8] = v;
  }
  double sol[8];
  if (!SolveLinear(m, sol)) return false;
  for (int i = 0; i < 8; ++i) h[i] = sol[i];
  h[8] = 1;
  return true;
}

uint8_t SampleChannel(const uint8_t* rgba, int width, int height, int stride,
                      float x, float y, int channel) {
  x = std::clamp(x, 0.f, static_cast<float>(width - 1));
  y = std::clamp(y, 0.f, static_cast<float>(height - 1));
  const int x0 = static_cast<int>(std::floor(x));
  const int y0 = static_cast<int>(std::floor(y));
  const int x1 = std::min(x0 + 1, width - 1);
  const int y1 = std::min(y0 + 1, height - 1);
  const float fx = x - static_cast<float>(x0);
  const float fy = y - static_cast<float>(y0);
  auto at = [&](int xx, int yy) {
    return static_cast<float>(rgba[static_cast<size_t>(yy) * stride + xx * 4 + channel]);
  };
  const float v = at(x0, y0) * (1 - fx) * (1 - fy) + at(x1, y0) * fx * (1 - fy) +
                  at(x0, y1) * (1 - fx) * fy + at(x1, y1) * fx * fy;
  return static_cast<uint8_t>(std::clamp(v, 0.f, 255.f));
}

struct RgbImage {
  int width = 0;
  int height = 0;
  std::vector<uint8_t> rgb;
};

RgbImage WarpQuad(const uint8_t* rgba, int src_w, int src_h, const Vec2 quad[4]) {
  RgbImage out;
  const int crop_w = std::max(
      1, static_cast<int>(std::round(std::max(Dist(quad[0], quad[1]), Dist(quad[2], quad[3])))));
  const int crop_h = std::max(
      1, static_cast<int>(std::round(std::max(Dist(quad[0], quad[3]), Dist(quad[1], quad[2])))));
  double h[9];
  if (!HomographyDestToSrc(quad, crop_w, crop_h, h)) return out;
  out.width = crop_w;
  out.height = crop_h;
  out.rgb.resize(static_cast<size_t>(crop_w) * crop_h * 3);
  for (int y = 0; y < crop_h; ++y) {
    for (int x = 0; x < crop_w; ++x) {
      const double den = h[6] * x + h[7] * y + h[8];
      const float sx = static_cast<float>((h[0] * x + h[1] * y + h[2]) / den);
      const float sy = static_cast<float>((h[3] * x + h[4] * y + h[5]) / den);
      const size_t dst = (static_cast<size_t>(y) * crop_w + x) * 3;
      out.rgb[dst + 0] = SampleChannel(rgba, src_w, src_h, src_w * 4, sx, sy, 0);
      out.rgb[dst + 1] = SampleChannel(rgba, src_w, src_h, src_w * 4, sx, sy, 1);
      out.rgb[dst + 2] = SampleChannel(rgba, src_w, src_h, src_w * 4, sx, sy, 2);
    }
  }
  if (crop_h * 1.0 / crop_w >= 1.5) {
    RgbImage rotated;
    rotated.width = crop_h;
    rotated.height = crop_w;
    rotated.rgb.resize(out.rgb.size());
    for (int y = 0; y < crop_h; ++y) {
      for (int x = 0; x < crop_w; ++x) {
        const int nx = y;
        const int ny = crop_w - 1 - x;
        const size_t src_i = (static_cast<size_t>(y) * crop_w + x) * 3;
        const size_t dst_i = (static_cast<size_t>(ny) * crop_h + nx) * 3;
        rotated.rgb[dst_i] = out.rgb[src_i];
        rotated.rgb[dst_i + 1] = out.rgb[src_i + 1];
        rotated.rgb[dst_i + 2] = out.rgb[src_i + 2];
      }
    }
    return rotated;
  }
  return out;
}

void Rotate180(RgbImage* img) {
  if (img == nullptr || img->rgb.empty()) return;
  const int w = img->width;
  const int h = img->height;
  std::vector<uint8_t> dst(img->rgb.size());
  for (int y = 0; y < h; ++y) {
    for (int x = 0; x < w; ++x) {
      const size_t src = (static_cast<size_t>(y) * w + x) * 3;
      const size_t di = (static_cast<size_t>(h - 1 - y) * w + (w - 1 - x)) * 3;
      dst[di] = img->rgb[src];
      dst[di + 1] = img->rgb[src + 1];
      dst[di + 2] = img->rgb[src + 2];
    }
  }
  img->rgb.swap(dst);
}

int RoundTo32(int value) {
  int rounded = static_cast<int>(std::round(static_cast<double>(value) / 32.0)) * 32;
  if (rounded < 32) rounded = 32;
  return rounded;
}

struct DetBox {
  Vec2 quad[4];
  float score = 0;
  float angle = 0;
};

std::vector<uint8_t> ReadWholeFile(const char* path) {
  std::vector<uint8_t> out;
  if (path == nullptr || path[0] == '\0') return out;
  std::ifstream ifs(path, std::ios::binary | std::ios::ate);
  if (!ifs) return out;
  const std::streamsize size = ifs.tellg();
  if (size <= 0) return out;
  ifs.seekg(0);
  out.resize(static_cast<size_t>(size));
  if (!ifs.read(reinterpret_cast<char*>(out.data()), size)) out.clear();
  return out;
}

class OnnxRapidOcr {
 public:
  OnnxRapidOcr(const std::vector<uint8_t>& det_model,
               const std::vector<uint8_t>& cls_model,
               const std::vector<uint8_t>& rec_model,
               const std::vector<std::string>& dictionary,
               int num_threads,
               int execution_provider)
      : num_threads_(num_threads > 0 ? num_threads : 4) {
    characters_.emplace_back("blank");
    characters_.insert(characters_.end(), dictionary.begin(), dictionary.end());
    characters_.emplace_back(" ");
    if (det_model.empty() || rec_model.empty()) return;
    if (!LoadApi()) return;
    OrtStatus* status = api_->CreateEnv(ORT_LOGGING_LEVEL_ERROR, "xue_hua_rapid_ocr", &env_);
    if (status != nullptr) {
      api_->ReleaseStatus(status);
      env_ = nullptr;
      return;
    }
    det_ = CreateSession(det_model, execution_provider);
    rec_ = CreateSession(rec_model, execution_provider);
    if (!cls_model.empty()) cls_ = CreateSession(cls_model, execution_provider);
    if (det_ == nullptr || rec_ == nullptr) ReleaseAll();
  }

  ~OnnxRapidOcr() { ReleaseAll(); }

  bool ready() const { return api_ != nullptr && env_ != nullptr && det_ != nullptr && rec_ != nullptr; }

  bool Recognize(const RgbaImage& image,
                 const OcrDetectOption& opt,
                 std::vector<C_OcrTextLine>* lines,
                 double* det_ms,
                 double* cls_ms,
                 double* rec_ms) {
    if (!ready() || lines == nullptr || !image.pixels_valid) return false;
    const auto det_t0 = std::chrono::steady_clock::now();
    std::vector<DetBox> boxes = Detect(image, opt);
    const auto det_t1 = std::chrono::steady_clock::now();
    if (det_ms != nullptr) {
      *det_ms = std::chrono::duration<double, std::milli>(det_t1 - det_t0).count();
    }

    struct Crop {
      RgbImage image;
      DetBox box;
      int cls_label = 0;
      float cls_score = 1.f;
    };
    std::vector<Crop> crops;
    crops.reserve(boxes.size());
    for (const DetBox& box : boxes) {
      RgbImage warped = WarpQuad(image.pixels.data(), image.width, image.height, box.quad);
      if (warped.rgb.empty()) continue;
      crops.push_back(Crop{std::move(warped), box, 0, 1.f});
    }

    const auto cls_t0 = std::chrono::steady_clock::now();
    if (opt.do_angle && cls_ != nullptr) {
      int n180 = 0;
      for (Crop& crop : crops) {
        Classify(crop.image, &crop.cls_label, &crop.cls_score);
        if (crop.cls_label == 1) n180++;
      }
      const bool majority180 = opt.most_angle && !crops.empty() && n180 * 2 > static_cast<int>(crops.size());
      for (Crop& crop : crops) {
        const bool rotate = opt.most_angle ? majority180
                                            : (crop.cls_label == 1 && crop.cls_score > 0.9f);
        if (rotate) {
          Rotate180(&crop.image);
          crop.cls_label = 1;
        } else if (opt.most_angle) {
          crop.cls_label = 0;
        }
      }
    }
    const auto cls_t1 = std::chrono::steady_clock::now();
    if (cls_ms != nullptr) {
      *cls_ms = std::chrono::duration<double, std::milli>(cls_t1 - cls_t0).count();
    }

    const auto rec_t0 = std::chrono::steady_clock::now();
    lines->clear();
    for (Crop& crop : crops) {
      float confidence = 0;
      const std::string text = RecognizeLine(crop.image, &confidence);
      if (text.empty() || confidence < opt.min_confidence) continue;
      C_OcrTextLine line{};
      line.text = DuplicateUtf8String(text);
      line.confidence = confidence;
      line.angle = opt.do_angle ? crop.box.angle : 0.f;
      line.angle_confidence = crop.cls_score;
      line.box_score = crop.box.score;
      float min_x = crop.box.quad[0].x, max_x = min_x, min_y = crop.box.quad[0].y, max_y = min_y;
      for (int k = 0; k < 4; ++k) {
        line.corner_points[k] = {crop.box.quad[k].x, crop.box.quad[k].y};
        min_x = std::min(min_x, crop.box.quad[k].x);
        max_x = std::max(max_x, crop.box.quad[k].x);
        min_y = std::min(min_y, crop.box.quad[k].y);
        max_y = std::max(max_y, crop.box.quad[k].y);
      }
      line.bounding_box = {min_x, min_y, max_x - min_x, max_y - min_y};
      lines->push_back(line);
    }
    const auto rec_t1 = std::chrono::steady_clock::now();
    if (rec_ms != nullptr) {
      *rec_ms = std::chrono::duration<double, std::milli>(rec_t1 - rec_t0).count();
    }
    return true;
  }

 private:
  bool LoadApi() {
#if defined(_WIN32)
    std::vector<std::string> names = SiblingCandidates();
    if (const char* env = std::getenv("ONNXRUNTIME_LIB")) names.insert(names.begin(), env);
    names.push_back("onnxruntime.dll");
    for (const std::string& name : names) {
      library_ = reinterpret_cast<void*>(LoadLibraryA(name.c_str()));
      if (library_ != nullptr) break;
    }
    if (library_ == nullptr) return false;
    auto get_base = reinterpret_cast<const OrtApiBase*(ORT_API_CALL*)(void)>(
        GetProcAddress(static_cast<HMODULE>(library_), "OrtGetApiBase"));
#else
    std::vector<std::string> names = SiblingCandidates();
    if (const char* env = std::getenv("ONNXRUNTIME_LIB")) names.insert(names.begin(), env);
    names.push_back("libonnxruntime.so.1");
    names.push_back("libonnxruntime.so");
    names.push_back("libonnxruntime.dylib");
    names.push_back("libonnxruntime.1.dylib");
    for (const std::string& name : names) {
      library_ = dlopen(name.c_str(), RTLD_NOW | RTLD_LOCAL);
      if (library_ != nullptr) break;
    }
    if (library_ == nullptr) return false;
    auto get_base = reinterpret_cast<const OrtApiBase*(ORT_API_CALL*)(void)>(
        dlsym(library_, "OrtGetApiBase"));
#endif
    if (get_base == nullptr) return false;
    const OrtApiBase* base = get_base();
    api_ = base != nullptr ? base->GetApi(ORT_API_VERSION) : nullptr;
    return api_ != nullptr;
  }

  static std::vector<std::string> SiblingCandidates() {
    std::vector<std::string> names;
    std::string module_path;
#if defined(_WIN32)
    HMODULE module = nullptr;
    if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                               GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                           reinterpret_cast<LPCSTR>(&OnnxRapidOcr::SiblingCandidates),
                           &module)) {
      char path[MAX_PATH];
      const DWORD n = GetModuleFileNameA(module, path, MAX_PATH);
      if (n > 0 && n < MAX_PATH) module_path = path;
    }
#else
    Dl_info info{};
    if (dladdr(reinterpret_cast<const void*>(&OnnxRapidOcr::SiblingCandidates), &info) &&
        info.dli_fname != nullptr) {
      module_path = info.dli_fname;
    }
#endif
    const auto slash = module_path.find_last_of("/\\");
    if (slash == std::string::npos) return names;
    std::string directory = module_path.substr(0, slash + 1);
    auto push_dir = [&](const std::string& dir) {
      names.push_back(dir + "libonnxruntime.so.1");
      names.push_back(dir + "libonnxruntime.so.1.20.1");
      names.push_back(dir + "libonnxruntime.so");
      names.push_back(dir + "onnxruntime.dll");
      names.push_back(dir + "libonnxruntime.dylib");
      names.push_back(dir + "libonnxruntime.1.dylib");
      names.push_back(dir + "libonnxruntime.1.20.1.dylib");
    };
    // Walk up from the plugin binary so Flutter macOS layouts resolve:
    // App.app/Contents/Frameworks/plugin.framework/Versions/A/plugin
    // -> Frameworks/libonnxruntime.dylib (CocoaPods vendored_libraries).
    for (int depth = 0; depth < 6; ++depth) {
      push_dir(directory);
      if (directory.size() <= 1) break;
      std::string parent = directory.substr(0, directory.size() - 1);
      const auto parent_slash = parent.find_last_of("/\\");
      if (parent_slash == std::string::npos) break;
      directory = parent.substr(0, parent_slash + 1);
    }
    return names;
  }


  OrtSession* CreateSession(const std::vector<uint8_t>& model, int execution_provider) {
    OrtSessionOptions* options = nullptr;
    OrtStatus* status = api_->CreateSessionOptions(&options);
    if (status != nullptr) {
      api_->ReleaseStatus(status);
      return nullptr;
    }
    status = api_->SetIntraOpNumThreads(options, num_threads_);
    if (status != nullptr) api_->ReleaseStatus(status);
    status = api_->SetSessionGraphOptimizationLevel(options, ORT_ENABLE_ALL);
    if (status != nullptr) api_->ReleaseStatus(status);
    const char* provider = nullptr;
    switch (execution_provider) {
      case OCR_EP_COREML:
        provider = "CoreMLExecutionProvider";
        break;
      case OCR_EP_NNAPI:
        provider = "NnapiExecutionProvider";
        break;
      case OCR_EP_DIRECTML:
        provider = "DmlExecutionProvider";
        break;
      case OCR_EP_WEBGPU:
        provider = "WebGpuExecutionProvider";
        break;
      default:
        break;
    }
    if (provider != nullptr) {
      status = api_->SessionOptionsAppendExecutionProvider(options, provider, nullptr, nullptr, 0);
      if (status != nullptr) api_->ReleaseStatus(status);
    }
    OrtSession* session = nullptr;
    status = api_->CreateSessionFromArray(env_, model.data(), model.size(), options, &session);
    api_->ReleaseSessionOptions(options);
    if (status != nullptr) {
      if (const char* message = api_->GetErrorMessage(status)) {
        std::fprintf(stderr, "rapidocr onnx session: %s\n", message);
      }
      api_->ReleaseStatus(status);
      return nullptr;
    }
    return session;
  }

  bool RunFloat(OrtSession* session, const std::vector<float>& input, const int64_t* shape,
                size_t rank, std::vector<float>* output, std::vector<int64_t>* out_shape) {
    OrtMemoryInfo* memory = nullptr;
    OrtStatus* status = api_->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memory);
    if (status != nullptr) {
      api_->ReleaseStatus(status);
      return false;
    }
    OrtValue* input_value = nullptr;
    status = api_->CreateTensorWithDataAsOrtValue(
        memory, const_cast<float*>(input.data()), input.size() * sizeof(float), shape, rank,
        ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &input_value);
    api_->ReleaseMemoryInfo(memory);
    if (status != nullptr) {
      api_->ReleaseStatus(status);
      return false;
    }
    OrtAllocator* allocator = nullptr;
    status = api_->GetAllocatorWithDefaultOptions(&allocator);
    if (status != nullptr) {
      api_->ReleaseStatus(status);
      api_->ReleaseValue(input_value);
      return false;
    }
    char* input_name = nullptr;
    char* output_name = nullptr;
    status = api_->SessionGetInputName(session, 0, allocator, &input_name);
    if (status != nullptr) {
      api_->ReleaseStatus(status);
      api_->ReleaseValue(input_value);
      return false;
    }
    status = api_->SessionGetOutputName(session, 0, allocator, &output_name);
    if (status != nullptr) {
      api_->ReleaseStatus(status);
      allocator->Free(allocator, input_name);
      api_->ReleaseValue(input_value);
      return false;
    }
    const char* input_names[] = {input_name};
    const char* output_names[] = {output_name};
    OrtValue* output_value = nullptr;
    status = api_->Run(session, nullptr, input_names, &input_value, 1, output_names, 1, &output_value);
    allocator->Free(allocator, input_name);
    allocator->Free(allocator, output_name);
    api_->ReleaseValue(input_value);
    if (status != nullptr) {
      api_->ReleaseStatus(status);
      return false;
    }
    OrtTensorTypeAndShapeInfo* info = nullptr;
    status = api_->GetTensorTypeAndShape(output_value, &info);
    if (status != nullptr) {
      api_->ReleaseStatus(status);
      api_->ReleaseValue(output_value);
      return false;
    }
    size_t dims = 0;
    status = api_->GetDimensionsCount(info, &dims);
    if (status != nullptr) {
      api_->ReleaseStatus(status);
      api_->ReleaseTensorTypeAndShapeInfo(info);
      api_->ReleaseValue(output_value);
      return false;
    }
    std::vector<int64_t> shape_out(dims);
    if (dims > 0) {
      status = api_->GetDimensions(info, shape_out.data(), dims);
      if (status != nullptr) {
        api_->ReleaseStatus(status);
        api_->ReleaseTensorTypeAndShapeInfo(info);
        api_->ReleaseValue(output_value);
        return false;
      }
    }
    api_->ReleaseTensorTypeAndShapeInfo(info);
    size_t count = 1;
    for (int64_t dim : shape_out) count *= static_cast<size_t>(std::max<int64_t>(dim, 1));
    float* data = nullptr;
    status = api_->GetTensorMutableData(output_value, reinterpret_cast<void**>(&data));
    if (status != nullptr || data == nullptr) {
      if (status != nullptr) api_->ReleaseStatus(status);
      api_->ReleaseValue(output_value);
      return false;
    }
    output->assign(data, data + count);
    if (out_shape != nullptr) *out_shape = std::move(shape_out);
    api_->ReleaseValue(output_value);
    return true;
  }

  std::vector<DetBox> Detect(const RgbaImage& image, const OcrDetectOption& opt) {
    int limit = opt.max_side_len > 0 ? opt.max_side_len : 960;
    limit = std::clamp(limit, 32, 4096);
    const int src_w = image.width;
    const int src_h = image.height;
    float ratio = 1.f;
    const int long_side = std::max(src_w, src_h);
    if (long_side > limit) ratio = static_cast<float>(limit) / static_cast<float>(long_side);
    const int resize_w = RoundTo32(static_cast<int>(src_w * ratio));
    const int resize_h = RoundTo32(static_cast<int>(src_h * ratio));
    std::vector<float> input(static_cast<size_t>(3) * resize_h * resize_w);
    for (int y = 0; y < resize_h; ++y) {
      const float sy = (static_cast<float>(y) + 0.5f) * src_h / static_cast<float>(resize_h) - 0.5f;
      for (int x = 0; x < resize_w; ++x) {
        const float sx = (static_cast<float>(x) + 0.5f) * src_w / static_cast<float>(resize_w) - 0.5f;
        for (int c = 0; c < 3; ++c) {
          const float pixel = SampleChannel(image.pixels.data(), src_w, src_h, src_w * 4, sx, sy, c);
          const float norm = (pixel / 255.f - 0.5f) / 0.5f;
          input[(static_cast<size_t>(c) * resize_h + y) * resize_w + x] = norm;
        }
      }
    }
    const int64_t shape[] = {1, 3, resize_h, resize_w};
    std::vector<float> pred;
    std::vector<int64_t> pred_shape;
    if (!RunFloat(det_, input, shape, 4, &pred, &pred_shape)) return {};
    int out_h = resize_h;
    int out_w = resize_w;
    if (pred_shape.size() == 4) {
      out_h = static_cast<int>(pred_shape[2]);
      out_w = static_cast<int>(pred_shape[3]);
    }
    if (out_h <= 0 || out_w <= 0 ||
        pred.size() < static_cast<size_t>(out_h) * out_w) {
      return {};
    }
    const float thresh = opt.box_thresh > 0 ? opt.box_thresh : 0.3f;
    const float score_thresh = opt.box_score_thresh > 0 ? opt.box_score_thresh : 0.5f;
    const float unclip = opt.unclip_ratio > 0 ? opt.unclip_ratio : 1.6f;
    std::vector<uint8_t> mask(static_cast<size_t>(out_w) * out_h);
    for (int i = 0; i < out_w * out_h; ++i) mask[i] = pred[i] > thresh ? 1 : 0;
    std::vector<uint8_t> dilated(mask.size());
    for (int y = 0; y < out_h; ++y) {
      for (int x = 0; x < out_w; ++x) {
        uint8_t on = 0;
        for (int ky = 0; ky < 2 && !on; ++ky) {
          for (int kx = 0; kx < 2; ++kx) {
            const int yy = y + ky;
            const int xx = x + kx;
            if (yy < out_h && xx < out_w && mask[yy * out_w + xx]) on = 1;
          }
        }
        dilated[y * out_w + x] = on;
      }
    }
    const int pixels = out_w * out_h;
    std::vector<int> parent(static_cast<size_t>(pixels));
    for (int i = 0; i < pixels; ++i) parent[i] = i;
    auto find = [&](int x) {
      int root = x;
      while (parent[root] != root) root = parent[root];
      while (parent[x] != root) {
        const int next = parent[x];
        parent[x] = root;
        x = next;
      }
      return root;
    };
    auto unite = [&](int a, int b) {
      a = find(a);
      b = find(b);
      if (a != b) parent[b] = a;
    };
    for (int y = 0; y < out_h; ++y) {
      for (int x = 0; x < out_w; ++x) {
        if (!dilated[y * out_w + x]) continue;
        const int id = y * out_w + x;
        for (int ky = -1; ky <= 0; ++ky) {
          for (int kx = -1; kx <= 1; ++kx) {
            if (ky == 0 && kx >= 0) continue;
            const int yy = y + ky;
            const int xx = x + kx;
            if (yy < 0 || xx < 0 || xx >= out_w) continue;
            if (dilated[yy * out_w + xx]) unite(id, yy * out_w + xx);
          }
        }
      }
    }
    std::unordered_map<int, int> dense;
    std::vector<std::vector<Vec2>> components;
    for (int y = 0; y < out_h; ++y) {
      for (int x = 0; x < out_w; ++x) {
        if (!dilated[y * out_w + x]) continue;
        bool boundary = x == 0 || y == 0 || x + 1 == out_w || y + 1 == out_h;
        if (!boundary) {
          boundary = !dilated[y * out_w + x - 1] || !dilated[y * out_w + x + 1] ||
                     !dilated[(y - 1) * out_w + x] || !dilated[(y + 1) * out_w + x];
        }
        if (!boundary) continue;
        const int root = find(y * out_w + x);
        const auto it = dense.find(root);
        int index;
        if (it == dense.end()) {
          index = static_cast<int>(components.size());
          dense.emplace(root, index);
          components.emplace_back();
        } else {
          index = it->second;
        }
        components[index].push_back(Vec2{static_cast<float>(x), static_cast<float>(y)});
      }
    }
    std::vector<DetBox> boxes;
    for (const std::vector<Vec2>& points : components) {
      if (points.size() < 4) continue;
      RotatedRect rect = MinAreaRect(ConvexHull(points));
      if (!rect.ok || std::min(rect.width, rect.height) < 3.f) continue;
      const float score = PolygonMean(pred.data(), out_w, out_h, rect.corners);
      if (score < score_thresh) continue;
      const float area = rect.width * rect.height;
      const float peri = 2.f * (rect.width + rect.height);
      const float distance = peri > 0 ? area * unclip / peri : 0.f;
      const float expand_w = rect.width + 2.f * distance;
      const float expand_h = rect.height + 2.f * distance;
      if (std::min(expand_w, expand_h) < 5.f) continue;
      const float rad = rect.angle_deg * 3.14159265f / 180.f;
      const float cos_t = std::cos(rad);
      const float sin_t = std::sin(rad);
      const float hw = expand_w * 0.5f;
      const float hh = expand_h * 0.5f;
      const Vec2 local[4] = {{-hw, -hh}, {hw, -hh}, {hw, hh}, {-hw, hh}};
      DetBox box;
      box.score = score;
      for (int k = 0; k < 4; ++k) {
        const float rx = local[k].x * cos_t - local[k].y * sin_t;
        const float ry = local[k].x * sin_t + local[k].y * cos_t;
        box.quad[k] = {rect.cx + rx, rect.cy + ry};
        box.quad[k].x = std::clamp(std::round(box.quad[k].x / out_w * src_w), 0.f,
                                    static_cast<float>(src_w - 1));
        box.quad[k].y = std::clamp(std::round(box.quad[k].y / out_h * src_h), 0.f,
                                    static_cast<float>(src_h - 1));
      }
      OrderQuad(box.quad);
      const float edge = std::atan2(box.quad[1].y - box.quad[0].y, box.quad[1].x - box.quad[0].x) *
                         180.f / 3.14159265f;
      box.angle = std::fabs(edge) <= 4.f ? 0.f : edge;
      const float bw = Dist(box.quad[0], box.quad[1]);
      const float bh = Dist(box.quad[0], box.quad[3]);
      if (bw <= 3.f || bh <= 3.f) continue;
      boxes.push_back(box);
    }
    std::sort(boxes.begin(), boxes.end(), [](const DetBox& a, const DetBox& b) {
      if (std::fabs(a.quad[0].y - b.quad[0].y) <= 10.f) return a.quad[0].x < b.quad[0].x;
      return a.quad[0].y < b.quad[0].y;
    });
    return boxes;
  }

  void Classify(const RgbImage& image, int* label, float* score) {
    const int img_h = 48;
    const int img_w = 192;
    const float ratio = image.height > 0 ? static_cast<float>(image.width) / image.height : 1.f;
    int resized_w = static_cast<int>(std::ceil(img_h * ratio));
    if (resized_w > img_w) resized_w = img_w;
    if (resized_w < 1) resized_w = 1;
    std::vector<float> input(static_cast<size_t>(3) * img_h * img_w, 0.f);
    for (int y = 0; y < img_h; ++y) {
      const float sy = (static_cast<float>(y) + 0.5f) * image.height / img_h - 0.5f;
      for (int x = 0; x < resized_w; ++x) {
        const float sx = (static_cast<float>(x) + 0.5f) * image.width / resized_w - 0.5f;
        for (int c = 0; c < 3; ++c) {
          const float pixel = SampleRgb(image, sx, sy, c);
          input[(static_cast<size_t>(c) * img_h + y) * img_w + x] = (pixel / 255.f - 0.5f) / 0.5f;
        }
      }
    }
    const int64_t shape[] = {1, 3, img_h, img_w};
    std::vector<float> prob;
    if (!RunFloat(cls_, input, shape, 4, &prob, nullptr) || prob.size() < 2) return;
    const int best = prob[1] > prob[0] ? 1 : 0;
    if (label != nullptr) *label = best;
    if (score != nullptr) *score = prob[best];
  }

  std::string RecognizeLine(const RgbImage& image, float* confidence) {
    const int img_h = 48;
    const float wh = image.height > 0 ? static_cast<float>(image.width) / image.height : 1.f;
    const float max_wh = std::max(320.f / 48.f, wh);
    int img_w = static_cast<int>(img_h * max_wh);
    if (img_w < 8) img_w = 8;
    if (img_w > 4096) img_w = 4096;
    int resized_w = static_cast<int>(std::ceil(img_h * wh));
    if (resized_w > img_w) resized_w = img_w;
    if (resized_w < 1) resized_w = 1;
    std::vector<float> input(static_cast<size_t>(3) * img_h * img_w, 0.f);
    for (int y = 0; y < img_h; ++y) {
      const float sy = (static_cast<float>(y) + 0.5f) * image.height / img_h - 0.5f;
      for (int x = 0; x < resized_w; ++x) {
        const float sx = (static_cast<float>(x) + 0.5f) * image.width / resized_w - 0.5f;
        for (int c = 0; c < 3; ++c) {
          const float pixel = SampleRgb(image, sx, sy, c);
          input[(static_cast<size_t>(c) * img_h + y) * img_w + x] = (pixel / 255.f - 0.5f) / 0.5f;
        }
      }
    }
    const int64_t shape[] = {1, 3, img_h, img_w};
    std::vector<float> logits;
    std::vector<int64_t> out_shape;
    if (!RunFloat(rec_, input, shape, 4, &logits, &out_shape) || out_shape.size() < 2) return {};
    const int time_steps = static_cast<int>(out_shape[out_shape.size() - 2]);
    const int classes = static_cast<int>(out_shape[out_shape.size() - 1]);
    if (time_steps <= 0 || classes <= 1) return {};
    std::string text;
    double conf_sum = 0;
    int conf_n = 0;
    int previous = -1;
    for (int t = 0; t < time_steps; ++t) {
      const float* row = logits.data() + static_cast<size_t>(t) * classes;
      int best = 0;
      float best_v = row[0];
      for (int c = 1; c < classes; ++c) {
        if (row[c] > best_v) {
          best_v = row[c];
          best = c;
        }
      }
      if (best == previous) continue;
      previous = best;
      if (best == 0 || best >= static_cast<int>(characters_.size())) continue;
      const std::string& token = characters_[best];
      if (token == "blank") continue;
      text += token;
      conf_sum += std::clamp(best_v, 0.f, 1.f);
      conf_n++;
    }
    if (confidence != nullptr) {
      *confidence = conf_n > 0 ? static_cast<float>(conf_sum / conf_n) : 0.f;
    }
    return text;
  }

  static float SampleRgb(const RgbImage& image, float x, float y, int channel) {
    if (image.width <= 0 || image.height <= 0) return 0;
    x = std::clamp(x, 0.f, static_cast<float>(image.width - 1));
    y = std::clamp(y, 0.f, static_cast<float>(image.height - 1));
    const int x0 = static_cast<int>(std::floor(x));
    const int y0 = static_cast<int>(std::floor(y));
    const int x1 = std::min(x0 + 1, image.width - 1);
    const int y1 = std::min(y0 + 1, image.height - 1);
    const float fx = x - static_cast<float>(x0);
    const float fy = y - static_cast<float>(y0);
    auto at = [&](int xx, int yy) {
      return static_cast<float>(image.rgb[(static_cast<size_t>(yy) * image.width + xx) * 3 + channel]);
    };
    return at(x0, y0) * (1 - fx) * (1 - fy) + at(x1, y0) * fx * (1 - fy) +
           at(x0, y1) * (1 - fx) * fy + at(x1, y1) * fx * fy;
  }

  void ReleaseAll() {
    if (api_ != nullptr) {
      if (det_ != nullptr) api_->ReleaseSession(det_);
      if (cls_ != nullptr) api_->ReleaseSession(cls_);
      if (rec_ != nullptr) api_->ReleaseSession(rec_);
      if (env_ != nullptr) api_->ReleaseEnv(env_);
    }
    det_ = nullptr;
    cls_ = nullptr;
    rec_ = nullptr;
    env_ = nullptr;
    api_ = nullptr;
    if (library_ != nullptr) {
#if defined(_WIN32)
      FreeLibrary(static_cast<HMODULE>(library_));
#else
      dlclose(library_);
#endif
      library_ = nullptr;
    }
  }

  const OrtApi* api_ = nullptr;
  void* library_ = nullptr;
  OrtEnv* env_ = nullptr;
  OrtSession* det_ = nullptr;
  OrtSession* cls_ = nullptr;
  OrtSession* rec_ = nullptr;
  int num_threads_ = 4;
  std::vector<std::string> characters_;
};

std::vector<uint8_t> ModelBytes(const uint8_t* bytes, size_t length, const char* path) {
  if (bytes != nullptr && length > 0) return std::vector<uint8_t>(bytes, bytes + length);
  return ReadWholeFile(path);
}
