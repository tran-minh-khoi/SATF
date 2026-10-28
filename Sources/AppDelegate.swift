import AppKit
import Combine
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let detector = ShakeDetector()
    private let radialMenu = RadialMenuController()
    private var dragChangeCountAtMouseDown = 0
    private var languageWatch: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        // Đổi ngôn ngữ: dựng lại menu, đổi tiêu đề các cửa sổ đang mở
        languageWatch = Settings.shared.$language.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.statusItem.menu = self?.makeMenu()
            SettingsWindowController.shared.retitle()
            AddOnsWindowController.shared.retitle()
        }

        detector.onMouseDown = { [weak self] in
            self?.dragChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
        }
        detector.onShake = { [weak self] in
            self?.openMenuForDraggedFiles()
        }
        detector.start()

        HotKeyManager.shared.onPress = { [weak self] in
            self?.handleHotKey()
        }
        HotKeyManager.shared.reload()

        Toast.show(L("SATF is ready", "SATF đã sẵn sàng"), Self.howToUse(), seconds: 5)
        AddOnsWindowController.shared.showOnFirstLaunch()
    }

    /// Ví dụ: "Kéo file, giữ ⇧ Shift rồi lắc nhẹ, hoặc bấm ⌥⇧Space"
    static func howToUse() -> String {
        let s = Settings.shared
        var ways: [String] = []
        if s.shakeEnabled {
            ways.append(s.shakeModifier.flag == nil ? L("Drag a file and give it a little shake", "Kéo file rồi lắc nhẹ") : L("Drag a file, hold \(s.shakeModifier.label) and give it a shake", "Kéo file, giữ \(s.shakeModifier.label) rồi lắc nhẹ"))
        }
        if s.hotKeyEnabled { ways.append(ways.isEmpty ? L("Drag a file and press \(s.hotKey.display)", "Kéo file rồi bấm \(s.hotKey.display)") : L("press \(s.hotKey.display)", "bấm \(s.hotKey.display)")) }
        return ways.isEmpty ? L("Click the SATF icon in the menu bar to get started", "Bấm icon SATF trên thanh menu để bắt đầu") : ways.joined(separator: L(", or ", ", hoặc "))
    }

    /// File đang được kéo (nếu có).
    /// Khi bắt đầu kéo file, Finder ghi danh sách file vào "drag pasteboard"; nếu pasteboard
    /// không đổi kể từ lúc nhấn chuột thì người dùng đang kéo thứ khác (cửa sổ, chữ...).
    private func draggedFiles() -> [URL]? {
        guard NSEvent.pressedMouseButtons & 1 != 0 else { return nil }
        let pb = NSPasteboard(name: .drag)
        guard pb.changeCount != dragChangeCountAtMouseDown,
              let urls = pb.readObjects(forClasses: [NSURL.self],
                                        options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return nil }
        return urls
    }

    @discardableResult
    private func openMenuForDraggedFiles() -> Bool {
        guard let files = draggedFiles() else { return false }
        radialMenu.show(files: files, at: NSEvent.mouseLocation)
        return true
    }

    private func handleHotKey() {
        if openMenuForDraggedFiles() { return }
        ShelfController.shared.toggle()
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Logo app thu nhỏ cho vừa thanh menu
        let logo = NSApp.applicationIconImage ?? NSImage()
        let icon = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            logo.draw(in: rect)
            return true
        }
        statusItem.button?.image = icon
        statusItem.button?.toolTip = "SATF"

        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let header = menu.addItem(withTitle: "SATF", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(.separator())

        add(menu, L("Open Shelf", "Mở khay"), "tray", #selector(toggleShelf))
        add(menu, L("Add-ons…", "Gói tải thêm…"), "shippingbox", #selector(openSetup))
        add(menu, L("Settings…", "Cài đặt…"), "gearshape", #selector(openSettings), key: ",")
        menu.addItem(.separator())
        add(menu, L("Report a Bug…", "Báo lỗi…"), "ladybug", #selector(reportBug))
        add(menu, L("Suggest a Feature…", "Góp ý tính năng…"), "lightbulb", #selector(suggestFeature))
        menu.addItem(.separator())
        add(menu, L("About SATF", "Giới thiệu SATF"), "info.circle", #selector(openAbout))
        add(menu, L("Uninstall SATF…", "Gỡ SATF khỏi máy…"), "trash", #selector(uninstall))
        add(menu, L("Quit SATF", "Thoát"), "power", #selector(quit), key: "q")

        return menu
    }

    private func add(_ menu: NSMenu, _ title: String, _ symbol: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        item.target = self
        menu.addItem(item)
    }

    @objc private func toggleShelf() { ShelfController.shared.toggle() }
    @objc private func openSetup() { AddOnsWindowController.shared.show() }
    @objc private func openSettings() { SettingsWindowController.shared.show() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Góp ý: mở app mail với thư soạn sẵn

    @objc private func reportBug() {
        sendFeedback(subject: L("SATF bug report", "SATF - Báo lỗi"),
                     body: L("What happened?\n\n\nWhat did you expect?\n\n\nSteps to reproduce:\n1. \n2. \n",
                             "Chuyện gì đã xảy ra?\n\n\nBạn mong muốn điều gì?\n\n\nCác bước để gặp lỗi:\n1. \n2. \n"))
    }

    @objc private func suggestFeature() {
        sendFeedback(subject: L("SATF feature idea", "SATF - Góp ý tính năng"),
                     body: L("I'd love SATF to…\n\n\nIt would help me because…\n",
                             "Mình muốn SATF có thể…\n\n\nĐiều này giúp mình…\n"))
    }

    private func sendFeedback(subject: String, body: String) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let full = body + "\n—\nSATF \(version) · macOS \(os)"
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = "contact@tranminhkhoi.dev"
        c.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: full)]
        if let url = c.url, NSWorkspace.shared.open(url) { return }
        // Máy chưa cài app mail: copy địa chỉ để người dùng tự gửi
        Clipboard.copyText("contact@tranminhkhoi.dev")
        Toast.show(L("No mail app found", "Chưa có app mail"),
                   L("Email address copied: contact@tranminhkhoi.dev", "Đã copy địa chỉ: contact@tranminhkhoi.dev"))
    }

    @objc private func openAbout() {
        let credits = NSMutableAttributedString(string: L("Drag, shake, convert. In a blink.\n\nMade by Tran Minh Khoi\n", "Kéo, lắc, đổi file trong nháy mắt.\n\nPhát triển bởi Tran Minh Khoi\n"),
                                                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        for (text, link) in [("tranminhkhoi.dev", "https://tranminhkhoi.dev"), ("  ·  ", nil), ("contact@tranminhkhoi.dev", "mailto:contact@tranminhkhoi.dev")] {
            var attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11)]
            if let link { attrs[.link] = URL(string: link) } else { attrs[.foregroundColor] = NSColor.secondaryLabelColor }
            credits.append(NSAttributedString(string: text, attributes: attrs))
        }
        credits.addAttribute(.paragraphStyle, value: center, range: NSRange(location: 0, length: credits.length))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    // MARK: - Gỡ cài đặt

    /// Xoá sạch mọi thứ SATF tạo ra trên máy, rồi đưa app vào Thùng rác.
    @objc private func uninstall() {
        let fm = FileManager.default
        let extra = Optional(fm.allocatedSize(of: Tools.dir)).flatMap { $0 > 1_000_000 ? $0 : nil }

        let alert = NSAlert()
        alert.messageText = L("Uninstall SATF?", "Gỡ SATF khỏi máy?")
        alert.informativeText = L("SATF and everything that came with it (settings", "SATF và mọi thứ đi kèm (cài đặt")
            + (extra.map { L(", add-ons ", ", gói tải thêm ") + ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "")
            + L(") will be removed. The app will be moved to the Trash.", ") sẽ được xoá. App sẽ được chuyển vào Thùng rác.")
        alert.addButton(withTitle: L("Uninstall", "Gỡ"))
        alert.addButton(withTitle: L("Cancel", "Huỷ"))
        alert.buttons[0].hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        try? SMAppService.mainApp.unregister()
        let lib = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        let id = Bundle.main.bundleIdentifier ?? "dev.tranminhkhoi.satf"
        for url in [Tools.dir,
                    fm.temporaryDirectory.appendingPathComponent("satf-lo-profile"),
                    lib.appendingPathComponent("Caches/\(id)"),
                    lib.appendingPathComponent("HTTPStorages/\(id)"),
                    lib.appendingPathComponent("Saved Application State/\(id).savedState")] {
            try? fm.removeItem(at: url)
        }
        UserDefaults.standard.removePersistentDomain(forName: id)
        UserDefaults.standard.synchronize()

        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in
            NSApp.terminate(nil)
        }
    }
}
