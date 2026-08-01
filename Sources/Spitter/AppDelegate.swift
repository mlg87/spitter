import AppKit
import Foundation
import SpitterCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: HotkeySettings!
    private var engine: HotkeyEngine!
    private var controller: DictationController!
    private var statusItem: StatusItemController!
    private var monitor: GlobalKeyMonitor!
    private let permissions = PermissionCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = HotkeySettings(store: UserDefaults.standard)
        engine = HotkeyEngine(binding: settings.binding, mode: settings.mode)

        controller = DictationController(
            makeSession: { AppleSpeechSession() },
            delivery: PasteboardDeliverer(),
            timers: DispatchTimers(),
            onStateChange: { [weak self] state in self?.statusItem.stateChanged(to: state) },
            onEvent: { [weak self] event in
                if case .failed(let message) = event { NSLog("Spitter: %@", message) }
                self?.statusItem.show(event)
            }
        )

        statusItem = StatusItemController(
            settings: settings,
            permissions: permissions,
            controller: controller,
            onBindingChange: { [weak self] binding in
                guard let self else { return }
                if let intent = engine.setBinding(binding) { controller.handle(intent) }
                statusItem.refresh()
            },
            onModeChange: { [weak self] mode in
                guard let self else { return }
                if let intent = engine.setMode(mode) { controller.handle(intent) }
                statusItem.refresh()
            }
        )

        permissions.onChange = { [weak self] in self?.statusItem.refresh() }
        permissions.requestAll()

        monitor = GlobalKeyMonitor(engine: engine) { [weak self] intent in
            self?.controller.handle(intent)
        }
        monitor.onTrustGained = { [weak self] in self?.statusItem.refresh() }
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
    }
}
