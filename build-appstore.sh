#!/bin/bash
# Build bản Mac App Store: build/appstore/SATF-<version>-appstore.pkg
# Khác bản tải từ web (build.sh): chạy trong sandbox, lưu file vào Downloads / thư mục tự chọn,
# không tự cập nhật, không có gói Excel & PowerPoint, không có mục Ủng hộ. Xem appstore/README.md.
#
# Cần (làm 1 lần, xem appstore/README.md):
#   - Chứng chỉ "Apple Distribution" và "Mac Installer Distribution" trong Keychain
#   - appstore/embedded.provisionprofile (Mac App Store profile cho dev.tranminhkhoi.satf)
# Tuỳ chọn:
#   BUILD_NUMBER=42 ./build-appstore.sh        số build (mặc định: số commit, luôn tăng)
#   UPLOAD=1 ASC_KEY_ID=… ASC_ISSUER_ID=… ./build-appstore.sh   kiểm tra + tải lên App Store Connect
#     (khoá API đặt ở ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8)
set -euo pipefail
cd "$(dirname "$0")"

APP=SATF
OUT=build/appstore
BUNDLE="$OUT/$APP.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"
PROFILE=appstore/embedded.provisionprofile
PKG="$OUT/$APP-$VERSION-appstore.pkg"

APP_ID="${APP_IDENTITY:-$(security find-identity -v -p codesigning | grep -o -E '"(Apple Distribution|3rd Party Mac Developer Application): [^"]+"' | head -1 | tr -d '"' || true)}"
PKG_ID="${INSTALLER_IDENTITY:-$(security find-identity -v | grep -o -E '"(3rd Party Mac Developer Installer|Mac Installer Distribution): [^"]+"' | head -1 | tr -d '"' || true)}"
missing=0
[ -f "$PROFILE" ] || { echo "✗ Thiếu $PROFILE (tải Mac App Store provisioning profile, xem appstore/README.md)"; missing=1; }
[ -n "$APP_ID" ]  || { echo "✗ Thiếu chứng chỉ \"Apple Distribution\" trong Keychain"; missing=1; }
[ -n "$PKG_ID" ]  || { echo "✗ Thiếu chứng chỉ \"Mac Installer Distribution\" trong Keychain"; missing=1; }
[ "$missing" = 0 ] || exit 1

rm -rf "$OUT" && mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources/FormatIcons"

echo "▸ Icon app từ assets/brand/logo.png…"
ICONSET="$OUT/AppIcon.iconset"
mkdir -p "$ICONSET"
for S in 16 32 128 256 512; do
  sips -z $S $S assets/brand/logo.png --out "$ICONSET/icon_${S}x${S}.png" >/dev/null
  sips -z $((S*2)) $((S*2)) assets/brand/logo.png --out "$ICONSET/icon_${S}x${S}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "▸ Biên dịch bản App Store (Apple Silicon + Intel)…"
for ARCH in arm64 x86_64; do
  xcrun swiftc -O -swift-version 5 -D APPSTORE \
    -sdk "$SDK" -target "$ARCH-apple-macos13.0" \
    Sources/*.swift -o "$OUT/$APP-$ARCH"
done
lipo -create -output "$BUNDLE/Contents/MacOS/$APP" "$OUT/$APP-arm64" "$OUT/$APP-x86_64"
rm "$OUT/$APP-arm64" "$OUT/$APP-x86_64"

PLIST="$BUNDLE/Contents/Info.plist"
cp Info.plist "$PLIST"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$PLIST"
plutil -replace CFBundleVersion -string "$BUILD" "$PLIST"
plutil -replace ITSAppUsesNonExemptEncryption -bool NO "$PLIST"            # không dùng mã hoá -> khỏi khai báo xuất khẩu
plutil -replace LSApplicationSecondaryCategoryType -string public.app-category.productivity "$PLIST"
plutil -remove NSAppleEventsUsageDescription "$PLIST" 2>/dev/null || true # bản App Store không điều khiển app khác

echo "▸ Tài nguyên…"
cp THIRD_PARTY_NOTICES.md LICENSE "$BUNDLE/Contents/Resources/"
for F in assets/icons/formats/*.png; do
  sips -Z 128 "$F" --out "$BUNDLE/Contents/Resources/FormatIcons/$(basename "$F")" >/dev/null
done
WEBP=1.5.0
CACHE=.cache
mkdir -p "$CACHE"
for A in arm64 x86-64; do
  TGZ="$CACHE/libwebp-$WEBP-mac-$A.tar.gz"
  [ -f "$TGZ" ] || curl -fsSL "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-$WEBP-mac-$A.tar.gz" -o "$TGZ"
  tar -xzf "$TGZ" -C "$CACHE" "libwebp-$WEBP-mac-$A/bin/cwebp"
done
lipo -create -output "$BUNDLE/Contents/Resources/cwebp" "$CACHE/libwebp-$WEBP-mac-arm64/bin/cwebp" "$CACHE/libwebp-$WEBP-mac-x86-64/bin/cwebp"
cp "$PROFILE" "$BUNDLE/Contents/embedded.provisionprofile"

echo "▸ Ký bằng ${APP_ID}…"
codesign --force --sign "$APP_ID" --entitlements appstore/cwebp.entitlements "$BUNDLE/Contents/Resources/cwebp"
codesign --force --sign "$APP_ID" --entitlements appstore/SATF.entitlements "$BUNDLE"
codesign --verify --strict --deep "$BUNDLE"
codesign -d --entitlements - --xml "$BUNDLE" 2>/dev/null | grep -q app-sandbox || { echo "✗ Thiếu sandbox trong chữ ký"; exit 1; }

echo "▸ Đóng gói ${PKG} (ký bằng ${PKG_ID})…"
productbuild --component "$BUNDLE" /Applications --sign "$PKG_ID" "$PKG"
pkgutil --check-signature "$PKG" | head -3

if [ "${UPLOAD:-0}" = 1 ]; then
  : "${ASC_KEY_ID:?Cần ASC_KEY_ID}" "${ASC_ISSUER_ID:?Cần ASC_ISSUER_ID}"
  echo "▸ Kiểm tra với App Store Connect…"
  xcrun altool --validate-app -f "$PKG" -t macos --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  echo "▸ Tải lên App Store Connect…"
  xcrun altool --upload-app -f "$PKG" -t macos --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  echo "✓ Đã tải lên. Bản build hiện trong App Store Connect sau 5–30 phút."
else
  echo "✓ Xong: $PKG  (version $VERSION, build $BUILD)"
  echo "  Tải lên: mở app Transporter, kéo file .pkg vào rồi bấm Deliver"
  echo "  hoặc: UPLOAD=1 ASC_KEY_ID=… ASC_ISSUER_ID=… ./build-appstore.sh"
fi
