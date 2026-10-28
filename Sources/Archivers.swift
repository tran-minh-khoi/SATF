import AppKit
import SwiftUI

/// App giải nén / nén người dùng cài thêm (The Unarchiver, Keka, BetterZip...).
struct ArchiveApp: Identifiable, Hashable {
    let id: String   // bundle id
    let url: URL
    var name: String { FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "") }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}

enum Archivers {
    /// Giá trị lưu trong Cài đặt: "" = hỏi mỗi lần (chỉ với giải nén), "builtin" = SATF tự làm, còn lại là bundle id
    static let builtin = "builtin"

    private static let extractorIDs = ["com.macpaw.site.theunarchiver", "cx.c3.theunarchiver", "com.aone.keka",
                                       "com.macitbetter.betterzip5", "com.macitbetter.betterzip", "com.winzip.WinZip-Mac"]
    private static let compressorIDs = ["com.aone.keka", "com.macitbetter.betterzip5", "com.macitbetter.betterzip", "com.winzip.WinZip-Mac"]

    static var extractors: [ArchiveApp] { installed(extractorIDs) }
    static var compressors: [ArchiveApp] { installed(compressorIDs) }

    private static func installed(_ ids: [String]) -> [ArchiveApp] {
        var seen = Set<URL>()
        return ids.compactMap { id in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id), seen.insert(url).inserted else { return nil }
            return ArchiveApp(id: id, url: url)
        }
    }

    /// Mở file bằng app đã chọn: app tự giải nén / nén theo cài đặt của nó
    static func open(_ files: [URL], with app: ArchiveApp, extracting: Bool) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.open(files, withApplicationAt: app.url, configuration: config) { _, error in
            DispatchQueue.main.async {
                if error != nil {
                    Toast.show(L("Couldn't open \(app.name)", "Chưa mở được \(app.name)"), "", style: .failure)
                } else {
                    Toast.show(extracting ? L("Extracting with \(app.name)…", "Đang giải nén bằng \(app.name)…")
                                          : L("Compressing with \(app.name)…", "Đang nén bằng \(app.name)…"),
                               L("The file will appear next to the original", "File sẽ nằm cạnh file gốc"))
                }
            }
        }
    }

    /// Giải nén / nén theo lựa chọn của người dùng. Lần đầu giải nén mà máy có app khác thì hỏi.
    /// Trả về false nếu SATF tự làm (để menu tròn chạy tiếp như thường).
    static func handle(_ files: [URL], format: Format, builtin: @escaping () -> Void) -> Bool {
        let extracting = format == .extract
        let apps = extracting ? extractors : compressors
        let saved = extracting ? Settings.shared.extractor : Settings.shared.compressor
        if let app = apps.first(where: { $0.id == saved }) {
            open(files, with: app, extracting: extracting)
            return true
        }
        guard extracting, saved.isEmpty, !apps.isEmpty else { return false }
        ArchiverChooser.shared.show(apps: apps) { choice in
            if let app = choice { open(files, with: app, extracting: true) } else { builtin() }
        }
        return true
    }
}

// MARK: - Hỏi chọn app giải nén

final class ArchiverChooser {
    static let shared = ArchiverChooser()
    private var window: NSWindow?

    /// `done(nil)` = dùng SATF
    func show(apps: [ArchiveApp], done: @escaping (ArchiveApp?) -> Void) {
        window?.close()
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 10), styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = L("Extract with", "Giải nén bằng")
        w.isReleasedWhenClosed = false
        let view = ArchiverChooserView(apps: apps) { [weak w] choice, remember in
            w?.close()
            if remember { Settings.shared.extractor = choice?.id ?? Archivers.builtin }
            done(choice)
        }
        let host = NSHostingView(rootView: view)
        w.contentView = host
        w.setContentSize(host.fittingSize)
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

struct ArchiverChooserView: View {
    let apps: [ArchiveApp]
    let pick: (ArchiveApp?, Bool) -> Void
    @State private var selected: String = Archivers.builtin

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Which app should extract this file?", "Dùng app nào để giải nén file này?"))
                .font(.system(size: 13, weight: .semibold))

            VStack(spacing: 4) {
                option(id: Archivers.builtin, name: L("SATF (built-in)", "SATF (có sẵn)"),
                       icon: NSApp.applicationIconImage)
                ForEach(apps) { app in option(id: app.id, name: app.name, icon: app.icon) }
            }

            HStack {
                Text(L("Change this later in Settings", "Đổi lại sau trong Cài đặt")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("Just once", "Chỉ lần này")) { pick(choice, false) }
                Button(L("Always", "Luôn dùng")) { pick(choice, true) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private var choice: ArchiveApp? { apps.first { $0.id == selected } }

    private func option(id: String, name: String, icon: NSImage?) -> some View {
        Button { selected = id } label: {
            HStack(spacing: 10) {
                Image(systemName: selected == id ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected == id ? Color.accentColor : Color.secondary)
                if let icon { Image(nsImage: icon).resizable().frame(width: 22, height: 22) }
                Text(name)
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(selected == id ? Color.accentColor.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
