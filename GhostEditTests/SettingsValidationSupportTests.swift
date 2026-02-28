import XCTest
@testable import GhostEditCore

final class SettingsValidationSupportTests: XCTestCase {

    // MARK: - validateHotkeyKeyCode

    func testHotkeyKeyCodeNilFails() {
        let error = SettingsValidationSupport.validateHotkeyKeyCode(nil)
        XCTAssertNotNil(error)
        XCTAssertEqual(error?.title, "Hotkey key is required")
    }

    func testHotkeyKeyCodeValidPasses() {
        XCTAssertNil(SettingsValidationSupport.validateHotkeyKeyCode(14))
    }

    // MARK: - validateModel

    func testModelBothNilFails() {
        let error = SettingsValidationSupport.validateModel(selectedOptionValue: nil, customModel: "")
        XCTAssertNotNil(error)
        XCTAssertEqual(error?.title, "Model is required")
    }

    func testModelWithSelectedOptionPasses() {
        XCTAssertNil(SettingsValidationSupport.validateModel(selectedOptionValue: "gpt-4", customModel: ""))
    }

    func testModelWithCustomModelPasses() {
        XCTAssertNil(SettingsValidationSupport.validateModel(selectedOptionValue: nil, customModel: "custom-model"))
    }

    func testModelBothProvidedPasses() {
        XCTAssertNil(SettingsValidationSupport.validateModel(selectedOptionValue: "gpt-4", customModel: "custom"))
    }

    // MARK: - validateHotkeyModifiers

    func testHotkeyModifiersZeroFails() {
        let error = SettingsValidationSupport.validateHotkeyModifiers(0)
        XCTAssertNotNil(error)
        XCTAssertEqual(error?.title, "Local hotkey modifiers are required")
    }

    func testHotkeyModifiersNonZeroPasses() {
        XCTAssertNil(SettingsValidationSupport.validateHotkeyModifiers(256))
    }

    // MARK: - validateCloudHotkeyKeyCode

    func testCloudHotkeyKeyCodeNilFails() {
        let error = SettingsValidationSupport.validateCloudHotkeyKeyCode(nil)
        XCTAssertNotNil(error)
        XCTAssertEqual(error?.title, "Cloud hotkey key is required")
    }

    func testCloudHotkeyKeyCodeValidPasses() {
        XCTAssertNil(SettingsValidationSupport.validateCloudHotkeyKeyCode(14))
    }

    // MARK: - validateCloudHotkeyModifiers

    func testCloudHotkeyModifiersZeroFails() {
        let error = SettingsValidationSupport.validateCloudHotkeyModifiers(0)
        XCTAssertNotNil(error)
        XCTAssertEqual(error?.title, "Cloud hotkey modifiers are required")
    }

    func testCloudHotkeyModifiersNonZeroPasses() {
        XCTAssertNil(SettingsValidationSupport.validateCloudHotkeyModifiers(256))
    }

    // MARK: - validateHotkeysNotDuplicate

    func testDuplicateHotkeysFails() {
        let error = SettingsValidationSupport.validateHotkeysNotDuplicate(
            localKeyCode: 14, localModifiers: 256,
            cloudKeyCode: 14, cloudModifiers: 256
        )
        XCTAssertNotNil(error)
        XCTAssertEqual(error?.title, "Hotkeys must be different")
    }

    func testDifferentKeyCodesPasses() {
        XCTAssertNil(SettingsValidationSupport.validateHotkeysNotDuplicate(
            localKeyCode: 14, localModifiers: 256,
            cloudKeyCode: 15, cloudModifiers: 256
        ))
    }

    func testDifferentModifiersPasses() {
        XCTAssertNil(SettingsValidationSupport.validateHotkeysNotDuplicate(
            localKeyCode: 14, localModifiers: 256,
            cloudKeyCode: 14, cloudModifiers: 512
        ))
    }

    // MARK: - validateHistoryLimit

    func testHistoryLimitValid() {
        if case .success(let v) = SettingsValidationSupport.validateHistoryLimit("100") {
            XCTAssertEqual(v, 100)
        } else { XCTFail("Expected success") }
    }

