import Carbon.HIToolbox

final class HotkeyManager {
    typealias Handler = () -> Void

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handler: Handler?

    private let hotKeyIdentifier: UInt32 = 1
    private let signature: OSType = 0x47465852 // "GFXR"

    deinit {
        unregister()
    }

    func registerDefault(handler: @escaping Handler) {
        register(
            keyCode: UInt32(kVK_ANSI_E),
            modifiers: UInt32(cmdKey),
            handler: handler
        )
    }

    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping Handler) {
        unregister()
        self.handler = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, eventRef, userData in
                guard let userData, let eventRef else {
                    return noErr
                }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()

                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr, hotKeyID.id == manager.hotKeyIdentifier else {
                    return noErr
                }

                manager.handler?()
                return noErr
            },
            1,
            &eventType,
            context,
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            return
        }

        let eventHotKeyID = EventHotKeyID(signature: signature, id: hotKeyIdentifier)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            eventHotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus != noErr {
            unregister()
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}
