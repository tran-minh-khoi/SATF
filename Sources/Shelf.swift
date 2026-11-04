import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Dữ liệu khay

final class ShelfModel: ObservableObject {
    @Published var files: [URL] = []
    @Published var selection: Set<URL> = []
    @Published var flash: String?
    /// File cuối cùng được bấm, làm mốc cho Shift-click
    private var anchor: URL?

    /// File mới nhất đứng đầu khay. File đã có trong khay thì được đưa lên đầu.
    func add(_ urls: [URL]) {
        var new: [URL] = []
        for url in urls.map({ $0.standardizedFileURL }) where !new.contains(url) { new.append(url) }
        guard !new.isEmpty else { return }
        files.removeAll { new.contains($0) }
        files.insert(contentsOf: new, at: 0)
    }

    func remove(_ url: URL) {
        files.removeAll { $0 == url }
        selection.remove(url)
    }

    func removeSelected() {
        files.removeAll { selection.contains($0) }
        selection.removeAll()
    }

    func clear() {
        files.removeAll()
        selection.removeAll()
    }

    func selectAll() { selection = Set(files) }

    /// Bấm: chọn một file. ⌘: thêm/bỏ. Shift: chọn cả đoạn từ file bấm trước.
    func click(_ url: URL, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selection.contains(url) { selection.remove(url) } else { selection.insert(url) }
        } else if modifiers.contains(.shift), let a = anchor, let i = files.firstIndex(of: a), let j = files.firstIndex(of: url) {
            selection.formUnion(files[min(i, j)...max(i, j)])
        } else if !selection.contains(url) {
            selection = [url]   // bấm vào file đã chọn thì giữ nguyên nhóm để kéo cả nhóm
        }
        anchor = url
    }

    /// Kéo một file đang được chọn = kéo cả nhóm đang chọn, theo đúng thứ tự trong khay
    func filesToDrag(startingAt url: URL) -> [URL] {
        selection.contains(url) ? files.filter { selection.contains($0) } : [url]
    }

    func load(_ providers: [NSItemProvider]) {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: NSURL.self) { [weak self] object, _ in
                guard let url = (object as? NSURL).map({ $0 as URL }), url.isFileURL else { return }
                DispatchQueue.main.async { self?.add([url]) }
            }
        }
    }

    func showFlash(_ text: String) {
        flash = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            if self?.flash == text { self?.flash = nil }
        }
    }
}

// MARK: - Điều khiển cửa sổ khay

final class ShelfController {
    static let shared = ShelfController()

    let model = ShelfModel()
    private var panel: FloatingPanel?
    private var keyMonitor: Any?

    var isOpen: Bool { panel?.isVisible == true }

    func open(adding files: [URL] = [], near point: NSPoint? = nil) {
        model.add(files)

        let panel: FloatingPanel
        if let existing = self.panel {
            panel = existing
        } else {
            let host = NSHostingView(rootView: ShelfView(model: model, onClose: { [weak self] in self?.close() }))
            let size = host.fittingSize
            host.frame = NSRect(origin: .zero, size: size)
            panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: size))
            panel.contentView = host
            self.panel = panel   // bóng do từng mảnh kính tự vẽ
        }

        if !panel.isVisible {
            let anchor = point ?? NSEvent.mouseLocation
            let size = panel.frame.size
            var origin = NSPoint(x: anchor.x + 60, y: anchor.y - size.height / 2)
            if let vf = NSScreen.containing(anchor)?.visibleFrame {
                if origin.x + size.width > vf.maxX { origin.x = anchor.x - 60 - size.width }
                origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - size.width - 8)
                origin.y = min(max(origin.y, vf.minY + 8), vf.maxY - size.height - 8)
            }
            panel.setFrameOrigin(origin)
        }
        // Nhận phím ngay (Esc để đóng) mà không kéo app khác ra khỏi màn hình: cửa sổ nổi không kích hoạt app
        panel.makeKeyAndOrderFront(nil)
        installKeys()
    }

    /// ⌘A chọn tất cả, Delete bỏ file đang chọn khỏi khay, Esc đóng khay (khi khay đang được focus)
    private func installKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }
            let cmd = event.modifierFlags.contains(.command)
            switch event.keyCode {
            case 0 where cmd:  // A
                self.model.selectAll()
            case 51, 117:      // Delete, Forward Delete
                guard !self.model.selection.isEmpty else { return event }
                self.model.removeSelected()
            case 53:           // Esc
                self.close()
            default:
                return event
            }
            return nil
        }
    }

    func toggle() {
        if isOpen { close() } else { open(near: NSEvent.mouseLocation) }
    }

    /// Đóng khay (file trong khay vẫn được giữ lại cho lần mở sau)
    func close() {
        panel?.orderOut(nil)
    }
}

