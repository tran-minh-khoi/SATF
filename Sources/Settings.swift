import AppKit
import Carbon.HIToolbox

enum Language: String, CaseIterable, Identifiable {
    case en, vi
    var id: String { rawValue }
    var label: String { self == .en ? "English" : "Tiếng Việt" }
}

/// Câu chữ theo ngôn ngữ đang chọn: L("English", "Tiếng Việt"). Mặc định tiếng Anh.
func L(_ en: String, _ vi: String) -> String {
    Settings.shared.language == .vi ? vi : en
}

enum ModifierChoice: String, CaseIterable, Identifiable {
    case none, shift, option, control, command

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return L("None", "Không cần")
        case .shift: return "⇧ Shift"
        case .option: return "⌥ Option"
        case .control: return "⌃ Control"
        case .command: return "⌘ Command"
        }
    }

    var flag: NSEvent.ModifierFlags? {
        switch self {
        case .none: return nil
        case .shift: return .shift
        case .option: return .option
        case .control: return .control
        case .command: return .command
        }
    }
}

enum Sensitivity: String, CaseIterable, Identifiable {
    case easy, normal, hard

    var id: String { rawValue }

    var label: String {
        switch self {
        case .easy: return L("Easy", "Nhạy")
        case .normal: return L("Normal", "Vừa")
        case .hard: return L("Firm", "Khó")
        }
    }

    /// Mỗi nhịp lắc phải đi xa tối thiểu (point)
    var minSwing: CGFloat {
        switch self {
        case .easy: return 25
        case .normal: return 35
        case .hard: return 50
        }
    }

    /// Số lần đổi chiều cần có
    var reversals: Int {
        switch self {
        case .easy: return 3
        case .normal: return 4
        case .hard: return 5
        }
    }
}

struct HotKey: Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String

    static let `default` = HotKey(keyCode: UInt32(kVK_Space),
                                  carbonModifiers: UInt32(optionKey) | UInt32(shiftKey),
                                  display: "⌥⇧Space")
}

/// Toàn bộ cài đặt, tự lưu vào UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    @Published var language: Language {
        didSet { defaults.set(language.rawValue, forKey: "language") }
    }
    /// App giải nén: "" = hỏi khi máy có app khác, "builtin" = SATF, còn lại là bundle id
    @Published var extractor: String {
        didSet { defaults.set(extractor, forKey: "extractor") }
    }
    /// App nén ZIP: "builtin" = SATF, còn lại là bundle id
    @Published var compressor: String {
        didSet { defaults.set(compressor, forKey: "compressor") }
    }
    @Published var shakeEnabled: Bool {
        didSet { defaults.set(shakeEnabled, forKey: "shakeEnabled") }
    }
    @Published var shakeModifier: ModifierChoice {
        didSet { defaults.set(shakeModifier.rawValue, forKey: "shakeModifier") }
    }
    @Published var sensitivity: Sensitivity {
        didSet { defaults.set(sensitivity.rawValue, forKey: "sensitivity") }
    }
    @Published var hotKeyEnabled: Bool {
        didSet {
            defaults.set(hotKeyEnabled, forKey: "hotKeyEnabled")
            HotKeyManager.shared.reload()
        }
    }
    @Published var hotKey: HotKey {
        didSet {
            defaults.set(Int(hotKey.keyCode), forKey: "hotKeyCode")
            defaults.set(Int(hotKey.carbonModifiers), forKey: "hotKeyMods")
            defaults.set(hotKey.display, forKey: "hotKeyDisplay")
            HotKeyManager.shared.reload()
        }
    }
    /// Thông báo khi phím tắt không đăng ký được (trùng app khác)
    @Published var hotKeyError: String?

    private init() {
        language = Language(rawValue: defaults.string(forKey: "language") ?? "") ?? .en
        extractor = defaults.string(forKey: "extractor") ?? ""
        compressor = defaults.string(forKey: "compressor") ?? "builtin"
        shakeEnabled = defaults.object(forKey: "shakeEnabled") as? Bool ?? true

        if let raw = defaults.string(forKey: "shakeModifier"), let m = ModifierChoice(rawValue: raw) {
            shakeModifier = m
        } else if defaults.object(forKey: "requireShift") as? Bool == false {
            shakeModifier = .none   // cài đặt cũ của bản trước
        } else {
            shakeModifier = .shift
        }

        sensitivity = Sensitivity(rawValue: defaults.string(forKey: "sensitivity") ?? "") ?? .normal
        hotKeyEnabled = defaults.object(forKey: "hotKeyEnabled") as? Bool ?? true

        if let display = defaults.string(forKey: "hotKeyDisplay") {
            hotKey = HotKey(keyCode: UInt32(defaults.integer(forKey: "hotKeyCode")),
                            carbonModifiers: UInt32(defaults.integer(forKey: "hotKeyMods")),
                            display: display)
        } else {
            hotKey = .default
        }
    }
}
