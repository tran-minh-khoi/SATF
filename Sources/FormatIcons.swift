import AppKit

/// Icon định dạng trong menu tròn. Nguồn: assets/icons/formats/<tên>.png,
/// build.sh thu nhỏ và chép vào SATF.app/Contents/Resources/FormatIcons/.
/// Định dạng không có icon thì dùng SF Symbol như cũ.
enum FormatIcons {
    /// Icon chỉ có một màu (nét đen trên nền trong suốt): vẽ dạng template để theo màu chữ, không bị chìm ở Dark Mode
    private static let monochrome: Set<String> = ["csv"]

    private static var cache: [String: NSImage] = [:]

    static func image(named name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        // Trong app: Resources/FormatIcons. Chạy ngoài app (scripts/screenshots.sh, chạy từ thư mục dự án): assets/icons/formats
        let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "FormatIcons")
            ?? URL(fileURLWithPath: "assets/icons/formats/\(name).png")
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = monochrome.contains(name)
        cache[name] = image
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
