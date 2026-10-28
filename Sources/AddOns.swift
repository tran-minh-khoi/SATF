import AppKit
import SwiftUI

/// Công cụ phụ: đi kèm app hoặc là gói tải thêm.
enum Tools {
    /// ~/Library/Application Support/SATF
    static let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("SATF")
    static let libreOfficeApp = dir.appendingPathComponent("LibreOffice.app")
    static let systemLibreOffice = "/Applications/LibreOffice.app/Contents/MacOS/soffice"

    static var soffice: String? {
        [libreOfficeApp.appendingPathComponent("Contents/MacOS/soffice").path, systemLibreOffice]
            .first(where: FileManager.default.isExecutableFile)
    }

    static var cwebp: String? {
        [Bundle.main.resourceURL?.appendingPathComponent("cwebp").path ?? "",
         "/opt/homebrew/bin/cwebp", "/usr/local/bin/cwebp"]
            .first(where: FileManager.default.isExecutableFile)
    }

    static func appInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// Máy đã tự đổi được Excel và PowerPoint (có Office hoặc iWork) thì không cần gói
    static var hasOfficeApps: Bool {
        (appInstalled("com.microsoft.Excel") || appInstalled("com.apple.iWork.Numbers"))
            && (appInstalled("com.microsoft.Powerpoint") || appInstalled("com.apple.iWork.Keynote"))
    }
}

// MARK: - Gói Excel & PowerPoint

/// Gói duy nhất trên Mac: LibreOffice, để đổi Excel & PowerPoint khi máy không có Office.
final class OfficeAddOn: ObservableObject {
    static let shared = OfficeAddOn()

    @Published private(set) var busy = false
    @Published private(set) var progress = 0.0
    @Published private(set) var status = ""
    @Published private(set) var failed = false
    @Published private(set) var diskSize: String?
    private var observation: NSKeyValueObservation?

    /// Đã tải về bởi SATF (xoá được)
    var downloaded: Bool { FileManager.default.fileExists(atPath: Tools.libreOfficeApp.path) }
    /// Dùng LibreOffice người dùng tự cài trong Applications
    var usingSystemCopy: Bool { !downloaded && FileManager.default.isExecutableFile(atPath: Tools.systemLibreOffice) }

    private init() { refreshSize() }

    /// File này cần gói mà máy chưa có?
    static func needed(for files: [URL]) -> Bool {
        guard Tools.soffice == nil else { return false }
        return files.contains { url in
            switch Converter.kind(of: url) {
            case .spreadsheet:
                return !Tools.appInstalled("com.microsoft.Excel") && !Tools.appInstalled("com.apple.iWork.Numbers")
            case .presentation:
                return !Tools.appInstalled("com.microsoft.Powerpoint") && !Tools.appInstalled("com.apple.iWork.Keynote")
            default:
                return false
            }
        }
    }

    func refreshSize() {
        guard downloaded else { diskSize = nil; return }
        DispatchQueue.global(qos: .utility).async {
            let bytes = FileManager.default.allocatedSize(of: Tools.libreOfficeApp)
            let text = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            DispatchQueue.main.async { self.diskSize = text }
        }
    }

    func remove() {
        busy = true
        status = L("Removing…", "Đang xoá…")
        DispatchQueue.global(qos: .userInitiated).async {
            try? FileManager.default.removeItem(at: Tools.libreOfficeApp)
            DispatchQueue.main.async {
                self.busy = false
                self.status = ""
                self.refreshSize()
            }
        }
    }

    func install(then done: @escaping (Bool) -> Void = { _ in }) {
        guard !busy else { return }
        busy = true
        failed = false
        progress = 0
        status = L("Getting ready…", "Đang chuẩn bị…")
        Task {
            do {
                try await installLibreOffice()
                await MainActor.run {
                    busy = false
                    status = ""
                    refreshSize()
                    done(true)
                }
            } catch {
                await MainActor.run {
                    busy = false
                    failed = true
                    status = (error as? ConvertError)?.message
                        ?? L("Download didn't finish. Check your internet and try again.", "Tải không thành công. Kiểm tra mạng rồi thử lại nhé.")
                    done(false)
                }
            }
        }
    }

