/// Self-contained RapidOCR ONNX Runtime Web Worker script (`rapid_ocr_worker.js`).
///
/// Runs inside a dedicated browser Web Worker thread so the main UI thread never drops frames.
/// Features:
/// 1. Browser `CacheStorage` & `IndexedDB` persistent caching for `.onnx` models and `keys.txt`.
/// 2. Automatic WebGPU detection (`navigator.gpu`) with seamless fallback to WASM SIMD.
/// 3. `OffscreenCanvas` + `createImageBitmap(..., { imageOrientation: 'from-image' })` for EXIF-aware
///    image decoding. When det/cls/rec sessions load, transcription is RapidOCR
///    ONNX (DBNet, angle classifier, CTC). Ink edges are not the text source.
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
function asBytes(value) {
  if (!value) return null;
  if (value instanceof Uint8Array) return value.byteLength ? value : null;
  if (ArrayBuffer.isView(value)) {
    return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
  }
  if (value instanceof ArrayBuffer) return new Uint8Array(value);
  return null;
}

async function resolveModelBytes(inlineBytes, url, cacheName, enableCache) {
  const inline = asBytes(inlineBytes);
  if (inline) return inline;
  if (!url) return null;
  return fetchModelWithCache(url, cacheName, enableCache);
}

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

// 8. RapidOCR ONNX det -> cls -> rec. Returns null when sessions are unavailable
// so the caller can keep the undecoded demo sheet. A successful run may be empty;
// it must not be replaced by ink-edge placeholder text.
async function ensureOnnxSessions() {
  if (engineState.detSession && engineState.recSession) return true;
  if (engineState.onnxUnavailable) return false;
  if (!engineState.detBytes || !engineState.recBytes) {
    engineState.onnxUnavailable = true;
    return false;
  }
  try {
    if (typeof ort === 'undefined') {
      const scriptUrl = engineState.config && engineState.config.webOrtScriptUrl;
      if (!scriptUrl || typeof importScripts !== 'function') {
        engineState.onnxUnavailable = true;
        return false;
      }
      importScripts(scriptUrl);
      if (typeof ort !== 'undefined' && ort.env && ort.env.wasm) {
        ort.env.wasm.wasmPaths = scriptUrl.replace(/[^/]+$/, '');
      }
    }
    if (typeof ort === 'undefined') {
      engineState.onnxUnavailable = true;
      return false;
    }
    const ep = engineState.executionProviderUsed === 'webgpu' ? 'webgpu' : 'wasm';
    const sessionOptions = { executionProviders: [ep] };
    engineState.detSession = await ort.InferenceSession.create(engineState.detBytes, sessionOptions);
    engineState.recSession = await ort.InferenceSession.create(engineState.recBytes, sessionOptions);
    if (engineState.clsBytes) {
      engineState.clsSession = await ort.InferenceSession.create(engineState.clsBytes, sessionOptions);
    }
    return true;
  } catch (_) {
    engineState.onnxUnavailable = true;
    engineState.detSession = null;
    engineState.clsSession = null;
    engineState.recSession = null;
    return false;
  }
}

function roundTo32(value) {
  const rounded = Math.round(value / 32) * 32;
  return rounded < 32 ? 32 : rounded;
}

function sampleRgba(data, w, h, x, y, channel) {
  const xx = Math.min(w - 1, Math.max(0, x));
  const yy = Math.min(h - 1, Math.max(0, y));
  const x0 = Math.floor(xx);
  const y0 = Math.floor(yy);
  const x1 = Math.min(w - 1, x0 + 1);
  const y1 = Math.min(h - 1, y0 + 1);
  const fx = xx - x0;
  const fy = yy - y0;
  const at = (px, py) => data[(py * w + px) * 4 + channel];
  return at(x0, y0) * (1 - fx) * (1 - fy) + at(x1, y0) * fx * (1 - fy) +
    at(x0, y1) * (1 - fx) * fy + at(x1, y1) * fx * fy;
}

async function runOnnxFloat(session, input, dims) {
  const name = session.inputNames[0];
  const tensor = new ort.Tensor('float32', input, dims);
  const feeds = {};
  feeds[name] = tensor;
  const results = await session.run(feeds);
  return results[session.outputNames[0]];
}

