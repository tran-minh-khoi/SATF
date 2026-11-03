# Phát hành SATF lên Mac App Store

Nhánh `appstore`. Bản App Store build bằng `./build-appstore.sh` (cờ biên dịch `APPSTORE`), bản tải từ web vẫn là `./build.sh`.

## Khác gì bản tải từ web

| | Bản web (`build.sh`) | Bản App Store (`build-appstore.sh`) |
|---|---|---|
| Sandbox | Không | Có (bắt buộc) |
| Lưu file kết quả | Cạnh file gốc | Downloads, hoặc thư mục chọn trong Cài đặt → File kết quả |
| Excel & PowerPoint | Có (LibreOffice / Office / iWork) | Không (sandbox không cho tải LibreOffice hay điều khiển app khác) |
| Tự cập nhật, Ủng hộ, Gói tải thêm, Gỡ cài đặt | Có | Không (App Store lo cập nhật & gỡ, không nhận ủng hộ ngoài In-App Purchase) |
| Ký | Developer ID + notarize | Apple Distribution + Mac Installer Distribution |

Code riêng nằm trong các khối `#if APPSTORE` (AppDelegate, SettingsWindow, RadialMenu, Converter) và `Sources/OutputFolder.swift`.

## Chuẩn bị (làm 1 lần)

1. **App ID**: [developer.apple.com → Identifiers](https://developer.apple.com/account/resources/identifiers/list) → `dev.tranminhkhoi.satf` (macOS). Không cần bật capability nào.
2. **Chứng chỉ** ([Certificates](https://developer.apple.com/account/resources/certificates/list)), tải về rồi bấm đúp để vào Keychain:
   - **Apple Distribution** (ký app)
   - **Mac Installer Distribution** (ký file .pkg)
3. **Provisioning profile**: [Profiles](https://developer.apple.com/account/resources/profiles/list) → *Mac App Store Connect* → App ID `dev.tranminhkhoi.satf` → chứng chỉ Apple Distribution → tải về, đổi tên thành `appstore/embedded.provisionprofile` (file này không đưa lên git).
4. **App Store Connect** → [Apps](https://appstoreconnect.apple.com/apps) → **+** → New App → macOS, Bundle ID `dev.tranminhkhoi.satf`, SKU `satf-mac`.

## Build & tải lên

```bash
./build-appstore.sh          # → build/appstore/SATF-<version>-appstore.pkg
```
Tải lên bằng app **Transporter** (Mac App Store, miễn phí): kéo file `.pkg` vào → Deliver.
Hoặc tự động bằng khoá API App Store Connect (Users and Access → Integrations → App Store Connect API):
copy `appstore/upload.env.example` thành `appstore/upload.env`, điền Key ID + Issuer ID, đặt file `AuthKey_<KEY_ID>.p8`
vào `~/.appstoreconnect/private_keys/`, rồi:
```bash
UPLOAD=1 ./build-appstore.sh
```
Số build (`CFBundleVersion`) = số commit nên luôn tăng; muốn đặt tay: `BUILD_NUMBER=42 ./build-appstore.sh`.

## Chạy thử trước khi gửi

```bash
APPSTORE=1 ./scripts/run-dev.sh      # bản App Store có sandbox, ký ad-hoc, mở luôn
./scripts/screenshots.sh build/appstore-screenshots appstore   # ảnh 2880x1800 tiếng Anh + tiếng Việt
```
Kiểm tra trong bản chạy thử: lắc khi kéo file → đổi định dạng → file mới xuất hiện trong Downloads; Cài đặt → File kết quả → Đổi… sang thư mục khác rồi thử lại; Khay; Copy; nén / giải nén ZIP; ảnh WebP.

## Điền App Store Connect

Nội dung soạn sẵn trong `appstore/metadata/`:
- `en-US/`, `vi/`: tên, phụ đề, mô tả, từ khoá, promotional text, ghi chú phiên bản
- `review_notes.txt`: ghi chú cho người duyệt (cách mở menu bằng cách lắc)
- `app_info.txt`: danh mục, độ tuổi, quyền riêng tư (Data Not Collected), mã hoá, URL

Trang chính sách & hỗ trợ nằm trên website (repo mk-widget-card-website): `/satf/privacy`, `/satf/support`.
