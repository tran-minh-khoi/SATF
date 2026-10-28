import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Dữ liệu khay

final class ShelfModel: ObservableObject {
    @Published var files: [URL] = []
    @Published var flash: String?

    func add(_ urls: [URL]) {
        for url in urls.map({ $0.standardizedFileURL }) where !files.contains(url) {
            files.append(url)
        }
    }

    func remove(_ url: URL) {
        files.removeAll { $0 == url }
    }

    func clear() {
        files.removeAll()
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
            panel.hasShadow = true
            self.panel = panel
            DispatchQueue.main.async { panel.invalidateShadow() }
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
        panel.orderFrontRegardless()
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
        VStack(spacing: 10) {
            header

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(targeted ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.025))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                    .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.55))

                if model.files.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 28, weight: .light))
                        Text(L("Drop files here", "Kéo file vào đây"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(targeted ? Color.accentColor : Color.secondary)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 6)], spacing: 8) {
                            ForEach(model.files, id: \.self) { url in
                                ShelfTile(url: url) { model.remove(url) }
                            }
                        }
                        .padding(10)
                    }
                }
            }
            .frame(height: 230)
            .animation(.easeOut(duration: 0.15), value: targeted)
            .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
                model.load(providers)
                return true
            }

            Text(model.flash ?? L("Drag files out to use them", "Kéo file ra ngoài để dùng"))
                .font(.system(size: 11))
                .foregroundStyle(model.flash == nil ? Color.secondary : Color.green)
                .lineLimit(1)
        }
        .padding(12)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12))
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.full.fill")
                .foregroundStyle(Color.accentColor)
            Text(L("Shelf", "Khay"))
                .font(.system(size: 13, weight: .semibold))
            if !model.files.isEmpty {
                Text("\(model.files.count)")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.1)))
            }

            // Kéo vùng trống ở thanh tiêu đề để di chuyển khay
            WindowDragArea()
                .frame(maxWidth: .infinity, minHeight: 22)

            ShareButton(items: { model.files })
                .frame(width: 22, height: 22)
                .opacity(model.files.isEmpty ? 0.35 : 1)

            iconButton("doc.on.clipboard", help: L("Copy all", "Copy tất cả")) {
                guard !model.files.isEmpty else { NSSound.beep(); return }
                Clipboard.copy(model.files)
                model.showFlash(L("Copied \(model.files.count) files", "Đã copy \(model.files.count) file"))
            }
            .opacity(model.files.isEmpty ? 0.35 : 1)

            iconButton("trash", help: L("Clear shelf", "Dọn khay")) { model.clear() }
                .opacity(model.files.isEmpty ? 0.35 : 1)

            iconButton("xmark", help: L("Close", "Đóng khay"), action: onClose)
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct ShelfTile: View {
    let url: URL
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 42, height: 42)
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
                .fill(Color.primary.opacity(hovering ? 0.08 : 0))
        )
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: -2)
            }
        }
        .onHover { hovering = $0 }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu {
            Button(L("Open", "Mở")) { NSWorkspace.shared.open(url) }
            Button(L("Show in Finder", "Hiện trong Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            Button(L("Remove from shelf", "Bỏ khỏi khay"), action: onRemove)
        }
        .help(url.path)
    }
}
