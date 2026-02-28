import Foundation

enum SettingsValidationSupport {
    struct ValidationError: Error, Equatable {
        let title: String
        let message: String
    }

    struct ValidatedSettings: Equatable {
        let hotkeyKeyCode: UInt32
        let hotkeyModifiers: UInt32
        let cloudHotkeyKeyCode: UInt32
        let cloudHotkeyModifiers: UInt32
        let model: String
        let historyLimit: Int
        let timeoutSeconds: Int
        let diffPreviewDuration: Int
    }

    static func validateHotkeyKeyCode(_ keyCode: UInt32?) -> ValidationError? {
        if keyCode == nil {
            return ValidationError(
                title: "Hotkey key is required",
                message: "Choose a hotkey key before saving."
            )
        }
        return nil
    }

    static func validateModel(selectedOptionValue: String?, customModel: String) -> ValidationError? {
        if selectedOptionValue == nil && customModel.isEmpty {
            return ValidationError(
                title: "Model is required",
                message: "Choose a model or enter a custom model name."
            )
        }
        return nil
    }

    static func validateHotkeyModifiers(_ modifiers: UInt32) -> ValidationError? {
        if modifiers == 0 {
            return ValidationError(
                title: "Local hotkey modifiers are required",
                message: "Select at least one modifier key (Command, Option, Control, or Shift) for the local hotkey."
            )
        }
        return nil
    }

    static func validateCloudHotkeyKeyCode(_ keyCode: UInt32?) -> ValidationError? {
        if keyCode == nil {
            return ValidationError(
                title: "Cloud hotkey key is required",
                message: "Choose a key for the cloud hotkey before saving."
            )
        }
        return nil
    }

    static func validateCloudHotkeyModifiers(_ modifiers: UInt32) -> ValidationError? {
        if modifiers == 0 {
            return ValidationError(
                title: "Cloud hotkey modifiers are required",
                message: "Select at least one modifier key (Command, Option, Control, or Shift) for the cloud hotkey."
            )
        }
        return nil
    }

    static func validateHotkeysNotDuplicate(
        localKeyCode: UInt32,
        localModifiers: UInt32,
        cloudKeyCode: UInt32,
        cloudModifiers: UInt32
    ) -> ValidationError? {
        if localKeyCode == cloudKeyCode && localModifiers == cloudModifiers {
            return ValidationError(
                title: "Hotkeys must be different",
                message: "The local and cloud hotkeys cannot use the same key combination."
            )
        }
        return nil
    }

    static func validateHistoryLimit(_ text: String) -> Result<Int, ValidationError> {
        guard let limit = Int(text), limit > 0 else {
            return .failure(ValidationError(
                title: "History size is invalid",
                message: "Enter a whole number greater than 0 for History N."
            ))
        }
        return .success(limit)
    }

    static func validateTimeoutSeconds(_ text: String) -> Result<Int, ValidationError> {
        guard let seconds = Int(text), seconds >= 5 else {
            return .failure(ValidationError(
                title: "Timeout is invalid",
                message: "Enter a whole number of at least 5 for Timeout (seconds)."
            ))
        }
        return .success(seconds)
    }

    static func validateDiffPreviewDuration(_ text: String) -> Result<Int, ValidationError> {
        guard let duration = Int(text), duration >= 1, duration <= 30 else {
            return .failure(ValidationError(
                title: "Popup duration is invalid",
                message: "Enter a whole number between 1 and 30 for popup duration."
            ))
        }
        return .success(duration)
    }

    /// Run all validations in order, returning the first error or the validated settings.
    static func validateAll(
        hotkeyKeyCode: UInt32?,
        hotkeyModifiers: UInt32,
        cloudHotkeyKeyCode: UInt32?,
        cloudHotkeyModifiers: UInt32,
        selectedOptionValue: String?,
        customModel: String,
        historyLimitText: String,
        timeoutText: String,
        diffPreviewDurationText: String
    ) -> Result<ValidatedSettings, ValidationError> {
        if let error = validateHotkeyKeyCode(hotkeyKeyCode) { return .failure(error) }
        if let error = validateModel(selectedOptionValue: selectedOptionValue, customModel: customModel) { return .failure(error) }
        if let error = validateHotkeyModifiers(hotkeyModifiers) { return .failure(error) }
        if let error = validateCloudHotkeyKeyCode(cloudHotkeyKeyCode) { return .failure(error) }
        if let error = validateCloudHotkeyModifiers(cloudHotkeyModifiers) { return .failure(error) }
        if let error = validateHotkeysNotDuplicate(
            localKeyCode: hotkeyKeyCode!, localModifiers: hotkeyModifiers,
            cloudKeyCode: cloudHotkeyKeyCode!, cloudModifiers: cloudHotkeyModifiers
        ) { return .failure(error) }

        let historyLimit: Int
        switch validateHistoryLimit(historyLimitText) {
        case .success(let v): historyLimit = v
        case .failure(let e): return .failure(e)
        }
        let timeoutSeconds: Int
        switch validateTimeoutSeconds(timeoutText) {
        case .success(let v): timeoutSeconds = v
        case .failure(let e): return .failure(e)
        }
        let diffPreviewDuration: Int
        switch validateDiffPreviewDuration(diffPreviewDurationText) {
        case .success(let v): diffPreviewDuration = v
        case .failure(let e): return .failure(e)
        }

        return .success(ValidatedSettings(
            hotkeyKeyCode: hotkeyKeyCode!,
            hotkeyModifiers: hotkeyModifiers,
            cloudHotkeyKeyCode: cloudHotkeyKeyCode!,
            cloudHotkeyModifiers: cloudHotkeyModifiers,
            model: customModel,
            historyLimit: historyLimit,
            timeoutSeconds: timeoutSeconds,
            diffPreviewDuration: diffPreviewDuration
        ))
    }

    /// Build hotkey modifier bitmask from individual checkbox states.
    static func buildHotkeyModifiers(command: Bool, option: Bool, control: Bool, shift: Bool) -> UInt32 {
        var modifiers: UInt32 = 0
        if command { modifiers |= (1 << 8) }
        if option { modifiers |= (1 << 11) }
        if control { modifiers |= (1 << 12) }
        if shift { modifiers |= (1 << 9) }
        return modifiers
    }

    /// Split a hotkey modifier bitmask into individual checkbox states.
    static func splitHotkeyModifiers(_ modifiers: UInt32) -> (command: Bool, option: Bool, control: Bool, shift: Bool) {
        return (
            command: (modifiers & (1 << 8)) != 0,
            option: (modifiers & (1 << 11)) != 0,
            control: (modifiers & (1 << 12)) != 0,
            shift: (modifiers & (1 << 9)) != 0
        )
    }
}
