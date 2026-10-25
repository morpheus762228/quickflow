import Carbon.HIToolbox

private func quickFlowHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return noErr }
    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard status == noErr else { return status }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.dispatch(identifier.id)
    return noErr
}

final class HotKeyManager {
    private var handlerRef: EventHandlerRef?
    private var registrations: [UInt32: EventHotKeyRef?] = [:]
    private var actions: [UInt32: () -> Void] = [:]

    static let signature: OSType = 0x51464C57 // 'QFLW'

    init?() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            quickFlowHotKeyHandler,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard status == noErr else {
            NSLog("[QuickFlow] InstallEventHandler failed: \(status)")
            return nil
        }
        NSLog("[QuickFlow] hotkey handler installed")
    }

    deinit {
        for (_, reference) in registrations {
            if let reference {
                UnregisterEventHotKey(reference)
            }
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32, action: @escaping () -> Void) -> Bool {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: HotKeyManager.signature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr else {
            NSLog("[QuickFlow] RegisterEventHotKey id=\(id) key=\(keyCode) mods=\(modifiers) FAILED status=\(status)")
            return false
        }
        NSLog("[QuickFlow] RegisterEventHotKey id=\(id) key=\(keyCode) mods=\(modifiers) OK")
        registrations[id] = reference
        actions[id] = action
        return true
    }

    func dispatch(_ id: UInt32) {
        actions[id]?()
    }

    func unregister(id: UInt32) {
        if let reference = registrations.removeValue(forKey: id), let reference {
            UnregisterEventHotKey(reference)
        }
        actions.removeValue(forKey: id)
    }

    static var commandOption: UInt32 {
        UInt32(cmdKey | optionKey)
    }
}
