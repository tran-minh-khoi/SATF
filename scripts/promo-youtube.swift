// Video giới thiệu SATF cho YouTube (ngang 1920×1080, 30 fps, nhạc EDM + hiệu ứng âm thanh).
// Câu mở đầu -> cách cũ -> SATF là lời giải (drop) -> demo -> kêu gọi. Phần demo dùng lại đúng các cảnh của
// bản TikTok (scripts/promo.swift), đặt ở nửa phải khung hình; chữ nằm bên trái.
import AppKit
import AVFoundation
import SwiftUI

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.appearance = NSAppearance(named: .darkAqua)
NSApp.applicationIconImage = NSImage(contentsOfFile: "assets/logo.png")
Settings.shared.language = .en
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
let samples = URL(fileURLWithPath: CommandLine.arguments[2])
func sample(_ n: String) -> URL { samples.appendingPathComponent(n) }

// Sân khấu demo: toạ độ dọc giống bản TikTok, thu nhỏ rồi đặt vào nửa phải khung ngang
let W: CGFloat = 540, H: CGFloat = 960
let C = CGPoint(x: 270, y: 480)
let M = CGPoint(x: 270, y: 470)                 // tâm menu tròn trên sân khấu
let LW: CGFloat = 960, LH: CGFloat = 540        // khung ngang (toạ độ thiết kế); xuất ra gấp đôi = 1920×1080
let AS: CGFloat = 0.78                          // độ thu sân khấu
let AX: CGFloat = 670, AY: CGFloat = 290        // tâm menu nằm ở đây trên khung ngang
let FPS = 30.0

// Mốc các cảnh (giây). Mọi mốc là bội của 0,5 s = một phách nhạc 120 BPM.
let H0 = 3.0                                    // câu mở đầu
let S1 = H0 + 3.0                               // hết "cách cũ" -> "Có cách nhanh hơn"
let DROP = S1 + 1.0                             // nhạc vào, SATF xuất hiện
let S2 = S1 + 3.5, S3 = S2 + 6, S4 = S3 + 4.5, S5 = S4 + 4, S6 = S5 + 6, S7 = S6 + 2.5
let DUR = S7 + 6.5
let cuts = [H0, S1, S2, S3, S4, S5, S6, S7]

// MARK: - Nhịp chuyển động

func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
func prog(_ t: Double, _ a: Double, _ d: Double) -> Double { clamp((t - a) / d) }
func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
func easeInOut(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
func spring(_ x: Double) -> Double { x >= 1 ? 1 : 1 - exp(-7 * x) * cos(11 * x) }   // nảy quá đà rồi về 1
func lerp(_ a: CGPoint, _ b: CGPoint, _ x: Double) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * CGFloat(x), y: a.y + (b.y - a.y) * CGFloat(x)) }

func polar(_ deg: Double, _ r: Double) -> CGPoint {
    CGPoint(x: M.x + CGFloat(cos(deg * .pi / 180) * r), y: M.y + CGFloat(sin(deg * .pi / 180) * r))
}

/// Chuyển cảnh kiểu "zoom xuyên": cảnh cũ phóng to rồi biến mất, cảnh mới thu từ nhỏ về, loé sáng ở giữa
func cutFX(_ t: Double) -> (scale: Double, alpha: Double, flash: Double) {
    for c in cuts {
        if t >= c - 0.25 && t < c { let x = prog(t, c - 0.25, 0.25); return (1 + 0.55 * x * x, 1 - x * x, 0.35 * x * x) }
        if t >= c && t < c + 0.4 { let x = easeOut(prog(t, c, 0.4)); return (0.72 + 0.28 * x, clamp(prog(t, c, 0.12)), 0.35 * (1 - clamp(prog(t, c, 0.18)))) }
    }
    return (1, 1, 0)
}

/// Camera trong từng cảnh: (giây, độ phóng, điểm nhìn)
let cameraKeys: [[(Double, Double, CGPoint)]] = [
    [],
    [(H0, 1, C), (H0 + 2.6, 1.06, C)],
    [],
    [(S2 + 2.2, 1, M), (S2 + 2.75, 1.32, polar(300, 105)), (S2 + 4.3, 1.32, polar(292, 110)), (S2 + 4.75, 1, M)],
    [(S3 + 1.2, 1, M), (S3 + 1.75, 1.3, polar(392, 105)), (S3 + 2.5, 1.3, polar(395, 110)), (S3 + 2.85, 1, M),
     (S3 + 2.95, 1, CGPoint(x: 270, y: 520)), (S4, 1.14, CGPoint(x: 270, y: 520))],
    [(S4 + 1.3, 1, M), (S4 + 1.65, 1.26, polar(350, 110)), (S4 + 2.05, 1.26, polar(292, 110)), (S4 + 2.6, 1.26, polar(290, 110)), (S4 + 2.95, 1, M)],
    [(S5 + 3.45, 1, C), (S5 + 3.7, 1.12, CGPoint(x: 270, y: 520)), (S5 + 4.3, 1.12, CGPoint(x: 270, y: 560)), (S5 + 4.8, 1, C)],
    [(S6, 1, C), (S7, 1.08, C)],
    [],
]
func camera(_ t: Double) -> (Double, CGPoint) {
    let i = cuts.lastIndex { t >= $0 }.map { $0 + 1 } ?? 0
    let keys = cameraKeys[i]
    guard let first = keys.first else { return (1, C) }
    if t <= first.0 { return (first.1, first.2) }
    for (a, b) in zip(keys, keys.dropFirst()) where t < b.0 {
        let x = easeInOut(prog(t, a.0, b.0 - a.0))
        return (a.1 + (b.1 - a.1) * x, lerp(a.2, b.2, x))
    }
    return (keys.last!.1, keys.last!.2)
}

// MARK: - Con trỏ

enum P { case xy(Double, Double), pol(Double, Double) }
func pt(_ p: P) -> CGPoint { switch p { case .xy(let x, let y): return CGPoint(x: x, y: y); case .pol(let a, let r): return polar(a, r) } }
enum Ghost { case none, photo(Double), doc(String, Color), stack(Int) }

struct Track {
    let keys: [(Double, P)]
    let pressed: [(Double, Double)]
    var shakes: [(Double, Double, Double, Double)] = []   // bắt đầu, kết thúc, chu kỳ, biên độ
    var ghost: Ghost = .none
    var visible: (Double, Double) { (keys.first!.0, keys.last!.0) }

    init(_ base: Double, _ keys: [(Double, P)], pressed: [(Double, Double)], shakes: [(Double, Double, Double, Double)] = [], ghost: Ghost = .none) {
        self.keys = keys.map { ($0.0 + base, $0.1) }
        self.pressed = pressed.map { ($0.0 + base, $0.1 + base) }
        self.shakes = shakes.map { ($0.0 + base, $0.1 + base, $0.2, $0.3) }
        self.ghost = ghost
    }

    func pos(_ t: Double) -> CGPoint {
        var p = pt(keys[0].1)
        for (a, b) in zip(keys, keys.dropFirst()) where t >= a.0 {
            let x = easeInOut(prog(t, a.0, b.0 - a.0))
            if case .pol(let a1, let r1) = a.1, case .pol(let a2, let r2) = b.1, r1 > 0 {
                p = polar(a1 + (a2 - a1) * x, r1 + (r2 - r1) * x)   // đi theo cung tròn
            } else {
                p = lerp(pt(a.1), pt(b.1), x)
            }
        }
        for (s, e, period, amp) in shakes where t > s && t < e {
            p.x += CGFloat(amp * sin(2 * .pi * (t - s) / period) * sin(.pi * (t - s) / (e - s)))
        }
        return p
    }
    func isPressed(_ t: Double) -> Bool { pressed.contains { t >= $0.0 && t < $0.1 } }
}

// Cửa sổ "cách cũ": vị trí bấm chuột
let oldCards: [(title: String, at: Double)] = [("Preview", 0.35), ("File", 0.8), ("Export", 1.25), ("Save As", 1.7)]
func oldCardCenter(_ i: Int) -> CGPoint { CGPoint(x: 236 + CGFloat(i) * 22, y: 292 + CGFloat(i) * 112) }
func oldClick(_ i: Int) -> P { let c = oldCardCenter(i); return .xy(Double(c.x) + 70, Double(c.y) + 32) }

