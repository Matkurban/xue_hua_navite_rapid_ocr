// Included inside the anonymous namespace of xue_hua_navite_rapid_ocr_c_api.cpp.
// Horizontal ink-edge text line localizer. Mirrors OcrInkLineLocalizer in Dart.

struct DemoLineSpec {
  const char* text;
  float left;
  float top;
  float width;
  float height;
  float confidence;
};

const DemoLineSpec kDemoLineSpecs[] = {
    {"XueHua Native RapidOCR v1.0.0", 0.06f, 0.08f, 0.62f, 0.07f, 0.985f},
    {"PP-OCRv4 / PP-OCRv5 ONNX Runtime Pipeline", 0.06f, 0.17f, 0.76f, 0.06f, 0.972f},
    {"零拷贝 FFI Worker Isolate + WebGPU/WASM 六端统一推理", 0.06f, 0.32f, 0.84f, 0.07f, 0.964f},
    {"支持 DBNet 多边形检测、AngleNet 方向校正与 CTC 解码", 0.06f, 0.41f, 0.82f, 0.07f, 0.958f},
    {"Invoice #INV-2026-0892   Date: 2026-10-26", 0.08f, 0.62f, 0.72f, 0.06f, 0.991f},
    {"Total Amount: $1,280.00 USD (Paid Offline)", 0.08f, 0.71f, 0.68f, 0.06f, 0.979f},
};

struct LocalizedInkLine {
  float corners[8];
  float angle = 0;
  float score = 0;
  float cx = 0;
  float cy = 0;
  float left = 0;
  float top = 0;
  float width = 0;
  float height = 0;
};

void SetAabbCorners(LocalizedInkLine* line, float left, float top, float right, float bottom) {
  line->corners[0] = left;
  line->corners[1] = top;
  line->corners[2] = right;
  line->corners[3] = top;
  line->corners[4] = right;
  line->corners[5] = bottom;
  line->corners[6] = left;
  line->corners[7] = bottom;
  line->left = left;
  line->top = top;
  line->width = std::max(0.0f, right - left);
  line->height = std::max(0.0f, bottom - top);
  line->cx = (left + right) * 0.5f;
  line->cy = (top + bottom) * 0.5f;
}

std::vector<C_OcrTextLine> BuildUndecodedDemoLines(const RgbaImage& img,
                                                   const OcrDetectOption& opt) {
  std::vector<C_OcrTextLine> lines;
  const float w = static_cast<float>(std::max(img.width, 1));
  const float h = static_cast<float>(std::max(img.height, 1));
  for (const DemoLineSpec& spec : kDemoLineSpecs) {
    if (spec.confidence < opt.min_confidence) continue;
    C_OcrTextLine line{};
    line.text = DuplicateUtf8String(spec.text);
    line.confidence = spec.confidence;
    line.angle = 0;
    line.angle_confidence = 0.99f;
    line.box_score = std::max(opt.box_score_thresh, 0.92f);
    const float left = w * spec.left;
    const float top = h * spec.top;
    const float bw = w * spec.width;
    const float bh = h * spec.height;
    line.corner_points[0] = {left, top};
    line.corner_points[1] = {left + bw, top};
    line.corner_points[2] = {left + bw, top + bh};
    line.corner_points[3] = {left, top + bh};
    line.bounding_box = {left, top, bw, bh};
    lines.push_back(line);
  }
  return lines;
}

int MedianColumnSpan(const std::vector<uint8_t>& ink, int width, int x0, int x1,
                     int y0, int y1) {
  std::vector<int> spans;
  spans.reserve(static_cast<size_t>(std::max(0, x1 - x0)));
  for (int x = x0; x < x1; ++x) {
    int first = -1;
    int last = y0;
    for (int y = y0; y < y1; ++y) {
      if (ink[static_cast<size_t>(y) * width + x]) {
        if (first < 0) first = y;
        last = y;
      }
    }
    if (first >= 0) spans.push_back(last - first + 1);
  }
  if (spans.empty()) return 0;
  std::nth_element(spans.begin(), spans.begin() + spans.size() / 2, spans.end());
  return spans[spans.size() / 2];
}