    private func installLibreOffice() async throws {
        let base = URL(string: "https://download.documentfoundation.org/libreoffice/stable/")!
        // Thư mục chứa các bản đang phát hành, ví dụ 25.8.7/ 26.8.1/ -> lấy bản mới nhất
        let (listing, _) = try await URLSession.shared.data(from: base)
        let html = String(decoding: listing, as: UTF8.self)
        let versions = html.components(separatedBy: "href=\"").compactMap { part -> String? in
            guard let end = part.range(of: "/\"") else { return nil }
            let v = String(part[..<end.lowerBound])
            return !v.isEmpty && v.allSatisfy { $0.isNumber || $0 == "." } ? v : nil
        }
        guard let version = versions.max(by: { $0.compare($1, options: .numeric) == .orderedAscending }) else {
            throw ConvertError(L("Couldn't download right now. Please try again later.", "Chưa tải được, thử lại sau nhé"))
        }
        #if arch(arm64)
        let (folder, name) = ("aarch64", "MacOS_aarch64")
        #else
        let (folder, name) = ("x86_64", "MacOS_x86-64")
        #endif
        let url = base.appendingPathComponent("\(version)/mac/\(folder)/LibreOffice_\(version)_\(name).dmg")

        let dmg = try await download(url)
        defer { try? FileManager.default.removeItem(at: dmg) }

        await MainActor.run { status = L("Installing…", "Đang cài…") }
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("satf-lo-\(UUID().uuidString)")
        try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noverify", "-mountpoint", mount.path, dmg.path])
        defer { try? run("/usr/bin/hdiutil", ["detach", "-force", mount.path]) }

        let fm = FileManager.default
        try fm.createDirectory(at: Tools.dir, withIntermediateDirectories: true)
        try? fm.removeItem(at: Tools.libreOfficeApp)
        try run("/usr/bin/ditto", [mount.appendingPathComponent("LibreOffice.app").path, Tools.libreOfficeApp.path])
        guard Tools.soffice != nil else {
            throw ConvertError(L("Install didn't finish. Please try again.", "Cài không thành công, thử lại nhé"))
        }
    }

    private func download(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let task = URLSession.shared.downloadTask(with: url) { tmp, response, error in
                if let error { return cont.resume(throwing: error) }
                guard let tmp, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    return cont.resume(throwing: ConvertError(L("Download didn't finish. Check your internet and try again.",
                                                                "Tải không thành công. Kiểm tra mạng rồi thử lại nhé.")))
                }
                // File tạm bị xoá khi hàm này kết thúc -> chuyển ra chỗ khác
                let keep = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dmg")
                do { try FileManager.default.moveItem(at: tmp, to: keep); cont.resume(returning: keep) }
                catch { cont.resume(throwing: error) }
            }
            observation = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
                let done = ByteCountFormatter.string(fromByteCount: p.completedUnitCount, countStyle: .file)
                let total = ByteCountFormatter.string(fromByteCount: max(p.totalUnitCount, 0), countStyle: .file)
                DispatchQueue.main.async {
                    self?.progress = p.fractionCompleted
                    self?.status = L("Downloading… \(done) of \(total)", "Đang tải… \(done) / \(total)")
                }
            }
            task.resume()
        }
    }

    private func run(_ path: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 { throw ConvertError(L("Install didn't finish. Please try again.", "Cài không thành công, thử lại nhé")) }
    }
}

