import Carbon.HIToolbox

final class HotkeyManager {
    /// Handler receives a variant ID: 0 = base hotkey, 1 = shift variant.
    typealias Handler = (Int) -> Void

    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var handler: Handler?

    private let signature: OSType = 0x47534544 // "GSED"

    deinit {
        unregister()
    }

    func registerDefault(handler: @escaping Handler) {
        registerWithVariant(
            keyCode: UInt32(kVK_ANSI_E),
            modifiers: UInt32(cmdKey),
            handler: handler
        )
    }

    /// Registers the base hotkey (variant 0) and auto-derives a Shift variant (variant 1).
    func registerWithVariant(keyCode: UInt32, modifiers: UInt32, handler: @escaping Handler) {
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

                guard status == noErr else {
                    return noErr
                }

                // Variant 0 uses id=1, variant 1 uses id=2
                let variant = Int(hotKeyID.id) - 1
                guard variant == 0 || variant == 1 else {
                    return noErr
                }

                manager.handler?(variant)
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

        // Register base hotkey (variant 0, id=1)
        let baseID = EventHotKeyID(signature: signature, id: 1)
        var baseRef: EventHotKeyRef?
        let baseStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            baseID,
            GetEventDispatcherTarget(),
            0,
            &baseRef
        )
        if baseStatus == noErr, let ref = baseRef {
            hotKeyRefs[1] = ref
        }

        // Register shift variant (variant 1, id=2) — base modifiers + Shift
        let shiftModifiers = modifiers | UInt32(shiftKey)
        let shiftID = EventHotKeyID(signature: signature, id: 2)
        var shiftRef: EventHotKeyRef?
        let shiftStatus = RegisterEventHotKey(
            keyCode,
            shiftModifiers,
            shiftID,
            GetEventDispatcherTarget(),
            0,
            &shiftRef
        )
        if shiftStatus == noErr, let ref = shiftRef {
            hotKeyRefs[2] = ref
        }

        // If neither registered, clean up
        if hotKeyRefs.isEmpty {
            unregister()
        }
    }

    /// Registers two fully independent hotkeys with separate key codes and modifiers.
    func registerDual(
        localKeyCode: UInt32, localModifiers: UInt32,
        cloudKeyCode: UInt32, cloudModifiers: UInt32,
        handler: @escaping Handler
    ) {
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

                guard status == noErr else {
                    return noErr
                }

                let variant = Int(hotKeyID.id) - 1
                guard variant == 0 || variant == 1 else {
                    return noErr
                }

                manager.handler?(variant)
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

        // Register local hotkey (variant 0, id=1)
        let localID = EventHotKeyID(signature: signature, id: 1)
        var localRef: EventHotKeyRef?
        let localStatus = RegisterEventHotKey(
            localKeyCode,
            localModifiers,
            localID,
            GetEventDispatcherTarget(),
            0,
            &localRef
        )
        if localStatus == noErr, let ref = localRef {
            hotKeyRefs[1] = ref
        }

        // Register cloud hotkey (variant 1, id=2)
        let cloudID = EventHotKeyID(signature: signature, id: 2)
        var cloudRef: EventHotKeyRef?
        let cloudStatus = RegisterEventHotKey(
            cloudKeyCode,
            cloudModifiers,
            cloudID,
            GetEventDispatcherTarget(),
            0,
            &cloudRef
        )
        if cloudStatus == noErr, let ref = cloudRef {
            hotKeyRefs[2] = ref
        }

        if hotKeyRefs.isEmpty {
            unregister()
        }
    }

    /// Legacy single-hotkey registration (always fires variant 0).
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        registerWithVariant(keyCode: keyCode, modifiers: modifiers) { _ in
            handler()
        }
    }

    func unregister() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}