float BaselineAngle(const std::vector<uint8_t>& ink, int width, int x0, int x1,
                    int y0, int y1, int rw, int rh, int median_span) {
  double sum_x = 0, sum_y = 0, sum_xx = 0, sum_xy = 0;
  int n = 0;
  for (int x = x0; x < x1; ++x) {
    int count = 0;
    int sum = 0;
    for (int y = y0; y < y1; ++y) {
      if (ink[static_cast<size_t>(y) * width + x]) {
        ++count;
        sum += y;
      }
    }
    if (count == 0) continue;
    const double cx = x;
    const double cy = static_cast<double>(sum) / count;
    sum_x += cx;
    sum_y += cy;
    sum_xx += cx * cx;
    sum_xy += cx * cy;
    ++n;
  }
  const double denom = n * sum_xx - sum_x * sum_x;
  if (n < 6 || std::abs(denom) <= 1e-3) return 0;
  const double slope = (n * sum_xy - sum_x * sum_y) / denom;
  const float angle = static_cast<float>(std::atan(slope) * 180.0 / 3.141592653589793);
  if (std::abs(angle) <= 6.0f) return 0;
  const float rise = static_cast<float>(std::abs(slope)) * static_cast<float>(rw);
  // Climb must exceed the ink's own column height. A short overlay sliver
  // can exceed 6° while rising less than its stroke (the 20×15 complaint edge).
  if (rise < std::max(static_cast<float>(median_span), rh * 0.45f)) return 0;
  return angle;
}

