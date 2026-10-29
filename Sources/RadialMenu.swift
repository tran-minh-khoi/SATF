import AppKit
import SwiftUI

// MARK: - Dữ liệu

/// Nửa trái: Copy (dưới) + Khay (trên). Nửa phải: Convert (trên) + Edit (dưới).
enum RadialSide { case clipboard, convert, edit }

enum RadialTarget: Equatable {
    case copy, openShelf, convert(Format), more
}

struct RadialItem: Identifiable {
    let id: Int
    let title: String
    let symbol: String
    let target: RadialTarget
}

extension Format {
    var symbol: String {
        switch self {
        case .png, .jpg, .webp, .heic, .gif, .tiff, .bmp, .avif: return "photo"
        case .ico: return "app"
        case .pdf: return "doc.richtext"
        case .txt: return "doc.plaintext"
        case .rtf, .docx, .odt: return "doc.text"
        case .html: return "chevron.left.forwardslash.chevron.right"
        case .csv: return "tablecells"
        case .mp4, .mov: return "film"
        case .m4a, .wav, .aiff: return "music.note"
        case .zip: return "doc.zipper"
        case .extract: return "archivebox"
        case .mergePDF: return "square.stack.3d.up"
        case .splitPDF: return "scissors"
        case .rotate: return "rotate.right"
        case .resize: return "arrow.down.right.and.arrow.up.left"
        case .compress: return "rectangle.compress.vertical"
        case .shrink: return "scalemass"
        case .stripMetadata: return "location.slash"
        case .longImage: return "rectangle.split.1x2"
        }
    }

    var isImageFormat: Bool { imageType != nil || self == .webp }
}

/// Màu của từng nửa, dùng chung cho menu tròn và thông báo
enum Theme {
    static let clipboard = Color(red: 0.22, green: 0.56, blue: 1.0)   // #388FFF
    static let convert = Color(red: 1.0, green: 0.52, blue: 0.16)     // #FF8529
    static let edit = Color(red: 0.20, green: 0.78, blue: 0.48)       // #34C77B
    static let donate = Color(red: 0.91, green: 0.31, blue: 0.36)     // #E8505B
}

// MARK: - Hình học
// Góc tính bằng độ, 0° = bên phải, tăng theo chiều kim đồng hồ (trục y hướng xuống).
// Nửa trái (90°→270°) = Clipboard, nửa phải (270°→450°) = Chuyển đổi.

enum RadialGeo {
    static let size = CGSize(width: 440, height: 480)
    static let center = CGPoint(x: 220, y: 220)          // tính từ góc trên-trái
    static let centerRadius: CGFloat = 44
    static let innerFrom: CGFloat = 52, innerTo: CGFloat = 118
    static let outerFrom: CGFloat = 124, outerTo: CGFloat = 194

    /// Phần của vòng trong
    static func sideRange(_ side: RadialSide) -> (Double, Double) {
        switch side {
        case .clipboard: return (90, 270)
        case .convert: return (270, 360)
        case .edit: return (360, 450)
        }
    }

    /// Nửa phải: trên là Convert, dưới là Edit
    static func rightSide(_ angle: Double) -> RadialSide { angle >= 270 ? .convert : .edit }

    /// Ô thứ `index` trong nửa `side`, xếp từ trên xuống dưới. `full`: trải cả vòng tròn, bắt đầu từ đỉnh.
    static func itemRange(_ side: RadialSide, index: Int, count: Int, full: Bool = false) -> (Double, Double) {
        if full {
            let span = 360.0 / Double(count)
            let start = 270 + Double(index) * span
            return (start, start + span)
        }
        let span = 180.0 / Double(count)
        switch side {
        case .convert, .edit:   // vòng ngoài của cả hai trải hết nửa phải
            let start = 270 + Double(index) * span
            return (start, start + span)
        case .clipboard:
            let end = 270 - Double(index) * span
            return (end - span, end)
        }
    }

    static func point(angleRad: Double, radius: CGFloat) -> CGPoint {
        CGPoint(x: center.x + CGFloat(cos(angleRad)) * radius,
                y: center.y + CGFloat(sin(angleRad)) * radius)
    }

