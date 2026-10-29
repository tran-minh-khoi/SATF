# Changelog

All notable changes to SATF are listed here. Versions follow [Semantic Versioning](https://semver.org).

## [1.1.0] — 2026-10-29

### Added
- **Merge into one PDF** when you hold several files: PDFs, Word, Excel, PowerPoint, images and text, in the order you picked them.
- **Split PDF**: one PDF per page.
- **One ZIP for several files**: holding several files and choosing ZIP now makes a single archive (`Archive.zip`) instead of one ZIP per file.

### Fixed
- Holding several files of different kinds (for example a ZIP and a photo) left only Copy and Shelf in the menu. ZIP is now always there.
- macOS: zipping or extracting an Excel/PowerPoint file no longer asks for the Office add-on.

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