// MARK: - Giao diện khay

struct ShelfView: View {
    @ObservedObject var model: ShelfModel
    @ObservedObject private var settings = Settings.shared   // đổi ngôn ngữ thì vẽ lại
    let onClose: () -> Void
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 12) {
            card
            // 3 nút tròn bằng kính, tách khỏi khay vuông
            HStack(spacing: 16) {
                ZStack {
                    GlassCircle(tint: .blue)
                    ShareButton(items: { model.files }).frame(width: 44, height: 44)
                }
                .frame(width: 44, height: 44)

                roundButton("doc.on.clipboard", tint: .green, help: L("Copy all", "Copy tất cả")) {
                    guard !model.files.isEmpty else { NSSound.beep(); return }
                    Clipboard.copy(model.files)
                    model.showFlash(L("Copied \(model.files.count) files", "Đã copy \(model.files.count) file"))
                }

                roundButton("trash", tint: .red, help: L("Clear shelf", "Dọn khay")) {
                    withAnimation(.easeOut(duration: 0.2)) { model.clear() }
                }
            }
            .opacity(model.files.isEmpty ? 0.45 : 1)
            .disabled(model.files.isEmpty)
        }
        .padding(14)   // chừa chỗ cho bóng
    }

    private var card: some View {
        VStack(spacing: 10) {
            header

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(targeted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                    .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.5))

                if model.files.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 28, weight: .light))
                        Text(L("Drop files here", "Kéo file vào đây"))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(targeted ? Color.accentColor : Color.secondary)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 6)], spacing: 8) {
                            ForEach(model.files, id: \.self) { url in
                                ShelfTile(url: url, model: model, selected: model.selection.contains(url))
                                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                            }
                        }
                        .padding(10)
                        .animation(.spring(response: 0.32, dampingFraction: 0.75), value: model.files)
                    }
                    // Bấm vào chỗ trống để bỏ chọn
                    .background(Color.clear.contentShape(Rectangle()).onTapGesture { model.selection.removeAll() })
                }
            }
            .frame(height: 230)
            .animation(.easeOut(duration: 0.15), value: targeted)
            .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
                model.load(providers)
                return true
            }

            Text(model.flash ?? hint)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(model.flash == nil ? Color.secondary : Color.green)
                .lineLimit(1)
        }
        .padding(12)
        .frame(width: 300)
        .background { GlassSurface(shape: RoundedRectangle(cornerRadius: 22, style: .continuous), base: 0.6) }
    }

    private var hint: String {
        if model.selection.count > 1 { return L("\(model.selection.count) selected · drag to move them together", "Đã chọn \(model.selection.count) file · kéo để mang đi cùng lúc") }
        if model.files.count > 1 { return L("⌘A selects all · Esc closes", "⌘A chọn tất cả · Esc để đóng") }
        return L("Drag files out to use them · Esc closes", "Kéo file ra ngoài để dùng · Esc để đóng")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.full.fill")
                .foregroundStyle(Color.accentColor)
            Text(L("Shelf", "Khay"))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .fixedSize()   // không bị rớt dòng khi thanh tiêu đề chật
            if !model.files.isEmpty {
                Text("\(model.files.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.1)))
            }

            // Kéo vùng trống ở thanh tiêu đề để di chuyển khay
            WindowDragArea()
                .frame(maxWidth: .infinity, minHeight: 22)

            // Kéo nút này = mang tất cả file trong khay đi cùng lúc
            FileDragSource(files: { model.files }) {
                Image(systemName: "hand.draw")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .frame(width: 22, height: 22)
            .help(L("Drag to take all files", "Kéo để mang tất cả file đi"))
            .opacity(model.files.isEmpty ? 0.35 : 1)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(L("Close (Esc)", "Đóng khay (Esc)"))
        }
    }

    private func roundButton(_ symbol: String, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                GlassCircle(tint: tint)
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(GlassPress())
        .help(help)
    }
}

