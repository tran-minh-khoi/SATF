import AppKit

/// Nơi lưu file kết quả.
/// - Bản tải từ web: ngay cạnh file gốc.
/// - Bản Mac App Store (sandbox, build với -D APPSTORE): app không được ghi vào thư mục của file gốc,
///   nên lưu vào thư mục người dùng chọn trong Cài đặt, mặc định là Downloads
///   (quyền com.apple.security.files.downloads.read-write). Thư mục tự chọn được giữ quyền qua security-scoped bookmark.
enum OutputFolder {
    static func directory(for src: URL) -> URL {
        #if APPSTORE
        return chosen ?? downloads
        #else
        return src.deletingLastPathComponent()
        #endif
    }

    #if APPSTORE
    private static let key = "outputFolderBookmark"
    private static var active: URL?

    static var downloads: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    /// Thư mục người dùng đã chọn (nil: dùng Downloads)
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
        FileManager.default.displayName(atPath: (chosen ?? downloads).path)
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
        panel.directoryURL = chosen ?? downloads
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return false }
        reset()
        UserDefaults.standard.set(data, forKey: key)
        _ = chosen
        return true
    }

    /// Quay về Downloads
    static func reset() {
        active?.stopAccessingSecurityScopedResource()
        active = nil
        UserDefaults.standard.removeObject(forKey: key)
    }
    #endif
}
