import AppKit
import ServiceManagement
import SpitterCore

/// Owns the menubar item: its icon (which mirrors the dictation state) and its menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    /// How long a delivery/failure icon stays up before falling back to the state icon.
    private static let flashSeconds: Double = 1.5

    private let statusItem: NSStatusItem
    private let settings: HotkeySettings
    private let permissions: PermissionCoordinator
    private let controller: DictationController
    private let onBindingChange: (HotkeyBinding) -> Void
    private let onModeChange: (ActivationMode) -> Void

    private var captureController: HotkeyCaptureController?
    private var flashResetItem: DispatchWorkItem?
    private var state: DictationController.State = .idle

    init(
        settings: HotkeySettings,
        permissions: PermissionCoordinator,
        controller: DictationController,
        onBindingChange: @escaping (HotkeyBinding) -> Void,
        onModeChange: @escaping (ActivationMode) -> Void
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.settings = settings
        self.permissions = permissions
        self.controller = controller
        self.onBindingChange = onBindingChange
        self.onModeChange = onModeChange
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        applyStateIcon()
    }

    // MARK: - State feedback

    func stateChanged(to newState: DictationController.State) {
        state = newState
        flashResetItem?.cancel()
        applyStateIcon()
    }

    func show(_ event: DictationController.Event) {
        switch event {
        case .delivered(.pasted): flash(GlyphColor.pasted)
        case .delivered(.copiedToClipboard): flash(GlyphColor.clipboard)
        case .emptyTranscript: flash(GlyphColor.empty)
        case .failed: flash(GlyphColor.failed)
        }
    }

    func refresh() {
        applyStateIcon()
    }

    /// `nil` means "render the adaptive template glyph", which is what idle uses so the menubar
    /// looks native at rest.
    private var stateColor: NSColor? {
        switch state {
        case .idle: return permissions.missing.isEmpty ? nil : GlyphColor.warning
        case .recording: return GlyphColor.recording
        case .transcribing: return GlyphColor.transcribing
        }
    }

    private func applyStateIcon() {
        setGlyph(stateColor)
    }

    private func setGlyph(_ color: NSColor?) {
        let image = MenubarGlyph.image(color: color)
        image.accessibilityDescription = "Spitter"
        statusItem.button?.image = image
    }

    private func flash(_ color: NSColor) {
        setGlyph(color)
        flashResetItem?.cancel()
        let reset = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.applyStateIcon() }
        }
        flashResetItem = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flashSeconds, execute: reset)
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let toggleTitle = state == .recording ? "Stop Dictation" : "Start Dictation"
        let toggle = menu.addItem(withTitle: toggleTitle, action: #selector(toggleDictation), keyEquivalent: "")
        toggle.target = self
        toggle.isEnabled = state != .transcribing

        menu.addItem(.separator())

        let info = menu.addItem(
            withTitle: "Hotkey: \(settings.binding.displayName) (\(settings.mode == .hold ? "hold" : "toggle"))",
            action: nil,
            keyEquivalent: ""
        )
        info.isEnabled = false

        let change = menu.addItem(
            withTitle: "Change Hotkey\u{2026}", action: #selector(changeHotkey), keyEquivalent: "")
        change.target = self

        let modeItem = menu.addItem(withTitle: "Mode", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        for (title, mode) in [("Hold to Talk", ActivationMode.hold), ("Press to Toggle", ActivationMode.toggle)] {
            let item = NSMenuItem(title: title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = settings.mode == mode ? .on : .off
            modeMenu.addItem(item)
        }
        modeItem.submenu = modeMenu

        let missing = permissions.missing
        if !missing.isEmpty {
            menu.addItem(.separator())
            for kind in missing {
                let item = menu.addItem(withTitle: kind.title, action: #selector(openPermission(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = kind
                item.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            }
        }

        menu.addItem(.separator())
        let launch = menu.addItem(
            withTitle: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = SMAppService.mainApp.status == .enabled ? .on : .off

        menu.addItem(.separator())
        let quit = menu.addItem(
            withTitle: "Quit Spitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
    }

    @objc private func toggleDictation() {
        controller.toggleFromMenu()
    }

    @objc private func changeHotkey() {
        let capture = HotkeyCaptureController { [weak self] binding in
            guard let self, let binding else {
                self?.captureController = nil
                return
            }
            settings.binding = binding
            onBindingChange(binding)
            captureController = nil
        }
        captureController = capture
        capture.begin()
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = ActivationMode(rawValue: raw) else { return }
        settings.mode = mode
        onModeChange(mode)
    }

    @objc private func openPermission(_ sender: NSMenuItem) {
        guard let kind = sender.representedObject as? PermissionKind else { return }
        permissions.openSettings(for: kind)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Spitter: launch-at-login change failed: \(error)")
        }
    }
}
