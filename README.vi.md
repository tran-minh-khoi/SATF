<p align="center">
  <img src="docs/images/hero.jpg" alt="SATF — Kéo. Lắc. Đổi file." width="100%">
</p>

<h1 align="center">SATF</h1>

<p align="center">
  <b>Kéo file, lắc nhẹ, đổi định dạng trong nháy mắt.</b><br>
  Menu tròn nhỏ gọn cho macOS và Windows, hiện ra ngay chỗ bạn đang kéo file.
</p>

<p align="center">
  <a href="https://github.com/tran-minh-khoi/SATF/releases/latest"><img alt="Tải về" src="https://img.shields.io/badge/t%E1%BA%A3i%20v%E1%BB%81-macOS%20%7C%20Windows-e8505b?style=for-the-badge"></a>
  <a href="LICENSE"><img alt="Giấy phép MIT" src="https://img.shields.io/badge/license-MIT-555?style=for-the-badge"></a>
</p>

<p align="center"><a href="README.md">English</a></p>

---

## SATF làm được gì?

Bình thường muốn đổi file phải mở app, tìm *Xuất*, chọn định dạng, chọn thư mục. Với SATF, bạn chỉ cần:

- **Lắc nhẹ** file đang kéo (hoặc bấm <kbd>⌥ ⇧ Space</kbd> / <kbd>Alt + Shift + Space</kbd>).
- Menu hiện ra **ngay dưới con trỏ**.
- **Thả** file vào định dạng muốn đổi. File mới nằm ngay cạnh file gốc.

Không tải lên mạng, không cần tài khoản, không quảng cáo. Mọi thứ chạy trên máy bạn.

## Tính năng

- 🎯 **Menu tròn ngay con trỏ:** bên phải là Chuyển đổi, bên trái là Copy và Khay.
- 🔄 **Đổi ảnh, PDF, tài liệu, video, nhạc:** định dạng hay dùng đứng trước, còn lại rê vào *Thêm* là thấy.
- 📦 **Giải nén** zip, rar, 7z, tar, gz, bz2, xz. Dùng được cả The Unarchiver, Keka, 7-Zip, WinRAR… nếu bạn thích.
- 🗂️ **Khay:** gom file từ nhiều nơi rồi kéo ra dùng một lần.
- 🪶 **Nhẹ:** gói nặng (LibreOffice, FFmpeg) chỉ tải khi cần, xoá được bất cứ lúc nào.
- 🔔 **Thông báo rõ ràng:** "Đang chuyển…", rồi "Xong · lưu trong thư mục Tải về". Bấm vào là mở đúng file.
- 🌏 **Tiếng Anh và Tiếng Việt.**
- 🧹 **Gỡ sạch**, không để lại gì.

## Tải về

| Hệ điều hành | Tải về | Yêu cầu |
|---|---|---|
| **macOS** | [SATF-1.0.0.dmg](https://github.com/tran-minh-khoi/SATF/releases/latest) | macOS 13 trở lên · Apple Silicon và Intel |
| **Windows** | [SATF-Setup-1.0.0.exe](https://github.com/tran-minh-khoi/SATF/releases/latest) | Windows 10 (2004) trở lên · 64-bit |

**macOS:** mở DMG, kéo SATF vào Applications rồi mở là chạy (app đã được Apple ký và kiểm tra).

**Windows:** chạy SATF-Setup, chọn ngôn ngữ và các gói muốn tải (bỏ qua cũng được). Nếu hiện *"Windows protected your PC"*: bấm **More info → Run anyway**.

> Bản macOS đã được Apple ký và kiểm tra. Bản Windows chưa có chữ ký số nên SmartScreen hỏi một lần. Mã nguồn có sẵn ở đây để bạn kiểm tra hoặc tự build.

## Cách dùng

<table>
  <tr>
    <td width="50%"><img src="docs/images/radial-convert.jpg" alt="Nửa chuyển đổi"></td>
    <td width="50%"><img src="docs/images/radial-all-formats.jpg" alt="Xem tất cả định dạng"></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/images/radial-copy.jpg" alt="Nửa copy"></td>
    <td width="50%"><img src="docs/images/shelf.jpg" alt="Khay"></td>
  </tr>
</table>

1. **Kéo** một hoặc nhiều file.
2. **Giữ Shift và lắc nhẹ** qua lại, hoặc bấm phím tắt.
3. **Thả** file vào:
   - **Chuyển đổi →** định dạng. Nhiều hơn 6 lựa chọn thì rê vào **Thêm** để bung cả vòng.
   - **Copy** (ô dưới): copy file.
   - **Khay** (ô trên): cất vào khay để dùng sau.
4. Đổi ý? Bấm <kbd>Esc</kbd>, bấm ra ngoài, hoặc thả file ra chỗ khác.

Không kéo file mà bấm phím tắt thì sẽ mở Khay.

## Định dạng hỗ trợ

Xem bảng đầy đủ trong [README tiếng Anh](README.md#what-it-converts). Tóm tắt:

- **Ảnh:** JPG, PNG, PDF, WebP, HEIC, GIF, TIFF, BMP (Mac có thêm AVIF, ICO).
- **PDF:** sang ảnh (mỗi trang một ảnh), TXT (Mac), DOCX (Windows).
- **Word, Excel, PowerPoint:** sang PDF, ảnh… (cần Microsoft Office hoặc gói Office).
- **Video, nhạc:** MP4, MOV, M4A, WAV, AIFF (Mac); MP4, MP3, M4A, WAV (Windows, cần gói Video & nhạc).
- **Tệp nén:** giải nén zip, rar, 7z, tar, gz, bz2, xz.
- **Mọi file và thư mục:** nén ZIP.

## Gói tải thêm

| Gói | Dùng cho | Dung lượng tải |
|---|---|---|
| **Office** (LibreOffice) | Mac: Excel, PowerPoint · Windows: Word, Excel, PowerPoint | ~300–350 MB |
| **Video & nhạc** (FFmpeg, chỉ Windows) | MP4, MP3, M4A, WAV | ~115 MB |

- **Lúc cài:** bộ cài Windows cho tick chọn gói. Mac hỏi ở lần mở đầu tiên (chỉ khi máy chưa có Office/iWork).
- **Khi cần:** SATF hỏi "Cần thêm một bước", tải xong thì đổi file luôn.
- **Dọn dung lượng:** menu → **Add-ons…**, bấm **Remove** từng gói. Cần lại thì SATF sẽ hỏi.

## Gỡ cài đặt

Menu SATF → **Gỡ SATF khỏi máy…** để xoá sạch app, cài đặt và các gói đã tải. Trên Windows cũng gỡ được trong *Settings → Apps* hoặc *Control Panel*.

## Góp ý

Menu SATF → **Báo lỗi…** / **Góp ý tính năng…** (mở thư soạn sẵn), hoặc [tạo issue trên GitHub](https://github.com/tran-minh-khoi/SATF/issues/new/choose).

## Tự build

```bash
./build.sh        # macOS: build/SATF-<phiên bản>.dmg
./build-win.sh    # Windows: build/windows/SATF-Setup-<phiên bản>.exe (cần .NET 10 SDK và makensis)
```

Chi tiết xem [README tiếng Anh](README.md#build-from-source) và [CONTRIBUTING.md](CONTRIBUTING.md).

## Giấy phép

[MIT](LICENSE). Thành phần bên thứ ba giữ giấy phép riêng, xem [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Tác giả

**Tran Minh Khoi** · [tranminhkhoi.dev](https://tranminhkhoi.dev) · [contact@tranminhkhoi.dev](mailto:contact@tranminhkhoi.dev)
