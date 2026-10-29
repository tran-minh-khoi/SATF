#!/bin/bash
# Dựng video giới thiệu dọc 1080×1920 cho TikTok/Reels -> build/promo/SATF-tiktok.mp4. Chỉ chạy trên macOS.
# Tuỳ chọn: ./scripts/promo.sh 5.5,7.9  -> lưu thêm ảnh tĩnh ở các giây đó để xem nhanh.
set -euo pipefail
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/samples"
cp assets/logo.png "$TMP/samples/Vacation photo.png"
cp assets/logo.png "$TMP/samples/Screenshot.png"
sips -s format jpeg assets/logo.png --out "$TMP/samples/Beach day.jpg" >/dev/null
for f in "Report Q3.docx" "Budget 2026.xlsx" "Pitch deck.pptx"; do printf x > "$TMP/samples/$f"; done

cp scripts/promo.swift "$TMP/main.swift"
xcrun swiftc -O -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  $(ls Sources/*.swift | grep -v main.swift) "$TMP/main.swift" -o "$TMP/promo" 2>&1 | grep -E "error" || true
"$TMP/promo" build/promo "$TMP/samples" "${1:-}"
