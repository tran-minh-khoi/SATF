// Kiểm tra các thao tác Edit. Chạy: scripts/test-mac.sh
import AppKit
import PDFKit
import ImageIO
import UniformTypeIdentifiers

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let logo = URL(fileURLWithPath: CommandLine.arguments[2])

// Ảnh chụp giả: 3000x2000 JPG có GPS + EXIF, hướng xoay 6 (chụp dọc)
func makePhoto(_ url: URL) {
    let w = 3000, h = 2000
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    for i in 0..<60 { ctx.setFillColor(CGColor(red: CGFloat(i%7)/7, green: CGFloat(i%5)/5, blue: CGFloat(i%3)/3, alpha: 1)); ctx.fill(CGRect(x: (i*97)%w, y: (i*53)%h, width: 400, height: 300)) }
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    let props: [CFString: Any] = [kCGImagePropertyOrientation: 6, kCGImageDestinationLossyCompressionQuality: 0.95,
        kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 10.77, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 106.7, kCGImagePropertyGPSLongitudeRef: "E"],
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "secret camera"],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "TestCam 9000"]]
    CGImageDestinationAddImage(dest, ctx.makeImage()!, props as CFDictionary)
    CGImageDestinationFinalize(dest)
}
func info(_ url: URL) -> String {
    let s = CGImageSourceCreateWithURL(url as CFURL, nil)!
    let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as! [CFString: Any]
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    let gps = p[kCGImagePropertyGPSDictionary] != nil, model = (p[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel] != nil
    return "\(p[kCGImagePropertyPixelWidth]!)x\(p[kCGImagePropertyPixelHeight]!) orient=\(p[kCGImagePropertyOrientation] ?? 1) gps=\(gps) model=\(model) \(size/1000)KB"
}
var failures = 0
func check(_ ok: Bool, _ msg: String) { print((ok ? "PASS " : "FAIL ") + msg); if !ok { failures += 1 } }

let photo = dir.appendingPathComponent("photo.jpg"); makePhoto(photo)
print("source:", info(photo))
let png = dir.appendingPathComponent("logo.png"); try! FileManager.default.copyItem(at: logo, to: png)

// Nhóm Convert/Edit
let t = Converter.targets(for: photo)
check(t.filter(\.isEdit) == [.rotate, .resize, .compress, .shrink, .stripMetadata], "photo edits \(t.filter(\.isEdit))")
check(Converter.targets(for: png).filter(\.isEdit) == [.rotate, .resize, .shrink, .stripMetadata], "png has no Compress")
check(Converter.targets(for: [photo, png]).filter(\.isEdit).prefix(2) == [.mergePDF, .longImage], "multi: merge + stack first")

func run(_ f: Format, _ src: URL) -> [URL] { do { return try Converter.convert(src, to: f) } catch { check(false, "\(f) threw: \(error.localizedDescription)"); return [] } }

// Xoay: ảnh gốc hiển thị 2000x3000 (orient 6) -> xoay -> 3000x2000, orient 1
if let r = run(.rotate, photo).first { let i = info(r); print("rotate:", i); check(i.hasPrefix("3000x2000 orient=1"), "rotate bakes orientation and turns") }
Settings.shared.resizeEdge = 1920
if let r = run(.resize, photo).first { let i = info(r); print("resize:", i); check(i.hasPrefix("1280x1920"), "resize long side 1920 keeping portrait") }
Settings.shared.compressLevel = .strong
if let r = run(.compress, photo).first { print("compress:", info(r)); check(info(r).contains("gps=false"), "compress drops GPS") }
Settings.shared.targetSizeKB = 200
if let r = run(.shrink, photo).first { let kb = (try! r.resourceValues(forKeys: [.fileSizeKey]).fileSize!); print("shrink:", info(r)); check(kb <= 200_000, "shrink under 200KB") }
if let r = run(.shrink, png).first { print("shrink png:", r.lastPathComponent, info(r)); check(r.pathExtension == "jpg", "png shrinks to jpg") }
if let r = run(.stripMetadata, photo).first { let i = info(r); print("strip:", i); check(i.contains("orient=6 gps=false model=false"), "strip keeps orientation, removes GPS+camera") }
if let r = run(.rotate, png).first { print("rotate png:", info(r)); check(r.pathExtension == "png", "png stays png") }

// Ghép dọc
do { let r = try Converter.process([photo, png], .longImage).first!; print("stack:", r.lastPathComponent, info(r)) } catch { check(false, "stack \(error)") }

// PDF: tạo PDF 3 trang, xoay
let pdfURL = dir.appendingPathComponent("doc.pdf")
let doc = PDFDocument(); for i in 0..<3 { doc.insert(PDFPage(image: NSImage(contentsOf: png)!)!, at: i) }; doc.write(to: pdfURL)
check(Converter.targets(for: pdfURL).filter(\.isEdit) == [.splitPDF, .rotate], "pdf edits")
if let r = run(.rotate, pdfURL).first { let d = PDFDocument(url: r)!; check(d.pageCount == 3 && d.page(at: 0)!.rotation == 90, "pdf rotated 90, 3 pages") }
print(failures == 0 ? "ALL PASS" : "\(failures) FAILED"); exit(failures == 0 ? 0 : 1)
