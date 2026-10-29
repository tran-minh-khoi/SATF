#!/bin/bash
# Build SATF.exe cho Windows (x64) ngay trên macOS hoặc Windows
set -euo pipefail
cd "$(dirname "$0")"

OUT="build/windows"

echo "▸ Tạo icon từ assets/logo.png…"
# AppIcon.ico (icon file exe, nhiều cỡ) và AppIcon.png (logo trong app) — tạo lại mỗi lần build
python3 - assets/logo.png Windows/AppIcon.ico <<'PY'
import struct, subprocess, sys, tempfile, os
src, dst = sys.argv[1], sys.argv[2]
frames = []
with tempfile.TemporaryDirectory() as tmp:
    for s in [16, 24, 32, 48, 64, 128, 256]:
        out = os.path.join(tmp, f"{s}.png")
        subprocess.run(["sips", "-z", str(s), str(s), src, "--out", out], stdout=subprocess.DEVNULL, check=True)
        frames.append((s, open(out, "rb").read()))
offset = 6 + 16 * len(frames)
with open(dst, "wb") as f:
    f.write(struct.pack("<HHH", 0, 1, len(frames)))
    for s, data in frames:
        f.write(struct.pack("<BBBBHHII", s % 256, s % 256, 0, 0, 1, 32, len(data), offset))
        offset += len(data)
    for _, data in frames:
        f.write(data)
PY
sips -z 256 256 assets/logo.png --out Windows/AppIcon.png >/dev/null

VERSION="$(tr -d '[:space:]' < VERSION)"

echo "▸ Biên dịch SATF.exe $VERSION (x64 self-contained)…"
rm -rf "$OUT"
dotnet publish Windows/SATF.Windows.csproj \
  -r win-x64 \
  -c Release \
  -p:PublishSingleFile=true \
  -p:Version="$VERSION" \
  -p:DebugType=none \
  --self-contained \
  -o "$OUT" >/dev/null

# NO_INSTALLER=1: chỉ cần SATF.exe (workflow MSIX cho Microsoft Store)
[ -n "${NO_INSTALLER:-}" ] && { echo "✓ Xong: $OUT/SATF.exe"; exit 0; }

echo "▸ Tạo bộ cài…"
command -v makensis >/dev/null || { echo "Thiếu makensis: brew install makensis"; exit 1; }
SETUP="SATF-Setup-$VERSION.exe"
LC_ALL=en_US.UTF-8 makensis -V2 -DROOT="$PWD" -DICON="$PWD/Windows/AppIcon.ico" -DVERSION="$VERSION" -DSOURCE="$PWD/$OUT/SATF.exe" -DOUTFILE="$PWD/$OUT/$SETUP" Windows/installer.nsi

echo "✓ Xong: $OUT/$SETUP (bộ cài) và $OUT/SATF.exe (bản chạy luôn, không cần cài)"
