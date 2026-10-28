#!/bin/bash
# Build SATF.app và SATF-<version>.dmg — chỉ cần Command Line Tools (xcode-select --install), không cần mở Xcode.
set -euo pipefail
cd "$(dirname "$0")"

APP=SATF
OUT=build
BUNDLE="$OUT/$APP.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

rm -rf "$BUNDLE" "$OUT"/*.dmg   # chỉ xoá bản Mac, giữ lại build/windows
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

echo "▸ Tạo icon từ assets/logo.png…"
LOGO=assets/logo.png
ICONSET="$OUT/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for S in 16 32 128 256 512; do
  sips -z $S $S "$LOGO" --out "$ICONSET/icon_${S}x${S}.png" >/dev/null
  sips -z $((S*2)) $((S*2)) "$LOGO" --out "$ICONSET/icon_${S}x${S}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "▸ Biên dịch (Apple Silicon + Intel)…"
for ARCH in arm64 x86_64; do
  xcrun swiftc -O -swift-version 5 \
    -sdk "$SDK" -target "$ARCH-apple-macos13.0" \
    Sources/*.swift -o "$OUT/$APP-$ARCH"
done
lipo -create -output "$BUNDLE/Contents/MacOS/$APP" "$OUT/$APP-arm64" "$OUT/$APP-x86_64"
rm "$OUT/$APP-arm64" "$OUT/$APP-x86_64"

VERSION="$(tr -d '[:space:]' < VERSION)"
cp Info.plist "$BUNDLE/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$BUNDLE/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$BUNDLE/Contents/Info.plist"

echo "▸ Đóng gói cwebp (xuất WebP)…"
WEBP=1.5.0
CACHE=.cache
mkdir -p "$CACHE"
for A in arm64 x86-64; do
  TGZ="$CACHE/libwebp-$WEBP-mac-$A.tar.gz"
  [ -f "$TGZ" ] || curl -fsSL "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-$WEBP-mac-$A.tar.gz" -o "$TGZ"
  tar -xzf "$TGZ" -C "$CACHE" "libwebp-$WEBP-mac-$A/bin/cwebp"
done
cp THIRD_PARTY_NOTICES.md LICENSE "$BUNDLE/Contents/Resources/"
lipo -create -output "$BUNDLE/Contents/Resources/cwebp" "$CACHE/libwebp-$WEBP-mac-arm64/bin/cwebp" "$CACHE/libwebp-$WEBP-mac-x86-64/bin/cwebp"

echo "▸ Ký ad-hoc…"
codesign --force --deep --sign - "$BUNDLE"

echo "▸ Tạo DMG…"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
cp -R "$BUNDLE" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$OUT/$APP-$VERSION.dmg" >/dev/null
rm -rf "$STAGE"

echo "✓ Xong: $OUT/$APP.app và $OUT/$APP-$VERSION.dmg"
