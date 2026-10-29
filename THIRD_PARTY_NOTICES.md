# Third-party notices

SATF is MIT-licensed (see [LICENSE](LICENSE)). It ships with, or can download, the components below. Each one stays under its own license.

## Bundled with SATF

### libwebp — `cwebp` (macOS app)

Used to save WebP images. Prebuilt binary from <https://developers.google.com/speed/webp>.

```
Copyright (c) 2010, Google Inc. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

  * Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.

  * Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in
    the documentation and/or other materials provided with the
    distribution.

  * Neither the name of Google nor the names of its contributors may
    be used to endorse or promote products derived from this software
    without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### SkiaSharp and Skia (Windows app)

Used to read and save WebP images.

- SkiaSharp — MIT License, Copyright (c) 2015–2016 Xamarin, Inc. and Copyright (c) 2017–2018 Microsoft Corporation. <https://github.com/mono/SkiaSharp>
- Skia — BSD 3-Clause License, Copyright (c) 2011 Google Inc. <https://skia.org>

### PDFsharp (Windows app)

Used to merge PDFs and split them into pages.

- PDFsharp — MIT License, Copyright (c) 2005–2025 empira Software GmbH, Troisdorf (Cologne Area), Germany. <https://github.com/empira/PDFsharp>

### .NET runtime (Windows app)

MIT License, Copyright (c) .NET Foundation and Contributors. <https://github.com/dotnet/runtime>

## Downloaded only if you choose to (Add-ons)

SATF does not include these. When you pick an add-on, SATF downloads it from the official source and keeps it in its own folder. You can remove it anytime from **Add-ons**.

| Add-on | Source | License |
|---|---|---|
| LibreOffice (Word, Excel & PowerPoint → PDF, images) | <https://www.libreoffice.org> | Mozilla Public License 2.0 |
| FFmpeg, Windows build by gyan.dev (video & music) | <https://www.gyan.dev/ffmpeg/builds/> · <https://ffmpeg.org> | GPL v3 |

## Apps SATF can hand files to

If you have Microsoft Office, Pages / Numbers / Keynote, The Unarchiver, Keka, BetterZip, WinZip, 7-Zip, WinRAR or Bandizip installed, SATF can ask them to do the work. SATF does not include or modify these apps.
