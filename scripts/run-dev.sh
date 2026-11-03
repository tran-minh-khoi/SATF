#!/bin/bash
# Build nhanh bản chạy thử để xem giao diện: chỉ chip của máy này, tối ưu như bản phát hành (-O), ký ad-hoc, không tạo DMG, rồi mở luôn.
# Bản SATF đang chạy (nếu có) sẽ được tắt trước. Chạy bản phát hành: ./build.sh
#   APPSTORE=1 ./scripts/run-dev.sh   chạy thử bản Mac App Store: bật sandbox, lưu file vào Downloads
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/dev/SATF.app
SDK="$(xcrun --sdk macosx --show-sdk-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/FormatIcons"
FLAG=""
[ "${APPSTORE:-0}" = 1 ] && FLAG="-D APPSTORE"
echo "▸ Biên dịch ($(uname -m)) ${FLAG}…"
xcrun swiftc -O -swift-version 5 $FLAG -sdk "$SDK" -target "$(uname -m)-apple-macos13.0" Sources/*.swift -o "$APP/Contents/MacOS/SATF"

cp Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$(tr -d '[:space:]' < VERSION)" "$APP/Contents/Info.plist"
cp THIRD_PARTY_NOTICES.md LICENSE assets/images/donate-qr.png "$APP/Contents/Resources/"
for F in assets/icons/formats/*.png; do
  sips -Z 128 "$F" --out "$APP/Contents/Resources/FormatIcons/$(basename "$F")" >/dev/null
done
# Icon app và cwebp lấy lại từ bản build đầy đủ gần nhất (nếu có) cho nhanh
for F in AppIcon.icns cwebp; do
  [ -f "build/SATF.app/Contents/Resources/$F" ] && cp "build/SATF.app/Contents/Resources/$F" "$APP/Contents/Resources/"
done
if [ "${APPSTORE:-0}" = 1 ]; then
  [ -f "$APP/Contents/Resources/cwebp" ] && codesign --force --sign - --entitlements appstore/cwebp.entitlements "$APP/Contents/Resources/cwebp"
  codesign --force --sign - --entitlements appstore/dev-sandbox.entitlements "$APP"
else
  codesign --force --deep --sign - "$APP" 2>/dev/null
fi

pkill -x SATF 2>/dev/null && sleep 0.7 || true
open "$APP"
echo "✓ Đang chạy bản thử: $APP"