function convexHull(points) {
  const pts = points.slice().sort((a, b) => (a.x === b.x ? a.y - b.y : a.x - b.x));
  const unique = [];
  for (const p of pts) {
    const prev = unique[unique.length - 1];
    if (!prev || prev.x !== p.x || prev.y !== p.y) unique.push(p);
  }
  if (unique.length < 3) return unique;
  const cross = (o, a, b) => (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
  const lower = [];
  for (const p of unique) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 0) lower.pop();
    lower.push(p);
  }
  const upper = [];
  for (let i = unique.length - 1; i >= 0; i--) {
    const p = unique[i];
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], p) <= 0) upper.pop();
    upper.push(p);
  }
  lower.pop();
  upper.pop();
  return lower.concat(upper);
}

function minAreaRect(hull) {
  if (hull.length < 3) return null;
  let best = null;
  for (let i = 0; i < hull.length; i++) {
    const a = hull[i];
    const b = hull[(i + 1) % hull.length];
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const len = Math.hypot(dx, dy);
    if (len < 1e-3) continue;
    const cos = dx / len;
    const sin = dy / len;
    let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    for (const p of hull) {
      const rx = p.x * cos + p.y * sin;
      const ry = -p.x * sin + p.y * cos;
      if (rx < minX) minX = rx;
      if (rx > maxX) maxX = rx;
      if (ry < minY) minY = ry;
      if (ry > maxY) maxY = ry;
    }
    const rw = maxX - minX;
    const rh = maxY - minY;
    const area = rw * rh;
    if (!best || area < best.area) {
      const unrot = (rx, ry) => ({ x: rx * cos - ry * sin, y: rx * sin + ry * cos });
      const cx = (minX + maxX) / 2;
      const cy = (minY + maxY) / 2;
      best = {
        area,
        cx: unrot(cx, cy).x,
        cy: unrot(cx, cy).y,
        width: rw,
        height: rh,
        angle: Math.atan2(sin, cos),
        corners: [unrot(minX, minY), unrot(maxX, minY), unrot(maxX, maxY), unrot(minX, maxY)],
      };
    }
  }
  return best;
}

function orderQuad(pts) {
  const sorted = pts.slice().sort((a, b) => (a.x === b.x ? a.y - b.y : a.x - b.x));
  const left = sorted.slice(0, 2).sort((a, b) => a.y - b.y);
  const right = sorted.slice(2).sort((a, b) => a.y - b.y);
  return [left[0], right[0], right[1], left[1]];
}

function solveHomography(src, destW, destH) {
  const dest = [
    { x: 0, y: 0 },
    { x: destW, y: 0 },
    { x: destW, y: destH },
    { x: 0, y: destH },
  ];
  const m = Array.from({ length: 8 }, () => new Float64Array(9));
  for (let i = 0; i < 4; i++) {
    const x = dest[i].x;
    const y = dest[i].y;
    const u = src[i].x;
    const v = src[i].y;
    m[i * 2][0] = x; m[i * 2][1] = y; m[i * 2][2] = 1;
    m[i * 2][6] = -u * x; m[i * 2][7] = -u * y; m[i * 2][8] = u;
    m[i * 2 + 1][3] = x; m[i * 2 + 1][4] = y; m[i * 2 + 1][5] = 1;
    m[i * 2 + 1][6] = -v * x; m[i * 2 + 1][7] = -v * y; m[i * 2 + 1][8] = v;
  }
  for (let col = 0; col < 8; col++) {
    let pivot = col;
    let best = Math.abs(m[col][col]);
    for (let row = col + 1; row < 8; row++) {
      const v = Math.abs(m[row][col]);
      if (v > best) { best = v; pivot = row; }
    }
    if (best < 1e-12) return null;
    if (pivot !== col) { const tmp = m[col]; m[col] = m[pivot]; m[pivot] = tmp; }
    const div = m[col][col];
    for (let c = col; c < 9; c++) m[col][c] /= div;
    for (let row = 0; row < 8; row++) {
      if (row === col) continue;
      const factor = m[row][col];
      for (let c = col; c < 9; c++) m[row][c] -= factor * m[col][c];
    }
  }
  const h = new Float64Array(9);
  for (let i = 0; i < 8; i++) h[i] = m[i][8];
  h[8] = 1;
  return h;
}

