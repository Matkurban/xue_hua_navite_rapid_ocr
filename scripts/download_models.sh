#!/usr/bin/env bash
# Download RapidOCR ONNX models + dictionaries aligned with RapidOCR v3.10.0
# Source of truth: https://github.com/RapidAI/RapidOCR/blob/v3.10.0/python/rapidocr/default_models.yaml
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/assets/models"
BASE="${MODELSCOPE_BASE:-https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/v3.10.0}"
mkdir -p "$DIR"
cd "$DIR"

# download <url> <out> [sha256]
download() {
  local url="$1" out="$2" expect_sha="${3:-}"
  if [[ -f "$out" && -s "$out" ]]; then
    if [[ -n "$expect_sha" ]]; then
      local got
      got="$(shasum -a 256 "$out" | awk '{print $1}')"
      if [[ "$got" == "$expect_sha" ]]; then
        echo "SKIP $out (sha256 ok)"
        return 0
      fi
      echo "REGET $out (sha256 mismatch)"
      rm -f "$out"
    else
      echo "SKIP $out"
      return 0
    fi
  fi
  echo "GET $out"
  if ! curl -L --fail --retry 3 --connect-timeout 30 -o "$out.tmp" "$url"; then
    rm -f "$out.tmp"
    echo "FAIL $out" >&2
    return 1
  fi
  if [[ -n "$expect_sha" ]]; then
    local got
    got="$(shasum -a 256 "$out.tmp" | awk '{print $1}')"
    if [[ "$got" != "$expect_sha" ]]; then
      echo "SHA256 FAIL $out expected=$expect_sha got=$got" >&2
      rm -f "$out.tmp"
      return 1
    fi
  fi
  mv "$out.tmp" "$out"
  echo "OK $out"
}

echo "RapidOCR model pack: v3.10.0 (ModelScope resolve/v3.10.0)"
echo "Target directory: $DIR"

# --- PP-OCRv4 defaults (onnxruntime section) ---
# cls
download "$BASE/onnx/PP-OCRv4/cls/ch_ppocr_mobile_v2.0_cls_mobile.onnx" \
  ch_ppocr_mobile_v2.0_cls_mobile.onnx \
  e47acedf663230f8863ff1ab0e64dd2d82b838fceb5957146dab185a89d6215c

# det
download "$BASE/onnx/PP-OCRv4/det/ch_PP-OCRv4_det_mobile.onnx" \
  ch_PP-OCRv4_det_mobile.onnx \
  d2a7720d45a54257208b1e13e36a8479894cb74155a5efe29462512d42f49da9
download "$BASE/onnx/PP-OCRv4/det/multi_PP-OCRv3_det_mobile.onnx" \
  multi_PP-OCRv3_det_mobile.onnx \
  5582933662898cd2b4c2eae8a7e5e4fbdff84773711f29db00a1cbd185059001

# rec + dicts
download "$BASE/onnx/PP-OCRv4/rec/ch_PP-OCRv4_rec_mobile.onnx" \
  ch_PP-OCRv4_rec_mobile.onnx \
  48fc40f24f6d2a207a2b1091d3437eb3cc3eb6b676dc3ef9c37384005483683b
download "$BASE/paddle/PP-OCRv4/rec/ch_PP-OCRv4_rec_mobile/ppocr_keys_v1.txt" \
  ppocr_keys_v1.txt

download "$BASE/onnx/PP-OCRv4/rec/en_PP-OCRv4_rec_mobile.onnx" \
  en_PP-OCRv4_rec_mobile.onnx \
  e8770c967605983d1570cdf5352041dfb68fa0c21664f49f47b155abd3e0e318
download "$BASE/paddle/PP-OCRv4/rec/en_PP-OCRv4_rec_mobile/en_dict.txt" \
  en_dict.txt

download "$BASE/onnx/PP-OCRv4/rec/japan_PP-OCRv4_rec_mobile.onnx" \
  japan_PP-OCRv4_rec_mobile.onnx \
  e1075a67dba758ecfc7ebc78a10ae61c95ac8fb66a9c86fab5541e33f085cb7a
download "$BASE/paddle/PP-OCRv4/rec/japan_PP-OCRv4_rec_mobile/japan_dict.txt" \
  japan_dict.txt

