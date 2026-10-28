# Contributing to SATF

Thanks for helping! Bug reports, ideas, translations and pull requests are all welcome.

## Reporting bugs and ideas

- Open an issue using the **Bug report** or **Feature request** template, or use **Report a Bug… / Suggest a Feature…** in the SATF menu (it opens an email).
- For bugs, please include your OS version, SATF version, and what you dragged (file type). On Windows, attach `%LOCALAPPDATA%\SATF\logs\satf.log` if SATF showed an error.

## Building

See [Build from source](README.md#build-from-source) in the README. Both apps build on a Mac:

```bash
./build.sh        # macOS app + DMG
./build-win.sh    # Windows exe + installer (needs .NET 10 SDK and makensis)
```

## Project layout

| Path | What's inside |
|---|---|
| `Sources/` | macOS app (Swift, AppKit + SwiftUI) |
| `Windows/` | Windows app (C#, WPF) and the NSIS installer script |
| `assets/logo.png` | The logo. All app icons are generated from it at build time |
| `docs/images/` | README screenshots, made by `scripts/screenshots.sh` |
| `VERSION` | Version number used by both apps |

## Guidelines

- Keep both apps in step: a feature on one platform should land on the other too, with the same wording.
- Every user-facing string goes through `L("English", "Tiếng Việt")` so both languages stay complete.
- Keep the wording short and friendly, with no technical jargon.
- Prefer what the OS already provides over new dependencies.
- Run the screenshot script if you change how the UI looks: `./scripts/screenshots.sh`.

## Releasing

1. Bump `VERSION` and add an entry to `CHANGELOG.md`.
2. Run `./build.sh` and `./build-win.sh`.
3. Upload `build/SATF-<version>.dmg` and `build/windows/SATF-Setup-<version>.exe` to a GitHub release.
