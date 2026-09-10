import AppKit
import Carbon.HIToolbox

/// Carbon hot keys. They need no Accessibility permission and, unlike a window's
/// key handling, they fire whatever app is in front — which is what the overlay
/// needs, since a background app cannot hold focus reliably.
@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var installed = false

    private func install() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return noErr }
            MainActor.assumeIsolated { HotkeyCenter.shared.fire(id.id) }
            return noErr
        }, 1, &spec, nil, nil)
    }

    private func fire(_ id: UInt32) { handlers[id]?() }

    /// Returns a token to pass to `unregister`, or nil if the system refused.
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> UInt32? {
        install()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x414E_4E54), id: id)   // 'ANNT'
        guard RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr,
              let ref else { return nil }
        refs[id] = ref
        handlers[id] = handler
        return id
    }

    func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers.removeValue(forKey: id)
    }
}

/// Double-tap of a bare modifier. Carbon hot keys need a key code, so this is
/// the one thing that cannot go through `HotkeyCenter`: it watches
/// `flagsChanged`, which means the app needs Accessibility permission.
@MainActor
final class DoubleModifierTap {
    private let maxHold: TimeInterval = 0.35    // a tap, not a chord being held
    private let maxGap: TimeInterval = 0.40     // between the two taps

    private let handler: () -> Void
    private var monitors: [Any] = []
    private var pressedAt: TimeInterval?
    private var lastTapAt: TimeInterval?
    private var dirty = false                   // another key went down while ⌘ was held

    init(handler: @escaping () -> Void) {
        self.handler = handler
        // A global monitor sees other apps; a local one sees our own windows.
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        } as Any)
    }

    private func handle(_ event: NSEvent) {
        if event.type == .keyDown {
            dirty = true
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let onlyCommand = flags == .command
        let now = event.timestamp

        if onlyCommand {
            pressedAt = now
            dirty = false
            return
        }
        guard flags.isEmpty, let down = pressedAt else {
            pressedAt = nil
            return
        }
        pressedAt = nil
        guard !dirty, now - down <= maxHold else { return }

        if let last = lastTapAt, now - last <= maxGap {
            lastTapAt = nil
            handler()
        } else {
            lastTapAt = now
        }
    }

    /// True when the app may watch events. Passing `prompt` shows the system
    /// dialog offering to open System Settings.
    static func hasAccessibility(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }
}
