#!/usr/bin/env bash
# Download RapidOCR PP-OCRv4 ONNX models + dictionaries into assets/models/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/assets/models"
BASE="${MODELSCOPE_BASE:-https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/v3.4.0}"
HF="${HF_BASE:-https://huggingface.co/SWHL/RapidOCR/resolve/main}"
mkdir -p "$DIR"
cd "$DIR"

download() {
  local url="$1" out="$2" alt="${3:-}"
  if [[ -f "$out" && -s "$out" ]]; then
    echo "SKIP $out"
    return 0
  fi
  echo "GET $out"
  if curl -L --fail --retry 3 --connect-timeout 30 -o "$out.tmp" "$url"; then
    mv "$out.tmp" "$out"
    echo "OK $out"
    return 0
  fi
  rm -f "$out.tmp"
  if [[ -n "$alt" ]] && curl -L --fail --retry 3 --connect-timeout 30 -o "$out.tmp" "$alt"; then
    mv "$out.tmp" "$out"
    echo "OK $out (hf)"
    return 0
  fi
  rm -f "$out.tmp"
  echo "FAIL $out" >&2
  return 1
}

download "$BASE/onnx/PP-OCRv4/cls/ch_ppocr_mobile_v2.0_cls_infer.onnx" ch_ppocr_mobile_v2.0_cls_infer.onnx "$HF/PP-OCRv4/ch_ppocr_mobile_v2.0_cls_infer.onnx"
download "$BASE/onnx/PP-OCRv4/det/ch_PP-OCRv4_det_infer.onnx" ch_PP-OCRv4_det_infer.onnx "$HF/PP-OCRv4/ch_PP-OCRv4_det_infer.onnx"
download "$BASE/onnx/PP-OCRv4/rec/ch_PP-OCRv4_rec_infer.onnx" ch_PP-OCRv4_rec_infer.onnx "$HF/PP-OCRv4/ch_PP-OCRv4_rec_infer.onnx"
download "$BASE/paddle/PP-OCRv4/rec/ch_PP-OCRv4_rec_infer/ppocr_keys_v1.txt" ppocr_keys_v1.txt
download "$BASE/onnx/PP-OCRv4/det/Multilingual_PP-OCRv3_det_infer.onnx" Multilingual_PP-OCRv3_det_infer.onnx "$HF/PP-OCRv4/Multilingual_PP-OCRv3_det_infer.onnx"
download "$BASE/onnx/PP-OCRv4/rec/en_PP-OCRv4_rec_infer.onnx" en_PP-OCRv4_rec_infer.onnx "$HF/PP-OCRv4/en_PP-OCRv4_rec_infer.onnx"
download "$BASE/paddle/PP-OCRv4/rec/en_PP-OCRv4_rec_infer/en_dict.txt" en_dict.txt
download "$BASE/onnx/PP-OCRv4/rec/japan_PP-OCRv4_rec_infer.onnx" japan_PP-OCRv4_rec_infer.onnx "$HF/PP-OCRv4/japan_PP-OCRv4_rec_infer.onnx"
download "$BASE/paddle/PP-OCRv4/rec/japan_PP-OCRv4_rec_infer/japan_dict.txt" japan_dict.txt
download "$BASE/onnx/PP-OCRv4/rec/korean_PP-OCRv4_rec_infer.onnx" korean_PP-OCRv4_rec_infer.onnx "$HF/PP-OCRv4/korean_PP-OCRv4_rec_infer.onnx"
download "$BASE/paddle/PP-OCRv4/rec/korean_PP-OCRv4_rec_infer/korean_dict.txt" korean_dict.txt
download "$BASE/onnx/PP-OCRv4/rec/latin_PP-OCRv3_rec_infer.onnx" latin_PP-OCRv3_rec_infer.onnx "$HF/PP-OCRv4/latin_PP-OCRv3_rec_infer.onnx"
download "$BASE/paddle/PP-OCRv4/rec/latin_PP-OCRv3_rec_infer/latin_dict.txt" latin_dict.txt
download "$BASE/onnx/PP-OCRv4/rec/cyrillic_PP-OCRv3_rec_infer.onnx" cyrillic_PP-OCRv3_rec_infer.onnx "$HF/PP-OCRv4/cyrillic_PP-OCRv3_rec_infer.onnx"
download "$BASE/paddle/PP-OCRv4/rec/cyrillic_PP-OCRv3_rec_infer/cyrillic_dict.txt" cyrillic_dict.txt
download "$BASE/onnx/PP-OCRv4/rec/arabic_PP-OCRv4_rec_infer.onnx" arabic_PP-OCRv4_rec_infer.onnx "$HF/PP-OCRv4/arabic_PP-OCRv4_rec_infer.onnx"
download "$BASE/paddle/PP-OCRv4/rec/arabic_PP-OCRv4_rec_infer/arabic_dict.txt" arabic_dict.txt
echo "Done. Models in $DIR"
ls -lh
