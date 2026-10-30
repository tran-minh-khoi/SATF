# Changelog

All notable changes to SATF are listed here. Versions follow [Semantic Versioning](https://semver.org).

## [1.2.2] — 2026-10-30

### Changed
- **Support SATF** window: the QR code and the new **Open the support page** button lead to [mktechvn.com/support](https://mktechvn.com/support), where every way to support SATF is in one place: Ko-fi, PayPal, GitHub and bank transfer in Vietnam (VietQR).

## [1.2.1] — 2026-10-29

### Added
- **Automatic updates.** SATF checks GitHub for a new version when it starts and once a day, and shows a notification you can click to update. It downloads the new version, checks it, installs it and restarts by itself.
  - macOS: the download must match GitHub's SHA-256 and be signed with SATF's Apple Developer ID and notarized before it replaces the app.
  - Windows: the installer must match GitHub's SHA-256, then installs silently over the current version.
- **Check for Updates…** in the menu bar / tray menu, and an **Updates** section in Settings (turn automatic checks off, check now).

### Changed
- Windows installer: updates install into the folder SATF is already in, and keep your "Start with Windows" choice.

### Note
- Versions before 1.2.1 can't update themselves: download 1.2.1 once from the website or GitHub. From then on, updates are automatic.

## [1.2.0] — 2026-10-29

### Added
- **Edit** in the radial menu: the right half is now split into **Convert** (top, orange) and **Edit** (bottom, green).
- Image edits, saved as a new file next to the original:
  - **Rotate** 90°.
  - **Resize** to a long side of 1080–3840px.
  - **Compress** with a Light, Balanced or Strong level (JPG, HEIC, WebP, AVIF).
  - **Under 1 MB**: picks the best quality that fits a target size (200 KB–5 MB) and shrinks the image only if needed. PNG, TIFF and BMP become JPG.
  - **Clean info**: removes location and camera details. On macOS the photo itself isn't re-compressed.
  - **Stack**: several images into one tall image.
- **Rotate PDF** (all pages, 90°).
- **Settings → Images**: compress level, target size and resize size.
- **Shake sensitivity** is now a 1–10 slider instead of three choices. Your old choice carries over.
- The **Settings** window can be resized and scrolls, so it fits small screens.
- **Shelf**: click, Ctrl/⌘-click and Shift-click to select, Ctrl+A/⌘A to select all, Delete to remove, Esc to deselect. Drag one selected file to take the whole selection, or use the drag handle to take everything. Double-click opens a file, right-click shows Open / Show in Finder or Explorer / Remove.
- **Support SATF** window with a VietQR code, opened from the name at the top of the menu bar / tray menu.

### Changed
- **Merge PDF** and **Split pages** moved from Convert to Edit.
- Image-to-image formats (JPG, PNG, WEBP…) show just their name, bigger, without the same photo icon repeated.
- macOS: monochrome menu bar icon that follows light and dark menu bars. Light trackpad feedback when moving between menu items, and a bouncier ✓ when done.
- Windows: the Shelf is redesigned to match the Mac: file icons in a grid, dashed drop zone, icon buttons, and animations when files are added and when the Shelf opens.

## [1.1.0] — 2026-10-29

### Added
- **Merge into one PDF** when you hold several files: PDFs, Word, Excel, PowerPoint, images and text, in the order you picked them.
- **Split PDF**: one PDF per page.
- **One ZIP for several files**: holding several files and choosing ZIP now makes a single archive (`Archive.zip`) instead of one ZIP per file.

### Fixed
- Holding several files of different kinds (for example a ZIP and a photo) left only Copy and Shelf in the menu. ZIP is now always there.
- macOS: zipping or extracting an Excel/PowerPoint file no longer asks for the Office add-on.
- Windows: the middle of the radial menu now shows the icon of the file you're holding right away, instead of the SATF logo until you moved the mouse.

## [1.0.0] — 2026-10-28

First public release for macOS and Windows.

### Added
- Radial menu that pops up where you drag a file: shake the file (hold Shift by default) or press the shortcut.
- **Copy** and **Shelf** on the left, **Convert** on the right. Most-used formats come first; hover **More** to see every format in a full circle.
- Conversions: images (JPG, PNG, PDF, WebP, HEIC, GIF, TIFF, BMP, AVIF, ICO), PDF to images/text, Word/Excel/PowerPoint to PDF, video and audio, ZIP.
- Extract zip, rar, 7z, tar, gz, bz2 and xz. Optionally use The Unarchiver, Keka, BetterZip, WinZip, 7-Zip, WinRAR or Bandizip.
- Floating Shelf to collect files and drag them out again.
- Optional add-ons (LibreOffice, FFmpeg): pick them during setup, or SATF asks when you need one. Remove them anytime.
- Progress and "saved to…" notifications. Click to reveal the file.
- English and Vietnamese.
- Windows installer with Start menu shortcut and a proper entry in Apps / Control Panel.
- Uninstall from inside the app that removes everything SATF created.
- Report a Bug / Suggest a Feature from the menu.