let tracks = [
    Track(H0, [(0.0, .xy(520, 900)), (0.3, oldClick(0)), (0.75, oldClick(1)), (1.2, oldClick(2)), (1.65, oldClick(3)), (2.4, oldClick(3)), (2.9, .xy(520, 920))],
          pressed: oldCards.map { ($0.at - 0.03, $0.at + 0.05) }),
    Track(S2, [(0, .xy(500, 900)), (0.45, .xy(276, 628)), (0.55, .xy(276, 628)), (1.0, .pol(0, 0)), (2.25, .pol(0, 0)),
               (2.65, .pol(315, 85)), (2.85, .pol(315, 85)), (3.45, .pol(285, 160)), (4.65, .pol(285, 160)), (5.15, .xy(500, 920))],
          pressed: [(0.5, 3.75)], shakes: [(1.0, 1.7, 0.35, 44)], ghost: .photo(0)),
    Track(S3, [(0, .xy(500, 900)), (0.3, .xy(276, 606)), (0.35, .xy(276, 606)), (0.7, .pol(0, 0)), (1.1, .pol(0, 0)),
               (1.4, .pol(405, 85)), (1.6, .pol(405, 85)), (2.0, .pol(396, 160)), (2.8, .pol(396, 160)), (3.3, .xy(500, 920))],
          pressed: [(0.3, 2.25)], shakes: [(0.7, 1.0, 0.3, 36)], ghost: .photo(0.5)),
    Track(S4, [(0.1, .xy(500, 900)), (0.5, .pol(0, 0)), (1.1, .pol(0, 0)), (1.4, .pol(405, 85)), (1.55, .pol(400, 160)),
               (2.0, .pol(285, 160)), (2.8, .pol(285, 160)), (3.2, .xy(500, 920))],
          pressed: [(0.5, 2.25)], ghost: .stack(3)),
    Track(S5, [(0.1, .xy(500, 900)), (0.45, .xy(276, 626)), (0.5, .xy(276, 626)), (0.9, .pol(0, 0)), (1.3, .pol(0, 0)),
               (1.7, .pol(222, 88)), (2.0, .pol(222, 88)), (2.35, .xy(500, 920))],
          pressed: [(0.5, 2.0)], shakes: [(0.9, 1.2, 0.3, 36)], ghost: .doc("DOCX", Theme.clipboard)),
    Track(S5 + 3.85, [(0, .xy(520, 900)), (0.35, .xy(262, 420)), (0.45, .xy(262, 420)), (1.0, .xy(250, 745)), (1.5, .xy(250, 745)), (1.95, .xy(520, 920))],
          pressed: [(0.4, 1.1)], ghost: .stack(4)),
]
func track(_ t: Double) -> Track? { tracks.first { t >= $0.visible.0 && t <= $0.visible.1 } }

// MARK: - Menu tròn (dùng thẳng RadialModel của app)

struct MenuShow { let model: RadialModel; let pop, drop, done, close: Double; let msg: String }
let menus = [
    MenuShow(model: RadialModel(files: [sample("Vacation photo.png")]), pop: S2 + 1.75, drop: S2 + 3.75, done: S2 + 4.15, close: S2 + 4.65, msg: "Done! · Vacation photo.jpg"),
    MenuShow(model: RadialModel(files: [sample("Beach day.jpg")]), pop: S3 + 1.0, drop: S3 + 2.25, done: S3 + 2.5, close: S3 + 2.75, msg: "Done! · now 862 KB"),
    MenuShow(model: RadialModel(files: [sample("Beach day.jpg"), sample("Vacation photo.png"), sample("Screenshot.png")]),
             pop: S4 + 1.0, drop: S4 + 2.25, done: S4 + 2.6, close: S4 + 2.9, msg: "Done! · 3 images → 1 PDF"),
    MenuShow(model: RadialModel(files: [sample("Report Q3.docx")]), pop: S5 + 1.25, drop: S5 + 2.0, done: S5 + 2.02, close: S5 + 2.1, msg: "On the Shelf"),
]
func menu(_ t: Double) -> MenuShow { menus.last { t >= $0.pop - 1.5 } ?? menus[0] }

// MARK: - Khay (ShelfView thật của app)

let shelf = ShelfController.shared.model
let shelfAt = CGPoint(x: 270, y: 420)
let shelfArrivals: [(file: String, from: CGPoint, at: Double)] = [
    ("Report Q3.docx", shelfAt, S5 + 2.3),
    ("Vacation photo.png", CGPoint(x: -60, y: 260), S5 + 2.9),
    ("Budget 2026.xlsx", CGPoint(x: 600, y: 330), S5 + 3.15),
    ("Pitch deck.pptx", CGPoint(x: 270, y: 1020), S5 + 3.4),
]
let shelfSelectAll = S5 + 3.65, mailDrop = S5 + 3.85 + 1.1

// MARK: - Âm thanh: danh sách sự kiện

enum Sfx { case pop(Double), textPop, tick(Double), whoosh(Double), click, chime(Double), thump, sweep, crash, riser, sparkle }
var events: [(Double, Sfx)] = []
func ev(_ base: Double, _ list: [(Double, Sfx)]) { events += list.map { ($0.0 + base, $0.1) } }

// Câu mở đầu: mỗi chữ đập xuống một tiếng
let hookWords = ["Still", "converting", "files"]
let hookTimes = [0.25, 0.5, 0.75]
let slowAt = 1.25
var hookSfx: [(Double, Sfx)] = [(slowAt, Sfx.thump), (slowAt, Sfx.pop(0.55)), (slowAt + 0.02, Sfx.crash)]
for (i, at) in hookTimes.enumerated() { hookSfx += [(at, Sfx.thump), (at, Sfx.pop(0.7 + Double(i) * 0.12))] }
ev(0, hookSfx)
ev(H0, [(0.05, .textPop), (2.05, .thump), (2.05, .pop(0.6))] + oldCards.flatMap { [($0.at, .click), ($0.at + 0.03, .pop(0.8))] })
// "There's a faster way." rồi drop: SATF xuất hiện
let fasterWords = ["There's", "a", "faster", "way."]
var fasterSfx: [(Double, Sfx)] = []
for i in fasterWords.indices { fasterSfx.append((0.05 + Double(i) * 0.12, Sfx.textPop)) }
ev(S1, fasterSfx)
var dropSfx: [(Double, Sfx)] = [(0, Sfx.crash), (0, Sfx.thump), (0, Sfx.pop(1.3)), (0.3, Sfx.sparkle)]
for i in 0..<4 { dropSfx.append((0.15 + Double(i) * 0.07, Sfx.pop(1 + Double(i) * 0.1))) }
for i in 0..<3 { dropSfx.append((0.55 + Double(i) * 0.18, Sfx.textPop)) }
ev(DROP, dropSfx)
ev(S2, [(0, .textPop), (0.1, .pop(1)), (0.5, .click), (1.75, .pop(1)), (1.75, .thump), (2.25, .textPop), (2.2, .whoosh(0.25)),
        (3.75, .click), (4.15, .chime(1)), (4.3, .whoosh(0.25)), (4.75, .textPop), (4.85, .pop(0.9)), (5.1, .pop(1.25))])
ev(S3, [(0, .textPop), (0.05, .pop(1)), (0.3, .click), (1.0, .pop(1)), (1.0, .thump), (1.2, .whoosh(0.25)), (2.25, .click), (2.5, .chime(1)),
        (2.95, .pop(1)), (3.05, .sweep), (3.65, .chime(1.5))])
ev(S4, [(0, .textPop), (0, .pop(0.9)), (0.125, .pop(1.05)), (0.25, .pop(1.2)), (0.5, .whoosh(0.4)), (1.0, .pop(1)), (1.0, .thump),
        (2.25, .click), (2.6, .chime(1)), (3.25, .thump), (3.25, .pop(1.1))])
ev(S5, [(0, .textPop), (0.05, .pop(1)), (0.5, .click), (1.25, .pop(1)), (1.25, .thump), (2.0, .click), (2.3, .pop(1.1)), (2.3, .textPop),
        (3.6, .click), (3.65, .tick(1.3)), (3.85, .pop(0.9)), (4.25, .click), (4.95, .chime(1))])
for a in shelfArrivals.dropFirst() { events += [(a.at - 0.3, .whoosh(0.25)), (a.at, .pop(1.15))] }
ev(S6, [(0, .textPop), (1.6, .textPop)])
ev(S7, [(0, .pop(1)), (0, .thump), (0.25, .textPop), (0.5, .textPop), (1.0, .tick(1)), (1.25, .tick(1.12)), (1.5, .tick(1.26)),
        (2.0, .crash), (2.0, .thump), (2.0, .pop(1.3)), (2.75, .sparkle)])
for c in cuts { events.append((c - 0.12, .whoosh(0.35))) }
for track in tracks { for (s, e, period, _) in track.shakes { var x = s + period / 4; while x < e { events.append((x, .whoosh(0.16))); x += period / 2 } } }

let formatChips: [(String, Color)] = [
    ("PNG", Theme.convert), ("JPG", Theme.convert), ("WEBP", Theme.convert), ("HEIC", Theme.convert),
    ("AVIF", Theme.convert), ("GIF", Theme.convert), ("PDF", Theme.edit), ("DOCX", Theme.edit),
    ("TXT", Theme.edit), ("HTML", Theme.edit), ("CSV", Theme.edit), ("MP4", Theme.clipboard),
    ("MOV", Theme.clipboard), ("M4A", Theme.clipboard), ("WAV", Theme.clipboard), ("ZIP", Theme.donate),
]
let chipStart = S6 + 0.15, chipStep = 0.08
for i in formatChips.indices { events.append((chipStart + Double(i) * chipStep, .tick(1 + Double(i) * 0.045))) }

