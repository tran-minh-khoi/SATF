#!/bin/bash
# Chạy thử các thao tác Edit (xoay, thu nhỏ, nén, ép dung lượng, xoá EXIF, ghép ảnh, PDF) trên file thật.
# Không cần mở app: biên dịch Sources/ cùng tests/EditTests.swift thành một chương trình riêng.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/src" "$TMP/in"
for f in Sources/*.swift; do [ "$(basename "$f")" = main.swift ] || cp "$f" "$TMP/src/"; done
cp tests/EditTests.swift "$TMP/src/main.swift"
xcrun swiftc -O -suppress-warnings -swift-version 5 -sdk "$(xcrun --sdk macosx --show-sdk-path)" -target "$(uname -m)-apple-macos13.0" "$TMP/src/"*.swift -o "$TMP/runner"
"$TMP/runner" "$TMP/in" assets/logo.png 2>&1 | grep -v 'CoreGraphics PDF'
