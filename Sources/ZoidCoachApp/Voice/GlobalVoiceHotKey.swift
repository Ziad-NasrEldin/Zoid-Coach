import Carbon
import Foundation

enum VoiceHotKeyPreset: String, CaseIterable, Identifiable {
    case controlOptionSpace
    case commandShiftSpace

    var id: String { rawValue }
    var label: String {
        switch self {
        case .controlOptionSpace: "Control-Option-Space"
        case .commandShiftSpace: "Command-Shift-Space"
        }
    }
    var keyCode: UInt32 { UInt32(kVK_Space) }
    var modifiers: UInt32 {
        switch self {
        case .controlOptionSpace: UInt32(controlKey | optionKey)
        case .commandShiftSpace: UInt32(cmdKey | shiftKey)
        }
    }
}

@MainActor
final class GlobalVoiceHotKey {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: (() -> Void)?

    func register(preset: VoiceHotKeyPreset = .controlOptionSpace, action: @escaping () -> Void) throws {
        unregister()
        self.action = action
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, context in
                guard let context else { return noErr }
                let owner = Unmanaged<GlobalVoiceHotKey>.fromOpaque(context).takeUnretainedValue()
                Task { @MainActor in owner.action?() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard status == noErr else { throw GlobalVoiceHotKeyError.registration(status) }
        let identifier = EventHotKeyID(signature: 0x5A4F4944, id: 1)
        let registration = RegisterEventHotKey(
            preset.keyCode,
            preset.modifiers,
            identifier,
            GetEventDispatcherTarget(),
            0,
            &hotKey
        )
        guard registration == noErr else {
            unregister()
            throw GlobalVoiceHotKeyError.registration(registration)
        }
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKey = nil
        eventHandler = nil
        action = nil
    }

}

enum GlobalVoiceHotKeyError: LocalizedError {
    case registration(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .registration(status): "Could not register the Zoid voice shortcut (\(status))."
        }
    }
}
