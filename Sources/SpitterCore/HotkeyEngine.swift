import Foundation

public enum HotkeyIntent: Equatable, Sendable {
    case begin
    case commit
    case cancel
}

/// Pure state machine translating normalized key events into dictation intents.
///
/// Kept free of AppKit so every activation rule below is unit-testable; the adapter layer only has
/// to produce `KeyEventDescriptor`s and forward the returned intent.
public final class HotkeyEngine {
    /// Releases faster than this are treated as an accidental tap of the modifier rather than a
    /// deliberate (if very short) dictation, and cancel instead of committing.
    public static let minimumHoldSeconds: Double = 0.25

    public private(set) var binding: HotkeyBinding
    public private(set) var mode: ActivationMode

    private var isActive = false
    private var beganAt: Double = 0
    /// True once a hold was cancelled mid-press: further events are ignored until the key is released.
    private var awaitingRelease = false
    /// Hotkey key currently physically down — used to debounce auto-repeat in toggle mode.
    private var hotkeyKeyIsDown = false
    /// A non-modifier key was pressed while the bound modifier was down, so the modifier was being
    /// used as a modifier (⌘C) and must not toggle on release.
    private var modifierWasUsedAsModifier = false

    public init(binding: HotkeyBinding, mode: ActivationMode) {
        self.binding = binding
        self.mode = mode
    }

    /// Returns `.cancel` when the change interrupts an in-flight recording.
    public func setBinding(_ newBinding: HotkeyBinding) -> HotkeyIntent? {
        binding = newBinding
        return resetForConfigurationChange()
    }

    public func setMode(_ newMode: ActivationMode) -> HotkeyIntent? {
        mode = newMode
        return resetForConfigurationChange()
    }

    private func resetForConfigurationChange() -> HotkeyIntent? {
        let wasActive = isActive
        isActive = false
        awaitingRelease = false
        hotkeyKeyIsDown = false
        modifierWasUsedAsModifier = false
        return wasActive ? .cancel : nil
    }

    public func handle(_ event: KeyEventDescriptor, at time: Double) -> HotkeyIntent? {
        switch (binding.kind, mode) {
        case (.modifierOnly(let code), .hold):
            return handleModifierHold(event, at: time, code: code)
        case (.modifierOnly(let code), .toggle):
            return handleModifierToggle(event, code: code)
        case (.combo(let code, let mods), .hold):
            return handleComboHold(event, at: time, code: code, required: mods)
        case (.combo(let code, let mods), .toggle):
            return handleComboToggle(event, code: code, required: mods)
        }
    }

    private func finishHold(at time: Double) -> HotkeyIntent {
        isActive = false
        return time - beganAt < Self.minimumHoldSeconds ? .cancel : .commit
    }

    private func handleModifierHold(_ event: KeyEventDescriptor, at time: Double, code: UInt16) -> HotkeyIntent? {
        if event.isModifierEvent && event.keyCode == code {
            switch event.phase {
            case .down:
                guard !isActive, !awaitingRelease else { return nil }
                isActive = true
                beganAt = time
                return .begin
            case .up:
                awaitingRelease = false
                guard isActive else { return nil }
                return finishHold(at: time)
            }
        }
        // A real keystroke mid-hold means the modifier was being used as a modifier (Fn + arrow),
        // not as a push-to-talk key. Other modifier presses are harmless and ignored.
        if isActive, event.phase == .down, !event.isModifierEvent {
            isActive = false
            awaitingRelease = true
            return .cancel
        }
        return nil
    }

    private func handleModifierToggle(_ event: KeyEventDescriptor, code: UInt16) -> HotkeyIntent? {
        if event.isModifierEvent && event.keyCode == code {
            switch event.phase {
            case .down:
                hotkeyKeyIsDown = true
                modifierWasUsedAsModifier = false
                return nil
            case .up:
                let usedAlone = hotkeyKeyIsDown && !modifierWasUsedAsModifier
                hotkeyKeyIsDown = false
                modifierWasUsedAsModifier = false
                guard usedAlone else { return nil }
                isActive.toggle()
                return isActive ? .begin : .commit
            }
        }
        if hotkeyKeyIsDown, event.phase == .down, !event.isModifierEvent {
            modifierWasUsedAsModifier = true
        }
        return nil
    }

    private func handleComboHold(
        _ event: KeyEventDescriptor,
        at time: Double,
        code: UInt16,
        required: Modifiers
    ) -> HotkeyIntent? {
        if !event.isModifierEvent && event.keyCode == code {
            switch event.phase {
            case .down:
                guard !isActive, event.modifiers.isSuperset(of: required) else { return nil }
                isActive = true
                beganAt = time
                return .begin
            case .up:
                guard isActive else { return nil }
                return finishHold(at: time)
            }
        }
        // Letting go of one of the required modifiers ends the hold just like releasing the key.
        if isActive, event.isModifierEvent, !event.modifiers.isSuperset(of: required) {
            return finishHold(at: time)
        }
        return nil
    }

    private func handleComboToggle(
        _ event: KeyEventDescriptor,
        code: UInt16,
        required: Modifiers
    ) -> HotkeyIntent? {
        guard !event.isModifierEvent, event.keyCode == code else { return nil }
        switch event.phase {
        case .down:
            guard !hotkeyKeyIsDown, event.modifiers.isSuperset(of: required) else { return nil }
            hotkeyKeyIsDown = true
            isActive.toggle()
            return isActive ? .begin : .commit
        case .up:
            hotkeyKeyIsDown = false
            return nil
        }
    }
}