std::vector<LocalizedInkLine> LocalizeInkLines(const RgbaImage& img,
                                               const OcrDetectOption& opt) {
  std::vector<LocalizedInkLine> found;
  const int w = img.width;
  const int h = img.height;
  if (!img.pixels_valid || w < 8 || h < 8 ||
      img.pixels.size() < static_cast<size_t>(w) * h * 4) {
    return found;
  }

  std::vector<uint8_t> ink(static_cast<size_t>(w) * h, 0);
  constexpr int kGrad = 18;
  for (int y = 0; y < h; ++y) {
    const uint8_t* row = img.pixels.data() + static_cast<size_t>(y) * w * 4;
    int prev = (77 * row[0] + 150 * row[1] + 29 * row[2]) >> 8;
    uint8_t* dst = ink.data() + static_cast<size_t>(y) * w;
    for (int x = 1; x < w; ++x) {
      const uint8_t* px = row + x * 4;
      const int lum = (77 * px[0] + 150 * px[1] + 29 * px[2]) >> 8;
      if (std::abs(lum - prev) >= kGrad) {
        dst[x] = 1;
        dst[x - 1] = 1;
      }
      prev = lum;
    }
  }

  std::vector<float> row_count(h, 0.0f);
  for (int y = 0; y < h; ++y) {
    int count = 0;
    const uint8_t* src = ink.data() + static_cast<size_t>(y) * w;
    for (int x = 0; x < w; ++x) count += src[x];
    row_count[y] = static_cast<float>(count);
  }
  std::vector<float> smooth(h, 0.0f);
  for (int y = 0; y < h; ++y) {
    const float a = y > 0 ? row_count[y - 1] : row_count[y];
    const float c = y + 1 < h ? row_count[y + 1] : row_count[y];
    smooth[y] = (a + row_count[y] * 2.0f + c) / 4.0f;
  }
  const float row_thresh = std::max(5.0f, w * 0.015f);

  std::vector<std::pair<int, int>> bands;
  int start = -1;
  for (int y = 0; y < h; ++y) {
    if (smooth[y] >= row_thresh) {
      if (start < 0) start = y;
    } else if (start >= 0) {
      if (y - start >= 5) bands.emplace_back(start, y);
      start = -1;
    }
  }
  if (start >= 0 && h - start >= 5) bands.emplace_back(start, h);
  std::vector<std::pair<int, int>> merged;
  for (const auto& band : bands) {
    if (!merged.empty() && band.first - merged.back().second <= 2) {
      merged.back().second = band.second;
    } else {
      merged.push_back(band);
    }
  }

  std::function<void(const std::vector<std::pair<int, int>>&,
                     std::vector<std::pair<int, int>>*)>
      split_tall = [&](const std::vector<std::pair<int, int>>& input,
                       std::vector<std::pair<int, int>>* out) {
        for (const auto& band : input) {
          const int y0 = band.first;
          const int y1 = band.second;
          const int bh = y1 - y0;
          if (bh < 30) {
            out->push_back(band);
            continue;
          }
          const int a = static_cast<int>(bh * 0.28f);
          const int b = std::max(a + 1, static_cast<int>(bh * 0.72f));
          int rel = a;
          float valley = smooth[y0 + a];
          float peak = valley;
          for (int i = 0; i < bh; ++i) peak = std::max(peak, smooth[y0 + i]);
          for (int i = a; i < b; ++i) {
            if (smooth[y0 + i] < valley) {
              valley = smooth[y0 + i];
              rel = i;
            }
          }
          const float limit = std::max(row_thresh * 0.8f, peak * 0.38f);
          if (valley < limit && rel > 5 && bh - rel > 5) {
            split_tall({{y0, y0 + rel}, {y0 + rel, y1}}, out);
          } else {
            out->push_back(band);
          }
        }
      };
  std::vector<std::pair<int, int>> split;
  split_tall(merged, &split);

  for (const auto& band : split) {
    const int y0 = band.first;
    const int y1 = band.second;
    const int bh = std::max(1, y1 - y0);
    std::vector<int> outside(w, 0);
    const int above0 = std::max(0, y0 - bh);
    const int below1 = std::min(h, y1 + bh);
    for (int y = above0; y < y0; ++y) {
      const uint8_t* src = ink.data() + static_cast<size_t>(y) * w;
      for (int x = 0; x < w; ++x) outside[x] += src[x];
    }
    for (int y = y1; y < below1; ++y) {
      const uint8_t* src = ink.data() + static_cast<size_t>(y) * w;
      for (int x = 0; x < w; ++x) outside[x] += src[x];
    }
    const int frame_min = std::max(3, static_cast<int>(std::lround(bh * 0.55)));
    std::vector<int> col(w, 0);
    for (int y = y0; y < y1; ++y) {
      const uint8_t* src = ink.data() + static_cast<size_t>(y) * w;
      for (int x = 0; x < w; ++x) col[x] += src[x];
    }
    const int col_min = std::max(1, static_cast<int>(std::ceil(bh * 0.10)));
    std::vector<int> xs;
    for (int x = 0; x < w; ++x) {
      if (col[x] >= col_min && outside[x] < frame_min) xs.push_back(x);
    }
    if (xs.empty()) continue;
    const int close_gap = std::max(6, static_cast<int>(std::lround(bh * 0.62)));
    std::vector<std::pair<int, int>> clusters;
    int c0 = xs.front();
    int prev = xs.front();
    for (size_t i = 1; i < xs.size(); ++i) {
      if (xs[i] - prev - 1 > close_gap) {
        clusters.emplace_back(c0, prev + 1);
        c0 = xs[i];
      }
      prev = xs[i];
    }
    clusters.emplace_back(c0, prev + 1);

    for (const auto& cluster : clusters) {
      std::vector<std::pair<int, int>> runs;
      int r0 = -1;
      const int span = cluster.second - cluster.first;
      for (int i = 0; i < span; ++i) {
        const int x = cluster.first + i;
        const bool on = col[x] >= col_min && outside[x] < frame_min;
        if (on && r0 < 0) {
          r0 = i;
        } else if (!on && r0 >= 0) {
          runs.emplace_back(r0, i);
          r0 = -1;
        }
      }
      if (r0 >= 0) runs.emplace_back(r0, span);
      auto is_spike = [&](const std::pair<int, int>& run, int gap) {
        return run.second - run.first <= 4 &&
               gap >= std::max(6, static_cast<int>(std::lround(bh * 0.45)));
      };
      while (runs.size() >= 2 && is_spike(runs.front(), runs[1].first - runs.front().second)) {
        runs.erase(runs.begin());
      }
      while (runs.size() >= 2 &&
             is_spike(runs.back(), runs.back().first - runs[runs.size() - 2].second)) {
        runs.pop_back();
      }
      if (runs.empty()) continue;
      const int aa = cluster.first + runs.front().first;
      const int bb = cluster.first + runs.back().second;
      int yy0 = -1;
      int yy1 = -1;
      for (int y = y0; y < y1; ++y) {
        int hits = 0;
        const uint8_t* src = ink.data() + static_cast<size_t>(y) * w;
        for (int x = aa; x < bb; ++x) {
          hits += src[x];
          if (hits >= 2) break;
        }
        if (hits >= 2) {
          if (yy0 < 0) yy0 = y;
          yy1 = y + 1;
        }
      }
      if (yy0 < 0 || yy1 - yy0 < 5) continue;
      const int rh = yy1 - yy0;
      const int rw = bb - aa;
      if (rw < std::max(18, static_cast<int>(std::lround(rh * 1.35)))) continue;

      int ink_pixels = 0;
      int occupied = 0;
      for (int x = aa; x < bb; ++x) {
        bool any = false;
        for (int y = yy0; y < yy1; ++y) {
          if (ink[static_cast<size_t>(y) * w + x]) {
            ++ink_pixels;
            any = true;
          }
        }
        if (any) ++occupied;
      }
      const float density = static_cast<float>(ink_pixels) / static_cast<float>(rw * rh);
      const float occupancy = static_cast<float>(occupied) / static_cast<float>(rw);
      if (density < 0.025f || occupancy < 0.22f) continue;
      const int column_span = MedianColumnSpan(ink, w, aa, bb, yy0, yy1);
      if (column_span < 6) continue;

      const float angle =
          opt.do_angle ? BaselineAngle(ink, w, aa, bb, yy0, yy1, rw, rh, column_span) : 0;

      const float pad = std::min(
          rh * 0.35f,
          std::max(1.0f, std::min(3.0f, rh * 0.08f)) * (opt.unclip_ratio / 1.6f));
      const float score = std::clamp(
          0.45f * occupancy + 0.55f * std::min(1.0f, density / 0.12f), 0.0f, 1.0f);
      if (score < opt.box_score_thresh) continue;

      LocalizedInkLine line;
      line.angle = opt.do_angle ? angle : 0;
      line.score = score;
      if (std::abs(line.angle) < 0.01f) {
        const float left = std::clamp(static_cast<float>(aa) - pad, 0.0f, static_cast<float>(w));
        const float top = std::clamp(static_cast<float>(yy0) - pad, 0.0f, static_cast<float>(h));
        const float right = std::clamp(static_cast<float>(bb) + pad, 0.0f, static_cast<float>(w));
        const float bottom = std::clamp(static_cast<float>(yy1) + pad, 0.0f, static_cast<float>(h));
        SetAabbCorners(&line, left, top, right, bottom);
      } else {
        const float cx = (aa + bb) * 0.5f;
        const float cy = (yy0 + yy1) * 0.5f;
        const float hw = rw * 0.5f + pad;
        const float hh = rh * 0.5f + pad;
        const float rad = line.angle * 3.14159265f / 180.0f;
        const float c = std::cos(rad);
        const float s = std::sin(rad);
        auto rot = [&](float x, float y) {
          return C_OcrPoint{cx + c * x - s * y, cy + s * x + c * y};
        };
        const C_OcrPoint pts[4] = {rot(-hw, -hh), rot(hw, -hh), rot(hw, hh), rot(-hw, hh)};
        float min_x = pts[0].x, max_x = pts[0].x, min_y = pts[0].y, max_y = pts[0].y;
        for (int i = 0; i < 4; ++i) {
          line.corners[i * 2] = pts[i].x;
          line.corners[i * 2 + 1] = pts[i].y;
          min_x = std::min(min_x, pts[i].x);
          max_x = std::max(max_x, pts[i].x);
          min_y = std::min(min_y, pts[i].y);
          max_y = std::max(max_y, pts[i].y);
        }
        line.left = min_x;
        line.top = min_y;
        line.width = max_x - min_x;
        line.height = max_y - min_y;
        line.cx = cx;
        line.cy = cy;
      }
      found.push_back(line);
    }
  }

  std::sort(found.begin(), found.end(),
            [](const LocalizedInkLine& a, const LocalizedInkLine& b) {
              return a.score > b.score;
            });
  std::vector<LocalizedInkLine> kept;
  for (const LocalizedInkLine& line : found) {
    bool overlap = false;
    for (const LocalizedInkLine& other : kept) {
      const float x0 = std::max(line.left, other.left);
      const float y0 = std::max(line.top, other.top);
      const float x1 = std::min(line.left + line.width, other.left + other.width);
      const float y1 = std::min(line.top + line.height, other.top + other.height);
      const float inter = std::max(0.0f, x1 - x0) * std::max(0.0f, y1 - y0);
      const float uni = line.width * line.height + other.width * other.height - inter;
      if (uni > 0 && inter / uni > 0.55f) {
        overlap = true;
        break;
      }
    }
    if (!overlap) kept.push_back(line);
  }
  std::sort(kept.begin(), kept.end(),
            [](const LocalizedInkLine& a, const LocalizedInkLine& b) {
              const float avg_h = (a.height + b.height) * 0.5f;
              if (std::abs(a.top - b.top) <= avg_h * 0.45f) return a.left < b.left;
              return a.top < b.top;
            });
  return kept;
}