// MARK: - Thành phần hình

final class Clock: ObservableObject { @Published var t = 0.0 }
let clock = Clock()

/// Nhịp trống (0…1, đỉnh ngay mỗi phách) trong đoạn có trống
func beatPulse(_ t: Double) -> Double {
    guard t >= DROP && t < S7 + 2.5 else { return 0 }
    return exp(-(t - DROP).truncatingRemainder(dividingBy: 0.5) * 7)
}

struct Backdrop: View {
    let t: Double
    var body: some View {
        let pulse = beatPulse(t)
        ZStack {
            LinearGradient(colors: [Color(red: 0.98, green: 0.42, blue: 0.40), Color(red: 0.55, green: 0.12, blue: 0.30)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // Không dùng blur: vẽ ngoài màn hình không áp được bộ lọc
            RadialGradient(colors: [.white.opacity(0.26), .clear], center: .center, startRadius: 0, endRadius: 520)
                .frame(width: 1300, height: 1300)
                .position(x: CGFloat(300 + sin(t * 0.6) * 80), y: CGFloat(120 + cos(t * 0.5) * 60))
            RadialGradient(colors: [Color(red: 1, green: 0.75, blue: 0.4).opacity(0.32), .clear], center: .center, startRadius: 0, endRadius: 320)
                .frame(width: 700, height: 700)
                .position(x: CGFloat(800 + sin(t * 0.8) * 70), y: CGFloat(430 + cos(t * 0.7) * 50))
            // Vệt sáng chéo trôi ngang
            ForEach(0..<3, id: \.self) { i in
                let x = (t * 60 + Double(i) * 420).truncatingRemainder(dividingBy: 1500) - 300
                LinearGradient(colors: [.clear, .white.opacity(0.07), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 140, height: 1100)
                    .rotationEffect(.degrees(24))
                    .position(x: CGFloat(x), y: LH / 2)
            }
            // Hạt sáng bay lên
            ForEach(0..<26, id: \.self) { i in
                let seed = Double(i) * 12.9898
                let speed = 18 + (sin(seed) + 1) * 14
                let y = Double(LH) + 20 - (t * speed + (cos(seed) + 1) * 300).truncatingRemainder(dividingBy: Double(LH) + 40)
                let x = (sin(seed * 3.7) + 1) / 2 * Double(LW) + sin(t * 0.9 + seed) * 14
                Circle().fill(.white.opacity(0.12 + 0.18 * (sin(seed * 5.1) + 1) / 2 + 0.15 * pulse))
                    .frame(width: CGFloat(3 + (i % 4) * 2), height: CGFloat(3 + (i % 4) * 2))
                    .position(x: CGFloat(x), y: CGFloat(y))
            }
            Color.white.opacity(0.045 * pulse)
        }
        .frame(width: LW, height: LH)
    }
}

/// Ảnh minh hoạ kiểu "hoàng hôn" thay cho thumbnail ảnh thật
struct PhotoThumb: View {
    var size: CGFloat = 110
    var hue: Double = 0
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hue: 0.08 + hue, saturation: 0.7, brightness: 1), Color(hue: 0.92 + hue, saturation: 0.6, brightness: 0.85),
                                    Color(hue: 0.75 + hue, saturation: 0.55, brightness: 0.55)], startPoint: .top, endPoint: .bottom)
            Circle().fill(Color(red: 1, green: 0.92, blue: 0.6)).frame(width: size * 0.32).offset(x: size * 0.14, y: -size * 0.04)
            Path { p in
                p.move(to: CGPoint(x: 0, y: size * 0.78))
                p.addLine(to: CGPoint(x: size * 0.3, y: size * 0.5)); p.addLine(to: CGPoint(x: size * 0.5, y: size * 0.68))
                p.addLine(to: CGPoint(x: size * 0.72, y: size * 0.44)); p.addLine(to: CGPoint(x: size, y: size * 0.74))
                p.addLine(to: CGPoint(x: size, y: size)); p.addLine(to: CGPoint(x: 0, y: size)); p.closeSubpath()
            }.fill(Color(red: 0.25, green: 0.1, blue: 0.3).opacity(0.85))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.12, style: .continuous).strokeBorder(.white, lineWidth: size > 60 ? 3 : 2))
        .shadow(color: .black.opacity(0.3), radius: size / 9, y: size / 18)
    }
}

/// Trang tài liệu tự vẽ (icon hệ thống phụ thuộc app mặc định trên máy)
struct DocIcon: View {
    var label = "PDF"
    var color = Color(red: 0.9, green: 0.22, blue: 0.24)
    var size: CGFloat = 148
    var body: some View {
        let k = size / 148
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 12 * k, style: .continuous).fill(.white)
            VStack(alignment: .leading, spacing: 9 * k) {
                ForEach(0..<5, id: \.self) { i in Capsule().fill(Color.black.opacity(0.12)).frame(width: (i == 4 ? 50 : 80) * k, height: 6 * k) }
            }.padding(.top, 22 * k)
            Text(label).font(.system(size: 24 * k, weight: .black, design: .rounded)).foregroundStyle(.white)
                .padding(.horizontal, 10 * k).padding(.vertical, 4 * k)
                .background(color, in: RoundedRectangle(cornerRadius: 8 * k))
                .padding(.top, 92 * k)
        }
        .frame(width: 116 * k, height: size)
        .shadow(color: .black.opacity(0.3), radius: 12 * k, y: 6 * k)
    }
}

struct FileTile<Icon: View>: View {
    let icon: Icon
    let name: String
    var badge: String? = nil
    var badgeColor: Color = Theme.edit
    var body: some View {
        VStack(spacing: 8) {
            icon.overlay(alignment: .topTrailing) {
                if let badge {
                    Text(badge).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(badgeColor, in: Capsule())
                        .offset(x: 12, y: -10).shadow(radius: 4)
                }
            }
            Text(name).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3).background(.black.opacity(0.22), in: Capsule())
                .fixedSize()
        }
    }
}

/// Cửa sổ giả cho phần "cách cũ"
struct WindowCard<Content: View>: View {
    let title: String
    let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.85)).frame(width: 9, height: 9) }
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 6)
                Spacer()
            }
            .padding(.horizontal, 12).frame(height: 28).background(Color(white: 0.22))
            content.padding(14).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 300)
        .background(Color(white: 0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .foregroundStyle(.white)
    }
}

/// Hiện bằng cú nảy, biến mất bằng thu nhỏ
struct Pop: ViewModifier {
    let t: Double, a: Double, b: Double
    var dy: CGFloat = 16
    func body(content: Content) -> some View {
        let p = spring(prog(t, a, 0.55)), out = easeInOut(prog(t, b - 0.22, 0.22))
        return content
            .scaleEffect(CGFloat((0.6 + 0.4 * p) * (1 - 0.25 * out)))
            .opacity(clamp(prog(t, a, 0.12)) * (1 - out))
            .offset(y: CGFloat(1 - p) * dy)
    }
}
extension View {
    func pop(_ t: Double, _ a: Double, _ b: Double = 999, dy: CGFloat = 16) -> some View { modifier(Pop(t: t, a: a, b: b, dy: dy)) }
    func at(_ x: CGFloat, _ y: CGFloat) -> some View { position(x: x, y: y) }
    func at(_ p: CGPoint) -> some View { position(p) }
    /// Chỉ hiện trong cảnh [a, b)
    func scene(_ t: Double, _ a: Double, _ b: Double) -> some View { opacity(t >= a && t < b ? 1 : 0) }
}

/// Chữ bên trái khung: nhãn nhỏ, các dòng trượt vào lần lượt, gạch chân chạy ra
struct SideHeadline: View {
    let t: Double, a: Double, b: Double
    let chip: String
    let lines: [String]
    var body: some View {
        let out = easeInOut(prog(t, b - 0.22, 0.22))
        let bar = easeOut(prog(t, a + 0.25, 0.45))
        VStack(alignment: .leading, spacing: 14) {
            Text(chip).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 6).background(.white.opacity(0.2), in: Capsule())
                .pop(t, a)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    let p = easeOut(prog(t, a + 0.08 + Double(i) * 0.09, 0.4))
                    Text(line).font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .fixedSize()
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                        .offset(x: CGFloat(1 - p) * -40)
                        .opacity(p)
                }
            }
            Capsule().fill(.white).frame(width: CGFloat(90 * bar), height: 6)
        }
        .frame(width: 400, alignment: .leading)
        .opacity(1 - out)
        .offset(x: CGFloat(-30 * out))
        .position(x: 260, y: LH / 2)
        .scene(t, a, b)
    }
}