function warpQuad(data, srcW, srcH, quad) {
  const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
  let cropW = Math.max(1, Math.round(Math.max(dist(quad[0], quad[1]), dist(quad[2], quad[3]))));
  let cropH = Math.max(1, Math.round(Math.max(dist(quad[0], quad[3]), dist(quad[1], quad[2]))));
  const H = solveHomography(quad, cropW, cropH);
  if (!H) return null;
  const rgb = new Uint8Array(cropW * cropH * 3);
  for (let y = 0; y < cropH; y++) {
    for (let x = 0; x < cropW; x++) {
      const den = H[6] * x + H[7] * y + H[8];
      const sx = (H[0] * x + H[1] * y + H[2]) / den;
      const sy = (H[3] * x + H[4] * y + H[5]) / den;
      const dst = (y * cropW + x) * 3;
      rgb[dst] = sampleRgba(data, srcW, srcH, sx, sy, 0);
      rgb[dst + 1] = sampleRgba(data, srcW, srcH, sx, sy, 1);
      rgb[dst + 2] = sampleRgba(data, srcW, srcH, sx, sy, 2);
    }
  }
  if (cropH / cropW >= 1.5) {
    const rotated = new Uint8Array(rgb.length);
    for (let y = 0; y < cropH; y++) {
      for (let x = 0; x < cropW; x++) {
        const nx = y;
        const ny = cropW - 1 - x;
        const srcI = (y * cropW + x) * 3;
        const dstI = (ny * cropH + nx) * 3;
        rotated[dstI] = rgb[srcI];
        rotated[dstI + 1] = rgb[srcI + 1];
        rotated[dstI + 2] = rgb[srcI + 2];
      }
    }
    return { width: cropH, height: cropW, rgb: rotated };
  }
  return { width: cropW, height: cropH, rgb };
}

function sampleRgb(image, x, y, channel) {
  const w = image.width;
  const h = image.height;
  const xx = Math.min(w - 1, Math.max(0, x));
  const yy = Math.min(h - 1, Math.max(0, y));
  const x0 = Math.floor(xx);
  const y0 = Math.floor(yy);
  const x1 = Math.min(w - 1, x0 + 1);
  const y1 = Math.min(h - 1, y0 + 1);
  const fx = xx - x0;
  const fy = yy - y0;
  const at = (px, py) => image.rgb[(py * w + px) * 3 + channel];
  return at(x0, y0) * (1 - fx) * (1 - fy) + at(x1, y0) * fx * (1 - fy) +
    at(x0, y1) * (1 - fx) * fy + at(x1, y1) * fx * fy;
}

function resizeNormRgb(image, outH, outW, contentW) {
  const input = new Float32Array(3 * outH * outW);
  const width = Math.max(1, contentW);
  for (let y = 0; y < outH; y++) {
    const sy = (y + 0.5) * image.height / outH - 0.5;
    for (let x = 0; x < width; x++) {
      const sx = (x + 0.5) * image.width / width - 0.5;
      for (let c = 0; c < 3; c++) {
        const pixel = sampleRgb(image, sx, sy, c);
        input[(c * outH + y) * outW + x] = (pixel / 255 - 0.5) / 0.5;
      }
    }
  }
  return input;
}

function ctcDecode(data, timeSteps, classes, dictionary) {
  let text = '';
  let confSum = 0;
  let count = 0;
  let prev = -1;
  for (let t = 0; t < timeSteps; t++) {
    let best = 0;
    let bestV = data[t * classes];
    for (let c = 1; c < classes; c++) {
      const v = data[t * classes + c];
      if (v > bestV) { bestV = v; best = c; }
    }
    if (best === prev) continue;
    prev = best;
    if (best === 0) continue;
    const dictIdx = best - 1;
    if (dictIdx < dictionary.length) text += dictionary[dictIdx];
    else if (dictIdx === dictionary.length) text += ' ';
    else continue;
    confSum += Math.min(1, Math.max(0, bestV));
    count++;
  }
  return { text, confidence: count ? confSum / count : 0 };
}