extension FileManager {
    func allocatedSize(of dir: URL) -> Int {
        guard let e = enumerator(at: dir, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total = 0
        for case let url as URL in e {
            total += (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0
        }
        return total
    }
}

// MARK: - Cửa sổ quản lý gói

/// Mở ở 3 chỗ: lần đầu mở app, khi thiếu gói lúc chuyển file, và từ menu "Add-ons…".
final class AddOnsWindowController {
    static let shared = AddOnsWindowController()
    private var window: NSWindow?

    enum Reason { case manage, welcome, needed }

    /// Lần đầu mở app: chào và hỏi có muốn thêm gói không (chỉ khi máy chưa tự đổi được Excel & PowerPoint)
    func showOnFirstLaunch() {
        let key = "welcomeShown"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard Tools.soffice == nil, !Tools.hasOfficeApps else { return }
        show(.welcome)
    }

    /// `onReady`: chạy tiếp việc đang dở sau khi tải xong (ví dụ chuyển file vừa thả)
    func show(_ reason: Reason = .manage, onReady: (() -> Void)? = nil) {
        window?.close()
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 10),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L("Add-ons", "Gói tải thêm")
        w.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: AddOnsView(reason: reason, close: { [weak w] in w?.close() }, onReady: onReady))
        w.contentView = host
        w.setContentSize(host.fittingSize)
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func retitle() { window?.title = L("Add-ons", "Gói tải thêm") }
}

struct AddOnsView: View {
    let reason: AddOnsWindowController.Reason
    let close: () -> Void
    let onReady: (() -> Void)?
    @ObservedObject private var addOn = OfficeAddOn.shared
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "tablecells")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Excel & PowerPoint", "Excel & PowerPoint")).font(.system(size: 13, weight: .semibold))
                    Text(L("Convert to PDF and images", "Đổi sang PDF và ảnh")).font(.system(size: 12))
                    Text(stateText).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                actionButton
            }
            .padding(12)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))

            if addOn.busy || !addOn.status.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if addOn.busy { ProgressView(value: addOn.progress) }
                    Text(addOn.status).font(.caption).foregroundStyle(addOn.failed ? .red : .secondary)
                }
            }

            HStack {
                Text(L("Remove add-ons anytime to free up space.", "Xoá gói bất cứ lúc nào để giải phóng dung lượng."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(reason == .needed ? L("Not now", "Để sau") : L("Done", "Xong"), action: close)
                    .keyboardShortcut(.cancelAction)
                    .disabled(addOn.busy)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    @ViewBuilder private var header: some View {
        switch reason {
        case .welcome:
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Welcome to SATF", "Chào mừng đến với SATF")).font(.system(size: 15, weight: .semibold))
                Text(L("Images, PDF, Word, music and video work right away. Want Excel and PowerPoint too? Add it now or later — SATF will ask when you need it.",
                       "Ảnh, PDF, Word, nhạc và video đã dùng được ngay. Muốn đổi cả Excel, PowerPoint? Thêm ngay hoặc để sau — khi cần SATF sẽ hỏi."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .needed:
            VStack(alignment: .leading, spacing: 4) {
                Text(L("One more step", "Cần thêm một bước")).font(.system(size: 15, weight: .semibold))
                Text(L("To convert this file, SATF needs the Excel & PowerPoint add-on. Your file will be converted as soon as it's ready.",
                       "Để đổi file này, SATF cần gói Excel & PowerPoint. Tải xong file sẽ được đổi ngay."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .manage:
            Text(L("Add-ons", "Gói tải thêm")).font(.system(size: 15, weight: .semibold))
        }
    }

    private var stateText: String {
        if addOn.usingSystemCopy { return L("Using LibreOffice already on this Mac", "Đang dùng LibreOffice có sẵn trên máy") }
        if addOn.downloaded { return L("Installed", "Đã cài") + (addOn.diskSize.map { " · \($0)" } ?? "") }
        if Tools.hasOfficeApps { return L("Optional — Microsoft Office already handles this", "Không bắt buộc — Microsoft Office đã làm được") }
        return L("Not installed · about 300 MB download", "Chưa cài · tải khoảng 300 MB")
    }

    @ViewBuilder private var actionButton: some View {
        if addOn.busy {
            ProgressView().controlSize(.small)
        } else if addOn.downloaded {
            Button(L("Remove", "Xoá"), role: .destructive) { addOn.remove() }
        } else if !addOn.usingSystemCopy {
            Button(L("Download", "Tải về")) {
                addOn.install { ok in
                    guard ok else { return }
                    if let onReady { close(); onReady() }
                    else { Toast.show(L("Excel & PowerPoint added", "Đã thêm Excel & PowerPoint"),
                                      L("Try dragging an Excel or PowerPoint file", "Kéo thử một file Excel hoặc PowerPoint nhé"), style: .success) }
                }
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}
