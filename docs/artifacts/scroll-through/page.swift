import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screen = NSScreen.screens[0].frame
let rect = NSRect(x: screen.midX - 300, y: screen.midY - 300, width: 600, height: 600)
let win = NSWindow(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: false)
win.title = "page"
let sv = NSTextView.scrollableTextView()
let tv = sv.documentView as! NSTextView
tv.font = .monospacedSystemFont(ofSize: 18, weight: .regular)
let wide = CommandLine.arguments.contains("wide")
tv.string = (1...400).map { n in "line \(n)" + (wide ? (1...40).map { " col\($0)" }.joined() : "") }.joined(separator: "\n")
if wide {
    sv.hasHorizontalScroller = true
    tv.isHorizontallyResizable = true
    tv.maxSize = NSSize(width: 1e6, height: 1e6)
    tv.textContainer!.widthTracksTextView = false
    tv.textContainer!.containerSize = NSSize(width: 1e6, height: 1e6)
}
win.contentView = sv
win.orderFrontRegardless()
sv.contentView.postsBoundsChangedNotifications = true
NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: sv.contentView, queue: nil) { _ in
    print("page x=\(sv.contentView.bounds.origin.x) y=\(sv.contentView.bounds.origin.y)"); fflush(stdout)
}
NotificationCenter.default.addObserver(forName: NSTextView.didChangeSelectionNotification, object: tv, queue: nil) { _ in
    print("page selection \(tv.selectedRange())"); fflush(stdout)
}
print("ready"); fflush(stdout)
app.run()
