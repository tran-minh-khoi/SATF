import AppKit
import ServiceManagement
import SwiftUI

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func retitle() { window?.title = L("SATF Settings", "Cài đặt SATF") }

    func show() {
        if window == nil {
            let host = NSHostingView(rootView: SettingsView())
            // Kéo đổi kích thước được; không cao hơn màn hình (máy màn nhỏ vẫn cuộn xem hết)
            let maxH = (NSScreen.main?.visibleFrame.height ?? 800) - 60
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: min(700, maxH)),
                             styleMask: [.titled, .closable, .resizable],
                             backing: .buffered, defer: false)
            w.contentMinSize = NSSize(width: 420, height: 360)
            w.title = L("SATF Settings", "Cài đặt SATF")
            w.contentView = host
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.title = L("SATF Settings", "Cài đặt SATF")
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// Chiều cao cửa sổ; ảnh chụp cho README dùng giá trị lớn hơn để thấy hết các mục
    var height: CGFloat = 700

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    if let icon = NSApp.applicationIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SATF")
                            .font(.headline)
                        Text(L("Drag, shake, convert. In a blink.", "Kéo, lắc, đổi file trong nháy mắt"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker(L("Language", "Ngôn ngữ"), selection: $settings.language) {
                    ForEach(Language.allCases) { Text($0.label).tag($0) }
                }
            }

            Section {
                Toggle(L("Shake while dragging to open the menu", "Lắc file đang kéo để mở menu"), isOn: $settings.shakeEnabled)

                Picker(L("Hold key", "Giữ kèm phím"), selection: $settings.shakeModifier) {
                    ForEach(ModifierChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .disabled(!settings.shakeEnabled)

                // 10 mức: kéo sang trái = lắc nhẹ là mở, sang phải = phải lắc mạnh (đỡ mở nhầm)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L("Sensitivity", "Độ nhạy"))
                        Spacer()
                        Text("\(settings.shakeLevel)/10").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(get: { Double(settings.shakeLevel) }, set: { settings.shakeLevel = Int($0.rounded()) }),
                           in: Double(ShakeLevel.range.lowerBound)...Double(ShakeLevel.range.upperBound), step: 1) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text(L("Light", "Nhẹ")).font(.caption).foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text(L("Firm", "Mạnh")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(!settings.shakeEnabled)
            } header: {
                Text(L("Shake", "Lắc chuột"))
            }

            Section {
                Toggle(L("Use keyboard shortcut", "Dùng phím tắt"), isOn: $settings.hotKeyEnabled)

                LabeledContent(L("Shortcut", "Tổ hợp phím")) {
                    ShortcutRecorder(hotKey: $settings.hotKey)
                }
                .disabled(!settings.hotKeyEnabled)

                if let error = settings.hotKeyError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text(L("Keyboard shortcut", "Phím tắt"))
            } footer: {
                Text(L("While dragging: opens the menu. Otherwise: shows or hides the shelf.", "Đang kéo file: mở menu. Không kéo file: mở hoặc đóng khay."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(L("Compress", "Nén ảnh"), selection: $settings.compressLevel) {
                    ForEach(CompressLevel.allCases) { Text($0.label).tag($0) }
                }
                Picker(L("Shrink to fit", "Ép dung lượng"), selection: $settings.targetSizeKB) {
                    ForEach(Settings.targetSizeChoices, id: \.self) { Text(L("Under ", "Dưới ") + sizeLabel($0)).tag($0) }
                }
                Picker(L("Resize to", "Thu nhỏ còn"), selection: $settings.resizeEdge) {
                    ForEach(Settings.resizeEdgeChoices, id: \.self) { Text(L("\($0)px long side", "cạnh dài \($0)px")).tag($0) }
                }
                Text(L("Edited images are saved as new files. The originals are never changed.",
                       "Ảnh sau khi sửa được lưu thành file mới, ảnh gốc giữ nguyên."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L("Images", "Ảnh"))
            }

            Section {
                Picker(L("Extract with", "Giải nén bằng"), selection: $settings.extractor) {
                    Text(L("Ask me", "Hỏi mỗi lần")).tag("")
                    Text(L("SATF (built-in)", "SATF (có sẵn)")).tag(Archivers.builtin)
                    ForEach(Archivers.extractors) { Text($0.name).tag($0.id) }
                }
                Picker(L("Compress with", "Nén ZIP bằng"), selection: $settings.compressor) {
                    Text(L("SATF (built-in)", "SATF (có sẵn)")).tag(Archivers.builtin)
                    ForEach(Archivers.compressors) { Text($0.name).tag($0.id) }
                }
            } header: {
                Text(L("Archives", "Tệp nén"))
            }

            Section {
                LabeledContent(L("Excel & PowerPoint add-on", "Gói Excel & PowerPoint")) {
                    Button(L("Manage…", "Quản lý…")) { AddOnsWindowController.shared.show() }
                }
            } header: {
                Text(L("Add-ons", "Gói tải thêm"))
            }

            Section {
                Toggle(L("Open at login", "Mở cùng macOS"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            NSSound.beep()
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            } header: {
                Text(L("General", "Hệ thống"))
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, idealWidth: 460, maxWidth: .infinity, minHeight: 360, idealHeight: height, maxHeight: .infinity)
    }
}

/// Nút ghi phím tắt: bấm vào rồi nhấn tổ hợp phím mới (Esc để huỷ).
struct ShortcutRecorder: View {
    @Binding var hotKey: HotKey
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            if recording { stop() } else { start() }
        } label: {
            Text(recording ? L("Press keys…", "Nhấn tổ hợp phím…") : hotKey.display)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(minWidth: 130)
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        HotKeyManager.shared.suspended = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {           // Esc: huỷ
                stop()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            // Bắt buộc có ít nhất ⌘, ⌥ hoặc ⌃ để không chiếm phím gõ thường
            guard !flags.intersection([.command, .option, .control]).isEmpty else {
                NSSound.beep()
                return nil
            }
            hotKey = HotKey(keyCode: UInt32(event.keyCode),
                            carbonModifiers: HotKeyManager.carbonFlags(flags),
                            display: HotKeyManager.symbols(flags) + HotKeyManager.keyName(event))
            stop()
            return nil
        }
    }

    private func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        if recording {
            recording = false
            HotKeyManager.shared.suspended = false
        }
    }
}
