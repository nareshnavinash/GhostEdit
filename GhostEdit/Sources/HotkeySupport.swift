import Carbon.HIToolbox
import Foundation

struct HotkeyKeyOption: Equatable {
    let title: String
    let keyCode: UInt32
}

enum HotkeySupport {
    private static let commandMask = UInt32(cmdKey)
    private static let optionMask = UInt32(optionKey)
    private static let controlMask = UInt32(controlKey)
    private static let shiftMask = UInt32(shiftKey)

    static let keyOptions: [HotkeyKeyOption] = [
        HotkeyKeyOption(title: "A", keyCode: UInt32(kVK_ANSI_A)),
        HotkeyKeyOption(title: "B", keyCode: UInt32(kVK_ANSI_B)),
        HotkeyKeyOption(title: "C", keyCode: UInt32(kVK_ANSI_C)),
        HotkeyKeyOption(title: "D", keyCode: UInt32(kVK_ANSI_D)),
        HotkeyKeyOption(title: "E", keyCode: UInt32(kVK_ANSI_E)),
        HotkeyKeyOption(title: "F", keyCode: UInt32(kVK_ANSI_F)),
        HotkeyKeyOption(title: "G", keyCode: UInt32(kVK_ANSI_G)),
        HotkeyKeyOption(title: "H", keyCode: UInt32(kVK_ANSI_H)),
        HotkeyKeyOption(title: "I", keyCode: UInt32(kVK_ANSI_I)),
        HotkeyKeyOption(title: "J", keyCode: UInt32(kVK_ANSI_J)),
        HotkeyKeyOption(title: "K", keyCode: UInt32(kVK_ANSI_K)),
        HotkeyKeyOption(title: "L", keyCode: UInt32(kVK_ANSI_L)),
        HotkeyKeyOption(title: "M", keyCode: UInt32(kVK_ANSI_M)),
        HotkeyKeyOption(title: "N", keyCode: UInt32(kVK_ANSI_N)),
        HotkeyKeyOption(title: "O", keyCode: UInt32(kVK_ANSI_O)),
        HotkeyKeyOption(title: "P", keyCode: UInt32(kVK_ANSI_P)),
        HotkeyKeyOption(title: "Q", keyCode: UInt32(kVK_ANSI_Q)),
        HotkeyKeyOption(title: "R", keyCode: UInt32(kVK_ANSI_R)),
        HotkeyKeyOption(title: "S", keyCode: UInt32(kVK_ANSI_S)),
        HotkeyKeyOption(title: "T", keyCode: UInt32(kVK_ANSI_T)),
        HotkeyKeyOption(title: "U", keyCode: UInt32(kVK_ANSI_U)),
        HotkeyKeyOption(title: "V", keyCode: UInt32(kVK_ANSI_V)),
        HotkeyKeyOption(title: "W", keyCode: UInt32(kVK_ANSI_W)),
        HotkeyKeyOption(title: "X", keyCode: UInt32(kVK_ANSI_X)),
        HotkeyKeyOption(title: "Y", keyCode: UInt32(kVK_ANSI_Y)),
        HotkeyKeyOption(title: "Z", keyCode: UInt32(kVK_ANSI_Z)),
        HotkeyKeyOption(title: "0", keyCode: UInt32(kVK_ANSI_0)),
        HotkeyKeyOption(title: "1", keyCode: UInt32(kVK_ANSI_1)),
        HotkeyKeyOption(title: "2", keyCode: UInt32(kVK_ANSI_2)),
        HotkeyKeyOption(title: "3", keyCode: UInt32(kVK_ANSI_3)),
        HotkeyKeyOption(title: "4", keyCode: UInt32(kVK_ANSI_4)),
        HotkeyKeyOption(title: "5", keyCode: UInt32(kVK_ANSI_5)),
        HotkeyKeyOption(title: "6", keyCode: UInt32(kVK_ANSI_6)),
        HotkeyKeyOption(title: "7", keyCode: UInt32(kVK_ANSI_7)),
        HotkeyKeyOption(title: "8", keyCode: UInt32(kVK_ANSI_8)),
        HotkeyKeyOption(title: "9", keyCode: UInt32(kVK_ANSI_9))
    ]

    static var defaultKeyCode: UInt32 {
        UInt32(kVK_ANSI_E)
    }

    static func keyTitle(for keyCode: UInt32) -> String {
        keyOptions.first(where: { $0.keyCode == keyCode })?.title ?? "KeyCode \(keyCode)"
    }

    static func makeModifiers(command: Bool, option: Bool, control: Bool, shift: Bool) -> UInt32 {
        var modifiers: UInt32 = 0
        if command {
            modifiers |= commandMask
        }
        if option {
            modifiers |= optionMask
        }
        if control {
            modifiers |= controlMask
        }
        if shift {
            modifiers |= shiftMask
        }
        return modifiers
    }

    static func splitModifiers(_ modifiers: UInt32) -> (command: Bool, option: Bool, control: Bool, shift: Bool) {
        (
            command: modifiers & commandMask != 0,
            option: modifiers & optionMask != 0,
            control: modifiers & controlMask != 0,
            shift: modifiers & shiftMask != 0
        )
    }

    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        let split = splitModifiers(modifiers)

        if split.command {
            parts.append("Cmd")
        }
        if split.option {
            parts.append("Option")
        }
        if split.control {
            parts.append("Control")
        }
        if split.shift {
            parts.append("Shift")
        }

        parts.append(keyTitle(for: keyCode))
        return parts.joined(separator: "+")
    }
}