    /// Điểm neo cho hiệu ứng phóng to/thu nhỏ quanh tâm hình tròn
    static var anchor: UnitPoint {
        UnitPoint(x: center.x / size.width, y: center.y / size.height)
    }
}

// MARK: - Trạng thái menu

final class RadialModel: ObservableObject {
    let files: [URL]
    let clipboardItems: [RadialItem]
    let allConvertItems: [RadialItem]
    let allEditItems: [RadialItem]

    /// Nửa vòng chứa tối đa bao nhiêu ô; nhiều hơn thì ô cuối là "Thêm".
    static let halfLimit = 6

    @Published var expanded: RadialSide? {
        didSet { if expanded != oldValue { showAll = false } }
    }
    /// Đang bung cả vòng tròn để xem hết định dạng
    @Published var showAll = false
    @Published var hoveredSide: RadialSide?
    @Published var hoveredItem: Int?
    @Published var status: PanelStatus = .idle

    init(files: [URL]) {
        self.files = files
        clipboardItems = [
            RadialItem(id: 0, title: "Copy", symbol: "doc.on.doc", target: .copy),
            RadialItem(id: 1, title: L("Shelf", "Khay"), symbol: "tray.and.arrow.down", target: .openShelf),
        ]
        let targets = Converter.targets(for: files)
        // Đổi giữa các định dạng ảnh: tên định dạng đã đủ rõ, bỏ icon ảnh lặp lại
        let allImages = files.allSatisfy { Converter.kind(of: $0) == .image }
        func item(_ index: Int, _ format: Format) -> RadialItem {
            RadialItem(id: index, title: format.label,
                       symbol: allImages && format.isImageFormat ? "" : format.symbol,
                       target: .convert(format))
        }
        allConvertItems = targets.filter { !$0.isEdit }.enumerated().map(item)
        allEditItems = targets.filter(\.isEdit).enumerated().map(item)
    }

    private func limited(_ all: [RadialItem], expanded side: RadialSide) -> [RadialItem] {
        let n = Self.halfLimit
        if (showAll && expanded == side) || all.count <= n { return all }
        return all.prefix(n - 1)
            + [RadialItem(id: n - 1, title: L("\(all.count - n + 1) more", "Thêm \(all.count - n + 1)"), symbol: "ellipsis.circle", target: .more)]
    }

    var convertItems: [RadialItem] { limited(allConvertItems, expanded: .convert) }
    var editItems: [RadialItem] { limited(allEditItems, expanded: .edit) }

    func items(_ side: RadialSide) -> [RadialItem] {
        switch side {
        case .clipboard: return clipboardItems
        case .convert: return convertItems
        case .edit: return editItems
        }
    }

    /// Hành động sẽ chạy nếu thả / bấm ở vị trí hiện tại
    var currentTarget: RadialTarget? {
        guard status == .idle, let side = hoveredSide else { return nil }
        if let i = hoveredItem {
            let list = items(side)
            return i < list.count ? list[i].target : nil
        }
        return side == .clipboard ? .copy : nil   // thả thẳng vào nửa Clipboard = copy luôn
    }

