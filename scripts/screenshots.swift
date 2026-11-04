import AppKit
import SwiftUI

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.appearance = NSAppearance(named: CommandLine.arguments[3] == "dark" ? .darkAqua : .aqua)
NSApp.applicationIconImage = NSImage(contentsOfFile: "assets/brand/logo.png")
let out = URL(fileURLWithPath: CommandLine.arguments[1])
// Chế độ "appstore": ảnh 2880x1800 cho Mac App Store, ngôn ngữ ở tham số thứ 5 (en | vi)
let appStoreMode = CommandLine.arguments.count > 4 && CommandLine.arguments[4] == "appstore"
let storeLang = CommandLine.arguments.count > 5 ? CommandLine.arguments[5] : "en"
// Ảnh README (dùng chung cho cả README.vi.md) luôn là tiếng Anh, không theo ngôn ngữ của máy
Settings.shared.language = appStoreMode && storeLang == "vi" ? .vi : .en
let samples = URL(fileURLWithPath: CommandLine.arguments[2])
func sample(_ n: String) -> URL { samples.appendingPathComponent(n) }

func snap<V: View>(_ name: String, _ view: V, size: CGSize, then: @escaping () -> Void) {
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(origin: .zero, size: size)
    let w = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    w.isOpaque = false
    w.backgroundColor = .clear
    w.contentView = host
    w.setFrameOrigin(NSPoint(x: -4000, y: -4000))   // ngoài màn hình
    w.orderFrontRegardless()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82])!.write(to: out.appendingPathComponent(name + ".jpg"))
        w.orderOut(nil)
        then()
    }
}

// Menu tròn: nửa Chuyển đổi đang mở, rê vào PDF
let m1 = RadialModel(files: [sample("Vacation photo.png")])
m1.expanded = .convert; m1.hoveredSide = .convert; m1.hoveredItem = 1
// Menu tròn: bung cả vòng
let m2 = RadialModel(files: [sample("Vacation photo.png")])
m2.expanded = .convert; m2.showAll = true; m2.hoveredSide = .convert; m2.hoveredItem = 3
// Menu tròn: rê vào Copy
let m3 = RadialModel(files: [sample("Report Q3.docx"), sample("Vacation photo.png")])
m3.hoveredSide = .clipboard; m3.hoveredItem = 0
// Menu tròn: nửa Chỉnh sửa của ảnh JPG, rê vào "< 1 MB"
let m4 = RadialModel(files: [sample("Beach day.jpg")])
m4.expanded = .edit; m4.hoveredSide = .edit
m4.hoveredItem = m4.editItems.firstIndex { $0.target == .convert(.shrink) }
// Menu tròn: nhiều file, Chỉnh sửa -> Gộp PDF
let m5 = RadialModel(files: [sample("Beach day.jpg"), sample("Vacation photo.png"), sample("Screenshot.png")])
m5.expanded = .edit; m5.hoveredSide = .edit; m5.hoveredItem = 0
// Menu tròn: nhiều file, Chuyển đổi -> ZIP
let m6 = RadialModel(files: [sample("Report Q3.docx"), sample("Vacation photo.png"), sample("Beach day.jpg")])
m6.expanded = .convert; m6.hoveredSide = .convert; m6.hoveredItem = 0

let shelfFiles = [sample("Vacation photo.png"), sample("Beach day.jpg"), sample("Report Q3.docx"), sample("Budget 2026.xlsx"), sample("Pitch deck.pptx"), sample("Holiday.zip")]
ShelfController.shared.model.add(shelfFiles)
ShelfController.shared.model.selection = [shelfFiles[0], shelfFiles[1]]   // đang chọn 2 file để kéo cùng lúc

// Nền gradient cùng tông logo
struct Backdrop<C: View>: View {
    let content: C
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.98, green: 0.42, blue: 0.40), Color(red: 0.55, green: 0.12, blue: 0.30)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [.white.opacity(0.25), .clear], center: .topLeading, startRadius: 0, endRadius: 700)
            content
        }
    }
}

struct Hero: View {
    let model: RadialModel
    var body: some View {
        Backdrop(content: HStack(spacing: 40) {
            VStack(alignment: .leading, spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 230, height: 230)
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
                Text("Drag. Shake. Convert.").font(.system(size: 46, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text("A tiny menu that pops up right where you drag a file.\nConvert, edit, copy or shelve it in one move.")
                    .font(.system(size: 21, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.88))
                Text("macOS · Windows · Free & open source").font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 7)
                    .background(.white.opacity(0.18), in: Capsule())
            }
            RadialMenuView(model: model).frame(width: RadialGeo.size.width, height: RadialGeo.size.height)
                .scaleEffect(1.15)
        }.padding(50))
    }
}

func onBackdrop<V: View>(_ v: V) -> some View {
    Backdrop(content: v.shadow(color: .black.opacity(0.3), radius: 24, y: 10).padding(40))
}

/// Ảnh JPEG đúng kích thước pixel (App Store không nhận ảnh có kênh alpha)
func snapExact<V: View>(_ name: String, _ view: V, points: CGSize, pixels: CGSize, then: @escaping () -> Void) {
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(origin: .zero, size: points)
    let w = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = host
    w.setFrameOrigin(NSPoint(x: -6000, y: -6000))
    w.orderFrontRegardless()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = points
        host.cacheDisplay(in: host.bounds, to: rep)
        try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!.write(to: out.appendingPathComponent(name + ".jpg"))
        w.orderOut(nil)
        then()
    }
}