/// Đập xuống: to gấp đôi rồi co về, rung nhẹ
struct Slam: ViewModifier {
    let t: Double, at: Double
    func body(content: Content) -> some View {
        let s = prog(t, at, 0.16)
        let after = t - at - 0.16
        let wob: Double = s >= 1 ? 0.05 * exp(-after * 12) * sin(after * 55) : 0
        return content
            .scaleEffect(CGFloat(2.4 - 1.4 * easeOut(s) + wob))
            .opacity(clamp(prog(t, at, 0.05)))
    }
}
extension View {
    func slam(_ t: Double, _ at: Double) -> some View { modifier(Slam(t: t, at: at)) }
}

/// Rung khung hình sau mỗi cú đập
let shakeHits: [(Double, Double)] = [(hookTimes[0], 5), (hookTimes[1], 5), (hookTimes[2], 5), (slowAt, 9), (H0 + 2.05, 6), (DROP, 12), (S7, 6)]
func screenShake(_ t: Double) -> CGSize {
    var x = 0.0, y = 0.0
    for (at, amp) in shakeHits where t >= at && t < at + 0.5 {
        let k = amp * exp(-(t - at) * 9)
        x += k * sin((t - at) * 63)
        y += k * cos((t - at) * 51)
    }
    return CGSize(width: x, height: y)
}

func stampScale(_ t: Double) -> Double {
    let s = prog(t, 2.05, 0.18)
    let wobble: Double = s >= 1 ? 0.04 * exp(-(t - 2.23) * 12) * sin((t - 2.23) * 60) : 0
    return 2.2 - 1.2 * easeOut(s) + wobble
}

/// Mũi tên chuột macOS
struct CursorShape: Shape {
    func path(in r: CGRect) -> Path {
        let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 17), (4, 13.2), (6.8, 19.6), (9.4, 18.6), (6.7, 12.2), (12, 12.2)]
        var p = Path()
        p.move(to: .zero)
        for (x, y) in pts.dropFirst() { p.addLine(to: CGPoint(x: x * 1.7, y: y * 1.7)) }
        p.closeSubpath()
        return p
    }
}

struct Keycap: View {
    let label: String
    let down: Bool
    var body: some View {
        Text(label).font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(Color(white: 0.15))
            .frame(width: 64, height: 60)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.96)))
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.6)).offset(y: down ? 1 : 5))
            .offset(y: down ? 4 : 0)
            .shadow(color: .black.opacity(0.25), radius: 8, y: 6)
    }
}

/// Vòng sóng lan ra từ tâm
struct ShockRings: View {
    let t: Double, at: Double
    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let start = at + Double(i) * 0.12
                let x = prog(t, start, 0.9)
                let d = CGFloat(40 + 900 * easeOut(x))
                Circle().strokeBorder(.white.opacity(0.7 * (1 - x)), lineWidth: CGFloat(10 * (1 - x) + 1))
                    .frame(width: d, height: d)
                    .opacity(t >= start && x < 1 ? 1 : 0)
            }
        }
        .frame(width: 940, height: 940)
    }
}

/// Pháo giấy bắn ra rồi rơi
struct Confetti: View {
    let t: Double, at: Double
    static let colors: [Color] = [Theme.convert, Theme.edit, Theme.clipboard, Color(red: 1, green: 0.86, blue: 0.35), .white]
    var body: some View {
        let dt = t - at
        let fade = 1 - prog(t, at + 1.4, 0.8)
        ZStack {
            ForEach(0..<44, id: \.self) { i in
                let seed = Double(i) * 7.31
                let ang = Double(i) / 44 * 2 * .pi + sin(seed) * 0.3
                let v = 260 + (sin(seed * 1.7) + 1) * 170
                let x = cos(ang) * v * dt
                let y = sin(ang) * v * dt * 0.75 + 260 * dt * dt
                RoundedRectangle(cornerRadius: 2).fill(Confetti.colors[i % 5])
                    .frame(width: CGFloat(8 + (i % 3) * 3), height: CGFloat(14 - (i % 3) * 3))
                    .rotationEffect(.degrees(dt * (200 + seed * 13)))
                    .offset(x: CGFloat(x), y: CGFloat(y))
                    .opacity(dt > 0 && dt < 2.2 ? fade : 0)
            }
        }
        .frame(width: 10, height: 10)
    }
}

/// Logo có vệt sáng quét chéo qua
struct LogoSweep: View {
    let t: Double, at: Double, size: CGFloat
    var body: some View {
        let sweep = easeInOut(prog(t, at + 0.45, 0.6))
        let logo = Image(nsImage: NSApp.applicationIconImage).resizable()
        ZStack {
            logo
            LinearGradient(colors: [.clear, .white.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: size * 0.4, height: size * 1.6)
                .rotationEffect(.degrees(20))
                .offset(x: CGFloat(-1.2 + 2.4 * sweep) * size)
        }
        .frame(width: size, height: size)
        .mask(logo.frame(width: size, height: size))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
    }
}

// MARK: - Khung cảnh

struct SceneView: View {
    @ObservedObject var clock: Clock

    var body: some View {
        let t = clock.t
        let tr = cutFX(t)
        let bgd: Double = 1 + (tr.scale - 1) * 0.15 + 0.012 * beatPulse(t)
        let bg = CGFloat(bgd)
        let cs = CGFloat(tr.scale)
        let ca: Double = tr.alpha
        let dropFlash: Double = t >= DROP ? 0.75 * exp(-(t - DROP) * 5) : 0
        let fl: Double = min(1, tr.flash + dropFlash)
        let sh = screenShake(t)
        ZStack(alignment: .topLeading) {
            Backdrop(t: t).scaleEffect(bg)
            ZStack(alignment: .topLeading) {
                stage(t)
                headlines(t)
                hook(t); reveal(t); outro(t)
            }
            .frame(width: LW, height: LH, alignment: .topLeading)
            .scaleEffect(cs)
            .opacity(ca)
            .offset(sh)
            Color.white.opacity(fl)
        }
        .frame(width: LW, height: LH)
        .clipped()
    }

    /// Các cảnh demo của bản dọc, có camera riêng, thu nhỏ và đặt vào nửa phải
    @ViewBuilder func stage(_ t: Double) -> some View {
        let (zoom, focus) = camera(t)
        let z = CGFloat(zoom)
        let anchor = UnitPoint(x: focus.x / W, y: focus.y / H)
        let dx: CGFloat = (W / 2 - focus.x) * (z - 1) * 0.8
        let dy: CGFloat = (H / 2 - focus.y) * (z - 1) * 0.5
        ZStack(alignment: .topLeading) {
            oldWay(t); convert(t); shrink(t); merge(t); shelfScene(t); formats(t)
            menuLayer(t)
            cursorLayer(t)
        }
        .frame(width: W, height: H, alignment: .topLeading)
        .scaleEffect(z, anchor: anchor)
        .offset(x: dx, y: dy)
        .frame(width: W, height: H, alignment: .topLeading)
        .scaleEffect(AS, anchor: .topLeading)
        .offset(x: AX - M.x * AS, y: AY - M.y * AS)
    }

    @ViewBuilder func headlines(_ t: Double) -> some View {
        SideHeadline(t: t, a: H0, b: S1, chip: "The old way", lines: ["Converting", "one file…"])
        SideHeadline(t: t, a: S2, b: S2 + 2.25, chip: "Step 1", lines: ["Drag any file,", "give it a", "little shake"])
        SideHeadline(t: t, a: S2 + 2.25, b: S2 + 4.75, chip: "Step 2", lines: ["Drop it on the", "format you", "need"])
        SideHeadline(t: t, a: S2 + 4.75, b: S3, chip: "PNG → JPG", lines: ["Done. It lands", "right next to", "the original ✓"])
        SideHeadline(t: t, a: S3, b: S4, chip: "Edit images", lines: ["Photo too big?", "Under 1 MB", "in one drop"])
        SideHeadline(t: t, a: S4, b: S5, chip: "Merge files", lines: ["Many images", "→ one PDF"])
        SideHeadline(t: t, a: S5, b: S5 + 2.3, chip: "Shelf", lines: ["Not now?", "Park it on", "the Shelf"])
        SideHeadline(t: t, a: S5 + 2.3, b: S6, chip: "Shelf", lines: ["Collect files,", "⌘A, drag them", "all at once"])
        SideHeadline(t: t, a: S6, b: S7, chip: "And more", lines: ["Images, PDF,", "Word, video,", "audio, ZIP…"])
    }

    // 0–3: câu mở đầu, từng chữ đập xuống
    @ViewBuilder func hook(_ t: Double) -> some View {
        let hl = easeOut(prog(t, slowAt + 0.05, 0.3))
        Group {
            HStack(spacing: 18) {
                ForEach(Array(hookWords.enumerated()), id: \.offset) { i, w in
                    Text(w).slam(t, hookTimes[i])
                }
            }
            .font(.system(size: 64, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.3), radius: 12, y: 5)
            .fixedSize()
            .at(LW / 2, 205)
            Text("the slow way?")
                .font(.system(size: 84, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.45, green: 0.08, blue: 0.2))
                .padding(.horizontal, 28).padding(.vertical, 6)
                .background(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(red: 1, green: 0.86, blue: 0.35))
                        .scaleEffect(x: CGFloat(hl), y: 1, anchor: .leading)
                }
                .fixedSize()
                .rotationEffect(.degrees(-2))
                .slam(t, slowAt)
                .at(LW / 2, 320)
        }
        .scaleEffect(CGFloat(1 + 0.04 * prog(t, 0, H0)))
        .scene(t, 0, H0)
    }