    func testHistoryLimitZeroFails() {
        if case .failure(let e) = SettingsValidationSupport.validateHistoryLimit("0") {
            XCTAssertEqual(e.title, "History size is invalid")
        } else { XCTFail("Expected failure") }
    }

    func testHistoryLimitNegativeFails() {
        if case .failure = SettingsValidationSupport.validateHistoryLimit("-5") {
        } else { XCTFail("Expected failure") }
    }

    func testHistoryLimitNonNumericFails() {
        if case .failure = SettingsValidationSupport.validateHistoryLimit("abc") {
        } else { XCTFail("Expected failure") }
    }

    func testHistoryLimitEmptyFails() {
        if case .failure = SettingsValidationSupport.validateHistoryLimit("") {
        } else { XCTFail("Expected failure") }
    }

    // MARK: - validateTimeoutSeconds

    func testTimeoutValid() {
        if case .success(let v) = SettingsValidationSupport.validateTimeoutSeconds("30") {
            XCTAssertEqual(v, 30)
        } else { XCTFail("Expected success") }
    }

    func testTimeoutBoundary() {
        if case .success(let v) = SettingsValidationSupport.validateTimeoutSeconds("5") {
            XCTAssertEqual(v, 5)
        } else { XCTFail("Expected success") }
    }

    func testTimeoutTooLowFails() {
        if case .failure(let e) = SettingsValidationSupport.validateTimeoutSeconds("4") {
            XCTAssertEqual(e.title, "Timeout is invalid")
        } else { XCTFail("Expected failure") }
    }

    func testTimeoutNonNumericFails() {
        if case .failure = SettingsValidationSupport.validateTimeoutSeconds("abc") {
        } else { XCTFail("Expected failure") }
    }

    // MARK: - validateDiffPreviewDuration

    func testDurationValid() {
        if case .success(let v) = SettingsValidationSupport.validateDiffPreviewDuration("10") {
            XCTAssertEqual(v, 10)
        } else { XCTFail("Expected success") }
    }

    func testDurationLowerBound() {
        if case .success(let v) = SettingsValidationSupport.validateDiffPreviewDuration("1") {
            XCTAssertEqual(v, 1)
        } else { XCTFail("Expected success") }
    }

    func testDurationUpperBound() {
        if case .success(let v) = SettingsValidationSupport.validateDiffPreviewDuration("30") {
            XCTAssertEqual(v, 30)
        } else { XCTFail("Expected success") }
    }

    func testDurationTooLowFails() {
        if case .failure(let e) = SettingsValidationSupport.validateDiffPreviewDuration("0") {
            XCTAssertEqual(e.title, "Popup duration is invalid")
        } else { XCTFail("Expected failure") }
    }

    func testDurationTooHighFails() {
        if case .failure = SettingsValidationSupport.validateDiffPreviewDuration("31") {
        } else { XCTFail("Expected failure") }
    }

    func testDurationNonNumericFails() {
        if case .failure = SettingsValidationSupport.validateDiffPreviewDuration("abc") {
        } else { XCTFail("Expected failure") }
    }

    // MARK: - validateAll

    func testValidateAllSuccess() {
        let result = SettingsValidationSupport.validateAll(
            hotkeyKeyCode: 14, hotkeyModifiers: 256,
            cloudHotkeyKeyCode: 14, cloudHotkeyModifiers: 768,
            selectedOptionValue: "model", customModel: "claude-3",
            historyLimitText: "100", timeoutText: "30", diffPreviewDurationText: "5"
        )
        if case .success(let settings) = result {
            XCTAssertEqual(settings.hotkeyKeyCode, 14)
            XCTAssertEqual(settings.historyLimit, 100)
            XCTAssertEqual(settings.timeoutSeconds, 30)
            XCTAssertEqual(settings.diffPreviewDuration, 5)
        } else { XCTFail("Expected success") }
    }

