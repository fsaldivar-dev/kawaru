import Carbon.HIToolbox

/// Keyboard shortcuts that work while another app (the video call) is in front. Registered through Carbon's
/// hot-key API, which needs no permission from the user.
final class Hotkeys {
    /// Called on the main thread with the identifier given to `register`.
    var onPress: ((Int) -> Void)?
    private var registered: [EventHotKeyRef] = []

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            if let context { Unmanaged<Hotkeys>.fromOpaque(context).takeUnretainedValue().onPress?(Int(pressed.id)) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    /// Returns false when the combination could not be taken (another app holds it).
    @discardableResult
    func register(id: Int, keyCode: Int, modifiers: Int) -> Bool {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: 0x4B57_5255 /* KWRU */, id: UInt32(id)),
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { registered.append(ref); return true }
        return false
    }
}

extension Effect {
    /// Control-Option and a digit: unlikely to clash, easy to hit without looking.
    var keyCode: Int {
        switch self {
        case .substitution: kVK_ANSI_1
        case .clones: kVK_ANSI_2
        case .away: kVK_ANSI_3
        case .question: kVK_ANSI_4
        case .confetti: kVK_ANSI_5
        case .breakTime: kVK_ANSI_6
        case .spotlight: kVK_ANSI_7
        }
    }

    var shortcut: String {
        switch self {
        case .substitution: "⌃⌥1"
        case .clones: "⌃⌥2"
        case .away: "⌃⌥3"
        case .question: "⌃⌥4"
        case .confetti: "⌃⌥5"
        case .breakTime: "⌃⌥6"
        case .spotlight: "⌃⌥7"
        }
    }
}
