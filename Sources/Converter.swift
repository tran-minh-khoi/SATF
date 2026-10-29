import AppKit
import AVFoundation
import PDFKit
import UniformTypeIdentifiers

// MARK: - Định dạng đích

enum Format: String, CaseIterable, Identifiable {
    case png, jpg, webp, heic, gif, tiff, bmp, avif, ico, pdf, txt, rtf, docx, odt, html, csv, mp4, mov, m4a, wav, aiff, zip
    case extract    // giải nén
    case mergePDF   // nhiều file -> một PDF
    case splitPDF   // một PDF -> mỗi trang một PDF

    var id: String { rawValue }

    var ext: String {
        switch self {
        case .mergePDF, .splitPDF: return "pdf"
        default: return rawValue
        }
    }

    var label: String {
        switch self {
        case .extract: return L("Extract", "Giải nén")
        case .mergePDF: return L("Merge PDF", "Gộp PDF")
        case .splitPDF: return L("Split PDF", "Tách PDF")
        default: return rawValue.uppercased()
        }
    }

    /// Dòng thông báo khi đang làm lâu
    var progressTitle: String {
        switch self {
        case .extract: return L("Extracting…", "Đang giải nén…")
        case .zip: return L("Compressing…", "Đang nén…")
        case .mergePDF: return L("Merging into one PDF…", "Đang gộp thành một PDF…")
        case .splitPDF: return L("Splitting PDF…", "Đang tách PDF…")
        default: return L("Converting to \(label)…", "Đang chuyển sang \(label)…")
        }
    }

    var imageType: UTType? {
        switch self {
        case .png: return .png
        case .jpg: return .jpeg
        case .heic: return .heic
        case .tiff: return .tiff
        case .gif: return .gif
        case .bmp: return .bmp
        case .avif: return UTType("public.avif")
        case .ico: return .ico
        default: return nil
        }
    }
}

enum FileKind { case image, pdf, document, spreadsheet, presentation, video, audio, archive, unknown }

struct ConvertError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - Bảng "file nào đổi được sang gì"

enum Converter {
    private static let documentExts: Set<String> = ["docx", "doc", "odt", "rtf", "rtfd", "txt", "md", "html", "htm", "webarchive"]
    private static let spreadsheetExts: Set<String> = ["xlsx", "xls", "xlsm", "ods", "numbers"]
    private static let presentationExts: Set<String> = ["pptx", "ppt", "odp", "key"]
    static let archiveExts: Set<String> = ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz"]