    // S1–S2: "There's a faster way." rồi drop: vòng sóng, pháo giấy, logo
    @ViewBuilder func reveal(_ t: Double) -> some View {
        let away = easeInOut(prog(t, DROP - 0.15, 0.15))
        Group {
            HStack(spacing: 14) {
                ForEach(Array(fasterWords.enumerated()), id: \.offset) { i, w in
                    Text(w).foregroundStyle(i == 2 ? Color(red: 1, green: 0.86, blue: 0.35) : .white)
                        .pop(t, S1 + 0.05 + Double(i) * 0.12, dy: 24)
                }
            }
            .font(.system(size: 62, weight: .black, design: .rounded))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 5)
            .fixedSize()
            .scaleEffect(CGFloat(1 + 1.5 * away))
            .opacity(1 - away)
            .at(LW / 2, LH / 2)
            .scene(t, S1, DROP)

            Group {
                ShockRings(t: t, at: DROP).at(LW / 2, 200)
                Confetti(t: t, at: DROP).at(LW / 2, 200)
                LogoSweep(t: t, at: DROP, size: 170)
                    .rotationEffect(.degrees((1 - spring(prog(t, DROP, 0.7))) * -40))
                    .pop(t, DROP, dy: 50)
                    .at(LW / 2, 200)
                HStack(spacing: 2) {
                    ForEach(Array("SATF".enumerated()), id: \.offset) { i, ch in
                        Text(String(ch)).pop(t, DROP + 0.15 + Double(i) * 0.07, dy: 40)
                    }
                }
                .font(.system(size: 92, weight: .black, design: .rounded)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 5)
                .fixedSize()
                .at(LW / 2, 350)
                HStack(spacing: 12) {
                    ForEach(Array(["Drag.", "Shake.", "Done."].enumerated()), id: \.offset) { i, w in
                        Text(w).foregroundStyle(i == 2 ? Color(red: 1, green: 0.86, blue: 0.35) : .white)
                            .pop(t, DROP + 0.55 + Double(i) * 0.18)
                    }
                }
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .fixedSize()
                .at(LW / 2, 432)
            }
            .scene(t, DROP, S2)
        }
    }

    // 0–3: cách cũ, 4 cửa sổ bật liên tiếp
    @ViewBuilder func oldWay(_ tg: Double) -> some View {
        let t = tg - H0
        Group {
            WindowCard(title: "Preview", content: HStack(spacing: 12) {
                PhotoThumb(size: 54)
                VStack(alignment: .leading, spacing: 4) { Text("Vacation photo.png").font(.system(size: 14, weight: .semibold)); Text("2048 × 1536 · 4.8 MB").font(.system(size: 11)).foregroundStyle(.secondary) }
            }).rotationEffect(.degrees(-3)).pop(t, 0.38).at(oldCardCenter(0))
            WindowCard(title: "File", content: VStack(alignment: .leading, spacing: 6) {
                Text("Open…").font(.system(size: 13)).foregroundStyle(.secondary)
                Text("Export…").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 5)).padding(.horizontal, -8)
                Text("Print…").font(.system(size: 13)).foregroundStyle(.secondary)
            }).rotationEffect(.degrees(2)).pop(t, 0.83).at(oldCardCenter(1))
            WindowCard(title: "Export", content: VStack(alignment: .leading, spacing: 10) {
                HStack { Text("Format").foregroundStyle(.secondary); Spacer(); Text("JPEG  ▾").padding(.horizontal, 8).padding(.vertical, 2).background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 5)) }
                HStack { Text("Quality").foregroundStyle(.secondary); Spacer(); Capsule().fill(.white.opacity(0.25)).frame(width: 120, height: 4).overlay(Circle().fill(.white).frame(width: 12).offset(x: 20)) }
            }.font(.system(size: 13))).rotationEffect(.degrees(-2)).pop(t, 1.28).at(oldCardCenter(2))
            WindowCard(title: "Save As", content: HStack {
                Text("Where: Desktop ▾").font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                Text("Save").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 4).background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6))
            }).rotationEffect(.degrees(3)).pop(t, 1.73).at(oldCardCenter(3))
        }
        .scaleEffect(CGFloat(1 - 0.06 * easeOut(prog(t, 2.05, 0.3))))
        .opacity(1 - 0.25 * prog(t, 2.05, 0.2))
        .scene(t, 0, S1 - H0)
        // Con dấu đỏ đóng mạnh xuống
        Text("4 windows. 8 clicks. 😩").font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(.white)
            .padding(.horizontal, 22).padding(.vertical, 14)
            .background(Color(red: 0.9, green: 0.16, blue: 0.2), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.8), lineWidth: 3))
            .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
            .rotationEffect(.degrees(-7))
            .scaleEffect(CGFloat(stampScale(t)))
            .opacity(clamp(prog(t, 2.05, 0.06)))
            .at(W / 2, 470)
            .scene(t, 0, S1 - H0)
    }

    @ViewBuilder func convert(_ t: Double) -> some View {
        Group {
            FileTile(icon: PhotoThumb(), name: "Vacation photo.png").pop(t, S2 + 0.1, S2 + 1.85).at(W / 2, 640)
            FileTile(icon: PhotoThumb(), name: "Vacation photo.png").pop(t, S2 + 4.85).at(150, 480)
            FileTile(icon: PhotoThumb(), name: "Vacation photo.jpg", badge: "NEW").pop(t, S2 + 5.1).at(390, 480)
        }.scene(t, S2, S3)
    }

    @ViewBuilder func shrink(_ t: Double) -> some View {
        let x = easeOut(prog(t, S3 + 3.05, 0.6))
        let mb = 4.8 - (4.8 - 0.862) * x
        Group {
            FileTile(icon: PhotoThumb(hue: 0.5), name: "Beach day.jpg", badge: "4.8 MB", badgeColor: .black.opacity(0.55))
                .pop(t, S3 + 0.05, S3 + 1.1).at(W / 2, 620)
            VStack(spacing: 14) {
                PhotoThumb(size: 170, hue: 0.5)
                Text(mb < 1 ? "\(Int(mb * 1000)) KB" : String(format: "%.1f MB", mb))
                    .font(.system(size: 54, weight: .black, design: .rounded)).foregroundStyle(.white).monospacedDigit()
                HStack(spacing: 10) {
                    Text("4.8 MB").strikethrough().foregroundStyle(.white.opacity(0.7))
                    Text("−82%").foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Theme.edit, in: Capsule())
                        .scaleEffect(CGFloat(spring(prog(t, S3 + 3.65, 0.5)))).opacity(clamp(prog(t, S3 + 3.65, 0.08)))
                }
                .font(.system(size: 20, weight: .bold, design: .rounded))
            }
            .pop(t, S3 + 2.95).at(W / 2, 520)
        }.scene(t, S3, S4)
    }

    @ViewBuilder func merge(_ t: Double) -> some View {
        let fly = easeInOut(prog(t, S4 + 0.5, 0.42))
        Group {
            ForEach(0..<3, id: \.self) { i in
                let start = [CGPoint(x: 130, y: 560), CGPoint(x: 270, y: 660), CGPoint(x: 410, y: 570)][i]
                PhotoThumb(size: 100, hue: [0.0, 0.5, 0.25][i])
                    .rotationEffect(.degrees([-8, 4, 10][i] * (1 - fly)))
                    .scaleEffect(CGFloat(1 - 0.65 * fly))
                    .opacity(1 - prog(t, S4 + 0.8, 0.12))
                    .pop(t, S4 + Double(i) * 0.125)
                    .at(lerp(start, M, fly))
            }
            FileTile(icon: DocIcon(), name: "Beach day.pdf", badge: "3 pages").pop(t, S4 + 3.25).at(W / 2, 500)
        }.scene(t, S4, S5)
    }

    @ViewBuilder func shelfScene(_ t: Double) -> some View {
        let dropped = t >= mailDrop
        Group {
            FileTile(icon: DocIcon(label: "DOCX", color: Theme.clipboard, size: 120), name: "Report Q3.docx").pop(t, S5 + 0.05, S5 + 1.35).at(W / 2, 640)
            ShelfView(model: shelf, onClose: {}).fixedSize()
                .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
                .pop(t, S5 + 2.3, dy: 30).at(shelfAt)
            ForEach(Array(shelfArrivals.dropFirst().enumerated()), id: \.offset) { i, a in
                let x = easeInOut(prog(t, a.at - 0.35, 0.35))
                Group {
                    if i == 0 { PhotoThumb(size: 70) } else { DocIcon(label: i == 1 ? "XLSX" : "PPTX", color: i == 1 ? Theme.edit : Theme.convert, size: 80) }
                }
                .scaleEffect(CGFloat(1 - 0.5 * x))
                .opacity(t >= a.at - 0.35 && t < a.at ? 1 : 0)
                .at(lerp(a.from, shelfAt, x))
            }
            HStack(spacing: 10) {
                Keycap(label: "⌘", down: t >= shelfSelectAll - 0.05 && t < shelfSelectAll + 0.2)
                Keycap(label: "A", down: t >= shelfSelectAll - 0.05 && t < shelfSelectAll + 0.2)
            }
            .pop(t, S5 + 3.35, S5 + 4.2).at(W / 2, 640)
            // Đích thả: một email mới
            HStack(spacing: 14) {
                Image(systemName: dropped ? "checkmark" : "envelope.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 48, height: 48).background((dropped ? Theme.edit : Theme.clipboard).gradient, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("New email").font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(dropped ? "4 attachments ✓" : "Drop files to attach").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(14).frame(width: 300)
            .background(Color(white: 0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(dropped ? Theme.edit : .white.opacity(0.15), lineWidth: dropped ? 2 : 1))
            .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
            .scaleEffect(CGFloat(dropped ? 1 + 0.08 * exp(-(t - mailDrop) * 6) * cos((t - mailDrop) * 18) : 1))
            .pop(t, S5 + 3.85).at(W / 2, 745)
        }.scene(t, S5, S6)
    }

    @ViewBuilder func formats(_ t: Double) -> some View {
        Group {
            ForEach(formatChips.indices, id: \.self) { i in
                let (name, color) = formatChips[i]
                Text(name).font(.system(size: 19, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    .frame(width: 104, height: 50)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.45)))
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                    .pop(t, chipStart + Double(i) * chipStep, dy: 30)
                    .at(CGFloat(87 + (i % 4) * 122), CGFloat(370 + (i / 4) * 66))
            }
            Text("No uploads · No accounts · No ads").font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92)).pop(t, S6 + 1.6).at(W / 2, 670)
        }.scene(t, S6, S7)
    }

    @ViewBuilder func outro(_ t: Double) -> some View {
        let cta = S7 + 2.75
        let gold = Color(red: 1, green: 0.85, blue: 0.3)
        Group {
            ShockRings(t: t, at: S7).at(LW / 2, 135)
            LogoSweep(t: t, at: S7, size: 130)
                .rotationEffect(.degrees((1 - spring(prog(t, S7, 0.6))) * 25))
                .scaleEffect(CGFloat(1 + 0.04 * sin(max(0, t - S7 - 0.7) * 4)))
                .pop(t, S7, dy: 40).at(LW / 2, 135)
            Text("SATF").font(.system(size: 72, weight: .black, design: .rounded)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 5)
                .pop(t, S7 + 0.25).at(LW / 2, 252)
            Text("Drag. Shake. Done.").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.92))
                .pop(t, S7 + 0.5).at(LW / 2, 310)
            HStack(spacing: 10) {
                ForEach(Array(["Free", "Open source", "macOS & Windows"].enumerated()), id: \.offset) { i, s in
                    Text(s).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7).background(.white.opacity(0.2), in: Capsule())
                        .pop(t, S7 + 1.0 + Double(i) * 0.25)
                }
            }
            .fixedSize()
            .at(LW / 2, 362)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text("github.com/tran-minh-khoi/SATF")
            }
            .font(.system(size: 21, weight: .heavy, design: .rounded))
            .foregroundStyle(Color(red: 0.55, green: 0.12, blue: 0.30))
            .padding(.horizontal, 22).padding(.vertical, 12)
            .background(.white, in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
            .fixedSize()
            .pop(t, S7 + 2.0).at(LW / 2, 425)
            // Kêu gọi tặng sao, sao bắn tung toé
            ZStack {
                ForEach(0..<16, id: \.self) { i in
                    let a = Double(i) / 16 * 2 * .pi + 0.3
                    let x = easeOut(prog(t, cta + 0.05, 1.1))
                    Image(systemName: "star.fill").font(.system(size: CGFloat(10 + (i % 3) * 5)))
                        .foregroundStyle(gold)
                        .rotationEffect(.degrees(x * 180))
                        .offset(x: CGFloat(cos(a) * (60 + 220 * x)), y: CGFloat(sin(a) * (20 + 70 * x)))
                        .opacity(t > cta ? 1 - prog(t, cta + 0.6, 0.6) : 0)
                }
                HStack(spacing: 10) {
                    Image(systemName: "star.fill").foregroundStyle(gold)
                        .rotationEffect(.degrees((1 - spring(prog(t, cta, 0.7))) * -120))
                    Text("Like it? Drop a star on GitHub!")
                }
                .font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(.black.opacity(0.25), in: Capsule())
                .overlay(Capsule().strokeBorder(gold.opacity(0.8), lineWidth: 1.5))
                .fixedSize()
                .scaleEffect(CGFloat(1 + 0.03 * sin(max(0, t - cta - 0.6) * 5)))
                .pop(t, cta)
            }
            .at(LW / 2, 492)
        }.scene(t, S7, 999)
    }

    @ViewBuilder func menuLayer(_ t: Double) -> some View {
        let s = menu(t)
        let open: Double = spring(prog(t, s.pop, 0.5))
        let close: Double = easeInOut(prog(t, s.close, 0.25))
        let kd: Double = (0.55 + 0.45 * open) * (1 - 0.25 * close)
        let alpha: Double = clamp(prog(t, s.pop, 0.1)) * (1 - close)
        let y: CGFloat = M.y + RadialGeo.size.height / 2 - RadialGeo.center.y
        RadialMenuView(model: s.model)
            .frame(width: RadialGeo.size.width, height: RadialGeo.size.height)
            .scaleEffect(CGFloat(kd), anchor: RadialGeo.anchor)
            .opacity(alpha)
            .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
            .position(x: M.x, y: y)
    }

    @ViewBuilder func ghost(_ g: Ghost) -> some View {
        switch g {
        case .none: EmptyView()
        case .photo(let hue): PhotoThumb(size: 46, hue: hue)
        case .doc(let label, let color): DocIcon(label: label, color: color, size: 52)
        case .stack(let n):
            ZStack(alignment: .topTrailing) {
                PhotoThumb(size: 44, hue: 0.25).rotationEffect(.degrees(10)).offset(x: 6)
                DocIcon(label: "DOC", color: Theme.clipboard, size: 50).rotationEffect(.degrees(-6))
                Text("\(n)").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.red)).offset(x: 14, y: -8)
            }
        }
    }

    @ViewBuilder func cursorLayer(_ t: Double) -> some View {
        if let tr = track(t) {
            let p = tr.pos(t), pressed = tr.isPressed(t)
            let alpha = min(prog(t, tr.visible.0, 0.15), 1 - prog(t, tr.visible.1 - 0.15, 0.15))
            let overMenu = t >= menu(t).pop && t < menu(t).drop
            ZStack(alignment: .topLeading) {
                if pressed {   // file đang cầm theo con trỏ
                    ghost(tr.ghost)
                        .scaleEffect(overMenu ? 0.75 : 1, anchor: .topLeading)
                        .opacity(overMenu ? 0.5 : 0.88).offset(x: 16, y: 24)
                }
                CursorShape().fill(.black).overlay(CursorShape().stroke(.white, lineWidth: 1.6))
                    .frame(width: 22, height: 34, alignment: .topLeading)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                    .scaleEffect(pressed ? 0.88 : 1, anchor: .topLeading)
            }
            .frame(width: 90, height: 90, alignment: .topLeading)
            .opacity(alpha)
            .position(x: p.x + 45, y: p.y + 45)
        }
    }
}