    var caption: String {
        switch status {
        case .working: return L("Converting…", "Đang chuyển…")
        case .done(let m), .failed(let m): return m
        case .idle: break
        }
        if let side = hoveredSide {
            if let i = hoveredItem, i < items(side).count {
                switch items(side)[i].target {
                case .copy: return L("Copy file", "Copy file")
                case .openShelf: return L("Keep on the shelf for later", "Cất vào khay để dùng sau")
                case .convert(.extract): return L("Extract here", "Giải nén tại đây")
                case .convert(.mergePDF): return L("Merge \(files.count) files into one PDF", "Gộp \(files.count) file thành một PDF")
                case .convert(.splitPDF): return L("One PDF per page", "Tách mỗi trang thành một PDF")
                case .convert(.rotate): return L("Rotate 90° · saves a copy", "Xoay 90° · lưu thành bản mới")
                case .convert(.resize): return L("Resize to \(Settings.shared.resizeEdge)px on the long side", "Thu nhỏ còn cạnh dài \(Settings.shared.resizeEdge)px")
                case .convert(.compress): return L("Make it smaller · \(Settings.shared.compressLevel.label)", "Giảm dung lượng · \(Settings.shared.compressLevel.label)")
                case .convert(.shrink): return L("Make it under \(sizeLabel(Settings.shared.targetSizeKB))", "Ép xuống dưới \(sizeLabel(Settings.shared.targetSizeKB))")
                case .convert(.stripMetadata): return L("Remove location & camera info", "Xoá vị trí & thông tin máy chụp")
                case .convert(.longImage): return L("Stack \(files.count) images into one tall image", "Ghép \(files.count) ảnh thành một ảnh dài")
                case .convert(.zip) where files.count > 1: return L("Compress \(files.count) files into one ZIP", "Nén \(files.count) file thành một ZIP")
                case .convert(let f): return L("Convert to \(f.label)", "Chuyển sang \(f.label)")
                case .more: return side == .edit ? L("See all edits", "Xem tất cả thao tác") : L("See all formats", "Xem tất cả định dạng")
                }
            }
            switch side {
            case .clipboard: return L("Drop here to copy", "Thả vào đây để copy")
            case .convert: return convertItems.isEmpty ? L("This file type can't be converted yet", "Loại file này chưa đổi được") : L("Move outward to pick a format", "Rê ra ngoài để chọn định dạng")
            case .edit: return editItems.isEmpty ? L("Nothing to edit for this file yet", "Loại file này chưa có thao tác sửa") : L("Move outward to pick an edit", "Rê ra ngoài để chọn thao tác")
            }
        }
        return files.count == 1 ? files[0].lastPathComponent : L("\(files.count) files", "\(files.count) file")
    }

    /// `p`: toạ độ tính từ góc trên-trái của menu
    func updateHover(_ p: CGPoint) {
        guard status == .idle else { return }
        let dx = Double(p.x - RadialGeo.center.x)
        let dy = Double(p.y - RadialGeo.center.y)
        let r = CGFloat(hypot(dx, dy))
        var angle = atan2(dy, dx) * 180 / .pi
        if angle < 0 { angle += 360 }
        let side: RadialSide = (angle >= 90 && angle < 270) ? .clipboard : RadialGeo.rightSide(angle)
        // Vòng ngoài nửa phải thuộc về nhóm đang mở (Convert hoặc Edit), dù chuột ở trên hay dưới
        let outerSide: RadialSide = side == .clipboard ? .clipboard
            : (expanded == .convert || expanded == .edit) ? expanded! : side

        var newSide: RadialSide?
        var newItem: Int?
        var newExpanded = expanded

        if side == .clipboard && !showAll && r >= RadialGeo.innerFrom - 4 && r <= RadialGeo.outerTo + 26 {
            // Nửa trái chia sẵn 2 ô: Copy ở dưới (90°–180°), Khay ở trên (180°–270°)
            newSide = .clipboard
            newItem = angle < 180 ? 0 : 1
            newExpanded = nil
        } else if r >= RadialGeo.innerFrom - 4 && r < RadialGeo.outerFrom - 3 {
            // Vòng trong: chọn nửa, bung vòng ngoài của nửa đó
            newSide = side
            if !items(side).isEmpty { newExpanded = side }
        } else if r >= RadialGeo.outerFrom - 3 && r <= RadialGeo.outerTo + 26 && showAll, let open = expanded {
            // Cả vòng tròn đang là lựa chọn của nhóm đang mở
            let list = items(open)
            newSide = open
            let span = 360.0 / Double(list.count)
            newItem = min(Int((angle - 270 + 360).truncatingRemainder(dividingBy: 360) / span), list.count - 1)
        } else if r >= RadialGeo.outerFrom - 3 && r <= RadialGeo.outerTo + 26 {
            // Vòng ngoài: chọn ô cụ thể
            let list = items(outerSide)
            if !list.isEmpty {
                newExpanded = outerSide
                newSide = outerSide
                newItem = itemIndex(outerSide, angle: angle, count: list.count)
            }
        }

        if newExpanded != expanded { expanded = newExpanded }
        if newSide != hoveredSide { hoveredSide = newSide }
        if newItem != hoveredItem {
            hoveredItem = newItem
            // Rung nhẹ trên trackpad mỗi khi sang ô mới (máy không có Force Touch thì bỏ qua)
            if newItem != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        }

        // Rê vào ô "Thêm" -> bung cả vòng tròn
        if let open = newSide, open != .clipboard, let i = newItem, i < items(open).count, items(open)[i].target == .more {
            showAll = true
            hoveredItem = nil
        }
    }