    /// Định dạng ảnh máy này ghi được (AVIF/HEIC tuỳ phiên bản macOS).
    private static let writableImageTypes = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])

    static func normalizedExt(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpeg": return "jpg"
        case "tif": return "tiff"
        case "htm": return "html"
        case let e: return e
        }
    }

    static func kind(of url: URL) -> FileKind {
        let ext = url.pathExtension.lowercased()
        if documentExts.contains(ext) { return .document }
        if spreadsheetExts.contains(ext) { return .spreadsheet }
        if presentationExts.contains(ext) { return .presentation }
        if archiveExts.contains(ext) { return .archive }
        guard let type = UTType(filenameExtension: ext) else { return .unknown }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .text) { return .document }
        return .unknown
    }

    /// Xếp theo mức hay dùng: cái phổ biến đứng trước. ZIP luôn ở cuối, file nào cũng nén được.
    static func targets(for url: URL) -> [Format] {
        var all: [Format]
        switch kind(of: url) {
        case .image:
            all = [.jpg, .png, .pdf, .webp, .heic, .gif, .tiff, .bmp, .avif, .ico]
                .filter { $0 == .pdf || $0 == .webp || writableImageTypes.contains($0.imageType?.identifier ?? "") }
        case .pdf:          all = [.jpg, .png, .splitPDF, .txt]
        case .document:     all = [.pdf, .docx, .txt, .rtf, .html, .odt]
        case .spreadsheet:  all = [.pdf, .csv]
        case .presentation: all = [.pdf, .png, .jpg]
        case .video:        all = [.mp4, .mov, .m4a]
        case .audio:        all = [.m4a, .wav, .aiff]
        case .archive:      return [.extract]
        case .unknown:      all = []
        }
        all.append(.zip)
        let own = normalizedExt(url)
        return all.filter { $0.rawValue != own }
    }

    /// Loại file đổi được sang PDF, nên gộp chung được vào một PDF
    private static let pdfKinds: Set<FileKind> = [.image, .pdf, .document, .spreadsheet, .presentation]

    /// Nhiều file:
    /// - "Gộp PDF" đứng đầu nếu file nào cũng đổi được sang PDF (PDF, Word, Excel, PowerPoint, ảnh, văn bản)
    /// - các định dạng mà file nào cũng đổi được (mỗi file ra một file mới)
    /// - ZIP luôn ở cuối: nén tất cả vào một file, kể cả khi có thư mục hay file nén
    static func targets(for urls: [URL]) -> [Format] {
        guard let first = urls.first else { return [] }
        if urls.count == 1 { return targets(for: first) }

        var common = targets(for: first).filter { $0 != .zip }
        for url in urls.dropFirst() {
            let t = Set(targets(for: url))
            common = common.filter { t.contains($0) }
        }
        let canMerge = urls.allSatisfy { pdfKinds.contains(kind(of: $0)) }
        return (canMerge ? [.mergePDF] : []) + common + [.zip]
    }

    // MARK: - Chạy chuyển đổi

    static func run(_ files: [URL], to format: Format, completion: @escaping (Result<[URL], Error>) -> Void) {
        let work = {
            do {
                var output: [URL] = []
                switch format {
                case .mergePDF:
                    output = [try mergePDF(files)]
                case .zip where files.count > 1:
                    output = [try zip(files)]   // nhiều file -> một file ZIP
                default:
                    for file in files { output += try convert(file, to: format) }
                }
                DispatchQueue.main.async { completion(.success(output)) }
            } catch {
                // Lỗi hệ thống thường khó hiểu -> đổi thành câu dễ hiểu
                let friendly = error as? ConvertError ?? ConvertError(L("Couldn't read this file. It may be damaged.", "Không đọc được file này, có thể file bị hỏng"))
                DispatchQueue.main.async { completion(.failure(friendly)) }
            }
        }
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }

    static func convert(_ src: URL, to format: Format) throws -> [URL] {
        if format == .zip { return [try zip(src)] }
        if format == .extract { return [try extract(src)] }
        if format == .mergePDF { return [try mergePDF([src])] }
        if format == .splitPDF { return try splitPDF(src) }
        switch kind(of: src) {
        case .image:          return [try convertImage(src, to: format)]
        case .pdf:            return try convertPDF(src, to: format)
        case .document:       return [try convertDocument(src, to: format)]
        case .spreadsheet:
            let dst = destination(for: src, ext: format.ext)
            try officeExport(src, ext: format.ext, to: dst)
            return [dst]
        case .presentation:
            let pdf = destination(for: src, ext: "pdf")
            try officeExport(src, ext: "pdf", to: pdf)
            if format == .pdf { return [pdf] }
            defer { try? FileManager.default.removeItem(at: pdf) }   // PDF chỉ là bước trung gian
            return try convertPDF(pdf, to: format, nameFrom: src)
        case .video, .audio:
            if format == .wav || format == .aiff { return [try afconvert(src, to: format)] }
            return [try exportMedia(src, to: format)]
        case .archive, .unknown: throw ConvertError(L("This file type can't be converted yet", "Loại file này chưa đổi được"))
        }
    }

    /// File mới nằm cạnh file gốc; trùng tên thì thêm " (1)", " (2)"...
    static func destination(for src: URL, ext: String, suffix: String = "") -> URL {
        let dir = src.deletingLastPathComponent()
        let base = src.deletingPathExtension().lastPathComponent + suffix
        var url = dir.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base) (\(n))").appendingPathExtension(ext)
            n += 1
        }
        return url
    }

    // MARK: - Ảnh

    private static func convertImage(_ src: URL, to format: Format) throws -> URL {
        let dst = destination(for: src, ext: format.ext)

        if format == .pdf {
            guard let image = NSImage(contentsOf: src), let page = PDFPage(image: image) else {
                throw ConvertError(L("Couldn't read the image \(src.lastPathComponent)", "Không đọc được ảnh \(src.lastPathComponent)"))
            }
            let doc = PDFDocument()
            doc.insert(page, at: 0)
            guard doc.write(to: dst) else { throw ConvertError(L("Couldn't save the PDF", "Không ghi được file PDF")) }
            return dst
        }

        // WebP (macOS không tự ghi được) và ICO (tối đa 256px): lấy ảnh đã xoay đúng chiều
        if format == .webp || format == .ico {
            guard let image = orientedImage(src, maxPixel: format == .ico ? 256 : nil) else {
                throw ConvertError(L("Couldn't read the image \(src.lastPathComponent)", "Không đọc được ảnh \(src.lastPathComponent)"))
            }
            if format == .webp { try writeWebP(image, to: dst) } else { try writeImage(image, to: dst, type: .ico) }
            return dst
        }

        guard let type = format.imageType else { throw ConvertError(L("Unsupported format", "Định dạng không hợp lệ")) }

        var image: CGImage
        var props: [CFString: Any] = [:]
        if let source = CGImageSourceCreateWithURL(src as CFURL, nil),
           let img = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            image = img
            // Giữ hướng xoay (ảnh chụp điện thoại) và DPI
            if let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                for key in [kCGImagePropertyOrientation, kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] {
                    if let v = p[key] { props[key] = v }
                }
            }
        } else if let ns = NSImage(contentsOf: src),
                  let img = render(ns, pixelSize: CGSize(width: ns.size.width * 2, height: ns.size.height * 2), background: nil) {
            image = img   // ví dụ SVG: ImageIO không đọc được nhưng NSImage thì được
        } else {
            throw ConvertError(L("Couldn't read the image \(src.lastPathComponent)", "Không đọc được ảnh \(src.lastPathComponent)"))
        }

        try writeImage(image, to: dst, type: type, properties: props)
        return dst
    }

    private static func orientedImage(_ src: URL, maxPixel: Int?) -> CGImage? {
        if let s = CGImageSourceCreateWithURL(src as CFURL, nil),
           let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any],
           let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int {
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: min(maxPixel ?? .max, max(w, h)),
            ]
            return CGImageSourceCreateThumbnailAtIndex(s, 0, opts as CFDictionary)
        }
        guard let ns = NSImage(contentsOf: src) else { return nil }   // SVG...
        var size = CGSize(width: ns.size.width * 2, height: ns.size.height * 2)
        if let m = maxPixel, max(size.width, size.height) > CGFloat(m) {
            let k = CGFloat(m) / max(size.width, size.height)
            size = CGSize(width: size.width * k, height: size.height * k)
        }
        return render(ns, pixelSize: size, background: nil)
    }

    /// macOS không có bộ ghi WebP → dùng cwebp đóng gói kèm app.
    private static func writeWebP(_ image: CGImage, to dst: URL) throws {
        guard let cwebp = Tools.cwebp else { throw ConvertError(L("Part of SATF is missing. Please reinstall the app.", "Thiếu một phần của SATF, hãy cài lại app")) }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try writeImage(image, to: tmp, type: .png)
        try shell(cwebp, ["-quiet", "-q", "90", "-alpha_q", "100", tmp.path, "-o", dst.path])
    }

    private static func writeImage(_ image: CGImage, to dst: URL, type: UTType, properties: [CFString: Any] = [:]) throws {
        var img = image
        if type == .jpeg, hasAlpha(image), let flat = flattenOnWhite(image) { img = flat }  // JPG không có nền trong suốt

        guard let dest = CGImageDestinationCreateWithURL(dst as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConvertError(L("This Mac can't save \((type.preferredFilenameExtension ?? "").uppercased()) files", "Máy này chưa hỗ trợ định dạng \((type.preferredFilenameExtension ?? "").uppercased())"))
        }
        var opts = properties
        opts[kCGImageDestinationLossyCompressionQuality] = 0.9
        CGImageDestinationAddImage(dest, img, opts as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ConvertError(L("Couldn't save the image", "Không lưu được ảnh")) }
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    private static func flattenOnWhite(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        return ctx.makeImage()
    }

    private static func render(_ image: NSImage, pixelSize: CGSize, background: CGColor?) -> CGImage? {
        let w = Int(pixelSize.width.rounded()), h = Int(pixelSize.height.rounded())
        guard w > 0, h > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        if let bg = background {
            ctx.setFillColor(bg)
            ctx.fill(rect)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        image.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    // MARK: - PDF

    private static func convertPDF(_ src: URL, to format: Format, nameFrom: URL? = nil) throws -> [URL] {
        let name = nameFrom ?? src
        guard let doc = PDFDocument(url: src) else { throw ConvertError(L("Couldn't open this PDF", "Không mở được file PDF này")) }
        if doc.isLocked { throw ConvertError(L("This PDF is password-protected", "File PDF đang khoá mật khẩu")) }

        if format == .txt {
            let dst = destination(for: name, ext: "txt")
            try (doc.string ?? "").write(to: dst, atomically: true, encoding: .utf8)
            return [dst]
        }

        guard let type = format.imageType else { throw ConvertError(L("Unsupported format", "Định dạng không hợp lệ")) }
        let scale: CGFloat = 2            // ~144 DPI, đủ nét để xem/gửi
        let multiPage = doc.pageCount > 1 // nhiều trang -> ten-1.png, ten-2.png...
        var output: [URL] = []

        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            var size = page.bounds(for: .mediaBox).size
            if page.rotation % 180 != 0 { size = CGSize(width: size.height, height: size.width) }
            let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)

            let thumb = page.thumbnail(of: pixelSize, for: .mediaBox)
            guard let cg = render(thumb, pixelSize: pixelSize, background: CGColor(gray: 1, alpha: 1)) else { continue }

            let dst = destination(for: name, ext: format.ext, suffix: multiPage ? "-\(i + 1)" : "")
            try writeImage(cg, to: dst, type: type,
                           properties: [kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale])
            output.append(dst)
        }
        if output.isEmpty { throw ConvertError(L("This PDF is empty", "File PDF trống")) }
        return output
    }

    // MARK: - Gộp / tách PDF

    /// Gộp nhiều file thành một PDF, theo đúng thứ tự đang cầm. File không phải PDF được đổi sang PDF trước
    /// (ảnh: mỗi ảnh một trang; Word, Excel, PowerPoint, văn bản: như khi đổi sang PDF).
    private static func mergePDF(_ files: [URL]) throws -> URL {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let merged = PDFDocument()
        var sources: [PDFDocument] = []   // giữ các PDF nguồn tới khi ghi xong

        for (i, file) in files.enumerated() {
            let pdfURL: URL
            switch kind(of: file) {
            case .pdf:
                pdfURL = file
            case .image:
                guard let image = NSImage(contentsOf: file), let page = PDFPage(image: image) else {
                    throw ConvertError(L("Couldn't read the image \(file.lastPathComponent)", "Không đọc được ảnh \(file.lastPathComponent)"))
                }
                merged.insert(page, at: merged.pageCount)
                continue
            case .document:
                pdfURL = tmp.appendingPathComponent("\(i).pdf")
                _ = try onMain { try convertDocumentBuiltIn(file, to: .pdf, dst: pdfURL) }
            case .spreadsheet, .presentation:
                pdfURL = tmp.appendingPathComponent("\(i).pdf")
                try officeExport(file, ext: "pdf", to: pdfURL)
            default:
                throw ConvertError(L("\(file.lastPathComponent) can't be added to a PDF", "Không gộp được \(file.lastPathComponent) vào PDF"))
            }

            guard let doc = PDFDocument(url: pdfURL) else {
                throw ConvertError(L("Couldn't open \(file.lastPathComponent)", "Không mở được \(file.lastPathComponent)"))
            }
            if doc.isLocked {
                throw ConvertError(L("\(file.lastPathComponent) is password-protected", "\(file.lastPathComponent) đang khoá mật khẩu"))
            }
            sources.append(doc)
            for p in 0..<doc.pageCount {
                guard let page = doc.page(at: p)?.copy() as? PDFPage else { continue }
                merged.insert(page, at: merged.pageCount)
            }
        }

        guard merged.pageCount > 0 else { throw ConvertError(L("Nothing to merge", "Không có trang nào để gộp")) }
        let dst = destination(for: files[0], ext: "pdf", suffix: L(" (merged)", " (gộp)"))
        let written = withExtendedLifetime(sources) { merged.write(to: dst) }
        guard written else { throw ConvertError(L("Couldn't save the PDF", "Không ghi được file PDF")) }
        return dst
    }

    /// Mỗi trang thành một file PDF riêng: ten-1.pdf, ten-2.pdf...
    private static func splitPDF(_ src: URL) throws -> [URL] {
        guard let doc = PDFDocument(url: src) else { throw ConvertError(L("Couldn't open this PDF", "Không mở được file PDF này")) }
        if doc.isLocked { throw ConvertError(L("This PDF is password-protected", "File PDF đang khoá mật khẩu")) }
        guard doc.pageCount > 1 else { throw ConvertError(L("This PDF has only one page", "File PDF này chỉ có một trang")) }

        var output: [URL] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i)?.copy() as? PDFPage else { continue }
            let single = PDFDocument()
            single.insert(page, at: 0)
            let dst = destination(for: src, ext: "pdf", suffix: "-\(i + 1)")
            guard single.write(to: dst) else { throw ConvertError(L("Couldn't save the PDF", "Không ghi được file PDF")) }
            output.append(dst)
        }
        return output
    }

    // MARK: - Văn bản (Word, RTF, TXT, HTML...)

    private static func readDocument(_ url: URL) throws -> NSAttributedString {
        typealias DT = NSAttributedString.DocumentType
        var opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
        switch url.pathExtension.lowercased() {
        case "docx": opts[.documentType] = DT.officeOpenXML
        case "doc": opts[.documentType] = DT.docFormat
        case "odt": opts[.documentType] = DT.openDocument
        case "rtf": opts[.documentType] = DT.rtf
        case "rtfd": opts[.documentType] = DT.rtfd
        case "html", "htm": opts[.documentType] = DT.html
        case "webarchive": opts[.documentType] = DT.webArchive
        default:
            opts[.documentType] = DT.plain
            opts[.characterEncoding] = String.Encoding.utf8.rawValue
        }
        return try NSAttributedString(url: url, options: opts, documentAttributes: nil)
    }

    private static func convertDocument(_ src: URL, to format: Format) throws -> URL {
        let dst = destination(for: src, ext: format.ext)
        // Đọc HTML và in ra PDF phải chạy trên main thread
        return try onMain { try convertDocumentBuiltIn(src, to: format, dst: dst) }
    }

    private static func onMain<T>(_ body: () throws -> T) throws -> T {
        Thread.isMainThread ? try body() : try DispatchQueue.main.sync(execute: body)
    }

    private static func convertDocumentBuiltIn(_ src: URL, to format: Format, dst: URL) throws -> URL {
        let text = try readDocument(src)
        let range = NSRange(location: 0, length: text.length)

        func write(_ type: NSAttributedString.DocumentType) throws {
            let data = try text.data(from: range, documentAttributes: [.documentType: type])
            try data.write(to: dst)
        }

        switch format {
        case .pdf:  try printToPDF(text, dst: dst)
        case .txt:  try text.string.write(to: dst, atomically: true, encoding: .utf8)
        case .rtf:  try write(.rtf)
        case .docx: try write(.officeOpenXML)
        case .html: try write(.html)
        case .odt:  try write(.openDocument)
        default:    throw ConvertError(L("Unsupported format", "Định dạng không hợp lệ"))
        }
        return dst
    }

    /// "In" văn bản ra file PDF khổ A4 (không hiện hộp thoại in).
    private static func printToPDF(_ text: NSAttributedString, dst: URL) throws {
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.paperSize = NSSize(width: 595.28, height: 841.89)
        info.topMargin = 56; info.bottomMargin = 56
        info.leftMargin = 56; info.rightMargin = 56
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL.rawValue] = dst

        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        textView.appearance = NSAppearance(named: .aqua)   // tránh chữ trắng khi máy đang Dark Mode
        textView.drawsBackground = true
        textView.backgroundColor = .white
        textView.textContainerInset = .zero
        textView.textStorage?.setAttributedString(text)
        if let lm = textView.layoutManager, let tc = textView.textContainer {
            tc.widthTracksTextView = false
            tc.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
            lm.ensureLayout(for: tc)
            textView.setFrameSize(NSSize(width: width, height: max(lm.usedRect(for: tc).height, 10)))
        }

        let op = NSPrintOperation(view: textView, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        guard op.run(), FileManager.default.fileExists(atPath: dst.path) else {
            throw ConvertError(L("Couldn't create the PDF", "Không tạo được PDF"))
        }
    }

    // MARK: - Video / âm thanh

    private static func exportMedia(_ src: URL, to format: Format) throws -> URL {
        let asset = AVURLAsset(url: src)
        let fileType: AVFileType
        let presets: [String]
        switch format {
        case .mp4: fileType = .mp4; presets = [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality]
        case .mov: fileType = .mov; presets = [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality]
        case .m4a: fileType = .m4a; presets = [AVAssetExportPresetAppleM4A]
        default: throw ConvertError(L("Unsupported format", "Định dạng không hợp lệ"))
        }

        let lastError: Error = ConvertError(L("Couldn't convert \(src.lastPathComponent)", "Không chuyển được \(src.lastPathComponent)"))
        // Thử "passthrough" trước (giữ nguyên chất lượng, rất nhanh), không được thì mã hóa lại.
        for preset in presets {
            guard let session = AVAssetExportSession(asset: asset, presetName: preset),
                  session.supportedFileTypes.contains(fileType) else { continue }
            let dst = destination(for: src, ext: format.ext)
            session.outputURL = dst
            session.outputFileType = fileType

            let done = DispatchSemaphore(value: 0)
            session.exportAsynchronously { done.signal() }
            done.wait()

            if session.status == .completed { return dst }
            try? FileManager.default.removeItem(at: dst)
        }
        throw lastError
    }

    // MARK: - Excel, PowerPoint nhờ app có sẵn trên máy

    /// Excel/PowerPoint → PDF. Thử lần lượt: LibreOffice (chạy ngầm) → Microsoft Office → Numbers/Keynote.
    private static func officeExport(_ src: URL, ext: String, to dst: URL) throws {
        let fm = FileManager.default
        if let soffice = Tools.soffice {
            let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: tmp) }
            // Hồ sơ riêng để không đụng LibreOffice người dùng đang mở
            let profile = fm.temporaryDirectory.appendingPathComponent("satf-lo-profile").absoluteString
            try? shell(soffice, ["-env:UserInstallation=\(profile)", "--headless", "--convert-to", ext,
                                 "--outdir", tmp.path, src.path])
            let out = tmp.appendingPathComponent(src.deletingPathExtension().lastPathComponent).appendingPathExtension(ext)
            if fm.fileExists(atPath: out.path) { try fm.moveItem(at: out, to: dst); return }
        }
        for script in appleScripts(for: src, ext: ext) {
            try? shell("/usr/bin/osascript", ["-e", script, src.path, dst.path])
            if fm.fileExists(atPath: dst.path) { return }
        }
        throw ConvertError(L("You need the Excel & PowerPoint add-on. Click the SATF icon in the menu bar → Add-ons…", "Cần thêm gói Excel & PowerPoint. Bấm icon SATF trên thanh menu → Gói tải thêm…"))
    }

    private static func appleScripts(for src: URL, ext: String) -> [String] {
        func installed(_ id: String) -> Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil }
        func iWork(_ id: String, _ fmt: String) -> String {
            """
            on run {src, dst}
              tell application id "\(id)"
                set d to open (POSIX file src)
                export d to (POSIX file dst) as \(fmt)
                close d saving no
              end tell
            end run
            """
        }
        var list: [(String, String)] = []   // (bundle id, script)
        switch kind(of: src) {
        case .spreadsheet:
            let f = ext == "csv" ? "CSV file format" : "PDF file format"
            list.append(("com.microsoft.Excel", """
            on run {src, dst}
              tell application id "com.microsoft.Excel"
                open (POSIX file src)
                set wb to active workbook
                save workbook as wb filename dst file format \(f)
                close wb saving no
              end tell
            end run
            """))
            list.append(("com.apple.iWork.Numbers", iWork("com.apple.iWork.Numbers", ext == "csv" ? "CSV" : "PDF")))
        case .presentation where ext == "pdf":
            list.append(("com.microsoft.Powerpoint", """
            on run {src, dst}
              tell application id "com.microsoft.Powerpoint"
                open (POSIX file src)
                set p to active presentation
                save p in (POSIX file dst as string) as save as PDF
                close p
              end tell
            end run
            """))
            list.append(("com.apple.iWork.Keynote", iWork("com.apple.iWork.Keynote", "PDF")))
        default: break
        }
        return list.filter { installed($0.0) }.map { $0.1 }
    }

    // MARK: - Tiện ích

    private static func zip(_ src: URL) throws -> URL {
        let dst = destination(for: src, ext: "zip")
        try shell("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", src.path, dst.path])
        return dst
    }

    /// Nén nhiều file / thư mục vào một file "Archive.zip" cạnh file đầu tiên.
    private static func zip(_ files: [URL]) throws -> URL {
        let fm = FileManager.default
        // Gom vào một thư mục tạm rồi nén cả thư mục. Trên APFS, copy là bản sao nhanh, không tốn thêm dung lượng.
        let stage = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        for file in files {
            try fm.copyItem(at: file, to: uniqueURL(in: stage, name: file.lastPathComponent))
        }
        let dst = uniqueURL(in: files[0].deletingLastPathComponent(), name: L("Archive", "Lưu trữ") + ".zip")
        try shell("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", stage.path, dst.path])
        return dst
    }

    /// Giải nén ra thư mục cạnh file. Bên trong chỉ có 1 thư mục/file thì đưa thẳng ra ngoài, khỏi lồng 2 lớp.
    private static func extract(_ src: URL) throws -> URL {
        let fm = FileManager.default
        let dir = src.deletingLastPathComponent()
        var base = src.deletingPathExtension()
        if base.pathExtension.lowercased() == "tar" { base = base.deletingPathExtension() }   // ví dụ .tar.gz
        let out = uniqueURL(in: dir, name: base.lastPathComponent)
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        do {
            if src.pathExtension.lowercased() == "zip" {
                try shell("/usr/bin/ditto", ["-x", "-k", src.path, out.path])
            } else {
                try shell("/usr/bin/tar", ["-xf", src.path, "-C", out.path])   // rar, 7z, tar, gz, bz2, xz
            }
        } catch {
            try? fm.removeItem(at: out)
            throw ConvertError(L("Couldn't extract this file. It may need a password or another app.",
                                 "Chưa giải nén được. File có thể cần mật khẩu hoặc app khác."))
        }
        try? fm.removeItem(at: out.appendingPathComponent("__MACOSX"))
        let items = (try? fm.contentsOfDirectory(at: out, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        if items.count == 1 {
            let target = uniqueURL(in: dir, name: items[0].lastPathComponent)
            if (try? fm.moveItem(at: items[0], to: target)) != nil {
                try? fm.removeItem(at: out)
                return target
            }
        }
        return out
    }

    /// "Tên", "Tên (1)", "Tên (2)"... cho file/thư mục chưa tồn tại
    static func uniqueURL(in dir: URL, name: String) -> URL {
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var url = dir.appendingPathComponent(name)
        var n = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent(ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)")
            n += 1
        }
        return url
    }

    private static func afconvert(_ src: URL, to format: Format) throws -> URL {
        let dst = destination(for: src, ext: format.ext)
        let args = format == .wav ? ["-f", "WAVE", "-d", "LEI16"] : ["-f", "AIFF", "-d", "BEI16"]
        try shell("/usr/bin/afconvert", args + [src.path, dst.path])
        return dst
    }

    private static func shell(_ path: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 { throw ConvertError(L("Conversion didn't work. Please try again.", "Chuyển không thành công, thử lại nhé")) }
    }
}
