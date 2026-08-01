import Foundation

/// Modifier flags, normalized by the adapter layer so the engine never touches AppKit.
public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let control = Modifiers(rawValue: 1 << 2)
    public static let shift = Modifiers(rawValue: 1 << 3)
    public static let function = Modifiers(rawValue: 1 << 4)
}

public enum KeyPhase: Equatable, Sendable {
    case down
    case up
}

/// Everything the engine needs to know about a keyboard event. `isModifierEvent` is true when the
/// event came from `flagsChanged` rather than `keyDown`/`keyUp`, which is what lets the engine tell
/// "the user pressed Fn" apart from "the user pressed a key while Fn was down".
public struct KeyEventDescriptor: Equatable, Sendable {
    public let phase: KeyPhase
    public let keyCode: UInt16
    public let isModifierEvent: Bool
    public let modifiers: Modifiers

    public init(phase: KeyPhase, keyCode: UInt16, isModifierEvent: Bool, modifiers: Modifiers) {
        self.phase = phase
        self.keyCode = keyCode
        self.isModifierEvent = isModifierEvent
        self.modifiers = modifiers
    }
}

/// Virtual key codes for the modifier keys, kept in one place because both the engine's display
/// names and the adapter's `flagsChanged` translation need them.
public enum ModifierKeyCodes {
    public static let function: UInt16 = 63
    public static let leftCommand: UInt16 = 55
    public static let rightCommand: UInt16 = 54
    public static let leftOption: UInt16 = 58
    public static let rightOption: UInt16 = 61
    public static let leftControl: UInt16 = 59
    public static let rightControl: UInt16 = 62
    public static let leftShift: UInt16 = 56
    public static let rightShift: UInt16 = 60

    /// Which flag a modifier key code raises. Also doubles as the "is this a modifier key" test.
    public static let flags: [UInt16: Modifiers] = [
        function: .function,
        leftCommand: .command, rightCommand: .command,
        leftOption: .option, rightOption: .option,
        leftControl: .control, rightControl: .control,
        leftShift: .shift, rightShift: .shift,
    ]

    static let names: [UInt16: String] = [
        function: "Fn",
        leftCommand: "Left \u{2318}", rightCommand: "Right \u{2318}",
        leftOption: "Left \u{2325}", rightOption: "Right \u{2325}",
        leftControl: "Left \u{2303}", rightControl: "Right \u{2303}",
        leftShift: "Left \u{21E7}", rightShift: "Right \u{21E7}",
    ]
}

public struct HotkeyBinding: Codable, Equatable, Sendable {
    public enum Kind: Codable, Equatable, Sendable {
        /// A bare modifier press, e.g. Fn or Right Option. No other key involved.
        case modifierOnly(keyCode: UInt16)
        case combo(keyCode: UInt16, modifiers: Modifiers)
    }

    public let kind: Kind

    public init(kind: Kind) { self.kind = kind }

    /// Fn held down — the same default Wispr Flow ships with.
    public static let `default` = HotkeyBinding(kind: .modifierOnly(keyCode: ModifierKeyCodes.function))

    public var displayName: String {
        switch kind {
        case .modifierOnly(let keyCode):
            return ModifierKeyCodes.names[keyCode] ?? "Key \(keyCode)"
        case .combo(let keyCode, let modifiers):
            var prefix = ""
            if modifiers.contains(.function) { prefix += "fn" }
            if modifiers.contains(.control) { prefix += "\u{2303}" }
            if modifiers.contains(.option) { prefix += "\u{2325}" }
            if modifiers.contains(.shift) { prefix += "\u{21E7}" }
            if modifiers.contains(.command) { prefix += "\u{2318}" }
            return prefix + KeyNames.name(for: keyCode)
        }
    }
}

public enum ActivationMode: String, Codable, Sendable, CaseIterable {
    case hold
    case toggle
}

enum KeyNames {
    private static let table: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
        24: "=", 27: "-", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Escape",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        109: "F10", 111: "F12", 118: "F4", 120: "F2", 122: "F1",
        123: "\u{2190}", 124: "\u{2192}", 125: "\u{2193}", 126: "\u{2191}",
    ]

    static func name(for keyCode: UInt16) -> String {
        table[keyCode] ?? ModifierKeyCodes.names[keyCode] ?? "Key \(keyCode)"
    }
}

/// Storage seam so settings can be exercised without touching the real `UserDefaults` domain.
public protocol SettingsStore: AnyObject {
    func data(forKey key: String) -> Data?
    func setData(_ data: Data?, forKey key: String)
}

extension UserDefaults: SettingsStore {
    public func setData(_ data: Data?, forKey key: String) { set(data, forKey: key) }
}

/// Persisted hotkey configuration. Corrupt or missing values fall back to the defaults rather than
/// trapping — a bad plist must never stop the app from launching.
public final class HotkeySettings {
    public static let bindingKey = "hotkey_binding"
    public static let modeKey = "activation_mode"

    private let store: SettingsStore

    public var binding: HotkeyBinding {
        didSet { store.setData(try? JSONEncoder().encode(binding), forKey: Self.bindingKey) }
    }

    public var mode: ActivationMode {
        didSet { store.setData(Data(mode.rawValue.utf8), forKey: Self.modeKey) }
    }

    public init(store: SettingsStore) {
        self.store = store
        self.binding =
            store.data(forKey: Self.bindingKey)
            .flatMap { try? JSONDecoder().decode(HotkeyBinding.self, from: $0) } ?? .default
        self.mode =
            store.data(forKey: Self.modeKey)
            .flatMap { ActivationMode(rawValue: String(decoding: $0, as: UTF8.self)) } ?? .hold
    }
}