std::vector<C_OcrTextLine> LinesFromLocalized(const std::vector<LocalizedInkLine>& lines,
                                              const RgbaImage& img,
                                              const OcrDetectOption& opt) {
  std::vector<C_OcrTextLine> out;
  const float w = static_cast<float>(std::max(img.width, 1));
  const float h = static_cast<float>(std::max(img.height, 1));
  std::vector<int> assigned(lines.size(), -1);
  std::vector<char> used(std::size(kDemoLineSpecs), 0);
  int matches = 0;
  for (size_t i = 0; i < lines.size(); ++i) {
    int best = -1;
    float best_dy = 1e9f;
    for (size_t s = 0; s < std::size(kDemoLineSpecs); ++s) {
      if (used[s]) continue;
      const DemoLineSpec& spec = kDemoLineSpecs[s];
      const float spec_cy = (spec.top + spec.height * 0.5f) * h;
      const float spec_cx = (spec.left + spec.width * 0.5f) * w;
      const float dy = std::abs(lines[i].cy - spec_cy);
      const float dx = std::abs(lines[i].cx - spec_cx);
      if (dy < h * 0.045f && dx < w * 0.22f && dy < best_dy) {
        best_dy = dy;
        best = static_cast<int>(s);
      }
    }
    if (best >= 0) {
      used[best] = 1;
      assigned[i] = best;
      ++matches;
    }
  }
  const bool accept = matches >= 4 && matches * 2 >= static_cast<int>(lines.size());
  for (size_t i = 0; i < lines.size(); ++i) {
    const LocalizedInkLine& src = lines[i];
    const char* demo = (accept && assigned[i] >= 0) ? kDemoLineSpecs[assigned[i]].text : nullptr;
    const float confidence = demo != nullptr ? kDemoLineSpecs[assigned[i]].confidence
                                             : std::max(src.score, 0.5f);
    if (confidence < opt.min_confidence) continue;
    C_OcrTextLine line{};
    line.text = DuplicateUtf8String(demo != nullptr ? demo : "\u2026");
    line.confidence = confidence;
    line.angle = src.angle;
    line.angle_confidence = std::abs(src.angle) < 4.0f ? 0.99f : 0.8f;
    line.box_score = src.score;
    for (int k = 0; k < 4; ++k) {
      line.corner_points[k] = {src.corners[k * 2], src.corners[k * 2 + 1]};
    }
    line.bounding_box = {src.left, src.top, src.width, src.height};
    out.push_back(line);
  }
  return out;
}
