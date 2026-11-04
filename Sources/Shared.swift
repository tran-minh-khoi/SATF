import AppKit
import SwiftUI

/// Cửa sổ nổi không viền, không giành focus của app đang dùng.
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
    }
    override var canBecomeKey: Bool { true }
}

enum PanelStatus: Equatable {
    case idle, working, done(String), failed(String)
}

enum Clipboard {
    static func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func copy(_ files: [URL]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(files.map { $0 as NSURL })
    }
}

extension NSScreen {
    static func containing(_ point: NSPoint) -> NSScreen? {
        screens.first { NSMouseInRect(point, $0.frame, false) } ?? main
    }
}

/// Vùng kéo để di chuyển cửa sổ không viền.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Menu share chuẩn của macOS (AirDrop, Mail, Tin nhắn...), hiện ngay dưới `view`.
enum Share {
    static func show(_ files: [URL], from view: NSView?) {
        guard !files.isEmpty, let view else { NSSound.beep(); return }
        NSApp.activate(ignoringOtherApps: true)
        NSSharingServicePicker(items: files).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}

/// Giữ NSView nằm dưới một view SwiftUI, để gắn menu/popover của AppKit vào đúng chỗ.
final class ViewAnchor { weak var view: NSView? }

struct AnchorView: NSViewRepresentable {
    let anchor: ViewAnchor
    func makeNSView(context: Context) -> NSView { let v = NSView(); anchor.view = v; return v }
    func updateNSView(_ nsView: NSView, context: Context) { anchor.view = nsView }
}

/// Thông báo nhỏ góc trên-phải màn hình. Chỉ có một thông báo tại một thời điểm, cái mới thay cái cũ.
final class Toast: ObservableObject {
    enum Style { case info, working, success, failure }

    static let shared = Toast()

    @Published private(set) var style: Style = .info
    @Published private(set) var title = ""
    @Published private(set) var subtitle = ""
    @Published private(set) var clickable = false
    private var action: (() -> Void)?
    private var panel: FloatingPanel?
    private var generation = 0

    /// `seconds = nil`: giữ nguyên tới khi có thông báo khác (dùng cho "Đang chuyển…").
    static func show(_ title: String, _ subtitle: String = "", style: Style = .info,
                     seconds: Double? = 4, onClick: (() -> Void)? = nil) {
        shared.present(title, subtitle, style, seconds, onClick)
    }

    func tap() {
        action?()
        hide()
    }

    private func present(_ title: String, _ subtitle: String, _ style: Style, _ seconds: Double?, _ onClick: (() -> Void)?) {
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.action = onClick
        self.clickable = onClick != nil
        generation += 1

        let panel = self.panel ?? makePanel()
        panel.ignoresMouseEvents = false
        if let host = panel.contentView {
            host.layoutSubtreeIfNeeded()
            let size = host.fittingSize
            let vf = NSScreen.main?.visibleFrame ?? .zero
            panel.setFrame(NSRect(x: vf.maxX - size.width - 4, y: vf.maxY - size.height, width: size.width, height: size.height),
                           display: true)
        }
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }

        if let seconds {
            let gen = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                if self?.generation == gen { self?.hide() }
            }
        }
    }

    private func hide() {
        guard let panel else { return }
        let gen = generation
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.35; panel.animator().alphaValue = 0 }) { [weak self] in
            if self?.generation == gen { panel.orderOut(nil) }
        }
    }

    private func makePanel() -> FloatingPanel {
        let host = ClickThroughHost(rootView: ToastView(toast: self))
        let panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize))
        panel.contentView = host
        self.panel = panel
        return panel
    }
}

/// Nhận cú bấm đầu tiên kể cả khi cửa sổ chưa được chọn.
final class ClickThroughHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct ToastView: View {
    @ObservedObject var toast: Toast
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title).font(.system(size: 13, weight: .semibold))
                if !toast.subtitle.isEmpty {
                    Text(toast.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if toast.clickable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(width: 320)
        // Nền kính có lớp đặc bên dưới: chữ đọc được dù phía sau thông báo là nền trắng hay đen
        .background { GlassSurface(shape: RoundedRectangle(cornerRadius: 16, style: .continuous), base: 0.72) }
        .scaleEffect(hovering && toast.clickable ? 1.02 : 1)
        .padding(12)   // chừa chỗ cho bóng
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { toast.tap() }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hovering)
        .animation(.easeOut(duration: 0.2), value: toast.style)
    }

    @ViewBuilder private var icon: some View {
        switch toast.style {
        case .info:
            Image(nsImage: NSApp.applicationIconImage).resizable()
        case .working:
            ProgressView().controlSize(.regular)
        case .success:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 30)).foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 26)).foregroundStyle(.orange)
        }
    }
}

extension URL {
    /// Tên thư mục chứa file, theo ngôn ngữ của máy (ví dụ "Tải về").
    var folderDisplayName: String {
        FileManager.default.displayName(atPath: deletingLastPathComponent().path)
    }
}
