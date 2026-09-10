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

    private var hint: String {
        board.confirmingExit
            ? "Press Esc Again to Discard"
            : "Drag to Draw   ⌥ Drag to Erase   ⌘Z Undo   ⌘⌘ Clear   Esc Esc Discard"
    }

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

    init(screen: NSScreen) {
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
    private var escArmed = false
    private var escTimer: Timer?

    var isVisible: Bool { !windows.isEmpty }

    /// Opens the canvas, or clears it if it is already open. Closing is esc's
    /// job alone, so a stray double-tap cannot throw the drawing away.
    func summonOrClear() {
        guard isVisible else {
            show()
            return
        }
        disarmEscape()
        windows.forEach { $0.board.clear() }   // checkpointed, so ⌘Z brings it back
    }

    func show() {
        // Deliberately stays .accessory: switching to .regular puts an icon in
        // the Dock for as long as the canvas is up. The panel is
        // .nonactivatingPanel and the shortcuts are global hot keys, so neither
        // needs the app to be a regular one.
        let mouse = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            let window = OverlayWindow(screen: screen)
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
        ]
        hotkeyTokens = keys.compactMap { center.register(keyCode: $0.0, modifiers: $0.1, handler: $0.2) }
        if hotkeyTokens.count < keys.count {
            NSLog("annotated: only %d of %d overlay hot keys registered", hotkeyTokens.count, keys.count)
        }
    }

    /// Esc discards everything, so it takes two presses. The first arms it for
    /// two seconds and says so in the HUD; the second dismisses.
    func handleEscape() {
        if escArmed {
            dismiss()
            return
        }
        escArmed = true
        windows.forEach { $0.board.confirmingExit = true }
        escTimer?.invalidate()
        escTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { _ in
            MainActor.assumeIsolated { self.disarmEscape() }
        }
    }

    /// Whether the first esc has been seen. Read by the checks.
    var armedForTest: Bool { escArmed }

    /// The live canvases. Read by the checks.
    var windowsForTest: [OverlayWindow] { windows }

    private func disarmEscape() {
        escArmed = false
        escTimer?.invalidate()
        escTimer = nil
        windows.forEach { $0.board.confirmingExit = false }
    }

    /// The window under the pointer, which is the one the user is drawing on.
    private var activeWindow: OverlayWindow? {
        let mouse = NSEvent.mouseLocation
        return windows.first { $0.frame.contains(mouse) } ?? windows.first
    }

    private var activeBoard: Board? { activeWindow?.board }


    func dismiss() {
        guard !windows.isEmpty else { return }
        for window in windows + huds as [NSWindow] {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        huds.removeAll()
        disarmEscape()
        hotkeyTokens.forEach(HotkeyCenter.shared.unregister)
        hotkeyTokens.removeAll()
        NSApp.hide(nil)
    }

}