/// Khung ảnh App Store: tiêu đề + mô tả bên trái, giao diện thật bên phải
struct StoreShot<C: View>: View {
    let title: String
    let subtitle: String
    let content: C
    var body: some View {
        Backdrop(content: HStack(spacing: 40) {
            VStack(alignment: .leading, spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 5)
                Text(title).font(.system(size: 54, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.system(size: 24, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 560, alignment: .leading)
            content.shadow(color: .black.opacity(0.3), radius: 24, y: 10)
                .frame(width: 720, height: 780)
        }.padding(60))
    }
}

func storeRadial(_ m: RadialModel) -> some View {
    RadialMenuView(model: m).frame(width: 440, height: 480).scaleEffect(1.55)
}

let shotPoints = CGSize(width: 1440, height: 900), shotPixels = CGSize(width: 2880, height: 1800)
let appStoreSteps: [(@escaping () -> Void) -> Void] = [
    { n in snapExact("\(storeLang)-1-convert", StoreShot(
        title: L("Drag. Shake.\nConvert.", "Kéo. Lắc.\nĐổi file."),
        subtitle: L("Give a file a little shake while you drag it. A glass menu pops up right under your cursor: drop it on a format and you're done.",
                    "Lắc nhẹ khi đang kéo file, menu kính hiện ngay dưới con trỏ. Thả vào định dạng muốn đổi là xong."),
        content: storeRadial(m1)), points: shotPoints, pixels: shotPixels, then: n) },
    { n in snapExact("\(storeLang)-2-edit", StoreShot(
        title: L("Quick image edits", "Sửa ảnh trong một nốt"),
        subtitle: L("Squeeze a photo under 1 MB, compress, resize, rotate or remove location and camera info. The original is never changed.",
                    "Ép ảnh dưới 1 MB, nén, thu nhỏ, xoay hoặc xoá vị trí & thông tin máy chụp. Ảnh gốc luôn giữ nguyên."),
        content: storeRadial(m4)), points: shotPoints, pixels: shotPixels, then: n) },
    { n in snapExact("\(storeLang)-3-merge", StoreShot(
        title: L("Merge into one PDF", "Gộp thành một PDF"),
        subtitle: L("Hold several images, PDFs or documents and merge them into one PDF, or stack images into one tall picture.",
                    "Cầm nhiều ảnh, PDF hay văn bản rồi gộp thành một PDF, hoặc ghép ảnh thành một ảnh dài."),
        content: storeRadial(m5)), points: shotPoints, pixels: shotPixels, then: n) },
    { n in snapExact("\(storeLang)-4-zip", StoreShot(
        title: L("Zip it in one move", "Nén ZIP một chạm"),
        subtitle: L("Holding several files? ZIP comes first. JPG, PNG, PDF, WebP, HEIC, MP4, M4A and more are one drop away.",
                    "Cầm nhiều file thì ZIP luôn đứng đầu. JPG, PNG, PDF, WebP, HEIC, MP4, M4A… chỉ cách một lần thả."),
        content: storeRadial(m6)), points: shotPoints, pixels: shotPixels, then: n) },
    { n in snapExact("\(storeLang)-5-shelf", StoreShot(
        title: L("Park files on the Shelf", "Cất file vào Khay"),
        subtitle: L("Collect files from different folders, select several and drag them out together.",
                    "Gom file từ nhiều thư mục, chọn vài file rồi kéo ra cùng lúc."),
        content: ShelfView(model: ShelfController.shared.model, onClose: {}).fixedSize().scaleEffect(1.5)),
        points: shotPoints, pixels: shotPixels, then: n) },
]

let readmeSteps: [(@escaping () -> Void) -> Void] = [
    { n in snap("hero", Hero(model: m4), size: CGSize(width: 1280, height: 640), then: n) },
    { n in snap("radial-convert", onBackdrop(RadialMenuView(model: m1).frame(width: 440, height: 480)), size: CGSize(width: 560, height: 560), then: n) },
    { n in snap("radial-all-formats", onBackdrop(RadialMenuView(model: m2).frame(width: 440, height: 480)), size: CGSize(width: 560, height: 560), then: n) },
    { n in snap("radial-copy", onBackdrop(RadialMenuView(model: m3).frame(width: 440, height: 480)), size: CGSize(width: 560, height: 560), then: n) },
    { n in snap("radial-edit", onBackdrop(RadialMenuView(model: m4).frame(width: 440, height: 480)), size: CGSize(width: 560, height: 560), then: n) },
    { n in snap("radial-merge", onBackdrop(RadialMenuView(model: m5).frame(width: 440, height: 480)), size: CGSize(width: 560, height: 560), then: n) },
    { n in snap("donate", onBackdrop(DonateView().background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))), size: CGSize(width: 440, height: 680), then: n) },
    { n in snap("shelf", onBackdrop(ShelfView(model: ShelfController.shared.model, onClose: {}).fixedSize()), size: CGSize(width: 420, height: 440), then: n) },
    { n in snap("settings", onBackdrop(SettingsView().frame(width: 460, height: 1100).background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))).frame(width: 540), size: CGSize(width: 540, height: 1180), then: n) },
]
let steps = appStoreMode ? appStoreSteps : readmeSteps
func run(_ i: Int) { if i < steps.count { let step = steps[i]; step({ run(i + 1) }) } else { exit(0) } }
DispatchQueue.main.async { run(0) }
app.run()