download "$BASE/onnx/PP-OCRv4/rec/korean_PP-OCRv4_rec_mobile.onnx" \
  korean_PP-OCRv4_rec_mobile.onnx \
  ab151ba9065eccd98f884cf4d927db091be86137276392072edd4f9d43ad7426
download "$BASE/paddle/PP-OCRv4/rec/korean_PP-OCRv4_rec_mobile/korean_dict.txt" \
  korean_dict.txt

download "$BASE/onnx/PP-OCRv4/rec/latin_PP-OCRv3_rec_mobile.onnx" \
  latin_PP-OCRv3_rec_mobile.onnx \
  e9d7a33667e8aaa702862975186adf2012e3f390cc0f9422865957125f8071cf
download "$BASE/paddle/PP-OCRv4/rec/latin_PP-OCRv3_rec_mobile/latin_dict.txt" \
  latin_dict.txt

download "$BASE/onnx/PP-OCRv4/rec/cyrillic_PP-OCRv3_rec_mobile.onnx" \
  cyrillic_PP-OCRv3_rec_mobile.onnx \
  1efb65bdc460af1c0e8733d005b20952b17ca5aac10ddb56c968333791c5eaa3
download "$BASE/paddle/PP-OCRv4/rec/cyrillic_PP-OCRv3_rec_mobile/cyrillic_dict.txt" \
  cyrillic_dict.txt

download "$BASE/onnx/PP-OCRv4/rec/arabic_PP-OCRv4_rec_mobile.onnx" \
  arabic_PP-OCRv4_rec_mobile.onnx \
  4a9011bef71687bb84288dc86ad2471bd5d37b717ddf672dd156f9e7a5601bac
download "$BASE/paddle/PP-OCRv4/rec/arabic_PP-OCRv4_rec_mobile/arabic_dict.txt" \
  arabic_dict.txt

# --- Optional PP-OCRv5 Chinese mobile (upgrade path) ---
if [[ "${DOWNLOAD_PPOCRV5:-1}" == "1" ]]; then
  echo "Also downloading optional PP-OCRv5 Chinese mobile models..."
  download "$BASE/onnx/PP-OCRv5/det/ch_PP-OCRv5_det_mobile.onnx" \
    ch_PP-OCRv5_det_mobile.onnx \
    4d97c44a20d30a81aad087d6a396b08f786c4635742afc391f6621f5c6ae78ae
  download "$BASE/onnx/PP-OCRv5/rec/ch_PP-OCRv5_rec_mobile.onnx" \
    ch_PP-OCRv5_rec_mobile.onnx \
    5825fc7ebf84ae7a412be049820b4d86d77620f204a041697b0494669b1742c5
  download "$BASE/paddle/PP-OCRv5/rec/ch_PP-OCRv5_rec_mobile/ppocrv5_dict.txt" \
    ppocrv5_dict.txt
  download "$BASE/onnx/PP-OCRv5/cls/ch_PP-LCNet_x0_25_textline_ori_cls_mobile.onnx" \
    ch_PP-LCNet_x0_25_textline_ori_cls_mobile.onnx \
    54379ae5174d026780215fc748a7f31910dee36818e63d49e17dc598ecc82df7
fi

# Remove legacy v3.4.0 *_infer filenames if present
for legacy in \
  ch_ppocr_mobile_v2.0_cls_infer.onnx \
  ch_PP-OCRv4_det_infer.onnx \
  ch_PP-OCRv4_rec_infer.onnx \
  Multilingual_PP-OCRv3_det_infer.onnx \
  en_PP-OCRv4_rec_infer.onnx \
  japan_PP-OCRv4_rec_infer.onnx \
  korean_PP-OCRv4_rec_infer.onnx \
  latin_PP-OCRv3_rec_infer.onnx \
  cyrillic_PP-OCRv3_rec_infer.onnx \
  arabic_PP-OCRv4_rec_infer.onnx \
  multilingual_PP-OCRv4_rec_infer.onnx
do
  if [[ -f "$legacy" ]]; then
    echo "RM legacy $legacy"
    rm -f "$legacy"
  fi
done

echo "Done. Models in $DIR (RapidOCR v3.10.0)"
echo "Native det/cls/rec also needs ONNX Runtime 1.20.1: scripts/download_onnxruntime.sh"
ls -lh
