import AppKit

/// Phát hiện cử chỉ "giữ chuột + lắc qua lại".
/// Không cần quyền Accessibility: chỉ theo dõi sự kiện chuột (không theo dõi bàn phím)
/// và đọc vị trí con trỏ / trạng thái phím giữ kèm hiện tại.
final class ShakeDetector {
    /// Gọi ngay khi người dùng nhấn chuột trái (ở bất kỳ app nào).
    var onMouseDown: (() -> Void)?
    /// Gọi khi phát hiện đủ số lần lắc trong lúc vẫn đang giữ chuột.
    var onShake: (() -> Void)?

    private let window: TimeInterval = 0.9      // các lần đổi chiều phải nằm trong khoảng này (giây)

    private var mouseDownMonitor: Any?
    private var timer: Timer?
    private var direction = 0                   // -1: sang trái, 1: sang phải, 0: chưa rõ
    private var extremeX: CGFloat = 0           // điểm xa nhất theo chiều hiện tại
    private var reversals: [TimeInterval] = []
    private var firedThisHold = false

    func start() {
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.beginTracking()
        }
    }

    private func beginTracking() {
        onMouseDown?()
        timer?.invalidate()
        timer = nil
        guard Settings.shared.shakeEnabled else { return }

        direction = 0
        reversals.removeAll()
        firedThisHold = false
        extremeX = NSEvent.mouseLocation.x

        // Chỉ lấy mẫu vị trí chuột trong lúc đang giữ chuột, ~60 lần/giây.
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        // Nhả chuột -> dừng theo dõi
        if NSEvent.pressedMouseButtons & 1 == 0 {
            timer?.invalidate()
            timer = nil
            return
        }
        guard !firedThisHold else { return }

        let settings = Settings.shared
        let minSwing = settings.sensitivity.minSwing
        let x = NSEvent.mouseLocation.x
        let now = ProcessInfo.processInfo.systemUptime
        let dx = x - extremeX

        if direction == 0 {
            if abs(dx) >= minSwing {
                direction = dx > 0 ? 1 : -1
                extremeX = x
            }
            return
        }

        if CGFloat(direction) * dx > 0 {
            // Vẫn đi tiếp cùng chiều: cập nhật điểm xa nhất
            extremeX = x
        } else if abs(dx) >= minSwing {
            // Đổi chiều đủ xa: tính là một nhịp lắc
            direction = -direction
            extremeX = x
            reversals.append(now)
            reversals.removeAll { now - $0 > window }

            if reversals.count >= settings.sensitivity.reversals {
                reversals.removeAll()
                if let flag = settings.shakeModifier.flag, !NSEvent.modifierFlags.contains(flag) { return }
                firedThisHold = true
                onShake?()
            }
        }
    }
}