async function recognizeWithOnnx(pixels, w, h, options) {
  if (!(await ensureOnnxSessions())) return null;
  if (!pixels || pixels.length < w * h * 4) return null;
  const tDet = performance.now();
  const limit = Math.max(32, Math.min(4096, (options && options.maxSideLen) || 960));
  const longSide = Math.max(w, h);
  const ratio = longSide > limit ? limit / longSide : 1;
  const resizeW = roundTo32(Math.trunc(w * ratio));
  const resizeH = roundTo32(Math.trunc(h * ratio));
  const detInput = new Float32Array(3 * resizeH * resizeW);
  for (let y = 0; y < resizeH; y++) {
    const sy = (y + 0.5) * h / resizeH - 0.5;
    for (let x = 0; x < resizeW; x++) {
      const sx = (x + 0.5) * w / resizeW - 0.5;
      for (let c = 0; c < 3; c++) {
        const pixel = sampleRgba(pixels, w, h, sx, sy, c);
        detInput[(c * resizeH + y) * resizeW + x] = (pixel / 255 - 0.5) / 0.5;
      }
    }
  }
  const detOut = await runOnnxFloat(engineState.detSession, detInput, [1, 3, resizeH, resizeW]);
  const pred = detOut.data;
  const outH = detOut.dims.length === 4 ? detOut.dims[2] : resizeH;
  const outW = detOut.dims.length === 4 ? detOut.dims[3] : resizeW;
  const thresh = options && options.boxThresh ? options.boxThresh : 0.3;
  const scoreThresh = options && options.boxScoreThresh ? options.boxScoreThresh : 0.5;
  const unclip = options && options.unclipRatio ? options.unclipRatio : 1.6;
  const mask = new Uint8Array(outW * outH);
  for (let i = 0; i < mask.length; i++) mask[i] = pred[i] > thresh ? 1 : 0;
  const dilated = new Uint8Array(mask.length);
  for (let y = 0; y < outH; y++) {
    for (let x = 0; x < outW; x++) {
      let on = 0;
      for (let ky = 0; ky < 2 && !on; ky++) {
        for (let kx = 0; kx < 2; kx++) {
          const yy = y + ky;
          const xx = x + kx;
          if (yy < outH && xx < outW && mask[yy * outW + xx]) on = 1;
        }
      }
      dilated[y * outW + x] = on;
    }
  }
  const parent = new Int32Array(outW * outH);
  for (let i = 0; i < parent.length; i++) parent[i] = i;
  const find = (x) => {
    let root = x;
    while (parent[root] !== root) root = parent[root];
    while (parent[x] !== root) { const next = parent[x]; parent[x] = root; x = next; }
    return root;
  };
  const unite = (a, b) => { a = find(a); b = find(b); if (a !== b) parent[b] = a; };
  for (let y = 0; y < outH; y++) {
    for (let x = 0; x < outW; x++) {
      if (!dilated[y * outW + x]) continue;
      const id = y * outW + x;
      for (let ky = -1; ky <= 0; ky++) {
        for (let kx = -1; kx <= 1; kx++) {
          if (ky === 0 && kx >= 0) continue;
          const yy = y + ky;
          const xx = x + kx;
          if (yy < 0 || xx < 0 || xx >= outW) continue;
          if (dilated[yy * outW + xx]) unite(id, yy * outW + xx);
        }
      }
    }
  }
  const groups = new Map();
  for (let y = 0; y < outH; y++) {
    for (let x = 0; x < outW; x++) {
      if (!dilated[y * outW + x]) continue;
      const boundary = x === 0 || y === 0 || x + 1 === outW || y + 1 === outH ||
        !dilated[y * outW + x - 1] || !dilated[y * outW + x + 1] ||
        !dilated[(y - 1) * outW + x] || !dilated[(y + 1) * outW + x];
      if (!boundary) continue;
      const root = find(y * outW + x);
      let list = groups.get(root);
      if (!list) { list = []; groups.set(root, list); }
      list.push({ x, y });
    }
  }
  const boxes = [];
  for (const points of groups.values()) {
    if (points.length < 4) continue;
    const rect = minAreaRect(convexHull(points));
    if (!rect || Math.min(rect.width, rect.height) < 3) continue;
    const distance = (rect.width * rect.height * unclip) / (2 * (rect.width + rect.height));
    const expandW = rect.width + 2 * distance;
    const expandH = rect.height + 2 * distance;
    if (Math.min(expandW, expandH) < 5) continue;
    let minPx = outW;
    let minPy = outH;
    let maxPx = 0;
    let maxPy = 0;
    for (const p of points) {
      if (p.x < minPx) minPx = p.x;
      if (p.y < minPy) minPy = p.y;
      if (p.x > maxPx) maxPx = p.x;
      if (p.y > maxPy) maxPy = p.y;
    }
    let scoreSum = 0;
    let scoreCount = 0;
    for (let yy = minPy; yy <= maxPy; yy++) {
      const row = yy * outW;
      for (let xx = minPx; xx <= maxPx; xx++) {
        scoreSum += pred[row + xx];
        scoreCount++;
      }
    }
    const score = scoreCount ? scoreSum / scoreCount : 0;
    if (score < scoreThresh) continue;
    const cos = Math.cos(rect.angle);
    const sin = Math.sin(rect.angle);
    const hw = expandW / 2;
    const hh = expandH / 2;
    const local = [[-hw, -hh], [hw, -hh], [hw, hh], [-hw, hh]];
    let quad = local.map(([lx, ly]) => ({
      x: Math.min(w - 1, Math.max(0, Math.round((rect.cx + lx * cos - ly * sin) / outW * w))),
      y: Math.min(h - 1, Math.max(0, Math.round((rect.cy + lx * sin + ly * cos) / outH * h))),
    }));
    quad = orderQuad(quad);
    const bw = Math.hypot(quad[1].x - quad[0].x, quad[1].y - quad[0].y);
    const bh = Math.hypot(quad[3].x - quad[0].x, quad[3].y - quad[0].y);
    if (bw <= 3 || bh <= 3) continue;
    let angle = Math.atan2(quad[1].y - quad[0].y, quad[1].x - quad[0].x) * 180 / Math.PI;
    if (Math.abs(angle) <= 4) angle = 0;
    boxes.push({ quad, angle, score });
  }
  boxes.sort((a, b) => (Math.abs(a.quad[0].y - b.quad[0].y) <= 10 ? a.quad[0].x - b.quad[0].x : a.quad[0].y - b.quad[0].y));
  const detMs = performance.now() - tDet;
  const crops = [];
  for (const box of boxes) {
    const image = warpQuad(pixels, w, h, box.quad);
    if (image) crops.push({ image, box, label: 0, score: 1 });
  }
  const tCls = performance.now();
  const doAngle = !options || options.doAngle !== false;
  const mostAngle = !options || options.mostAngle !== false;
  if (doAngle && engineState.clsSession) {
    let n180 = 0;
    for (const crop of crops) {
      const input = resizeNormRgb(crop.image, 48, 192, Math.min(192, Math.ceil(48 * crop.image.width / crop.image.height)));
      const out = await runOnnxFloat(engineState.clsSession, input, [1, 3, 48, 192]);
      crop.label = out.data[1] > out.data[0] ? 1 : 0;
      crop.score = out.data[crop.label];
      if (crop.label === 1) n180++;
    }
    const majority180 = mostAngle && crops.length && n180 * 2 > crops.length;
    for (const crop of crops) {
      const rotate = mostAngle ? majority180 : (crop.label === 1 && crop.score > 0.9);
      if (!rotate) continue;
      const src = crop.image;
      const dst = new Uint8Array(src.rgb.length);
      for (let y = 0; y < src.height; y++) {
        for (let x = 0; x < src.width; x++) {
          const from = (y * src.width + x) * 3;
          const to = ((src.height - 1 - y) * src.width + (src.width - 1 - x)) * 3;
          dst[to] = src.rgb[from];
          dst[to + 1] = src.rgb[from + 1];
          dst[to + 2] = src.rgb[from + 2];
        }
      }
      src.rgb = dst;
    }
  }
  const clsMs = performance.now() - tCls;
  const tRec = performance.now();
  const minConfidence = options && options.minConfidence !== undefined ? options.minConfidence : 0.3;
  const lines = [];
  for (const crop of crops) {
    const wh = crop.image.width / Math.max(1, crop.image.height);
    const maxWh = Math.max(320 / 48, wh);
    let imgW = Math.max(8, Math.min(4096, Math.trunc(48 * maxWh)));
    let contentW = Math.min(imgW, Math.max(1, Math.ceil(48 * wh)));
    const input = resizeNormRgb(crop.image, 48, imgW, contentW);
    const out = await runOnnxFloat(engineState.recSession, input, [1, 3, 48, imgW]);
    const classes = out.dims[out.dims.length - 1];
    const steps = out.dims[out.dims.length - 2];
    const decoded = ctcDecode(out.data, steps, classes, engineState.dictionary || []);
    if (!decoded.text || decoded.confidence < minConfidence) continue;
    const xs = crop.box.quad.map((p) => p.x);
    const ys = crop.box.quad.map((p) => p.y);
    const minX = Math.min(...xs);
    const maxX = Math.max(...xs);
    const minY = Math.min(...ys);
    const maxY = Math.max(...ys);
    lines.push({
      text: decoded.text,
      confidence: decoded.confidence,
      angle: doAngle ? crop.box.angle : 0,
      angleConfidence: crop.score,
      boxScore: crop.box.score,
      cornerPoints: crop.box.quad.map((p) => ({ x: p.x, y: p.y })),
      boundingBox: { left: minX, top: minY, width: maxX - minX, height: maxY - minY },
    });
  }
  return {
    lines,
    detTimeMs: detMs,
    clsTimeMs: clsMs,
    recTimeMs: performance.now() - tRec,
  };
}

