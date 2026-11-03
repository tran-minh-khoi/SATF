import AppKit

/// Icon định dạng trong menu tròn. Nguồn: assets/icons/formats/<tên>.png,
/// build.sh thu nhỏ và chép vào SATF.app/Contents/Resources/FormatIcons/.
/// Định dạng không có icon thì dùng SF Symbol như cũ.
enum FormatIcons {
    /// Icon chỉ có một màu (nét đen trên nền trong suốt): vẽ dạng template để theo màu chữ, không bị chìm ở Dark Mode
    private static let monochrome: Set<String> = ["csv"]

    /// nil = đã tìm và không có icon (ví dụ AVIF): nhớ lại để không tìm file mỗi lần vẽ menu
    private static var cache: [String: NSImage?] = [:]

    static func image(named name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        var url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "FormatIcons")
        // Chạy ngoài app (scripts/screenshots.sh, từ thư mục dự án): lấy thẳng từ assets/icons/formats
        if url == nil, Bundle.main.bundleURL.pathExtension != "app" {
            url = URL(fileURLWithPath: "assets/icons/formats/\(name).png")
        }
        let image = url.flatMap(NSImage.init(contentsOf:))
        image?.isTemplate = monochrome.contains(name)
        cache[name] = .some(image)
        return image
    }
}

extension Format {
    /// Tên file trong assets/icons/formats/. Chỉ gán khi chữ in trên icon khớp đúng định dạng đích
    /// (AVIF chưa có icon nên dùng SF Symbol; doc.png, mp3.png, svg.png, pptx.png, sheets.png chưa có định dạng đích tương ứng).
    var iconName: String? {
        switch self {
        case .png, .jpg, .webp, .heic, .gif, .bmp, .tiff, .ico, .pdf, .docx, .txt, .rtf, .odt, .html, .csv,
             .mp4, .mov, .m4a, .wav, .aiff, .zip: return rawValue
        default: return nil
        }
    }

    var icon: NSImage? { iconName.flatMap(FormatIcons.image(named:)) }
}
