import AppKit
import SwiftUI

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.appearance = NSAppearance(named: CommandLine.arguments[3] == "dark" ? .darkAqua : .aqua)
NSApp.applicationIconImage = NSImage(contentsOfFile: "assets/logo.png")
let out = URL(fileURLWithPath: CommandLine.arguments[1])
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

let steps: [(@escaping () -> Void) -> Void] = [
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
func run(_ i: Int) { if i < steps.count { let step = steps[i]; step({ run(i + 1) }) } else { exit(0) } }
DispatchQueue.main.async { run(0) }
app.run()
