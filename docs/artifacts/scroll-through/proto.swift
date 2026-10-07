import AppKit
import QuartzCore
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let m = NSEvent.mouseLocation
let rect = NSRect(x: m.x - 100, y: m.y - 100, width: 200, height: 200)

// scrollee window under the overlay
let win = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
let sv = NSScrollView(frame: NSRect(origin: .zero, size: rect.size))
let doc = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 5000))
sv.documentView = doc
win.contentView = sv
win.orderFrontRegardless(); doc.scroll(NSPoint(x: 0, y: 2500))
sv.contentView.postsBoundsChangedNotifications = true
NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: sv.contentView, queue: nil) { _ in
    print("underneath scrolled y=\(sv.contentView.bounds.origin.y)"); fflush(stdout)
}

final class V: NSView {
    override func mouseDown(with event: NSEvent) { print("overlay got mouseDown"); fflush(stdout) }
    override func scrollWheel(with event: NSEvent) { print("overlay got scroll"); fflush(stdout) }
}
let overlay = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
overlay.level = .screenSaver
overlay.backgroundColor = NSColor.white.withAlphaComponent(1.0 / 255.0)
overlay.isOpaque = false
overlay.contentView = V(frame: NSRect(origin: .zero, size: rect.size))
overlay.orderFrontRegardless()
NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { e in print("mouseDown in \(e.window === overlay ? "overlay" : "underneath")"); fflush(stdout); return e }

let marker: Int64 = 0x616e6e6f
let types: [CGEventType] = [.scrollWheel, .leftMouseDown]
let mask = types.reduce(CGEventMask(0)) { $0 | 1 << $1.rawValue }
let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
    callback: { _, type, event, _ in
        print("tap saw \(type.rawValue) reposted=\(event.getIntegerValueField(.eventSourceUserData) == marker)"); fflush(stdout)
        guard event.getIntegerValueField(.eventSourceUserData) != marker else { return Unmanaged.passUnretained(event) }
        let want = type == .scrollWheel
        guard overlay.ignoresMouseEvents != want else { return Unmanaged.passUnretained(event) }
        overlay.ignoresMouseEvents = want; if CommandLine.arguments.contains("flush") { CATransaction.flush() }
        let copy = event.copy()!
        copy.setIntegerValueField(.eventSourceUserData, value: marker)
        let delay = Double(CommandLine.arguments.last!) ?? 0
        if CommandLine.arguments.contains("nudge") {
            let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: event.location, mouseButton: .left)!
            move.setIntegerValueField(.eventSourceUserData, value: marker)
            move.post(tap: .cghidEventTap)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { copy.post(tap: .cghidEventTap) }
        return nil
    }, userInfo: nil)
print("tap \(tap != nil)"); fflush(stdout)
if let tap { CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0)!, .commonModes) ; CGEvent.tapEnable(tap: tap, enable: true) }

DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    for i in 0..<3 {
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.25) {
            print("post \(i)"); fflush(stdout)
            CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 40, wheel2: 0, wheel3: 0)!.post(tap: .cghidEventTap)
            if i == 2 {
                let p = CGEvent(source: nil)!.location
                guard overlay.frame.contains(NSEvent.mouseLocation) else { print("cursor moved, no click"); return }
                CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
                CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
            }
        }
    }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { exit(0) }
app.run()