    func clearHover() {
        if hoveredSide != nil { hoveredSide = nil }
        if hoveredItem != nil { hoveredItem = nil }
    }

    private func itemIndex(_ side: RadialSide, angle: Double, count: Int) -> Int {
        let span = 180.0 / Double(count)
        let raw: Double
        switch side {
        case .convert, .edit: raw = ((angle < 90 ? angle + 360 : angle) - 270) / span
        case .clipboard: raw = (270 - angle) / span
        }
        return min(max(Int(raw), 0), count - 1)
    }
}

// MARK: - Hình vành khuyên

struct RingSegment: Shape {
    var start: Double
    var end: Double
    var inner: CGFloat
    var outer: CGFloat
    var center: CGPoint
    var gap: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        let gapOuter = Double(gap / outer) * 180 / .pi
        let gapInner = Double(gap / inner) * 180 / .pi
        var p = Path()
        p.addArc(center: center, radius: outer,
                 startAngle: .degrees(start + gapOuter), endAngle: .degrees(end - gapOuter), clockwise: false)
        p.addArc(center: center, radius: inner,
                 startAngle: .degrees(end - gapInner), endAngle: .degrees(start + gapInner), clockwise: true)
        p.closeSubpath()
        return p
    }
}

// MARK: - Giao diện

private enum SegmentState { case normal, active, hovered, disabled }