// MARK: - Cập nhật trạng thái app theo thời gian (và ghi lại tiếng "tách")

func update(_ t: Double) {
    // Khay
    let files = shelfArrivals.filter { t >= $0.at }.map { sample($0.file) }
    if shelf.files != files { shelf.files = files }
    let sel: Set<URL> = t >= shelfSelectAll ? Set(files) : []
    if shelf.selection != sel { shelf.selection = sel }

    let s = menu(t)
    let m = s.model
    if t >= s.drop + 0.4 && t < s.done { if m.status != .working { m.status = .working } }   // hiện vòng xoay một nhịp ngắn
    else if t >= s.done { if m.status == .idle || m.status == .working { m.status = .done(s.msg) } }
    guard t >= s.pop, t < s.drop, let tr = track(t) else { return }
    let before = (m.hoveredSide, m.hoveredItem, m.expanded)
    let p = tr.pos(t)
    m.updateHover(CGPoint(x: p.x - M.x + RadialGeo.center.x, y: p.y - M.y + RadialGeo.center.y))
    if m.hoveredItem != before.1 && m.hoveredItem != nil { events.append((t, .tick(1 + Double(m.hoveredItem!) * 0.06))) }
    else if m.hoveredSide != before.0 && m.hoveredSide != nil { events.append((t, .tick(0.8))) }
    if m.expanded != before.2 && m.expanded != nil { events.append((t, .whoosh(0.18))) }
}

