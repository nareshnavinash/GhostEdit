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

    static func readFullText(
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
            kAXValueAttribute as String
        )
        guard textResult == .success, let text = textValue as? String else {
            return nil
        }

        return text.isEmpty ? nil : text
    }

    static func readCursorPosition(
        appPID: pid_t,
        provider: AXElementProviding = SystemAXElementProvider()
    ) -> Int? {
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

        let (rangeResult, rangeValue) = provider.copyAttribute(
            focusedElement,
            kAXSelectedTextRangeAttribute as String
        )
        guard rangeResult == .success, let axValue = rangeValue else {
            return nil
        }

        var cfRange = CFRange(location: 0, length: 0)
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(axValue as! AXValue, .cfRange, &cfRange) else {
            return nil
        }

        return cfRange.location
    }

    static func setCursorPosition(
        appPID: pid_t,
        position: Int,
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

        var cfRange = CFRange(location: position, length: 0)
        // swiftlint:disable:next force_unwrapping
        let rangeValue = AXValueCreate(.cfRange, &cfRange)!

        let result = provider.setAttribute(
            focusedElement,
            kAXSelectedTextRangeAttribute as String,
            rangeValue
        )
        return result == .success
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

    static func replaceTextAtRange(
        appPID: pid_t,
        range: CFRange,
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

        var cfRange = range
        // swiftlint:disable:next force_unwrapping
        let rangeValue = AXValueCreate(.cfRange, &cfRange)!

        let rangeResult = provider.setAttribute(
            focusedElement,
            kAXSelectedTextRangeAttribute as String,
            rangeValue
        )
        guard rangeResult == .success else {
            return false
        }

        let textResult = provider.setAttribute(
            focusedElement,
            kAXSelectedTextAttribute as String,
            text as CFTypeRef
        )
        return textResult == .success
    }
}
