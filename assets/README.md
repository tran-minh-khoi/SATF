# assets

Source images for SATF. Only `build.sh` / `build-win.sh` read from here; nothing in this folder is loaded at runtime by path.

```
assets/
├── brand/
│   └── logo.png            App logo (1254×1254). Every app icon is generated from it at build time
├── icons/
│   └── formats/            File-format icons shown in the radial menu (512×512 PNG, transparent)
│       ├── pdf.png  doc.png  docx.png  odt.png  rtf.png  txt.png  html.png
│       ├── csv.png  sheets.png  pptx.png
│       ├── jpg.png  png.png  webp.png  heic.png  gif.png  bmp.png  tiff.png  ico.png  svg.png
│       ├── mp4.png  mov.png  m4a.png  wav.png  aiff.png  mp3.png
│       └── zip.png
└── images/
    └── donate-qr.png       QR code in the Support SATF window (macOS + Windows)
```

## Format icons

- **Naming:** lowercase, named after the format printed on the icon (`pdf.png`, `heic.png`). Generic icons keep a descriptive name (`sheets.png`).
- **Size:** export at 512×512, transparent background, artwork centered.
- **Build:** `build.sh` shrinks each icon to 128px and copies it to `SATF.app/Contents/Resources/FormatIcons/`.
- **Wiring:** `Format.iconName` in `Sources/FormatIcons.swift` maps a target format to its icon. Only map an icon when the label on it matches the target exactly (e.g. `mp3.png` is not used for M4A). Formats without an icon fall back to an SF Symbol.
- **Monochrome icons** (single-color line art, like `csv.png`) are listed in `FormatIcons.monochrome` so they're drawn as template images and follow Light/Dark Mode.
- Currently not mapped (no matching target yet): `doc.png`, `mp3.png`, `svg.png`, `sheets.png`, `pptx.png`.
- AVIF has no icon and falls back to an SF Symbol. Add `avif.png` here and map it in `Format.iconName` to change that.
