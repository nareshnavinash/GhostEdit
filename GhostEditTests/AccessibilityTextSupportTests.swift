import XCTest
@testable import GhostEditCore

private final class StubAXProvider: AXElementProviding {
    var focusResult: AXError = .success
    var selectedTextResult: AXError = .success
    var setResult: AXError = .success
    var selectedText: String?
    private(set) var lastSetText: String?
    private(set) var lastSetAttribute: String?

    func createApplication(_ pid: pid_t) -> AXUIElement {
        AXUIElementCreateSystemWide()
    }

    func copyAttribute(_ element: AXUIElement, _ attribute: String) -> (AXError, CFTypeRef?) {
        if attribute == (kAXFocusedUIElementAttribute as String) {
            if focusResult != .success {
                return (focusResult, nil)
            }
            // Return a valid AXUIElement as the "focused element".
            let placeholder: AXUIElement = AXUIElementCreateSystemWide()
            return (.success, placeholder)
        }

        if attribute == (kAXSelectedTextAttribute as String) {
            if selectedTextResult != .success {
                return (selectedTextResult, nil)
            }
            if let text = selectedText {
                return (.success, text as CFTypeRef)
            }
            return (.success, nil)
        }

        return (.failure, nil)
    }

    func setAttribute(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> AXError {
        lastSetAttribute = attribute
        lastSetText = value as? String
        return setResult
    }
}

final class AccessibilityTextSupportTests: XCTestCase {

    // MARK: - readSelectedText

    func testReadSelectedTextReturnsTextWhenAvailable() {
        let provider = StubAXProvider()
        provider.selectedText = "Hello world"

        let result = AccessibilityTextSupport.readSelectedText(appPID: 1, provider: provider)
        XCTAssertEqual(result, "Hello world")
    }

    func testReadSelectedTextTrimsWhitespace() {
        let provider = StubAXProvider()
        provider.selectedText = "  trimmed text  \n"

        let result = AccessibilityTextSupport.readSelectedText(appPID: 1, provider: provider)
        XCTAssertEqual(result, "trimmed text")
    }

    func testReadSelectedTextReturnsNilWhenTextIsWhitespaceOnly() {
        let provider = StubAXProvider()
        provider.selectedText = "   \n\t  "

        let result = AccessibilityTextSupport.readSelectedText(appPID: 1, provider: provider)
        XCTAssertNil(result)
    }

    func testReadSelectedTextReturnsNilWhenFocusedElementFails() {
        let provider = StubAXProvider()
        provider.focusResult = .cannotComplete
        provider.selectedText = "should not reach this"

        let result = AccessibilityTextSupport.readSelectedText(appPID: 1, provider: provider)
        XCTAssertNil(result)
    }

    func testReadSelectedTextReturnsNilWhenSelectedTextAttributeFails() {
        let provider = StubAXProvider()
        provider.selectedTextResult = .attributeUnsupported
        provider.selectedText = nil

        let result = AccessibilityTextSupport.readSelectedText(appPID: 1, provider: provider)
        XCTAssertNil(result)
    }

    func testReadSelectedTextReturnsNilWhenTextIsNotAString() {
        let provider = StubAXProvider()
        // selectedText is nil, so copyAttribute returns (success, nil) for the text attribute.
        provider.selectedText = nil

        let result = AccessibilityTextSupport.readSelectedText(appPID: 1, provider: provider)
        XCTAssertNil(result)
    }

    // MARK: - replaceSelectedText

    func testReplaceSelectedTextReturnsTrueOnSuccess() {
        let provider = StubAXProvider()

        let result = AccessibilityTextSupport.replaceSelectedText(
            appPID: 1,
            with: "corrected",
            provider: provider
        )

        XCTAssertTrue(result)
        XCTAssertEqual(provider.lastSetText, "corrected")
        XCTAssertEqual(provider.lastSetAttribute, kAXSelectedTextAttribute as String)
    }

    func testReplaceSelectedTextReturnsFalseWhenFocusedElementFails() {
        let provider = StubAXProvider()
        provider.focusResult = .cannotComplete

        let result = AccessibilityTextSupport.replaceSelectedText(
            appPID: 1,
            with: "corrected",
            provider: provider
        )

        XCTAssertFalse(result)
        XCTAssertNil(provider.lastSetText)
    }

    func testReplaceSelectedTextReturnsFalseWhenSetAttributeFails() {
        let provider = StubAXProvider()
        provider.setResult = .attributeUnsupported

        let result = AccessibilityTextSupport.replaceSelectedText(
            appPID: 1,
            with: "corrected",
            provider: provider
        )

        XCTAssertFalse(result)
    }

    // MARK: - SystemAXElementProvider

    func testSystemProviderCreateApplicationReturnsElement() {
        let provider = SystemAXElementProvider()
        let element = provider.createApplication(1)
        // AXUIElementCreateApplication always succeeds; just verify it doesn't crash.
        XCTAssertNotNil(element)
    }

    func testSystemProviderCopyAttributeExecutesWithoutCrash() {
        let provider = SystemAXElementProvider()
        let element = AXUIElementCreateSystemWide()
        let (error, _) = provider.copyAttribute(element, kAXFocusedUIElementAttribute as String)
        // System-wide element doesn't have a focused UI element; expect a non-success error.
        // We only need the code to execute for coverage.
        XCTAssertNotEqual(error, .success)
    }

    func testSystemProviderSetAttributeExecutesWithoutCrash() {
        let provider = SystemAXElementProvider()
        let element = AXUIElementCreateSystemWide()
        let error = provider.setAttribute(element, kAXSelectedTextAttribute as String, "test" as CFTypeRef)
        // Setting on system-wide element without permission should fail.
        XCTAssertNotEqual(error, .success)
    }
}
