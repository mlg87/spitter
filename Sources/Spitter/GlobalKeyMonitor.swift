import AppKit
import ApplicationServices
import Foundation
import SpitterCore

/// Watches system-wide key events and feeds them to the `HotkeyEngine`.
///
/// Uses `NSEvent` global monitors rather than a `CGEventTap`: a tap could swallow the hotkey's
/// keystroke, but it needs the separate Input Monitoring grant. One permission is the better trade
/// for v1, at the cost of combo hotkeys also reaching the frontmost app (documented in the README).
@MainActor
final class GlobalKeyMonitor {
    /// How often to re-check for the Accessibility grant while it is missing.
    private static let trustPollSeconds: Double = 3

    private let engine: HotkeyEngine
    private let onIntent: (HotkeyIntent) -> Void
    private var monitor: Any?
    private var pollTimer: Timer?

    /// Fires when Accessibility trust is granted, so the menu can drop its warning.
    var onTrustGained: (() -> Void)?

    init(engine: HotkeyEngine, onIntent: @escaping (HotkeyIntent) -> Void) {
        self.engine = engine
        self.onIntent = onIntent
    }

    /// Installs the monitor, or polls until Accessibility trust arrives and then installs it.
    func start() {
        guard monitor == nil else { return }
        guard AXIsProcessTrusted() else {
            startPollingForTrust()
            return
        }
        install()
    }

    private func startPollingForTrust() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.trustPollSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, AXIsProcessTrusted() else { return }
                self.pollTimer?.invalidate()
                self.pollTimer = nil
                self.install()
                self.onTrustGained?()
            }
        }
    }

    private func install() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func handle(_ event: NSEvent) {
        guard let descriptor = Self.describe(event) else { return }
        if let intent = engine.handle(descriptor, at: event.timestamp) {
            onIntent(intent)
        }
    }

    /// Translates an `NSEvent` into the engine's transport-free descriptor.
    ///
    /// `flagsChanged` carries no phase of its own: the key is going *down* when its own flag is
    /// present in the post-event modifier set, and coming *up* when it is not.
    static func describe(_ event: NSEvent) -> KeyEventDescriptor? {
        let modifiers = translate(event.modifierFlags)
        switch event.type {
        case .keyDown:
            return KeyEventDescriptor(
                phase: .down, keyCode: event.keyCode, isModifierEvent: false, modifiers: modifiers)
        case .keyUp:
            return KeyEventDescriptor(phase: .up, keyCode: event.keyCode, isModifierEvent: false, modifiers: modifiers)
        case .flagsChanged:
            guard let flag = ModifierKeyCodes.flags[event.keyCode] else { return nil }
            let phase: KeyPhase = modifiers.contains(flag) ? .down : .up
            return KeyEventDescriptor(phase: phase, keyCode: event.keyCode, isModifierEvent: true, modifiers: modifiers)
        default:
            return nil
        }
    }

    static func translate(_ flags: NSEvent.ModifierFlags) -> Modifiers {
        var modifiers: Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.function) { modifiers.insert(.function) }
        return modifiers
    }
}
