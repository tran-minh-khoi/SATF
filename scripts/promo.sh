#!/bin/bash
# Dựng video giới thiệu SATF vào build/promo/. Chỉ chạy trên macOS.
#   ./scripts/promo.sh            -> TikTok/Reels dọc 1080×1920  (SATF-tiktok.mp4)
#   ./scripts/promo.sh youtube    -> YouTube ngang 1920×1080     (SATF-youtube.mp4)
# Thêm danh sách giây để lưu ảnh tĩnh xem nhanh, vd: ./scripts/promo.sh youtube 1.3,7.5
set -euo pipefail
cd "$(dirname "$0")/.."

KIND=tiktok
if [ "${1:-}" = youtube ] || [ "${1:-}" = tiktok ]; then KIND="$1"; shift; fi
SRC=scripts/promo.swift
[ "$KIND" = youtube ] && SRC=scripts/promo-youtube.swift

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/samples"
cp assets/logo.png "$TMP/samples/Vacation photo.png"
cp assets/logo.png "$TMP/samples/Screenshot.png"
sips -s format jpeg assets/logo.png --out "$TMP/samples/Beach day.jpg" >/dev/null
for f in "Report Q3.docx" "Budget 2026.xlsx" "Pitch deck.pptx"; do printf x > "$TMP/samples/$f"; done

cp "$SRC" "$TMP/main.swift"
xcrun swiftc -O -suppress-warnings -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  $(ls Sources/*.swift | grep -v main.swift) "$TMP/main.swift" -o "$TMP/promo"
"$TMP/promo" build/promo "$TMP/samples" "${1:-}"
