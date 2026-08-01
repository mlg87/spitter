import AVFoundation
import AppKit
import ApplicationServices
import Foundation
import Speech

/// The three TCC grants Spitter needs, plus deep links to the panes that grant them.
enum PermissionKind: CaseIterable {
    case microphone
    case speechRecognition
    case accessibility

    var title: String {
        switch self {
        case .microphone: return "Microphone access needed"
        case .speechRecognition: return "Speech Recognition access needed"
        // Spelled out because the common failure is not a missing grant but a stale one: macOS
        // still shows Spitter ticked after an update, while TCC has silently stopped honouring it.
        case .accessibility: return "Accessibility needed \u{2014} remove & re-add Spitter"
        }
    }

    var settingsURL: URL? {
        let anchor: String
        switch self {
        case .microphone: anchor = "Privacy_Microphone"
        case .speechRecognition: anchor = "Privacy_SpeechRecognition"
        case .accessibility: anchor = "Privacy_Accessibility"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }
}

@MainActor
final class PermissionCoordinator {
    /// Called whenever a grant lands so the menu can drop its warning items.
    var onChange: (() -> Void)?

    var microphoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    var speechGranted: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    var missing: [PermissionKind] {
        PermissionKind.allCases.filter { kind in
            switch kind {
            case .microphone: return !microphoneGranted
            case .speechRecognition: return !speechGranted
            case .accessibility: return !accessibilityGranted
            }
        }
    }

    /// Prompts for everything at launch. Accessibility cannot be granted from a prompt, so the
    /// system dialog only points the user at System Settings; `GlobalKeyMonitor` polls for the grant.
    func requestAll() {
        // These completions are marked `@Sendable` on purpose: without it they would inherit this
        // type's `@MainActor` isolation, and Speech/AVFoundation invoke them on a background queue,
        // which trips the Swift 6 executor assertion and kills the app at launch.
        let coordinator = UncheckedBox(self)
        SFSpeechRecognizer.requestAuthorization { @Sendable _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { coordinator.value.onChange?() } }
        }
        AVCaptureDevice.requestAccess(for: .audio) { @Sendable _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { coordinator.value.onChange?() } }
        }
        // Literal rather than `kAXTrustedCheckOptionPrompt`, which is an unsafe global under Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openSettings(for kind: PermissionKind) {
        guard let url = kind.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }
}
