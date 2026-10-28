import AppKit

// App chạy nền (chỉ có icon trên menu bar, không hiện trên Dock)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