    func testValidateAllFailsOnFirstError() {
        let result = SettingsValidationSupport.validateAll(
            hotkeyKeyCode: nil, hotkeyModifiers: 256,
            cloudHotkeyKeyCode: 14, cloudHotkeyModifiers: 256,
            selectedOptionValue: "model", customModel: "claude-3",
            historyLimitText: "100", timeoutText: "30", diffPreviewDurationText: "5"
        )
        if case .failure(let error) = result {
            XCTAssertEqual(error.title, "Hotkey key is required")
        } else { XCTFail("Expected failure") }
    }

    func testValidateAllFailsOnDuplicate() {
        let result = SettingsValidationSupport.validateAll(
            hotkeyKeyCode: 14, hotkeyModifiers: 256,
            cloudHotkeyKeyCode: 14, cloudHotkeyModifiers: 256,
            selectedOptionValue: "model", customModel: "claude-3",
            historyLimitText: "100", timeoutText: "30", diffPreviewDurationText: "5"
        )
        if case .failure(let error) = result {
            XCTAssertEqual(error.title, "Hotkeys must be different")
        } else { XCTFail("Expected failure") }
    }

    func testValidateAllFailsOnTimeout() {
        let result = SettingsValidationSupport.validateAll(
            hotkeyKeyCode: 14, hotkeyModifiers: 256,
            cloudHotkeyKeyCode: 15, cloudHotkeyModifiers: 256,
            selectedOptionValue: "model", customModel: "claude-3",
            historyLimitText: "100", timeoutText: "2", diffPreviewDurationText: "5"
        )
        if case .failure(let error) = result {
            XCTAssertEqual(error.title, "Timeout is invalid")
        } else { XCTFail("Expected failure") }
    }

    // MARK: - buildHotkeyModifiers / splitHotkeyModifiers

    func testBuildModifiersCommand() {
        let m = SettingsValidationSupport.buildHotkeyModifiers(command: true, option: false, control: false, shift: false)
        XCTAssertEqual(m, 1 << 8)
    }

    func testBuildModifiersOption() {
        let m = SettingsValidationSupport.buildHotkeyModifiers(command: false, option: true, control: false, shift: false)
        XCTAssertEqual(m, 1 << 11)
    }

    func testBuildModifiersControl() {
        let m = SettingsValidationSupport.buildHotkeyModifiers(command: false, option: false, control: true, shift: false)
        XCTAssertEqual(m, 1 << 12)
    }

    func testBuildModifiersShift() {
        let m = SettingsValidationSupport.buildHotkeyModifiers(command: false, option: false, control: false, shift: true)
        XCTAssertEqual(m, 1 << 9)
    }

    func testBuildModifiersAll() {
        let m = SettingsValidationSupport.buildHotkeyModifiers(command: true, option: true, control: true, shift: true)
        XCTAssertEqual(m, (1 << 8) | (1 << 11) | (1 << 12) | (1 << 9))
    }

    func testBuildModifiersNone() {
        let m = SettingsValidationSupport.buildHotkeyModifiers(command: false, option: false, control: false, shift: false)
        XCTAssertEqual(m, 0)
    }

    func testSplitModifiersRoundTrip() {
        let m = SettingsValidationSupport.buildHotkeyModifiers(command: true, option: false, control: true, shift: false)
        let (command, option, control, shift) = SettingsValidationSupport.splitHotkeyModifiers(m)
        XCTAssertTrue(command)
        XCTAssertFalse(option)
        XCTAssertTrue(control)
        XCTAssertFalse(shift)
    }

    func testSplitModifiersZero() {
        let (command, option, control, shift) = SettingsValidationSupport.splitHotkeyModifiers(0)
        XCTAssertFalse(command)
        XCTAssertFalse(option)
        XCTAssertFalse(control)
        XCTAssertFalse(shift)
    }

    func testSplitModifiersAll() {
        let all = SettingsValidationSupport.buildHotkeyModifiers(command: true, option: true, control: true, shift: true)
        let (command, option, control, shift) = SettingsValidationSupport.splitHotkeyModifiers(all)
        XCTAssertTrue(command)
        XCTAssertTrue(option)
        XCTAssertTrue(control)
        XCTAssertTrue(shift)
    }
}