struct RadialMenuView: View {
    @ObservedObject var model: RadialModel
    @State private var appeared = false


    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                if let open = model.expanded, open != .clipboard {
                    outerRing(open)
                        .id("\(open)-\(model.showAll)")   // đổi bố cục -> chạy lại hiệu ứng bung
                        .transition(.scale(scale: 0.82, anchor: RadialGeo.anchor).combined(with: .opacity))
                }
                clipboardSegment(model.clipboardItems[0], range: (90, 180))    // Copy ở dưới
                clipboardSegment(model.clipboardItems[1], range: (180, 270))   // Khay ở trên
                innerHalf(.convert)   // trên
                innerHalf(.edit)      // dưới
            }
            .opacity(model.status == .idle ? 1 : 0.3)

            centerDisc
            captionView
        }
        .frame(width: RadialGeo.size.width, height: RadialGeo.size.height, alignment: .topLeading)
        .scaleEffect(appeared ? 1 : 0.6, anchor: RadialGeo.anchor)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: model.expanded)
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: model.showAll)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: model.hoveredItem)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: model.hoveredSide)
        .animation(.spring(response: 0.35, dampingFraction: 0.55), value: model.status)   // ✓ nảy nhẹ khi xong
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { appeared = true }
        }
    }

    private func tint(_ side: RadialSide) -> Color {
        switch side {
        case .clipboard: return Theme.clipboard
        case .convert: return Theme.convert
        case .edit: return Theme.edit
        }
    }

    // Vòng trong: 2 nửa
    private func clipboardSegment(_ item: RadialItem, range: (Double, Double)) -> some View {
        let hovered = model.hoveredSide == .clipboard && model.hoveredItem == item.id
        return segment(range: range, inner: RadialGeo.innerFrom, outer: RadialGeo.innerTo,
                       tint: Theme.clipboard, state: hovered ? .hovered : .normal,
                       title: item.title, symbol: item.symbol, big: true)
    }

    private func innerHalf(_ side: RadialSide) -> some View {
        let state: SegmentState
        if model.items(side).isEmpty {
            state = .disabled
        } else if model.hoveredSide == side && model.hoveredItem == nil {
            state = .hovered
        } else if model.expanded == side {
            state = .active
        } else {
            state = .normal
        }
        return segment(range: RadialGeo.sideRange(side),
                       inner: RadialGeo.innerFrom, outer: RadialGeo.innerTo,
                       tint: tint(side), state: state,
                       title: side == .convert ? L("Convert", "Chuyển đổi") : L("Edit", "Chỉnh sửa"),
                       symbol: side == .convert ? "arrow.triangle.2.circlepath" : "square.and.pencil",
                       big: true)
    }

    // Vòng ngoài: các lựa chọn con của nửa đang mở
    private func outerRing(_ side: RadialSide) -> some View {
        let list = model.items(side)
        return ZStack {
            ForEach(list) { item in
                segment(range: RadialGeo.itemRange(side, index: item.id, count: list.count,
                                                    full: model.showAll),
                        inner: RadialGeo.outerFrom, outer: RadialGeo.outerTo,
                        tint: tint(side),
                        state: (model.hoveredSide == side && model.hoveredItem == item.id) ? .hovered : .normal,
                        title: item.title, symbol: item.symbol, big: false)
            }
        }
    }

    private func segment(range: (Double, Double), inner: CGFloat, outer: CGFloat, tint: Color,
                         state: SegmentState, title: String, symbol: String, big: Bool) -> some View {
        let shape = RingSegment(start: range.0, end: range.1, inner: inner, outer: outer, center: RadialGeo.center)
        let mid = (range.0 + range.1) / 2 * .pi / 180
        let push: CGFloat = state == .hovered ? 9 : 0
        let labelPoint = RadialGeo.point(angleRad: mid, radius: (inner + outer) / 2)

        let fill: AnyShapeStyle
        switch state {
        case .hovered: fill = AnyShapeStyle(tint.gradient)
        case .active: fill = AnyShapeStyle(tint.opacity(0.3))
        case .normal: fill = AnyShapeStyle(tint.opacity(0.13))
        case .disabled: fill = AnyShapeStyle(Color.primary.opacity(0.03))
        }
        let labelColor: Color = state == .hovered ? .white : (state == .disabled ? .secondary : .primary)

        return ZStack {
            shape.fill(.regularMaterial)
            shape.fill(fill)
            shape.stroke(state == .hovered ? Color.white.opacity(0.55) : tint.opacity(state == .disabled ? 0.1 : 0.45),
                         lineWidth: 1)
            VStack(spacing: 3) {
                if !symbol.isEmpty {
                    Image(systemName: symbol)
                        .font(.system(size: big ? 19 : 15, weight: .semibold))
                }
                Text(title)   // không có icon (ví dụ JPG, PNG): chữ to hơn cho dễ đọc
                    .font(.system(size: big ? 12 : (symbol.isEmpty ? 14 : 11), weight: .bold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(labelColor)
            .scaleEffect(state == .hovered ? 1.12 : 1)
            .position(labelPoint)
        }
        .compositingGroup()
        .shadow(color: state == .hovered ? tint.opacity(0.55) : Color.black.opacity(0.14),
                radius: state == .hovered ? 14 : 5, y: 2)
        .offset(x: CGFloat(cos(mid)) * push, y: CGFloat(sin(mid)) * push)
    }

    // Tâm: icon file đang cầm / trạng thái
    private var centerDisc: some View {
        ZStack {
            Circle().fill(.regularMaterial)
            Circle().strokeBorder(Color.primary.opacity(0.12))
            switch model.status {
            case .idle:
                Image(nsImage: NSWorkspace.shared.icon(forFile: model.files[0].path))
                    .resizable()
                    .frame(width: 48, height: 48)
                    .overlay(alignment: .topTrailing) {
                        if model.files.count > 1 {
                            Text("\(model.files.count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Color.red))
                                .offset(x: 6, y: -4)
                        }
                    }
            case .working:
                ProgressView()
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white, .green)
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.orange)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: RadialGeo.centerRadius * 2, height: RadialGeo.centerRadius * 2)
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        .position(RadialGeo.center)
    }

    private var captionView: some View {
        Text(model.caption)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(2)
            .truncationMode(.middle)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
            .frame(maxWidth: 380)
            .position(x: RadialGeo.center.x, y: RadialGeo.size.height - 22)
    }
}

// MARK: - Lớp bắt chuột / kéo-thả (nằm trên lớp vẽ SwiftUI)

final class RadialInteractionView: NSView {
    private let model: RadialModel
    var onActivate: ((RadialTarget) -> Void)?
    private var trackingArea: NSTrackingArea?

    init(model: RadialModel) {
        self.model = model
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }   // y hướng xuống, khớp với SwiftUI
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    private func hover(_ windowPoint: NSPoint) {
        model.updateHover(convert(windowPoint, from: nil))
    }

    // Chế độ bấm (sau khi đã nhả chuột)
    override func mouseMoved(with event: NSEvent) { hover(event.locationInWindow) }
    override func mouseExited(with event: NSEvent) { model.clearHover() }
    override func mouseDown(with event: NSEvent) { hover(event.locationInWindow) }
    override func mouseUp(with event: NSEvent) {
        hover(event.locationInWindow)
        if let target = model.currentTarget { onActivate?(target) }
    }

    // Chế độ kéo-thả (đang cầm file)
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        hover(sender.draggingLocation)
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        hover(sender.draggingLocation)
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { model.clearHover() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hover(sender.draggingLocation)
        guard let target = model.currentTarget else { return false }
        DispatchQueue.main.async { [weak self] in self?.onActivate?(target) }
        return true
    }
}

// MARK: - Điều khiển cửa sổ menu

final class RadialMenuController {
    private var panel: FloatingPanel?
    private var model: RadialModel?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var watch: Timer?

    func show(files: [URL], at point: NSPoint) {
        close()
        let model = RadialModel(files: files)
        let size = RadialGeo.size

        let root = NSView(frame: NSRect(origin: .zero, size: size))
        let host = NSHostingView(rootView: RadialMenuView(model: model))
        host.frame = root.bounds
        host.autoresizingMask = [.width, .height]
        let overlay = RadialInteractionView(model: model)
        overlay.frame = root.bounds
        overlay.autoresizingMask = [.width, .height]
        overlay.onActivate = { [weak self] target in self?.activate(target) }
        root.addSubview(host)
        root.addSubview(overlay)

        let panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: size))
        panel.contentView = root

        // Đặt tâm hình tròn đúng vị trí con trỏ
        var origin = NSPoint(x: point.x - RadialGeo.center.x,
                             y: point.y - (size.height - RadialGeo.center.y))
        if let vf = NSScreen.containing(point)?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX), vf.maxX - size.width)
            origin.y = min(max(origin.y, vf.minY), vf.maxY - size.height)
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()

        self.panel = panel
        self.model = model

        // Bấm ra ngoài -> đóng; Esc -> đóng
        startWatching()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.close(); return nil }
            return event
        }
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        model = nil
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        clickMonitor = nil
        keyMonitor = nil
        watch?.invalidate()
        watch = nil
        HotKeyManager.shared.setEscapeEnabled(false)
    }

    /// Con trỏ đang nằm ngoài vòng tròn menu?
    private func cursorOutsideMenu() -> Bool {
        guard let panel else { return true }
        let c = NSPoint(x: panel.frame.minX + RadialGeo.center.x, y: panel.frame.maxY - RadialGeo.center.y)
        let m = NSEvent.mouseLocation
        return hypot(m.x - c.x, m.y - c.y) > RadialGeo.outerTo + 26
    }

    /// Thả file ra ngoài menu, hoặc bấm ra ngoài vòng tròn -> đóng menu.
    /// Dò bằng trạng thái nút chuột vì lúc đang kéo file, hệ thống không báo sự kiện chuột cho app khác.
    private func startWatching() {
        var wasDown = NSEvent.pressedMouseButtons & 1 != 0
        watch = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self, let model = self.model, model.status == .idle else { return }
            let down = NSEvent.pressedMouseButtons & 1 != 0
            if down != wasDown && self.cursorOutsideMenu() { self.close() }
            wasDown = down
        }
        // Esc tắt menu kể cả khi SATF không phải app đang được chọn
        HotKeyManager.shared.onEscape = { [weak self] in self?.close() }
        HotKeyManager.shared.setEscapeEnabled(true)
    }

    private func activate(_ target: RadialTarget) {
        guard let model = model, model.status == .idle else { return }
        switch target {
        case .copy:
            Clipboard.copy(model.files)
            finish(model, .done(L("Copied", "Đã copy")), after: 0.8)

        case .openShelf:
            let center = panel.map { NSPoint(x: $0.frame.minX + RadialGeo.center.x,
                                             y: $0.frame.maxY - RadialGeo.center.y) } ?? NSEvent.mouseLocation
            close()
            ShelfController.shared.open(adding: model.files, near: center)

        case .more:
            model.showAll = true

        case .convert(let format):
            let files = model.files
            // Giải nén / nén bằng app người dùng chọn (hoặc hỏi lần đầu)
            if format == .extract || format == .zip,
               Archivers.handle(files, format: format, builtin: { Self.convert(files, to: format, showProgressAfter: 0) }) {
                close()
                return
            }
            // Thiếu gói: hỏi tải, tải xong tự chuyển tiếp (nén / giải nén / tách PDF không cần gói)
            if ![Format.zip, .extract, .splitPDF].contains(format), OfficeAddOn.needed(for: files) {
                close()
                AddOnsWindowController.shared.show(.needed) {
                    Self.convert(files, to: format, showProgressAfter: 0)
                }
                return
            }
            model.clearHover()
            model.status = .working
            Self.convert(files, to: format, showProgressAfter: 1, onSlow: { [weak self] in
                if self?.model === model { self?.close() }
            }, onFinish: { [weak self] ok in
                self?.finish(model, ok ? .done(L("Done!", "Xong!")) : .failed(L("Couldn't convert", "Chưa chuyển được")), after: 0.7)
            })
        }
    }

    /// Chuyển file và báo kết quả ở góc màn hình. Lâu hơn `showProgressAfter` giây thì hiện "Đang chuyển…".
    static func convert(_ files: [URL], to format: Format, showProgressAfter delay: Double,
                        onSlow: @escaping () -> Void = {}, onFinish: @escaping (Bool) -> Void = { _ in }) {
        let what = files.count == 1 ? files[0].lastPathComponent : L("\(files.count) files", "\(files.count) file")
        let slow = DispatchWorkItem {
            onSlow()
            Toast.show(format.progressTitle, what, style: .working, seconds: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: slow)

        Converter.run(files, to: format) { result in
            slow.cancel()
            switch result {
            case .success(let urls):
                NSSound(named: "Pop")?.play()
                onFinish(true)
                let name = urls.count == 1 ? urls[0].lastPathComponent : L("\(urls.count) files", "\(urls.count) file")
                Toast.show(L("Done", "Đã chuyển xong"),
                           L("\(name) · saved in \(urls[0].folderDisplayName)\nClick to show", "\(name) · lưu trong thư mục \(urls[0].folderDisplayName)\nBấm để xem"),
                           style: .success, seconds: 6) {
                    NSWorkspace.shared.activateFileViewerSelecting(urls)
                }
            case .failure(let error):
                NSSound.beep()
                onFinish(false)
                Toast.show(L("Couldn't convert", "Chưa chuyển được"), error.localizedDescription, style: .failure, seconds: 7)
            }
        }
    }

    private func finish(_ model: RadialModel, _ status: PanelStatus, after delay: Double) {
        model.status = status
        if status == .done(L("Copied", "Đã copy")) { NSSound(named: "Pop")?.play() }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            // Chỉ đóng nếu menu này vẫn đang hiện (chưa bị thay bằng menu mới)
            if let self, self.model === model { self.close() }
        }
    }
}
