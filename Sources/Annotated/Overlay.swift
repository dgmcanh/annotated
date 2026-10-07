import AppKit
import Carbon.HIToolbox
import SwiftUI

struct BoardView: View {
    @ObservedObject var board: Board

    var body: some View {
        Canvas { context, _ in
            for stroke in board.strokes {
                context.fill(stroke.path, with: .color(Color(nsColor: stroke.color)))
            }
            if !board.live.isEmpty {
                context.fill(freehandPath(board.live, width: board.width, finished: false),
                             with: .color(Color(nsColor: board.color)))
            }
        }
        .ignoresSafeArea()
    }
}

/// Owns pointer input. SwiftUI hit testing returns nil over transparent
/// content, which lets the click fall through to whatever app is underneath, so
/// the canvas claims every point itself and drives the board from AppKit mouse
/// events. Doing it here also samples the pointer at the event rate rather than
/// the rate a SwiftUI gesture reports.
final class CanvasHostingView: NSHostingView<BoardView> {
    private let board: Board

    init(board: Board) {
        self.board = board
        super.init(rootView: BoardView(board: board))
    }

    @available(*, unavailable) required init(rootView: BoardView) { fatalError() }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { self }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) { NSCursor.crosshair.set() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    private func location(of event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return isFlipped ? point : CGPoint(x: point.x, y: bounds.height - point.y)
    }

    var onScroll: ((NSEvent) -> Void)?

    override func scrollWheel(with event: NSEvent) { onScroll?(event) }

    override func mouseDown(with event: NSEvent) {
        NSCursor.crosshair.set()
        NSEvent.isMouseCoalescingEnabled = false   // denser samples make smoother ink
        board.beginInput(at: location(of: event), erasing: event.modifierFlags.contains(.option))
    }

    override func mouseDragged(with event: NSEvent) {
        board.extendInput(to: location(of: event))
    }

    override func mouseUp(with event: NSEvent) {
        board.endInput(at: location(of: event))
        NSEvent.isMouseCoalescingEnabled = true
    }
}

/// Border and key hints, in a window of its own so it can be left out of the
/// screenshot. Ignores the mouse; the canvas underneath gets every event.
struct HUDView: View {
    @ObservedObject var board: Board

    private let hint = "Drag to Draw   ⌥ Drag to Erase   ⌘Z Undo   ⌃⌃ Clear   Esc Discard"

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor.opacity(0.9), lineWidth: 4)


            Text(hint)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .modifier(GlassPill())
                .padding(.bottom, 12)
        }
        .ignoresSafeArea()
    }
}

/// Liquid Glass where the OS has it, a tinted capsule everywhere else.
struct GlassPill: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .foregroundStyle(.primary)
                .glassEffect(.regular, in: .capsule)
        } else {
            content
                .foregroundStyle(.white)
                .background(Capsule().fill(Color.accentColor.opacity(0.9)))
        }
    }
}

final class HUDWindow: NSWindow {
    init(screen: NSScreen, board: Board) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        contentView = NSHostingView(rootView: HUDView(board: board))
        setFrame(screen.frame, display: true)
    }
}

/// A non-activating panel, not a plain window. Under the cooperative
/// activation macOS 14 introduced, a background `.accessory` app cannot take
/// focus from the app in front, so `NSApp.activate` does nothing and an
/// ordinary window never becomes key: no mouse events, no key events. A panel
/// with `.nonactivatingPanel` takes both while the app stays in the background.
final class OverlayWindow: NSPanel {
    let board = Board()

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(screen: NSScreen, onScroll: @escaping (NSEvent) -> Void) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .screenSaver                    // above the menu bar and the Dock
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // Not .clear: the window server does not hit-test a fully transparent
        // window, so clicks fall through to the app underneath. One alpha step
        // out of 255 is enough to own the click and is invisible on screen.
        backgroundColor = NSColor.white.withAlphaComponent(1.0 / 255.0)
        isOpaque = false
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        worksWhenModal = true

        let hosting = CanvasHostingView(board: board)
        hosting.onScroll = onScroll
        hosting.frame = NSRect(origin: .zero, size: screen.frame.size)
        contentView = hosting
        setFrame(screen.frame, display: true)
    }

}

@MainActor
final class OverlayController {
    private var windows: [OverlayWindow] = []
    private var huds: [HUDWindow] = []
    private var hotkeyTokens: [UInt32] = []

    var isVisible: Bool { !windows.isEmpty }

    /// Opens the canvas, or clears it if it is already open. Closing is esc's
    /// job alone, so a stray double-tap cannot throw the drawing away.
    func summonOrClear() {
        guard isVisible else {
            show()
            return
        }
        windows.forEach { $0.board.clear() }   // checkpointed, so ⌘Z brings it back
    }

