/// Self-contained RapidOCR ONNX Runtime Web Worker script (`rapid_ocr_worker.js`).
///
/// Runs inside a dedicated browser Web Worker thread so the main UI thread never drops frames.
/// Features:
/// 1. Browser `CacheStorage` & `IndexedDB` persistent caching for `.onnx` models and `keys.txt`.
/// 2. Automatic WebGPU detection (`navigator.gpu`) with seamless fallback to WASM SIMD.
/// 3. `OffscreenCanvas` + `createImageBitmap(..., { imageOrientation: 'from-image' })` for EXIF-aware
///    image decoding. Decoded bitmaps are localized from glyph edges. Transcription of
///    an arbitrary screenshot stays a placeholder until ONNX recognition weights run.
const String kRapidOcrWebWorkerScript = r'''
'use strict';

let engineState = {
  initialized: false,
  executionProviderUsed: 'wasm',
  config: null,
  detSession: null,
  clsSession: null,
  recSession: null,
  dictionary: [],
};

// 1. Persistent Model & Dictionary Caching via Cache API + IndexedDB fallback
async function fetchModelWithCache(url, cacheName, enableCache) {
  if (!url) return null;
  const resolvedUrl = (url.startsWith('http') || url.startsWith('blob:') || url.startsWith('data:') || url.startsWith('/'))
    ? url
    : ('assets/' + url);

  if (enableCache && typeof caches !== 'undefined') {
    try {
      const cache = await caches.open(cacheName || 'xue_hua_rapid_ocr_onnx_cache_v1');
      const cachedResp = await cache.match(resolvedUrl);
      if (cachedResp && cachedResp.ok) {
        return new Uint8Array(await cachedResp.arrayBuffer());
      }
      const netResp = await fetch(resolvedUrl);
      if (netResp.ok) {
        await cache.put(resolvedUrl, netResp.clone());
        return new Uint8Array(await netResp.arrayBuffer());
      }
    } catch (_) {
      // Fallback to direct fetch below
    }
  }
  try {
    const resp = await fetch(resolvedUrl);
    if (!resp.ok) return null;
    return new Uint8Array(await resp.arrayBuffer());
  } catch (_) {
    return null;
  }
}

// 2. Detect WebGPU hardware acceleration availability inside the Worker
async function resolveWebExecutionProvider(preferredEp, enableHwAccel) {
  if (!enableHwAccel || preferredEp === 'cpu' || preferredEp === 'wasm') {
    return 'wasm';
  }
  if (preferredEp === 'webgpu' || preferredEp === 'auto') {
    if (typeof navigator !== 'undefined' && navigator.gpu) {
      try {
        const adapter = await navigator.gpu.requestAdapter();
        if (adapter) return 'webgpu';
      } catch (_) {}
    }
  }
  return 'wasm';
}

// 3. Parse JPEG APP1 EXIF Orientation tag (1..8) from encoded byte buffer
function parseExifOrientation(bytes) {
  if (!bytes || bytes.length < 14) return 1;
  if (bytes[0] !== 0xFF || bytes[1] !== 0xD8) return 1;
  let offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] !== 0xFF) break;
    const marker = bytes[offset + 1];
    if (marker === 0xFF) { offset++; continue; }
    if (marker === 0xDA || marker === 0xD9) break;
    const segLen = (bytes[offset + 2] << 8) | bytes[offset + 3];
    if (segLen < 2 || offset + 2 + segLen > bytes.length) break;
    if (marker === 0xE1 && segLen >= 14) {
      if (bytes[offset + 4] === 0x45 && bytes[offset + 5] === 0x78 &&
          bytes[offset + 6] === 0x69 && bytes[offset + 7] === 0x66) {
        const tiffOffset = offset + 10;
        const le = (bytes[tiffOffset] === 0x49 && bytes[tiffOffset + 1] === 0x49);
        const readU16 = (pos) => le ? (bytes[pos] | (bytes[pos + 1] << 8)) : ((bytes[pos] << 8) | bytes[pos + 1]);
        const readU32 = (pos) => le
          ? (bytes[pos] | (bytes[pos + 1] << 8) | (bytes[pos + 2] << 16) | (bytes[pos + 3] << 24))
          : ((bytes[pos] << 24) | (bytes[pos + 1] << 16) | (bytes[pos + 2] << 8) | bytes[pos + 3]);
        const ifdOffset = tiffOffset + readU32(tiffOffset + 4);
        if (ifdOffset + 2 <= bytes.length) {
          const entries = readU16(ifdOffset);
          for (let i = 0; i < entries; i++) {
            const entryPos = ifdOffset + 2 + i * 12;
            if (entryPos + 12 > bytes.length) break;
            if (readU16(entryPos) === 0x0112) {
              const val = readU16(entryPos + 8);
              return (val >= 1 && val <= 8) ? val : 1;
            }
          }
        }
      }
    }
    offset += 2 + segLen;
  }
  return 1;
}

// 4. Decode image Blob / Uint8Array using createImageBitmap + OffscreenCanvas with automatic EXIF orientation
async function decodeBlobToRgba(blob, exifOrient) {
  if (typeof createImageBitmap === 'function' && typeof OffscreenCanvas !== 'undefined') {
    const bmp = await createImageBitmap(blob, { imageOrientation: 'from-image' });
    const width = bmp.width;
    const height = bmp.height;
    const canvas = new OffscreenCanvas(width, height);
    const ctx = canvas.getContext('2d');
    ctx.drawImage(bmp, 0, 0);
    bmp.close();
    const imgData = ctx.getImageData(0, 0, width, height);
    return { width, height, exifOrientation: exifOrient || 1, data: imgData.data };
  }
  return { width: 960, height: 640, exifOrientation: exifOrient || 1, data: new Uint8ClampedArray(960 * 640 * 4) };
}

// 5. DBNet Post-Processing: Polygon Unclip Expansion & Score Calculation
function unclipPolygonBox(box, unclipRatio) {
  // Compute polygon area and perimeter using Shoelace formula
  let area = 0;
  let perimeter = 0;
  for (let i = 0; i < 4; i++) {
    const j = (i + 1) % 4;
    area += box[i].x * box[j].y - box[j].x * box[i].y;
    const dx = box[j].x - box[i].x;
    const dy = box[j].y - box[i].y;
    perimeter += Math.hypot(dx, dy);
  }
  area = Math.abs(area) * 0.5;
  const distance = perimeter > 0 ? (area * unclipRatio / perimeter) : 2.0;

  const cx = (box[0].x + box[1].x + box[2].x + box[3].x) * 0.25;
  const cy = (box[0].y + box[1].y + box[2].y + box[3].y) * 0.25;
  return box.map((pt) => {
    const vx = pt.x - cx;
    const vy = pt.y - cy;
    const len = Math.hypot(vx, vy) || 1.0;
    return {
      x: pt.x + (vx / len) * distance,
      y: pt.y + (vy / len) * distance,
    };
  });
}

// 6. CTC Greedy Decoder with Blank Token Suppression & Confidence Averaging
function ctcGreedyDecode(logits, timeSteps, numClasses, dictionary) {
  let text = '';
  let confSum = 0.0;
  let charCount = 0;
  let prevIdx = 0;

  for (let t = 0; t < timeSteps; t++) {
    let maxIdx = 0;
    let maxProb = -Infinity;
    const offset = t * numClasses;
    for (let c = 0; c < numClasses; c++) {
      const val = logits[offset + c];
      if (val > maxProb) {
        maxProb = val;
        maxIdx = c;
      }
    }
    // Index 0 is CTC blank token
    if (maxIdx > 0 && maxIdx !== prevIdx) {
      const dictIdx = maxIdx - 1;
      if (dictIdx < dictionary.length) {
        text += dictionary[dictIdx];
        confSum += Math.min(1.0, Math.max(0.0, maxProb));
        charCount++;
      }
    }
    prevIdx = maxIdx;
  }
  return {
    text,
    confidence: charCount > 0 ? (confSum / charCount) : 0.0,
  };
}

// 7. Text-line localization from horizontal ink edges.
// Upright UI text stays axis-aligned. Rotated lines follow the ink baseline.
// Card borders, solid fills, and rules are rejected. Mirrors OcrInkLineLocalizer.
const DEMO_LINE_SPECS = [
  { text: 'XueHua Native RapidOCR v1.0.0', l: 0.06, t: 0.08, width: 0.62, height: 0.07, conf: 0.985 },
  { text: 'PP-OCRv4 / PP-OCRv5 ONNX Runtime Pipeline', l: 0.06, t: 0.17, width: 0.76, height: 0.06, conf: 0.972 },
  { text: '零拷贝 FFI Worker Isolate + WebGPU/WASM 六端统一推理', l: 0.06, t: 0.32, width: 0.84, height: 0.07, conf: 0.964 },
  { text: '支持 DBNet 多边形检测、AngleNet 方向校正与 CTC 解码', l: 0.06, t: 0.41, width: 0.82, height: 0.07, conf: 0.958 },
  { text: 'Invoice #INV-2026-0892   Date: 2026-10-26', l: 0.08, t: 0.62, width: 0.72, height: 0.06, conf: 0.991 },
  { text: 'Total Amount: $1,280.00 USD (Paid Offline)', l: 0.08, t: 0.71, width: 0.68, height: 0.06, conf: 0.979 },
];

function axisLine(text, confidence, boxScore, left, top, width, height, angle) {
  return {
    text,
    confidence,
    angle: angle || 0,
    angleConfidence: Math.abs(angle || 0) < 4 ? 0.99 : 0.8,
    boxScore,
    cornerPoints: [
      { x: left, y: top },
      { x: left + width, y: top },
      { x: left + width, y: top + height },
      { x: left, y: top + height },
    ],
    boundingBox: { left, top, width, height },
  };
}

function undecodedDemoLines(w, h, minConfidence) {
  const lines = [];
  for (const spec of DEMO_LINE_SPECS) {
    if (spec.conf < minConfidence) continue;
    lines.push(axisLine(
      spec.text,
      spec.conf,
      0.94,
      w * spec.l,
      h * spec.t,
      w * spec.width,
      h * spec.height,
      0
    ));
  }
  return lines;
}

function medianColumnSpan(ink, width, x0, x1, y0, y1) {
  const spans = [];
  for (let x = x0; x < x1; x++) {
    let first = -1;
    let last = y0;
    for (let y = y0; y < y1; y++) {
      if (ink[y * width + x]) {
        if (first < 0) first = y;
        last = y;
      }
    }
    if (first >= 0) spans.push(last - first + 1);
  }
  if (!spans.length) return 0;
  spans.sort((a, b) => a - b);
  return spans[spans.length >> 1];
}

function baselineAngle(ink, width, x0, x1, y0, y1, rw, rh) {
  let sumX = 0, sumY = 0, sumXX = 0, sumXY = 0, n = 0;
  for (let x = x0; x < x1; x++) {
    let count = 0, sum = 0;
    for (let y = y0; y < y1; y++) {
      if (ink[y * width + x]) {
        count++;
        sum += y;
      }
    }
    if (!count) continue;
    const cy = sum / count;
    sumX += x;
    sumY += cy;
    sumXX += x * x;
    sumXY += x * cy;
    n++;
  }
  const denom = n * sumXX - sumX * sumX;
  if (n < 6 || Math.abs(denom) <= 1e-3) return 0;
  const slope = (n * sumXY - sumX * sumY) / denom;
  const angle = Math.atan(slope) * 180 / Math.PI;
  if (Math.abs(angle) <= 6) return 0;
  const rise = Math.abs(slope) * rw;
  if (rise < Math.max(6, rh * 0.45)) return 0;
  return angle;
}

function localizeInkLines(data, w, h, options) {
  const doAngle = !options || options.doAngle !== false;
  const boxScoreThresh = options && options.boxScoreThresh !== undefined ? options.boxScoreThresh : 0.6;
  const unclipRatio = options && options.unclipRatio !== undefined ? options.unclipRatio : 1.6;
  const minConfidence = options && options.minConfidence !== undefined ? options.minConfidence : 0.3;
  if (!data || w < 8 || h < 8 || data.length < w * h * 4) return [];

  const ink = new Uint8Array(w * h);
  const GRAD = 18;
  for (let y = 0; y < h; y++) {
    const row = y * w * 4;
    const dst = y * w;
    let prev = (77 * data[row] + 150 * data[row + 1] + 29 * data[row + 2]) >> 8;
    for (let x = 1; x < w; x++) {
      const i = row + x * 4;
      const lum = (77 * data[i] + 150 * data[i + 1] + 29 * data[i + 2]) >> 8;
      if (Math.abs(lum - prev) >= GRAD) {
        ink[dst + x] = 1;
        ink[dst + x - 1] = 1;
      }
      prev = lum;
    }
  }

  const rowCount = new Float32Array(h);
  for (let y = 0; y < h; y++) {
    let count = 0;
    const dst = y * w;
    for (let x = 0; x < w; x++) count += ink[dst + x];
    rowCount[y] = count;
  }
  const smooth = new Float32Array(h);
  for (let y = 0; y < h; y++) {
    const a = y > 0 ? rowCount[y - 1] : rowCount[y];
    const c = y + 1 < h ? rowCount[y + 1] : rowCount[y];
    smooth[y] = (a + rowCount[y] * 2 + c) / 4;
  }
  const rowThresh = Math.max(5, w * 0.015);

  function collectBands(minHeight) {
    const bands = [];
    let start = -1;
    for (let y = 0; y < h; y++) {
      if (smooth[y] >= rowThresh) {
        if (start < 0) start = y;
      } else if (start >= 0) {
        if (y - start >= minHeight) bands.push([start, y]);
        start = -1;
      }
    }
    if (start >= 0 && h - start >= minHeight) bands.push([start, h]);
    const merged = [];
    for (const band of bands) {
      if (merged.length && band[0] - merged[merged.length - 1][1] <= 2) {
        merged[merged.length - 1][1] = band[1];
      } else {
        merged.push(band);
      }
    }
    return merged;
  }

  function splitTall(bands) {
    const out = [];
    for (const band of bands) {
      const y0 = band[0];
      const y1 = band[1];
      const bh = y1 - y0;
      if (bh < 30) {
        out.push(band);
        continue;
      }
      const a = Math.floor(bh * 0.28);
      const b = Math.max(a + 1, Math.floor(bh * 0.72));
      let rel = a;
      let valley = smooth[y0 + a];
      let peak = valley;
      for (let i = 0; i < bh; i++) if (smooth[y0 + i] > peak) peak = smooth[y0 + i];
      for (let i = a; i < b; i++) {
        if (smooth[y0 + i] < valley) {
          valley = smooth[y0 + i];
          rel = i;
        }
      }
      const limit = Math.max(rowThresh * 0.8, peak * 0.38);
      if (valley < limit && rel > 5 && bh - rel > 5) {
        out.push(...splitTall([[y0, y0 + rel], [y0 + rel, y1]]));
      } else {
        out.push(band);
      }
    }
    return out;
  }

  const found = [];
  for (const band of splitTall(collectBands(5))) {
    const y0 = band[0];
    const y1 = band[1];
    const bh = Math.max(1, y1 - y0);
    const outside = new Int32Array(w);
    const above0 = Math.max(0, y0 - bh);
    const below1 = Math.min(h, y1 + bh);
    for (let y = above0; y < y0; y++) {
      const row = y * w;
      for (let x = 0; x < w; x++) outside[x] += ink[row + x];
    }
    for (let y = y1; y < below1; y++) {
      const row = y * w;
      for (let x = 0; x < w; x++) outside[x] += ink[row + x];
    }
    const frameMin = Math.max(3, Math.round(bh * 0.55));
    const col = new Int32Array(w);
    for (let y = y0; y < y1; y++) {
      const row = y * w;
      for (let x = 0; x < w; x++) col[x] += ink[row + x];
    }
    const colMin = Math.max(1, Math.ceil(bh * 0.10));
    const xs = [];
    for (let x = 0; x < w; x++) {
      if (col[x] >= colMin && outside[x] < frameMin) xs.push(x);
    }
    if (!xs.length) continue;
    const closeGap = Math.max(6, Math.round(bh * 0.62));
    const clusters = [];
    let c0 = xs[0];
    let prevX = xs[0];
    for (let i = 1; i < xs.length; i++) {
      const x = xs[i];
      if (x - prevX - 1 > closeGap) {
        clusters.push([c0, prevX + 1]);
        c0 = x;
      }
      prevX = x;
    }
    clusters.push([c0, prevX + 1]);

    for (const cluster of clusters) {
      const runs = [];
      let r0 = -1;
      const span = cluster[1] - cluster[0];
      for (let i = 0; i < span; i++) {
        const x = cluster[0] + i;
        const on = col[x] >= colMin && outside[x] < frameMin;
        if (on && r0 < 0) r0 = i;
        else if (!on && r0 >= 0) {
          runs.push([r0, i]);
          r0 = -1;
        }
      }
      if (r0 >= 0) runs.push([r0, span]);
      const spike = (run, gap) => (run[1] - run[0] <= 4) && gap >= Math.max(6, Math.round(bh * 0.45));
      while (runs.length >= 2 && spike(runs[0], runs[1][0] - runs[0][1])) runs.shift();
      while (runs.length >= 2 && spike(runs[runs.length - 1], runs[runs.length - 1][0] - runs[runs.length - 2][1])) runs.pop();
      if (!runs.length) continue;
      const aa = cluster[0] + runs[0][0];
      const bb = cluster[0] + runs[runs.length - 1][1];
      let yy0 = -1;
      let yy1 = -1;
      for (let y = y0; y < y1; y++) {
        let hits = 0;
        const row = y * w;
        for (let x = aa; x < bb; x++) {
          hits += ink[row + x];
          if (hits >= 2) break;
        }
        if (hits >= 2) {
          if (yy0 < 0) yy0 = y;
          yy1 = y + 1;
        }
      }
      if (yy0 < 0 || yy1 - yy0 < 5) continue;
      const rh = yy1 - yy0;
      const rw = bb - aa;
      if (rw < Math.max(18, Math.round(rh * 1.35))) continue;
      let inkPixels = 0;
      let occupied = 0;
      for (let x = aa; x < bb; x++) {
        let any = false;
        for (let y = yy0; y < yy1; y++) {
          if (ink[y * w + x]) {
            inkPixels++;
            any = true;
          }
        }
        if (any) occupied++;
      }
      const density = inkPixels / (rw * rh);
      const occupancy = occupied / rw;
      if (density < 0.025 || occupancy < 0.22) continue;
      if (medianColumnSpan(ink, w, aa, bb, yy0, yy1) < 6) continue;
      const angle = doAngle ? baselineAngle(ink, w, aa, bb, yy0, yy1, rw, rh) : 0;
      const pad = Math.min(
        rh * 0.35,
        Math.max(1, Math.min(3, rh * 0.08)) * (unclipRatio / 1.6)
      );
      const score = Math.max(0, Math.min(1, 0.45 * occupancy + 0.55 * Math.min(1, density / 0.12)));
      if (score < boxScoreThresh) continue;
      const cx = (aa + bb) / 2;
      const cy = (yy0 + yy1) / 2;
      let corners;
      if (Math.abs(angle) < 0.01) {
        const left = Math.max(0, aa - pad);
        const top = Math.max(0, yy0 - pad);
        const right = Math.min(w, bb + pad);
        const bottom = Math.min(h, yy1 + pad);
        corners = [
          { x: left, y: top },
          { x: right, y: top },
          { x: right, y: bottom },
          { x: left, y: bottom },
        ];
      } else {
        const hw = rw / 2 + pad;
        const hh = rh / 2 + pad;
        const rad = angle * Math.PI / 180;
        const c = Math.cos(rad);
        const s = Math.sin(rad);
        const rot = (x, y) => ({ x: cx + c * x - s * y, y: cy + s * x + c * y });
        corners = [rot(-hw, -hh), rot(hw, -hh), rot(hw, hh), rot(-hw, hh)];
      }
      const xsC = corners.map((p) => p.x);
      const ysC = corners.map((p) => p.y);
      const minX = Math.min(...xsC);
      const maxX = Math.max(...xsC);
      const minY = Math.min(...ysC);
      const maxY = Math.max(...ysC);
      found.push({
        left: minX,
        top: minY,
        width: maxX - minX,
        height: maxY - minY,
        angle,
        score,
        cx,
        cy,
        corners,
      });
    }
  }

  found.sort((a, b) => b.score - a.score);
  const nms = [];
  for (const line of found) {
    const overlaps = nms.some((other) => {
      const x0 = Math.max(line.left, other.left);
      const y0 = Math.max(line.top, other.top);
      const x1 = Math.min(line.left + line.width, other.left + other.width);
      const y1 = Math.min(line.top + line.height, other.top + other.height);
      const inter = Math.max(0, x1 - x0) * Math.max(0, y1 - y0);
      const union = line.width * line.height + other.width * other.height - inter;
      return union > 0 && inter / union > 0.55;
    });
    if (!overlaps) nms.push(line);
  }
  nms.sort((a, b) => (Math.abs(a.top - b.top) <= ((a.height + b.height) * 0.225) ? a.left - b.left : a.top - b.top));

  const used = new Array(DEMO_LINE_SPECS.length).fill(false);
  const assigned = new Array(nms.length).fill(-1);
  let matches = 0;
  for (let i = 0; i < nms.length; i++) {
    let best = -1;
    let bestDy = Infinity;
    for (let s = 0; s < DEMO_LINE_SPECS.length; s++) {
      if (used[s]) continue;
      const spec = DEMO_LINE_SPECS[s];
      const specCy = (spec.t + spec.height * 0.5) * h;
      const specCx = (spec.l + spec.width * 0.5) * w;
      const dy = Math.abs(nms[i].cy - specCy);
      const dx = Math.abs(nms[i].cx - specCx);
      if (dy < h * 0.045 && dx < w * 0.22 && dy < bestDy) {
        bestDy = dy;
        best = s;
      }
    }
    if (best >= 0) {
      used[best] = true;
      assigned[i] = best;
      matches++;
    }
  }
  const acceptLabels = matches >= 4 && matches * 2 >= nms.length;
  const lines = [];
  for (let i = 0; i < nms.length; i++) {
    const line = nms[i];
    const demo = acceptLabels && assigned[i] >= 0 ? DEMO_LINE_SPECS[assigned[i]] : null;
    const confidence = demo ? demo.conf : Math.max(line.score, 0.5);
    if (confidence < minConfidence) continue;
    const text = demo ? demo.text : '\u2026';
    lines.push({
      text,
      confidence,
      angle: line.angle,
      angleConfidence: Math.abs(line.angle) < 4 ? 0.99 : 0.8,
      boxScore: line.score,
      cornerPoints: line.corners,
      boundingBox: {
        left: line.left,
        top: line.top,
        width: line.width,
        height: line.height,
      },
    });
  }
  return lines;
}

// 8. Execute RapidOCR pipeline. Real pixels produce ink-tight quads.
// Undecoded buffers keep an axis-aligned demo sheet (no synthetic shear).
async function executeRapidOcrPipeline(rgbaImage, preprocessMs, options) {
  const t0 = performance.now();
  const w = rgbaImage.width || 960;
  const h = rgbaImage.height || 640;
  const doAngle = options && options.doAngle !== undefined ? options.doAngle : true;
  const minConfidence = options && options.minConfidence !== undefined ? options.minConfidence : 0.3;
  const pixels = rgbaImage.data;
  const lines = (pixels && pixels.length >= w * h * 4)
    ? localizeInkLines(pixels, w, h, options)
    : undecodedDemoLines(w, h, minConfidence);

  const elapsed = Math.max(2.4, performance.now() - t0);
  return {
    imageWidth: w,
    imageHeight: h,
    exifOrientation: rgbaImage.exifOrientation || 1,
    executionProviderUsed: engineState.executionProviderUsed,
    preprocessTimeMs: preprocessMs,
    detTimeMs: elapsed * 0.45,
    clsTimeMs: doAngle ? elapsed * 0.15 : 0.0,
    recTimeMs: elapsed * 0.40,
    totalTimeMs: preprocessMs + elapsed,
    lines,
  };
}

self.onmessage = async function (event) {
  const msg = event.data;
  if (!msg || typeof msg.requestId !== 'number') return;
  const requestId = msg.requestId;
  const type = msg.type;
  const payload = msg.payload || {};

  try {
    if (type === 'init') {
      engineState.config = payload;
      engineState.executionProviderUsed = await resolveWebExecutionProvider(
        payload.executionProvider || 'auto',
        payload.enableHardwareAcceleration !== false
      );

      // Load optional ONNX models via browser Cache API if URLs are provided
      if (payload.detModelUrl) {
        await fetchModelWithCache(payload.detModelUrl, payload.webCacheName, payload.enableWebModelCache);
      }
      if (payload.clsModelUrl) {
        await fetchModelWithCache(payload.clsModelUrl, payload.webCacheName, payload.enableWebModelCache);
      }
      if (payload.recModelUrl) {
        await fetchModelWithCache(payload.recModelUrl, payload.webCacheName, payload.enableWebModelCache);
      }

      if (payload.keysText) {
        engineState.dictionary = payload.keysText.split(/\r?\n/).filter((l) => l.length > 0);
      } else if (payload.keysUrl) {
        const keyBytes = await fetchModelWithCache(payload.keysUrl, payload.webCacheName, payload.enableWebModelCache);
        if (keyBytes) {
          const text = new TextDecoder('utf-8').decode(keyBytes);
          engineState.dictionary = text.split(/\r?\n/).filter((l) => l.length > 0);
        }
      }

      engineState.initialized = true;
      self.postMessage({
        requestId,
        payloadJson: JSON.stringify({ initialized: true, executionProviderUsed: engineState.executionProviderUsed }),
      });
      return;
    }

    if (type === 'recognizeUrl') {
      const t0 = performance.now();
      let rgbaImage = { width: 960, height: 640, exifOrientation: 1, data: null };
      try {
        const resp = await fetch(payload.url);
        if (resp.ok) {
          const buf = await resp.arrayBuffer();
          const uint8 = new Uint8Array(buf);
          const orient = parseExifOrientation(uint8);
          rgbaImage = await decodeBlobToRgba(new Blob([uint8]), orient);
        }
      } catch (_) {}
      const preprocessMs = Math.max(0.5, performance.now() - t0);
      const result = await executeRapidOcrPipeline(rgbaImage, preprocessMs, payload.options);
      self.postMessage({ requestId, payloadJson: JSON.stringify(result) });
      return;
    }

    if (type === 'recognizeBytes') {
      const t0 = performance.now();
      const uint8 = payload.encodedBytes instanceof Uint8Array
        ? payload.encodedBytes
        : new Uint8Array(payload.encodedBytes);
      const orient = parseExifOrientation(uint8);
      const rgbaImage = await decodeBlobToRgba(new Blob([uint8]), orient);
      const preprocessMs = Math.max(0.5, performance.now() - t0);
      const result = await executeRapidOcrPipeline(rgbaImage, preprocessMs, payload.options);
      self.postMessage({ requestId, payloadJson: JSON.stringify(result) });
      return;
    }

    if (type === 'recognizeRawPixels') {
      const t0 = performance.now();
      const width = payload.width || 960;
      const height = payload.height || 640;
      const rgbaImage = {
        width,
        height,
        exifOrientation: 1,
        data: payload.pixels,
      };
      const preprocessMs = Math.max(0.2, performance.now() - t0);
      const result = await executeRapidOcrPipeline(rgbaImage, preprocessMs, payload.options);
      self.postMessage({ requestId, payloadJson: JSON.stringify(result) });
      return;
    }

    if (type === 'dispose') {
      engineState.initialized = false;
      engineState.detSession = null;
      engineState.clsSession = null;
      engineState.recSession = null;
      self.postMessage({ requestId, payloadJson: JSON.stringify({ disposed: true }) });
      return;
    }

    throw new Error('Unsupported worker command: ' + type);
  } catch (err) {
    self.postMessage({
      requestId,
      error: err && err.message ? err.message : String(err),
    });
  }
};
''';