/// Nút tròn bằng kính, sáng lên khi trỏ vào
private struct GlassCircle: View {
    let tint: Color
    @State private var hovering = false
    var body: some View {
        GlassSurface(shape: Circle(), tint: tint, state: hovering ? .hovered : .normal, base: 0.45)
            .scaleEffect(hovering ? 1.08 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Bấm thì lún nhẹ
private struct GlassPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct ShelfTile: View {
    let url: URL
    @ObservedObject var model: ShelfModel
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 42, height: 42)
                .scaleEffect(hovering ? 1.06 : 1)
            Text(url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(height: 26, alignment: .top)
        }
        .frame(width: 78)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(hovering ? 0.08 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(selected ? 0.7 : 0), lineWidth: 1.5)
        )
        // Lớp AppKit nhận bấm / kéo: kéo được nhiều file cùng lúc (SwiftUI trên macOS 13 chỉ kéo được một)
        .overlay(
            FileDragSource(files: { model.filesToDrag(startingAt: url) },
                           onClick: { model.click(url, modifiers: $0) },
                           onDoubleClick: { NSWorkspace.shared.open(url) },
                           menu: { menu() }) { Color.clear }
        )
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { withAnimation(.easeOut(duration: 0.18)) { model.remove(url) } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: -2)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .animation(.easeOut(duration: 0.12), value: selected)
        .onHover { hovering = $0 }
        .help(url.path)
    }

    private func menu() -> NSMenu {
        let m = NSMenu()
        let files = model.filesToDrag(startingAt: url)
        m.addItem(MenuAction(L("Open", "Mở")) { files.forEach { NSWorkspace.shared.open($0) } })
        m.addItem(MenuAction(L("Show in Finder", "Hiện trong Finder")) { NSWorkspace.shared.activateFileViewerSelecting(files) })
        m.addItem(.separator())
        m.addItem(MenuAction(files.count > 1 ? L("Remove \(files.count) from shelf", "Bỏ \(files.count) file khỏi khay") : L("Remove from shelf", "Bỏ khỏi khay")) { [model] in
            files.forEach { model.remove($0) }
        })
        return m
    }
}

/// NSMenuItem chạy closure
final class MenuAction: NSMenuItem {
    private let run: () -> Void
    init(_ title: String, _ run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { run() }
}

/// Vùng bấm/kéo kiểu Finder: kéo ra được nhiều file một lúc.
struct FileDragSource<Content: View>: NSViewRepresentable {
    let files: () -> [URL]
    var onClick: ((NSEvent.ModifierFlags) -> Void)? = nil
    var onDoubleClick: (() -> Void)? = nil
    var menu: (() -> NSMenu)? = nil
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> SourceView {
        let v = SourceView()
        let host = NSHostingView(rootView: content())
        host.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: v.leadingAnchor), host.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            host.topAnchor.constraint(equalTo: v.topAnchor), host.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])
        update(v)
        return v
    }

    func updateNSView(_ v: SourceView, context: Context) { update(v) }

    private func update(_ v: SourceView) {
        v.files = files
        v.onClick = onClick
        v.onDoubleClick = onDoubleClick
        v.makeMenu = menu
    }

    final class SourceView: NSView, NSDraggingSource {
        var files: () -> [URL] = { [] }
        var onClick: ((NSEvent.ModifierFlags) -> Void)?
        var onDoubleClick: (() -> Void)?
        var makeMenu: (() -> NSMenu)?
        private var downPoint: NSPoint?

        override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }   // nhận chuột thay cho nội dung bên trong
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            downPoint = event.locationInWindow
            if event.clickCount == 2 { onDoubleClick?() } else { onClick?(event.modifierFlags) }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = downPoint, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 3 else { return }
            downPoint = nil
            let urls = files()
            guard !urls.isEmpty else { return }
            // Các icon xếp chồng lệch nhau một chút, giống khi kéo nhiều file trong Finder
            let items = urls.prefix(64).enumerated().map { i, url -> NSDraggingItem in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                let p = convert(event.locationInWindow, from: nil)
                item.setDraggingFrame(NSRect(x: p.x - 24 + CGFloat(min(i, 4)) * 4, y: p.y - 24 - CGFloat(min(i, 4)) * 4, width: 48, height: 48), contents: icon)
                return item
            }
            beginDraggingSession(with: Array(items), event: event, source: self)
        }

        override func menu(for event: NSEvent) -> NSMenu? { makeMenu?() }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? [.copy, .move, .link, .generic] : [.copy, .generic]
        }
    }
}
