#!/bin/bash
# Chụp lại ảnh giao diện cho README (docs/images/*.jpg) từ chính code SwiftUI của app. Chỉ chạy trên macOS.
set -euo pipefail
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/samples" docs/images

# File mẫu để hiện trong menu / khay
cp assets/logo.png "$TMP/samples/Vacation photo.png"
cp assets/logo.png "$TMP/samples/Screenshot.png"
sips -s format jpeg assets/logo.png --out "$TMP/samples/Beach day.jpg" >/dev/null
cp assets/donate-vietqr.png "$TMP/"   # cửa sổ Ủng hộ đọc mã QR cạnh chương trình chụp
for f in "Report Q3.docx" "Budget 2026.xlsx" "Pitch deck.pptx" "Holiday.zip"; do printf 'x' > "$TMP/samples/$f"; done

cp scripts/screenshots.swift "$TMP/main.swift"   # Swift chỉ chạy code trực tiếp trong main.swift
xcrun swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  $(ls Sources/*.swift | grep -v main.swift) "$TMP/main.swift" -o "$TMP/shots" 2>/dev/null
"$TMP/shots" docs/images "$TMP/samples" dark
echo "✓ Đã cập nhật docs/images"