    func show() {
        // Deliberately stays .accessory: switching to .regular puts an icon in
        // the Dock for as long as the canvas is up. The panel is
        // .nonactivatingPanel and the shortcuts are global hot keys, so neither
        // needs the app to be a regular one.
        let mouse = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            let window = OverlayWindow(screen: screen) { [weak self] in self?.scrollLanded($0) }
            window.orderFrontRegardless()
            if screen.frame.contains(mouse) { window.makeKeyAndOrderFront(nil) }
            windows.append(window)
        }
        if windows.first(where: { $0.isKeyWindow }) == nil { windows.first?.makeKey() }
        for window in windows {
            guard let screen = window.screen else { continue }
            let hud = HUDWindow(screen: screen, board: window.board)
            hud.orderFrontRegardless()
            huds.append(hud)
        }
        NSApp.activate(ignoringOtherApps: true)
        registerOverlayHotkeys()
        installEventTap()
    }

    // MARK: - Scrolling through the canvas

    // The canvas owns every click, so the wheel never reaches the app
    // underneath. An event tap sees each scroll first and makes the canvas
    // click-through while the wheel turns, then claims the pointer back.
    // `ignoresMouseEvents` takes 5–60 ms to reach the window server and the
    // event that flips it has already been routed, so both directions replay
    // events: a scroll that still lands on the canvas, and a click that would
    // otherwise land on the app.

    private static let reposted: Int64 = 0x616e6e6f   // marks events this app posted itself
    private var eventTap: CFMachPort?
    private var claimBack: DispatchWorkItem?
    private var heldClicks: [CGEvent]?

    private var passesThrough = false {
        didSet { windows.forEach { $0.ignoresMouseEvents = passesThrough } }
    }

    /// Without Accessibility permission there is no tap and the wheel stays on
    /// the canvas, as it did before.
    private func installEventTap() {
        let types: [CGEventType] = [.scrollWheel, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | 1 << $1.rawValue }
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, info in
                let controller = Unmanaged<OverlayController>.fromOpaque(info!).takeUnretainedValue()
                return MainActor.assumeIsolated { controller.filter(type, event) }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
    }

    private func removeEventTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        eventTap = nil
        claimBack?.cancel()
        heldClicks = nil
        passesThrough = false
    }

    private func filter(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.reposted { return pass }

        if type == .scrollWheel {
            passesThrough = true
            claimBack?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.passesThrough = false }
            claimBack = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
            return pass
        }

        // A click while the canvas is still click-through: hold it and the
        // drag behind it until the canvas owns the pointer again, then replay.
        if heldClicks != nil {
            event.copy().map { heldClicks?.append($0) }
            return nil
        }
        guard passesThrough, type == .leftMouseDown, let copy = event.copy() else { return pass }
        claimBack?.cancel()
        passesThrough = false
        heldClicks = [copy]
        // 80 ms covers the slowest toggle measured; a click this soon after a scroll is rare.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, let held = self.heldClicks else { return }
            self.heldClicks = nil
            held.forEach(Self.repost)
        }
        return nil
    }

    /// A scroll that reached the canvas before it turned click-through. Sent
    /// again until it lands on the app, for half a second at most.
    private func scrollLanded(_ event: NSEvent) {
        guard passesThrough, ProcessInfo.processInfo.systemUptime - event.timestamp < 0.5,
              let copy = event.cgEvent?.copy() else { return }
        // Routing stamped the canvas into the copy; field 51 is the private
        // target-window field, and left set the copy goes straight back to the
        // canvas however long it waits. The two public fields are not enough.
        copy.setIntegerValueField(CGEventField(rawValue: 51)!, value: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { Self.repost(copy) }
    }

    private static func repost(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: reposted)
        event.post(tap: .cghidEventTap)
    }

    /// While the canvas is up its shortcuts are global. A background app cannot
    /// hold key focus reliably, and a shortcut that stops working once focus
    /// moves would leave the overlay with no way to close.
    private func registerOverlayHotkeys() {
        let center = HotkeyCenter.shared
        let cmd = UInt32(cmdKey), shift = UInt32(shiftKey)
        let keys: [(UInt32, UInt32, () -> Void)] = [
            (UInt32(kVK_Escape), 0, { [weak self] in self?.handleEscape() }),
            (UInt32(kVK_ANSI_Z), cmd, { [weak self] in self?.activeBoard?.undo() }),
            (UInt32(kVK_ANSI_Z), cmd | shift, { [weak self] in self?.activeBoard?.redo() }),
            (UInt32(kVK_ANSI_Q), cmd, { NSApp.terminate(nil) }),
        ]
        hotkeyTokens = keys.compactMap { center.register(keyCode: $0.0, modifiers: $0.1, handler: $0.2) }
        if hotkeyTokens.count < keys.count {
            NSLog("annotated: only %d of %d overlay hot keys registered", hotkeyTokens.count, keys.count)
        }
    }

    /// Esc discards everything and closes. One press.
    func handleEscape() { dismiss() }

    /// The live canvases. Read by the checks.
    var windowsForTest: [OverlayWindow] { windows }

    /// The window under the pointer, which is the one the user is drawing on.
    private var activeWindow: OverlayWindow? {
        let mouse = NSEvent.mouseLocation
        return windows.first { $0.frame.contains(mouse) } ?? windows.first
    }

    private var activeBoard: Board? { activeWindow?.board }


    func dismiss() {
        guard !windows.isEmpty else { return }
        removeEventTap()
        for window in windows + huds as [NSWindow] {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        huds.removeAll()
        hotkeyTokens.forEach(HotkeyCenter.shared.unregister)
        hotkeyTokens.removeAll()
        NSApp.hide(nil)
    }

}