// MARK: - Tổng hợp âm thanh

let SR = 44100.0
let N = Int((DUR + 0.5) * SR)
var L = [Float](repeating: 0, count: N), R = [Float](repeating: 0, count: N)
var rng = SystemRandomNumberGenerator()
func noise() -> Double { Double.random(in: -1...1, using: &rng) }

func render(_ start: Double, _ dur: Double, gain: Double, pan: Double = 0, _ f: (Double, Int) -> Double) {
    let s0 = Int(start * SR)
    let gl = Float(gain * (1 - max(0, pan))), gr = Float(gain * (1 + min(0, pan)))
    for i in 0..<Int(dur * SR) where s0 + i < N && s0 + i >= 0 {
        let v = Float(f(Double(i) / SR, i))
        L[s0 + i] += v * gl; R[s0 + i] += v * gr
    }
}
func midi(_ n: Int) -> Double { 440 * pow(2, Double(n - 69) / 12) }

// Một-cực lọc thấp/cao, đủ cho trống và tiếng gió
struct OnePole { var y = 0.0; mutating func low(_ x: Double, _ fc: Double) -> Double { y += (1 - exp(-2 * .pi * fc / SR)) * (x - y); return y } }

func kick(_ at: Double, _ g: Double = 0.9) {
    var ph = 0.0
    render(at, 0.4, gain: g) { t, _ in ph += 2 * .pi * (48 + 130 * exp(-t * 32)) / SR; return sin(ph) * exp(-t * 8) }
}
func clap(_ at: Double) {
    var hp = OnePole()
    render(at, 0.22, gain: 0.28) { t, _ in let n = noise(); let h = n - hp.low(n, 1200); return h * exp(-t * 22) * (t < 0.01 ? 0.6 : 1) }
}
func hat(_ at: Double, _ g: Double = 0.09) {
    var hp = OnePole()
    render(at, 0.06, gain: g, pan: 0.2) { t, _ in let n = noise(); return (n - hp.low(n, 7000)) * exp(-t * 70) }
}
func tone(_ at: Double, _ dur: Double, _ freq: Double, gain: Double, decay: Double, pan: Double = 0, harm: Double = 0.25) {
    render(at, dur, gain: gain, pan: pan) { t, _ in
        let env = min(1, t / 0.004) * exp(-t * decay) * min(1, (dur - t) / 0.02)
        return (sin(2 * .pi * freq * t) + harm * sin(4 * .pi * freq * t)) * env
    }
}
func bass(_ at: Double, _ dur: Double, _ freq: Double) {
    var lp = OnePole()
    render(at, dur, gain: 0.32) { t, _ in
        let raw = sin(2 * .pi * freq * t) + sin(6 * .pi * freq * t) / 3 + sin(10 * .pi * freq * t) / 5
        return lp.low(raw, 500) * min(1, t / 0.006) * min(1, (dur - t) / 0.02) * (0.7 + 0.3 * exp(-t * 10))
    }
}

func sfx(_ at: Double, _ e: Sfx) {
    switch e {
    case .pop(let k):
        var ph = 0.0
        render(at, 0.12, gain: 0.42) { t, _ in ph += 2 * .pi * (380 + 900 * min(1, t / 0.05)) * k / SR; return sin(ph) * exp(-t * 38) }
    case .textPop:
        var ph = 0.0
        render(at, 0.1, gain: 0.26) { t, _ in ph += 2 * .pi * (260 + 520 * min(1, t / 0.05)) / SR; return sin(ph) * exp(-t * 40) }
    case .tick(let k):
        render(at, 0.04, gain: 0.2) { t, _ in (sin(2 * .pi * 2100 * k * t) + 0.3 * noise()) * exp(-t * 140) }
    case .whoosh(let d):
        var lp = OnePole(), lp2 = OnePole()
        render(at - d * 0.4, d, gain: 0.5 * min(1, d / 0.25 + 0.4)) { t, _ in
            let x = t / d
            let fc = 300 + 3200 * sin(.pi * x)
            return lp2.low(lp.low(noise(), fc), fc) * sin(.pi * x)
        }
    case .click:
        render(at, 0.03, gain: 0.35) { t, _ in (noise() * 0.6 + sin(2 * .pi * 3200 * t)) * exp(-t * 260) }
        render(at + 0.06, 0.03, gain: 0.2) { t, _ in (noise() * 0.6 + sin(2 * .pi * 2600 * t)) * exp(-t * 260) }
    case .chime(let k):
        tone(at, 0.9, 1318.5 * k, gain: 0.2, decay: 6, pan: -0.15)
        tone(at + 0.08, 1.0, 1975.5 * k, gain: 0.18, decay: 5, pan: 0.15)
    case .thump:
        var ph = 0.0
        render(at, 0.3, gain: 0.55) { t, _ in ph += 2 * .pi * (55 + 90 * exp(-t * 25)) / SR; return sin(ph) * exp(-t * 11) }
    case .sweep:   // số giảm dần: tiếng tách dày, cao -> thấp
        for i in 0..<14 { sfx(at + Double(i) * 0.042, .tick(1.4 - Double(i) * 0.06)) }
    case .crash:
        var hp = OnePole()
        render(at, 2.2, gain: 0.2) { t, _ in let n = noise(); return (n - hp.low(n, 5000)) * exp(-t * 2.4) }
    case .riser:
        var lp = OnePole()
        render(at, 1.0, gain: 0.3) { t, _ in lp.low(noise(), 400 + 6000 * t * t) * t * t }
    case .sparkle:   // chuỗi nốt cao lấp lánh đi lên
        for (i, n) in [84, 88, 91, 96, 100, 103].enumerated() { tone(at + Double(i) * 0.06, 0.6, midi(n), gain: 0.09, decay: 7, pan: i % 2 == 0 ? -0.4 : 0.4) }
    }
}

// Nhạc cụ thêm cho bản YouTube
func saw(_ cycles: Double) -> Double { 2 * (cycles - floor(cycles)) - 1 }

func snare(_ at: Double, _ g: Double = 0.3) {
    var hp = OnePole()
    render(at, 0.25, gain: g) { t, _ in
        let n = noise()
        let h = n - hp.low(n, 1500)
        return (h * 0.8 + sin(2 * .pi * 190 * t) * 0.5 * exp(-t * 30)) * exp(-t * 16)
    }
}
func openHat(_ at: Double, _ g: Double = 0.08) {
    var hp = OnePole()
    render(at, 0.25, gain: g, pan: -0.2) { t, _ in let n = noise(); return (n - hp.low(n, 6500)) * exp(-t * 14) }
}
func boom(_ at: Double, _ g: Double = 0.75) {   // tiếng trầm rền khi đập chữ / drop
    var ph = 0.0
    render(at, 1.4, gain: g) { t, _ in ph += 2 * .pi * (38 + 60 * exp(-t * 18)) / SR; return sin(ph) * exp(-t * 3) * min(1, t / 0.003) }
}
func sawBass(_ at: Double, _ dur: Double, _ freq: Double, gain: Double = 0.36) {
    var lp = OnePole(), lp2 = OnePole()
    render(at, dur, gain: gain) { t, _ in
        let fc = 160 + 1500 * exp(-t * 14)
        let x = saw(freq * t) * 0.7 + sin(2 * .pi * freq * t) * 0.7
        return lp2.low(lp.low(x, fc), fc) * min(1, t / 0.004) * min(1, (dur - t) / 0.015)
    }
}
/// Hợp âm "supersaw": mỗi nốt 3 giọng lệch nhẹ, tách trái phải
func supersaw(_ at: Double, _ dur: Double, _ notes: [Int], gain: Double, cutoff: Double, decay: Double, duck: Bool = false) {
    for n in notes {
        for (d, pan) in [(-0.12, -0.6), (0.0, 0.0), (0.12, 0.6)] {
            let f = midi(n) * pow(2, d / 12)
            let offset = Double(n) * 0.137 + d
            var lp = OnePole(), lp2 = OnePole()
            render(at, dur, gain: gain, pan: pan) { t, _ in
                var env = min(1, t / 0.01) * min(1, (dur - t) / 0.05) * exp(-t * decay)
                if duck { env *= 1 - 0.8 * exp(-(at + t - DROP).truncatingRemainder(dividingBy: 0.5) * 9) }
                return lp2.low(lp.low(saw(f * t + offset), cutoff), cutoff) * env
            }
        }
    }
}

