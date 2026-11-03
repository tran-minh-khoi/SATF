#!/bin/bash
# Chụp lại ảnh giao diện cho README (docs/images/*.jpg) từ chính code SwiftUI của app. Chỉ chạy trên macOS.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-docs/images}"   # thư mục lưu ảnh (mặc định cho README)
MODE="${2:-}"             # appstore: ảnh 2880x1800 cho Mac App Store (tiếng Anh + tiếng Việt), giao diện bản App Store

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/samples" "$OUT"

# File mẫu để hiện trong menu / khay
cp assets/brand/logo.png "$TMP/samples/Vacation photo.png"
cp assets/brand/logo.png "$TMP/samples/Screenshot.png"
sips -s format jpeg assets/brand/logo.png --out "$TMP/samples/Beach day.jpg" >/dev/null
cp assets/images/donate-qr.png "$TMP/"   # cửa sổ Ủng hộ đọc mã QR cạnh chương trình chụp
for f in "Report Q3.docx" "Budget 2026.xlsx" "Pitch deck.pptx" "Holiday.zip"; do printf 'x' > "$TMP/samples/$f"; done

cp scripts/screenshots.swift "$TMP/main.swift"   # Swift chỉ chạy code trực tiếp trong main.swift
FLAG=""
[ "$MODE" = appstore ] && FLAG="-D APPSTORE"
xcrun swiftc $FLAG -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  $(ls Sources/*.swift | grep -v main.swift) "$TMP/main.swift" -o "$TMP/shots" 2>/dev/null
if [ "$MODE" = appstore ]; then
  for LANG_CODE in en vi; do "$TMP/shots" "$OUT" "$TMP/samples" dark appstore "$LANG_CODE"; done
else
  "$TMP/shots" "$OUT" "$TMP/samples" dark
fi
echo "✓ Đã lưu ảnh vào $OUT"
