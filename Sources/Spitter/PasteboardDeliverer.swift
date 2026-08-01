import AppKit
import ApplicationServices
import Foundation
import SpitterCore

/// Reads whatever currently owns keyboard focus, system-wide, via the Accessibility API.
enum FocusInspector {
    static func currentFocus() -> FocusedElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
            let focusedValue = focused
        else { return nil }

        // Force-cast is safe: the attribute is documented to return an AXUIElement.
        let element = focusedValue as! AXUIElement  // swift-format-ignore: NeverForceUnwrap

        var roleValue: CFTypeRef?
        let role =
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success
            ? roleValue as? String : nil

        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)

        return FocusedElement(role: role, valueSettable: settable.boolValue)
    }
}

/// Delivers text either by synthesizing ⌘V into the focused field or, when nothing text-editable is
/// focused, by leaving it on the clipboard for the user to paste.
final class PasteboardDeliverer: TextDelivering {
    /// Delay before the previous clipboard contents are put back. Long enough for the target app to
    /// service the paste, short enough that the user's own ⌘V still finds their data.
    private static let restoreDelay: Double = 0.5

    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func deliver(_ text: String) -> DeliveryOutcome {
        let route = DeliveryPolicy.decide(
            focus: FocusInspector.currentFocus(), accessibilityTrusted: AXIsProcessTrusted())
        switch route {
        case .clipboardOnly:
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return .copiedToClipboard
        case .paste:
            let snapshot = snapshotPasteboard()
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            postCommandV()
            let deferred = UncheckedBox((snapshot, pasteboard))
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.restoreDelay) {
                restore(deferred.value.0, into: deferred.value.1)
            }
            return .pasted
        }
    }

    private func snapshotPasteboard() -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { contents[type] = data }
            }
            return contents
        }
    }

    private func postCommandV() {
        let vKeyCode: CGKeyCode = 9  // kVK_ANSI_V
        guard
            let down = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

private func restore(_ snapshot: [[NSPasteboard.PasteboardType: Data]], into pasteboard: NSPasteboard) {
    pasteboard.clearContents()
    guard !snapshot.isEmpty else { return }
    let items = snapshot.map { contents -> NSPasteboardItem in
        let item = NSPasteboardItem()
        for (type, data) in contents { item.setData(data, forType: type) }
        return item
    }
    pasteboard.writeObjects(items)
}