func synthesize() {
    // 120 BPM, vòng Am – F – C – G, mỗi hợp âm một ô nhịp (2 s) tính từ lúc drop
    let chords: [[Int]] = [[57, 60, 64], [57, 60, 65], [55, 60, 64], [55, 59, 62]]
    let roots = [33, 29, 36, 31]
    func bar(_ t: Double) -> Int { ((Int(floor((t - DROP) / 2)) % 4) + 4) % 4 }
    let grooveTo = S7 + 2.5

    // 1. Câu mở đầu: nền trầm Am, mỗi chữ một tiếng rền, gió cuộn lên
    render(0, H0, gain: 0.05) { t, _ in [45, 57, 64].reduce(0.0) { $0 + sin(2 * .pi * midi($1) * t) } * min(1, t / 0.3) }
    for at in hookTimes + [slowAt] { boom(at, at == slowAt ? 0.9 : 0.6); kick(at, 0.7) }

    // 2. Cách cũ: trống nhẹ, bass tối, như đang chờ đợi
    var b = 0
    while H0 + Double(b) * 0.5 < S1 {
        let t = H0 + Double(b) * 0.5
        kick(t, 0.45)
        if b % 2 == 1 { hat(t + 0.25, 0.05) }
        bass(t, 0.4, midi(33))
        b += 1
    }
    render(H0, S1 - H0, gain: 0.045) { t, _ in [45, 57, 60, 64].reduce(0.0) { $0 + sin(2 * .pi * midi($1) * t) } }

    // 3. "There's a faster way": trống dồn + gió cuộn, ngắt một nhịp rồi drop
    var roll = S1, step = 0.25
    while roll < DROP - 0.05 {
        snare(roll, 0.12 + 0.2 * (roll - S1) / (DROP - S1))
        roll += step
        if roll > S1 + 0.5 { step = 0.125 }
        if roll > S1 + 0.75 { step = 0.0625 }
    }
    render(S1 - 0.5, DROP - S1 + 0.5, gain: 0.3) { t, _ in
        let x = t / (DROP - S1 + 0.5)
        return noise() * x * x * (1 - prog(t, DROP - S1 + 0.4, 0.1))
    }
    supersaw(S1, DROP - S1, [57, 60, 64], gain: 0.02, cutoff: 800, decay: 0)

    // 4. Drop -> hết phần demo: trống đầy đủ, bass, hợp âm, giai điệu rải
    boom(DROP, 1)
    b = 0
    while DROP + Double(b) * 0.5 < grooveTo {
        let t = DROP + Double(b) * 0.5
        let k = bar(t)
        let chord = chords[k]
        kick(t, 0.95)
        if b % 2 == 1 { clap(t); snare(t, 0.18) }
        hat(t + 0.125, 0.06); hat(t + 0.375, 0.06); openHat(t + 0.25)
        sawBass(t, 0.22, midi(roots[k])); sawBass(t + 0.25, 0.22, midi(roots[k] + 12), gain: 0.3)
        supersaw(t + 0.25, 0.2, chord.map { $0 + 12 }, gain: 0.03, cutoff: 3200, decay: 6)
        for q in 0..<4 {   // giai điệu rải nốt móc kép
            let n = chord[(b * 4 + q) % 3] + (q == 3 ? 36 : 24)
            tone(t + Double(q) * 0.125, 0.2, midi(n), gain: 0.05, decay: 16, pan: q % 2 == 0 ? -0.35 : 0.35, harm: 0.45)
        }
        // Trống dồn ngay trước mỗi lần chuyển cảnh
        if cuts.contains(where: { $0 > t && $0 - t <= 0.5 }) {
            for r in 0..<4 { snare(t + Double(r) * 0.125, 0.1 + Double(r) * 0.04) }
        }
        b += 1
    }
    // Pad nền mỗi ô nhịp, nhún theo trống
    var barStart = DROP
    while barStart < grooveTo {
        supersaw(barStart, min(2, grooveTo - barStart), chords[bar(barStart)], gain: 0.018, cutoff: 1800, decay: 0, duck: true)
        barStart += 2
    }

    // 5. Kết: đập mạnh lúc logo hiện, hợp âm ngân dài tới hết
    boom(S7, 0.9)
    kick(grooveTo, 1); boom(grooveTo, 0.8)
    supersaw(grooveTo, DUR - grooveTo + 0.4, [45, 57, 60, 64, 69], gain: 0.03, cutoff: 2400, decay: 0.6)

    for (t, e) in events { sfx(t, e) }

    // Nén + chuẩn hoá về -1 dBFS
    for i in 0..<N { L[i] = tanhf(L[i] * 1.5); R[i] = tanhf(R[i] * 1.5) }
    let peak = max(L.map(abs).max()!, R.map(abs).max()!)
    let k = 0.89 / peak
    for i in 0..<N { L[i] *= k; R[i] *= k }
    // Tắt dần 0,6 s cuối
    for i in 0..<Int(0.6 * SR) { let g = Float(i) / Float(0.6 * SR); L[N - 1 - i] *= g; R[N - 1 - i] *= g }
}

func writeWav(_ url: URL) throws {
    var d = Data()
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    let n = Int(DUR * SR)
    d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + n * 4)); d.append("WAVEfmt ".data(using: .ascii)!)
    u32(16); u16(1); u16(2); u32(UInt32(SR)); u32(UInt32(SR) * 4); u16(4); u16(16)
    d.append("data".data(using: .ascii)!); u32(UInt32(n * 4))
    for i in 0..<n { u16(UInt16(bitPattern: Int16(L[i] * 32767))); u16(UInt16(bitPattern: Int16(R[i] * 32767))) }
    try d.write(to: url)
}

// MARK: - Ghi video

let OUTW = 1920, OUTH = 1080
let scale = NSScreen.main?.backingScaleFactor ?? 2
let f = 2 / scale
let host = NSHostingView(rootView: SceneView(clock: clock).scaleEffect(f, anchor: .topLeading).frame(width: LW * f, height: LH * f, alignment: .topLeading))
host.frame = NSRect(x: 0, y: 0, width: LW * f, height: LH * f)
let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
win.contentView = host
win.setFrameOrigin(NSPoint(x: -4000, y: -4000))
win.orderFrontRegardless()

try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let silentURL = outDir.appendingPathComponent("video-only.mp4")
let wavURL = outDir.appendingPathComponent("SATF-youtube-audio.wav")
let finalURL = outDir.appendingPathComponent("SATF-youtube.mp4")
for u in [silentURL, finalURL] { try? FileManager.default.removeItem(at: u) }

let writer = try! AVAssetWriter(outputURL: silentURL, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: OUTW, AVVideoHeightKey: OUTH,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 20_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: OUTW, kCVPixelBufferHeightKey as String: OUTH,
])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let total = Int(DUR * FPS)
let stills = CommandLine.arguments.count > 3 ? CommandLine.arguments[3].split(separator: ",").compactMap { Double($0) } : []
var frame = 0

func capture() -> CGImage {
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    return rep.cgImage!
}

func append(_ img: CGImage, _ i: Int) {
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
    CVPixelBufferLockBaseAddress(pb!, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb!), width: OUTW, height: OUTH, bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(pb!), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: OUTW, height: OUTH))
    CVPixelBufferUnlockBaseAddress(pb!, [])
    adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(FPS)))
}

func setTime(_ t: Double) {
    var tx = Transaction()
    tx.disablesAnimations = true
    withTransaction(tx) { update(t); clock.t = t }
}

func step() {
    guard frame < total else { return finish() }
    guard input.isReadyForMoreMediaData else { return DispatchQueue.main.asyncAfter(deadline: .now() + 0.005, execute: step) }
    let t = Double(frame) / FPS
    setTime(t)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) {   // để SwiftUI vẽ xong trạng thái mới
        let img = capture()
        if frame == 0 { print("frame px:", img.width, "x", img.height) }
        append(img, frame)
        if let s = stills.first(where: { abs($0 - t) < 0.5 / FPS }) {
            try? NSBitmapImageRep(cgImage: img).representation(using: .jpeg, properties: [.compressionFactor: 0.8])!
                .write(to: outDir.appendingPathComponent(String(format: "still-%05.2f.jpg", s)))
        }
        if frame % 75 == 0 { print("frame \(frame)/\(total)") }
        frame += 1
        step()
    }
}

func finish() {
    input.markAsFinished()
    writer.finishWriting {
        DispatchQueue.main.async {
            synthesize()
            try! writeWav(wavURL)
            // Ghép tiếng lỗi thì thoát mã khác 0 để promo.sh báo lỗi, không báo xong giả
            Task {
                let ok = await mux()
                exit(ok ? 0 : 1)
            }
        }
    }
}

func mux() async -> Bool {
    do {
        let comp = AVMutableComposition()
        let v = AVURLAsset(url: silentURL), a = AVURLAsset(url: wavURL)
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: DUR, preferredTimescale: 600))
        let vt = try await v.loadTracks(withMediaType: .video)[0]
        let at = try await a.loadTracks(withMediaType: .audio)[0]
        try comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(range, of: vt, at: .zero)
        try comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(range, of: at, at: .zero)
        let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality)!
        try await ex.export(to: finalURL, as: .mp4)
        try? FileManager.default.removeItem(at: silentURL)
        print("✓", finalURL.path)
        return true
    } catch {
        FileHandle.standardError.write(Data("mux failed: \(error)\n".utf8))
        return false
    }
}

// Cho menu tròn chạy xong hiệu ứng xuất hiện của chính nó rồi mới bắt đầu quay
setTime(0)
DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: step)
app.run()
