/// Snapshot of whatever currently has keyboard focus, as reported by the Accessibility API.
public struct FocusedElement: Equatable, Sendable {
    public let role: String?
    public let valueSettable: Bool

    public init(role: String?, valueSettable: Bool) {
        self.role = role
        self.valueSettable = valueSettable
    }
}

public enum DeliveryRoute: Equatable, Sendable {
    case paste
    case clipboardOnly
}

public enum DeliveryPolicy {
    /// `AXWebArea` is included because browsers report it for contenteditable regions (Gmail,
    /// Notion) where the focused element itself has no settable value.
    public static let textRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXSearchField", "AXComboBox", "AXWebArea",
    ]

    /// Both synthesizing ⌘V and inspecting focus require Accessibility trust, so an untrusted
    /// process can only ever put the text on the clipboard.
    public static func decide(focus: FocusedElement?, accessibilityTrusted: Bool) -> DeliveryRoute {
        guard accessibilityTrusted, let focus else { return .clipboardOnly }
        if focus.valueSettable { return .paste }
        if let role = focus.role, textRoles.contains(role) { return .paste }
        return .clipboardOnly
    }
}
