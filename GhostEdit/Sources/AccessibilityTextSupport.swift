import ApplicationServices

protocol AXElementProviding {
    func createApplication(_ pid: pid_t) -> AXUIElement
    func copyAttribute(_ element: AXUIElement, _ attribute: String) -> (AXError, CFTypeRef?)
    func setAttribute(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> AXError
}

struct SystemAXElementProvider: AXElementProviding {
    func createApplication(_ pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    func copyAttribute(_ element: AXUIElement, _ attribute: String) -> (AXError, CFTypeRef?) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (error, value)
    }

    func setAttribute(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(element, attribute as CFString, value)
    }
}

enum AccessibilityTextSupport {
    static func readSelectedText(
        appPID: pid_t,
        provider: AXElementProviding = SystemAXElementProvider()
    ) -> String? {
        let appElement = provider.createApplication(appPID)

        let (focusResult, focusedValue) = provider.copyAttribute(
            appElement,
            kAXFocusedUIElementAttribute as String
        )
        guard focusResult == .success, let focused = focusedValue else {
            return nil
        }

        // swiftlint:disable:next force_cast
        let focusedElement = focused as! AXUIElement

        let (textResult, textValue) = provider.copyAttribute(
            focusedElement,
            kAXSelectedTextAttribute as String
        )
        guard textResult == .success, let text = textValue as? String else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func replaceSelectedText(
        appPID: pid_t,
        with text: String,
        provider: AXElementProviding = SystemAXElementProvider()
    ) -> Bool {
        let appElement = provider.createApplication(appPID)

        let (focusResult, focusedValue) = provider.copyAttribute(
            appElement,
            kAXFocusedUIElementAttribute as String
        )
        guard focusResult == .success, let focused = focusedValue else {
            return false
        }

        // swiftlint:disable:next force_cast
        let focusedElement = focused as! AXUIElement

        let result = provider.setAttribute(
            focusedElement,
            kAXSelectedTextAttribute as String,
            text as CFTypeRef
        )
        return result == .success
    }
}
