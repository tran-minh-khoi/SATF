import AppKit

/// Nơi lưu file kết quả.
/// - Bản tải từ web: ngay cạnh file gốc.
/// - Bản Mac App Store (sandbox, build với -D APPSTORE): app không được ghi vào thư mục của file gốc,
///   nên lưu vào thư mục người dùng tự chọn (hỏi ở lần đổi file đầu tiên, đổi lại được trong Cài đặt).
///   Apple không cho đặt sẵn nơi lưu như Downloads (Guideline 2.4.5). Quyền thư mục được giữ qua security-scoped bookmark.
enum OutputFolder {
    static func directory(for src: URL) -> URL {
        #if APPSTORE
        // Chưa chọn thì ghi cạnh file gốc sẽ bị sandbox chặn và báo lỗi; RadialMenuController.convert hỏi trước nên hiếm khi xảy ra
        return chosen ?? src.deletingLastPathComponent()
        #else
        return src.deletingLastPathComponent()
        #endif
    }

    #if APPSTORE
    private static let key = "outputFolderBookmark"
    private static var active: URL?

    /// Thư mục người dùng đã chọn (nil: chưa chọn)
    static var chosen: URL? {
        if let active { return active }
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: key)
        }
        active = url
        return url
    }

    static var displayName: String {
        chosen.map { FileManager.default.displayName(atPath: $0.path) } ?? L("Not chosen yet", "Chưa chọn")
    }

    /// Hỏi người dùng chọn thư mục lưu. Trả về true nếu đã đổi.
    @discardableResult
    static func choose() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = L("Choose", "Chọn")
        panel.message = L("Converted and edited files will be saved here", "File sau khi chuyển và sửa sẽ được lưu ở đây")
        panel.directoryURL = chosen
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return false }
        active?.stopAccessingSecurityScopedResource()
        active = nil
        UserDefaults.standard.set(data, forKey: key)
        _ = chosen
        return true
    }
    #endif
}
