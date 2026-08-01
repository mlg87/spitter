import AppKit

// Menubar-only app: no Dock icon, no main window (LSUIElement in Info.plist).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
