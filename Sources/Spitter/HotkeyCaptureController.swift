import AppKit
import SpitterCore

/// Modal-ish panel that records the user's next keystroke and turns it into a `HotkeyBinding`.
///
/// A bare modifier press (flags go up, then back to empty with no key in between) becomes
/// `.modifierOnly`; anything else becomes a `.combo` with whatever modifiers were held.
@MainActor
final class HotkeyCaptureController {
    private let onFinish: (HotkeyBinding?) -> Void
    private var panel: NSPanel?
    private var monitor: Any?
    private var candidateModifierKey: UInt16?
    private var sawKeyDown = false

    init(onFinish: @escaping (HotkeyBinding?) -> Void) {
        self.onFinish = onFinish
    }

    func begin() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 110),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Set Spitter Hotkey"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.center()

        let label = NSTextField(
            labelWithString:
                "Press your new hotkey.\nA single modifier (Fn, \u{2325}, \u{2318}\u{2026}) works too. Esc cancels.")
        label.alignment = .center
        label.frame = NSRect(x: 20, y: 25, width: 320, height: 60)
        panel.contentView?.addSubview(label)

        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
            return nil  // swallow everything while capturing
        }
    }

    private func handle(_ event: NSEvent) {
        let modifiers = GlobalKeyMonitor.translate(event.modifierFlags)
        switch event.type {
        case .keyDown:
            if event.keyCode == 53 && modifiers.isEmpty {
                finish(nil)
                return
            }
            sawKeyDown = true
            finish(HotkeyBinding(kind: .combo(keyCode: event.keyCode, modifiers: modifiers)))
        case .flagsChanged:
            guard ModifierKeyCodes.flags[event.keyCode] != nil else { return }
            if modifiers.isEmpty {
                // All flags released: a bare modifier tap, provided no real key intervened.
                if let candidate = candidateModifierKey, !sawKeyDown {
                    finish(HotkeyBinding(kind: .modifierOnly(keyCode: candidate)))
                } else {
                    candidateModifierKey = nil
                    sawKeyDown = false
                }
            } else {
                candidateModifierKey = event.keyCode
            }
        default:
            break
        }
    }

    private func finish(_ binding: HotkeyBinding?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel?.orderOut(nil)
        panel = nil
        onFinish(binding)
    }
}
