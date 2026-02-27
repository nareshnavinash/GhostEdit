import Carbon.HIToolbox
import XCTest
@testable import GhostEditCore

final class HotkeySupportTests: XCTestCase {
    func testKeyTitleReturnsKnownAndFallbackValues() {
        XCTAssertEqual(HotkeySupport.keyTitle(for: UInt32(kVK_ANSI_E)), "E")
        XCTAssertEqual(HotkeySupport.keyTitle(for: 999), "KeyCode 999")
    }

    func testDefaultKeyCodeIsE() {
        XCTAssertEqual(HotkeySupport.defaultKeyCode, UInt32(kVK_ANSI_E))
    }

    func testMakeAndSplitModifiersRoundTrip() {
        let modifiers = HotkeySupport.makeModifiers(
            command: true,
            option: true,
            control: true,
            shift: false
        )

        let split = HotkeySupport.splitModifiers(modifiers)
        XCTAssertTrue(split.command)
        XCTAssertTrue(split.option)
        XCTAssertTrue(split.control)
        XCTAssertFalse(split.shift)
    }

    func testMakeModifiersCanReturnZero() {
        let modifiers = HotkeySupport.makeModifiers(
            command: false,
            option: false,
            control: false,
            shift: false
        )
        XCTAssertEqual(modifiers, 0)
    }

    func testDisplayStringIncludesModifiersAndKey() {
        let modifiers = HotkeySupport.makeModifiers(
            command: true,
            option: true,
            control: false,
            shift: true
        )

        let display = HotkeySupport.displayString(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: modifiers
        )

        XCTAssertEqual(display, "Cmd+Option+Shift+K")
    }

    func testDisplayStringWithoutModifiersShowsOnlyKey() {
        let display = HotkeySupport.displayString(
            keyCode: UInt32(kVK_ANSI_7),
            modifiers: 0
        )

        XCTAssertEqual(display, "7")
    }

    func testDisplayStringIncludesControlModifier() {
        let modifiers = HotkeySupport.makeModifiers(
            command: false,
            option: false,
            control: true,
            shift: false
        )

        let display = HotkeySupport.displayString(
            keyCode: UInt32(kVK_ANSI_D),
            modifiers: modifiers
        )

        XCTAssertEqual(display, "Control+D")
    }

    func testSymbolStringCmdE() {
        let modifiers = HotkeySupport.makeModifiers(command: true, option: false, control: false, shift: false)
        let result = HotkeySupport.symbolString(keyCode: UInt32(kVK_ANSI_E), modifiers: modifiers)
        XCTAssertEqual(result, "\u{2318}E")
    }

    func testSymbolStringCmdShiftE() {
        let modifiers = HotkeySupport.makeModifiers(command: true, option: false, control: false, shift: true)
        let result = HotkeySupport.symbolString(keyCode: UInt32(kVK_ANSI_E), modifiers: modifiers)
        XCTAssertEqual(result, "\u{21E7}\u{2318}E")
    }

    func testSymbolStringAllModifiers() {
        let modifiers = HotkeySupport.makeModifiers(command: true, option: true, control: true, shift: true)
        let result = HotkeySupport.symbolString(keyCode: UInt32(kVK_ANSI_E), modifiers: modifiers)
        XCTAssertEqual(result, "\u{2303}\u{2325}\u{21E7}\u{2318}E")
    }

    func testSymbolStringNoModifiers() {
        let result = HotkeySupport.symbolString(keyCode: UInt32(kVK_ANSI_E), modifiers: 0)
        XCTAssertEqual(result, "E")
    }

    func testKeyOptionsContainsAlphaNumericSet() {
        XCTAssertTrue(HotkeySupport.keyOptions.contains(where: { $0.title == "A" }))
        XCTAssertTrue(HotkeySupport.keyOptions.contains(where: { $0.title == "Z" }))
        XCTAssertTrue(HotkeySupport.keyOptions.contains(where: { $0.title == "0" }))
        XCTAssertTrue(HotkeySupport.keyOptions.contains(where: { $0.title == "9" }))
    }
}
