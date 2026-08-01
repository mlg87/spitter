import Foundation
import SpitterCore

private let fnKey: UInt16 = 63
private let spaceKey: UInt16 = 49
private let leftArrow: UInt16 = 123

private func modDown(_ code: UInt16, _ mods: Modifiers) -> KeyEventDescriptor {
    KeyEventDescriptor(phase: .down, keyCode: code, isModifierEvent: true, modifiers: mods)
}

private func modUp(_ code: UInt16, _ mods: Modifiers = []) -> KeyEventDescriptor {
    KeyEventDescriptor(phase: .up, keyCode: code, isModifierEvent: true, modifiers: mods)
}

private func keyDown(_ code: UInt16, _ mods: Modifiers = []) -> KeyEventDescriptor {
    KeyEventDescriptor(phase: .down, keyCode: code, isModifierEvent: false, modifiers: mods)
}

private func keyUp(_ code: UInt16, _ mods: Modifiers = []) -> KeyEventDescriptor {
    KeyEventDescriptor(phase: .up, keyCode: code, isModifierEvent: false, modifiers: mods)
}

func runHotkeyEngineTests() {
    test("hold + modifier-only: press and hold begins, release commits") {
        let engine = HotkeyEngine(binding: .default, mode: .hold)
        expectEqual(engine.handle(modDown(fnKey, .function), at: 0), .begin)
        expectEqual(engine.handle(modUp(fnKey), at: 2.0), .commit)
    }

    test("hold + modifier-only: release inside the tap window cancels") {
        let engine = HotkeyEngine(binding: .default, mode: .hold)
        expectEqual(engine.handle(modDown(fnKey, .function), at: 10), .begin)
        expectEqual(engine.handle(modUp(fnKey), at: 10.2), .cancel)
    }

    test("hold + modifier-only: a real keyDown mid-hold cancels and the release is swallowed") {
        let engine = HotkeyEngine(binding: .default, mode: .hold)
        expectEqual(engine.handle(modDown(fnKey, .function), at: 0), .begin)
        expectEqual(engine.handle(keyDown(leftArrow, .function), at: 0.5), .cancel)
        expectNil(engine.handle(keyUp(leftArrow, .function), at: 0.6), "keyUp after cancel")
        expectNil(engine.handle(modUp(fnKey), at: 0.7), "release after cancel must not commit")
    }

    test("hold + modifier-only: clean restart after a cancel") {
        let engine = HotkeyEngine(binding: .default, mode: .hold)
        _ = engine.handle(modDown(fnKey, .function), at: 0)
        _ = engine.handle(keyDown(leftArrow, .function), at: 0.1)
        _ = engine.handle(modUp(fnKey), at: 0.2)
        expectEqual(engine.handle(modDown(fnKey, .function), at: 1.0), .begin)
        expectEqual(engine.handle(modUp(fnKey), at: 3.0), .commit)
    }

    test("hold + modifier-only: other modifiers held alongside do not cancel") {
        let engine = HotkeyEngine(binding: .default, mode: .hold)
        expectEqual(engine.handle(modDown(fnKey, .function), at: 0), .begin)
        expectNil(engine.handle(modDown(56, [.function, .shift]), at: 0.3), "shift press")
        expectEqual(engine.handle(modUp(fnKey), at: 1.0), .commit)
    }

    test("hold + combo: begins on matching keyDown, commits on keyUp") {
        let binding = HotkeyBinding(kind: .combo(keyCode: spaceKey, modifiers: [.control, .option]))
        let engine = HotkeyEngine(binding: binding, mode: .hold)
        expectNil(engine.handle(keyDown(spaceKey, [.control]), at: 0), "missing option modifier")
        expectEqual(engine.handle(keyDown(spaceKey, [.control, .option, .shift]), at: 1), .begin)
        expectEqual(engine.handle(keyUp(spaceKey, [.control, .option]), at: 3), .commit)
    }

    test("hold + combo: dropping a required modifier commits") {
        let binding = HotkeyBinding(kind: .combo(keyCode: spaceKey, modifiers: [.control, .option]))
        let engine = HotkeyEngine(binding: binding, mode: .hold)
        expectEqual(engine.handle(keyDown(spaceKey, [.control, .option]), at: 0), .begin)
        expectEqual(engine.handle(modUp(58, [.control]), at: 2), .commit)
    }

    test("hold + combo: auto-repeat keyDowns and other keys are ignored while held") {
        let binding = HotkeyBinding(kind: .combo(keyCode: spaceKey, modifiers: [.control]))
        let engine = HotkeyEngine(binding: binding, mode: .hold)
        expectEqual(engine.handle(keyDown(spaceKey, [.control]), at: 0), .begin)
        expectNil(engine.handle(keyDown(spaceKey, [.control]), at: 0.1), "auto-repeat")
        expectNil(engine.handle(keyDown(leftArrow, [.control]), at: 0.2), "unrelated key")
        expectEqual(engine.handle(keyUp(spaceKey, [.control]), at: 1), .commit)
    }

    test("hold + combo: tap shorter than the minimum hold cancels") {
        let binding = HotkeyBinding(kind: .combo(keyCode: spaceKey, modifiers: [.control]))
        let engine = HotkeyEngine(binding: binding, mode: .hold)
        expectEqual(engine.handle(keyDown(spaceKey, [.control]), at: 5), .begin)
        expectEqual(engine.handle(keyUp(spaceKey, [.control]), at: 5.1), .cancel)
    }

    test("toggle + combo: press starts, next press commits, repeats debounced") {
        let binding = HotkeyBinding(kind: .combo(keyCode: spaceKey, modifiers: [.control, .option]))
        let engine = HotkeyEngine(binding: binding, mode: .toggle)
        expectEqual(engine.handle(keyDown(spaceKey, [.control, .option]), at: 0), .begin)
        expectNil(engine.handle(keyDown(spaceKey, [.control, .option]), at: 0.05), "auto-repeat")
        _ = engine.handle(keyUp(spaceKey, [.control, .option]), at: 0.1)
        expectNil(engine.handle(keyUp(spaceKey, [.control, .option]), at: 0.1), "keyUp emits nothing")
        expectEqual(engine.handle(keyDown(spaceKey, [.control, .option]), at: 4), .commit)
    }

    test("toggle + combo: no minimum hold, a quick tap still starts") {
        let binding = HotkeyBinding(kind: .combo(keyCode: spaceKey, modifiers: []))
        let engine = HotkeyEngine(binding: binding, mode: .toggle)
        expectEqual(engine.handle(keyDown(spaceKey, []), at: 0), .begin)
        _ = engine.handle(keyUp(spaceKey, []), at: 0.01)
        expectEqual(engine.handle(keyDown(spaceKey, []), at: 0.02), .commit)
    }

    test("toggle + modifier-only: fires on release when the modifier was used alone") {
        let engine = HotkeyEngine(binding: .default, mode: .toggle)
        expectNil(engine.handle(modDown(fnKey, .function), at: 0), "no intent on press")
        expectEqual(engine.handle(modUp(fnKey), at: 0.1), .begin)
        _ = engine.handle(modDown(fnKey, .function), at: 5)
        expectEqual(engine.handle(modUp(fnKey), at: 5.1), .commit)
    }

    test("toggle + modifier-only: modifier used as a modifier does not toggle") {
        let binding = HotkeyBinding(kind: .modifierOnly(keyCode: 55))
        let engine = HotkeyEngine(binding: binding, mode: .toggle)
        _ = engine.handle(modDown(55, .command), at: 0)
        expectNil(engine.handle(keyDown(8, .command), at: 0.1), "cmd-C")
        expectNil(engine.handle(keyUp(8, .command), at: 0.2), "cmd-C release")
        expectNil(engine.handle(modUp(55), at: 0.3), "command release must not toggle")
    }

    test("changing the binding while recording cancels") {
        let engine = HotkeyEngine(binding: .default, mode: .hold)
        expectEqual(engine.handle(modDown(fnKey, .function), at: 0), .begin)
        expectEqual(engine.setBinding(HotkeyBinding(kind: .modifierOnly(keyCode: 61))), .cancel)
        expectNil(engine.handle(modUp(fnKey), at: 1), "old binding is dead")
        expectEqual(engine.handle(modDown(61, .option), at: 2), .begin)
    }

    test("changing the mode while recording cancels; idle change is silent") {
        let engine = HotkeyEngine(binding: .default, mode: .hold)
        expectNil(engine.setMode(.toggle), "idle mode change")
        _ = engine.handle(modDown(fnKey, .function), at: 0)
        expectEqual(engine.handle(modUp(fnKey), at: 0.1), .begin)
        expectEqual(engine.setMode(.hold), .cancel)
    }

    test("binding display names cover modifiers, combos, and unknown keys") {
        expectEqual(HotkeyBinding.default.displayName, "Fn")
        expectEqual(HotkeyBinding(kind: .modifierOnly(keyCode: 61)).displayName, "Right \u{2325}")
        expectEqual(
            HotkeyBinding(kind: .combo(keyCode: spaceKey, modifiers: [.control, .option])).displayName,
            "\u{2303}\u{2325}Space"
        )
        expectEqual(HotkeyBinding(kind: .combo(keyCode: 200, modifiers: [])).displayName, "Key 200")
    }

    test("settings round-trip through the store and survive corruption") {
        let store = InMemorySettingsStore()
        let settings = HotkeySettings(store: store)
        expectEqual(settings.binding, .default)
        expectEqual(settings.mode, .hold)

        let custom = HotkeyBinding(kind: .combo(keyCode: spaceKey, modifiers: [.control]))
        settings.binding = custom
        settings.mode = .toggle

        let reloaded = HotkeySettings(store: store)
        expectEqual(reloaded.binding, custom)
        expectEqual(reloaded.mode, .toggle)

        store.setData(Data("not json".utf8), forKey: "hotkey_binding")
        store.setData(Data("nonsense".utf8), forKey: "activation_mode")
        let recovered = HotkeySettings(store: store)
        expectEqual(recovered.binding, .default, "corrupt binding falls back")
        expectEqual(recovered.mode, .hold, "corrupt mode falls back")
    }
}

/// Test double for `SettingsStore`; the app uses the `UserDefaults` conformance.
final class InMemorySettingsStore: SettingsStore {
    private var storage: [String: Data] = [:]
    func data(forKey key: String) -> Data? { storage[key] }
    func setData(_ data: Data?, forKey key: String) { storage[key] = data }
}
