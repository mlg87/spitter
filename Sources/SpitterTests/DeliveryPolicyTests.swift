import SpitterCore

func runDeliveryPolicyTests() {
    test("without Accessibility trust everything goes to the clipboard") {
        let field = FocusedElement(role: "AXTextField", valueSettable: true)
        expectEqual(DeliveryPolicy.decide(focus: field, accessibilityTrusted: false), .clipboardOnly)
        expectEqual(DeliveryPolicy.decide(focus: nil, accessibilityTrusted: false), .clipboardOnly)
    }

    test("no focused element means clipboard only") {
        expectEqual(DeliveryPolicy.decide(focus: nil, accessibilityTrusted: true), .clipboardOnly)
    }

    test("a settable value pastes regardless of role") {
        let custom = FocusedElement(role: "AXUnknownWidget", valueSettable: true)
        expectEqual(DeliveryPolicy.decide(focus: custom, accessibilityTrusted: true), .paste)
    }

    test("known text roles paste even when the value is not settable") {
        for role in DeliveryPolicy.textRoles {
            let element = FocusedElement(role: role, valueSettable: false)
            expectEqual(DeliveryPolicy.decide(focus: element, accessibilityTrusted: true), .paste, role)
        }
    }

    test("web areas paste because browsers report them for contenteditable regions") {
        let webArea = FocusedElement(role: "AXWebArea", valueSettable: false)
        expectEqual(DeliveryPolicy.decide(focus: webArea, accessibilityTrusted: true), .paste)
    }

    test("non-text focus falls back to the clipboard") {
        expectEqual(
            DeliveryPolicy.decide(
                focus: FocusedElement(role: "AXButton", valueSettable: false), accessibilityTrusted: true),
            .clipboardOnly
        )
        expectEqual(
            DeliveryPolicy.decide(focus: FocusedElement(role: nil, valueSettable: false), accessibilityTrusted: true),
            .clipboardOnly
        )
    }
}
