import AppKit
import CryptoKit

/// Tự cập nhật: hỏi GitHub bản mới nhất, có bản mới thì báo. Bấm vào là tải DMG,
/// kiểm tra (SHA-256 khớp GitHub, ký bằng đúng Developer ID của SATF, đã được Apple kiểm tra),
/// rồi thay app cũ và mở lại. Không cần máy chủ riêng.
final class Updater {
    static let shared = Updater()

    struct Release {
        let version: String
        let pageURL: URL
        let dmgURL: URL
        /// SHA-256 của file DMG do GitHub tính (dạng hex), nếu có
        let sha256: String?
    }

    /// Bản mới hơn bản đang chạy (nil = đang là bản mới nhất / chưa kiểm tra)
    private(set) var available: Release?
    private(set) var installing = false
    /// Có / hết bản mới: dựng lại menu
    var onChange: (() -> Void)?

    private let latestAPI = URL(string: "https://api.github.com/repos/tran-minh-khoi/SATF/releases/latest")!
    private let releasesPage = URL(string: "https://github.com/tran-minh-khoi/SATF/releases/latest")!
    private let bundleID = "dev.tranminhkhoi.satf"
    private var timer: Timer?

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Kiểm tra lúc mở app (sau một lát) và mỗi ngày một lần khi app chạy liên tục
    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.autoCheck() }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in self?.autoCheck() }
    }

    private func autoCheck() {
        guard Settings.shared.autoUpdateCheck else { return }
        check(userInitiated: false)
    }

    // MARK: - Kiểm tra

    func check(userInitiated: Bool) {
        var request = URLRequest(url: latestAPI, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SATF/\(Self.currentVersion) (macOS)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            let release = ok ? data.flatMap(Self.parse) : nil
            DispatchQueue.main.async { self?.handle(release, userInitiated: userInitiated) }
        }.resume()
    }

    private func handle(_ release: Release?, userInitiated: Bool) {
        guard let release else {
            if userInitiated {
                Toast.show(L("Couldn't check for updates", "Không kiểm tra được bản mới"),
                           L("Check your internet connection and try again.", "Kiểm tra kết nối mạng rồi thử lại nhé."), style: .failure)
            }
            return
        }
        if Self.isNewer(release.version, than: Self.currentVersion) {
            let changed = available?.version != release.version
            available = release
            if changed { onChange?() }
            Toast.show(L("SATF \(release.version) is available", "Đã có SATF \(release.version)"),
                       L("Click to update now", "Bấm để cập nhật ngay"), seconds: 15) { [weak self] in self?.install() }
        } else {
            if available != nil {
                available = nil
                onChange?()
            }
            if userInitiated {
                Toast.show(L("SATF is up to date", "SATF đang là bản mới nhất"),
                           L("Version \(Self.currentVersion)", "Phiên bản \(Self.currentVersion)"), style: .success)
            }
        }
    }

    static func parse(_ data: Data) -> Release? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              json["draft"] as? Bool != true,
              json["prerelease"] as? Bool != true,
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap({ URL(string: $0) }),
              let assets = json["assets"] as? [[String: Any]],
              let dmg = assets.first(where: { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }),
              let url = (dmg["browser_download_url"] as? String).flatMap({ URL(string: $0) }),
              url.scheme == "https", url.host == "github.com",
              url.path.hasPrefix("/tran-minh-khoi/SATF/releases/download/")
        else { return nil }

        let digest = (dmg["digest"] as? String).flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)).lowercased() : nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return Release(version: version, pageURL: page, dmgURL: url, sha256: digest)
    }

    /// "1.2.1" > "1.2.0"
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0
            let q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    // MARK: - Cài bản mới

    func install() {
        guard let release = available, !installing else { return }
        let app = Bundle.main.bundleURL

        // Chạy từ DMG, thư mục không ghi được, hoặc bản build thử (không có Developer ID):
        // mở trang tải để người dùng tự cài.
        guard app.pathExtension == "app",
              !app.path.hasPrefix("/Volumes/"),
              FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path),
              let team = Self.teamID(of: app)
        else {
            NSWorkspace.shared.open(release.pageURL)
            return
        }

        installing = true
        Toast.show(L("Downloading SATF \(release.version)…", "Đang tải SATF \(release.version)…"),
                   L("SATF will restart when it's done", "Xong SATF sẽ tự mở lại"), style: .working, seconds: nil)

        URLSession.shared.downloadTask(with: release.dmgURL) { [weak self] tmp, response, _ in
            guard let self else { return }
            // File tải về bị xoá ngay khi hàm này kết thúc: chuyển sang chỗ khác trước
            var dmg: URL?
            if let tmp, (response as? HTTPURLResponse)?.statusCode == 200 {
                let dest = FileManager.default.temporaryDirectory.appendingPathComponent("SATF-\(release.version)-\(UUID().uuidString).dmg")
                if (try? FileManager.default.moveItem(at: tmp, to: dest)) != nil { dmg = dest }
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let result: Result<URL, UpdateError>
                if let dmg {
                    result = self.installFromDMG(dmg, release: release, team: team, replacing: app)
                    try? FileManager.default.removeItem(at: dmg)
                } else {
                    result = .failure(UpdateError(L("The download didn't finish.", "Tải về chưa xong.")))
                }
                DispatchQueue.main.async { self.finish(result, release: release) }
            }
        }.resume()
    }

    struct UpdateError: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    /// Chạy ở luồng nền. Trả về đường dẫn app mới để mở lại.
    private func installFromDMG(_ dmg: URL, release: Release, team: String, replacing app: URL) -> Result<URL, UpdateError> {
        let fm = FileManager.default

        // 1. File tải về đúng là file trên GitHub
        if let expected = release.sha256 {
            guard let data = try? Data(contentsOf: dmg, options: .mappedIfSafe) else {
                return .failure(UpdateError(L("Couldn't read the download.", "Không đọc được file vừa tải.")))
            }
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actual == expected else {
                return .failure(UpdateError(L("The download is damaged.", "File tải về bị hỏng.")))
            }
        }

        // 2. Mở DMG (chỉ đọc, không hiện lên Finder)
        let mount = fm.temporaryDirectory.appendingPathComponent("satf-update-\(UUID().uuidString)")
        try? fm.createDirectory(at: mount, withIntermediateDirectories: true)
        guard Self.run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path]).status == 0 else {
            return .failure(UpdateError(L("Couldn't open the update.", "Không mở được bản cập nhật.")))
        }
        defer {
            _ = Self.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
            try? fm.removeItem(at: mount)
        }

        let newApp = mount.appendingPathComponent("SATF.app")
        guard fm.fileExists(atPath: newApp.path) else {
            return .failure(UpdateError(L("The update doesn't contain SATF.", "Bản cập nhật không có SATF.")))
        }

        // 3. Ký bằng đúng Developer ID của SATF và đã được Apple kiểm tra (notarize)
        let requirement = "=anchor apple generic and identifier \"\(bundleID)\" and certificate leaf[subject.OU] = \"\(team)\""
        guard Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R", requirement, newApp.path]).status == 0,
              Self.run("/usr/sbin/spctl", ["--assess", "--type", "execute", newApp.path]).status == 0
        else {
            return .failure(UpdateError(L("The update isn't signed by SATF's developer.", "Bản cập nhật không có chữ ký của nhà phát triển SATF.")))
        }

        // 4. Đúng phiên bản vừa báo
        let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist"))
        guard let newVersion = info?["CFBundleShortVersionString"] as? String,
              Self.isNewer(newVersion, than: Self.currentVersion)
        else {
            return .failure(UpdateError(L("The update is older than this version.", "Bản cập nhật cũ hơn bản đang dùng.")))
        }

        // 5. Chép ra cạnh app cũ (cùng ổ đĩa) rồi thay thế trong một bước
        guard let staging = try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true) else {
            return .failure(UpdateError(L("Couldn't prepare the update.", "Không chuẩn bị được bản cập nhật.")))
        }
        defer { try? fm.removeItem(at: staging) }
        let staged = staging.appendingPathComponent("SATF.app")
        guard Self.run("/usr/bin/ditto", [newApp.path, staged.path]).status == 0 else {
            return .failure(UpdateError(L("Couldn't copy the update.", "Không chép được bản cập nhật.")))
        }
        do {
            let result = try fm.replaceItemAt(app, withItemAt: staged)
            return .success(result ?? app)
        } catch {
            return .failure(UpdateError(L("Couldn't replace the old version.", "Không thay được bản cũ.")))
        }
    }

    private func finish(_ result: Result<URL, UpdateError>, release: Release) {
        installing = false
        switch result {
        case .success(let app):
            Toast.show(L("Updated to SATF \(release.version)", "Đã cập nhật SATF \(release.version)"),
                       L("Restarting…", "Đang mở lại…"), style: .success, seconds: 2)
            // Đợi bản cũ thoát hẳn rồi mở bản mới
            let pid = ProcessInfo.processInfo.processIdentifier
            let script = "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\""
            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
            relaunch.arguments = ["-c", script, app.path]
            try? relaunch.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
        case .failure(let error):
            Toast.show(L("Couldn't update SATF", "Chưa cập nhật được SATF"),
                       error.message + " " + L("Click to download it from GitHub.", "Bấm để tải từ GitHub."),
                       style: .failure, seconds: 12) { [weak self] in
                _ = NSWorkspace.shared.open(self?.available?.pageURL ?? release.pageURL)
            }
        }
    }

    // MARK: - Tiện ích

    /// Team ID trong chữ ký Developer ID của app (nil nếu ký ad-hoc / chưa ký)
    private static func teamID(of app: URL) -> String? {
        let output = run("/usr/bin/codesign", ["-dv", "--verbose=2", app.path]).output
        for line in output.split(separator: "\n") where line.hasPrefix("TeamIdentifier=") {
            let id = String(line.dropFirst("TeamIdentifier=".count)).trimmingCharacters(in: .whitespaces)
            return id.isEmpty || id == "not set" ? nil : id
        }
        return nil
    }

    @discardableResult
    private static func run(_ tool: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