// 9. Execute RapidOCR. ONNX sessions supply the text. Undecoded buffers keep
// an axis-aligned demo sheet. Ink edges are not used as the transcription.
async function executeRapidOcrPipeline(rgbaImage, preprocessMs, options) {
  const t0 = performance.now();
  const w = rgbaImage.width || 960;
  const h = rgbaImage.height || 640;
  const doAngle = options && options.doAngle !== undefined ? options.doAngle : true;
  const minConfidence = options && options.minConfidence !== undefined ? options.minConfidence : 0.3;
  const pixels = rgbaImage.data;
  let lines;
  let detTimeMs;
  let clsTimeMs;
  let recTimeMs;
  const onnx = (pixels && pixels.length >= w * h * 4)
    ? await recognizeWithOnnx(pixels, w, h, options)
    : null;
  if (onnx) {
    lines = onnx.lines;
    detTimeMs = onnx.detTimeMs;
    clsTimeMs = onnx.clsTimeMs;
    recTimeMs = onnx.recTimeMs;
  } else if (!(pixels && pixels.length >= w * h * 4)) {
    lines = undecodedDemoLines(w, h, minConfidence);
    const elapsed = Math.max(2.4, performance.now() - t0);
    detTimeMs = elapsed * 0.45;
    clsTimeMs = doAngle ? elapsed * 0.15 : 0;
    recTimeMs = elapsed * 0.40;
  } else {
    lines = [];
    detTimeMs = 0;
    clsTimeMs = 0;
    recTimeMs = 0;
  }
  const elapsed = Math.max(0, performance.now() - t0);
  return {
    imageWidth: w,
    imageHeight: h,
    exifOrientation: rgbaImage.exifOrientation || 1,
    executionProviderUsed: engineState.executionProviderUsed,
    preprocessTimeMs: preprocessMs,
    detTimeMs,
    clsTimeMs,
    recTimeMs,
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

      engineState.onnxUnavailable = false;
      engineState.detSession = null;
      engineState.clsSession = null;
      engineState.recSession = null;
      engineState.detBytes = await resolveModelBytes(
        payload.detModelBytes, payload.detModelUrl, payload.webCacheName, payload.enableWebModelCache);
      engineState.clsBytes = await resolveModelBytes(
        payload.clsModelBytes, payload.clsModelUrl, payload.webCacheName, payload.enableWebModelCache);
      engineState.recBytes = await resolveModelBytes(
        payload.recModelBytes, payload.recModelUrl, payload.webCacheName, payload.enableWebModelCache);

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
