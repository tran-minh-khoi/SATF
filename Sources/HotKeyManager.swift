import AppKit
import Carbon.HIToolbox

/// Phím tắt toàn cục qua Carbon RegisterEventHotKey — không cần quyền Accessibility.
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onPress: (() -> Void)?
    /// Esc khi menu tròn đang mở
    var onEscape: (() -> Void)?
    private var escapeRef: EventHotKeyRef?
    /// Tạm tắt khi đang ghi phím tắt mới trong Cài đặt
    var suspended = false {
        didSet { reload() }
    }

    private var hotKeyRef: EventHotKeyRef?
    private var handlerInstalled = false

    func reload() {
        unregister()
        let settings = Settings.shared
        guard settings.hotKeyEnabled, !suspended else {
            settings.hotKeyError = nil
            return
        }
        installHandlerIfNeeded()

        let id = EventHotKeyID(signature: OSType(0x5348_4B44), id: 1)   // 'SHKD'
        let status = RegisterEventHotKey(settings.hotKey.keyCode,
                                         settings.hotKey.carbonModifiers,
                                         id,
                                         GetApplicationEventTarget(),
                                         0,
                                         &hotKeyRef)
        settings.hotKeyError = status == OSStatus(noErr) ? nil : L("Another app already uses this shortcut. Try a different one.", "Phím này đã có app khác dùng, chọn phím khác nhé.")
    }

    /// Chỉ giữ phím Esc trong lúc menu tròn đang mở, để không chặn Esc của app khác.
    func setEscapeEnabled(_ on: Bool) {
        if let ref = escapeRef { UnregisterEventHotKey(ref); escapeRef = nil }
        guard on else { return }
        installHandlerIfNeeded()
        RegisterEventHotKey(UInt32(kVK_Escape), 0, EventHotKeyID(signature: OSType(0x5348_4B44), id: 2),
                            GetApplicationEventTarget(), 0, &escapeRef)
    }

    private func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var key = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
            DispatchQueue.main.async {
                if key.id == 2 { HotKeyManager.shared.onEscape?() } else { HotKeyManager.shared.onPress?() }
            }
            return OSStatus(noErr)
        }, 1, &spec, nil, nil)
        handlerInstalled = true
    }

    // MARK: - Tiện ích chuyển đổi phím

    static func carbonFlags(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    static func symbols(_ flags: NSEvent.ModifierFlags) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s
    }

    static func keyName(_ event: NSEvent) -> String {
        let names: [UInt16: String] = [
            49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        if let name = names[event.keyCode] { return name }
        return (event.charactersIgnoringModifiers ?? "?").uppercased()
    }
}
