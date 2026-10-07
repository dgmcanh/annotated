import CoreGraphics
import Foundation
let main = CGDisplayBounds(CGMainDisplayID())
let env = ProcessInfo.processInfo.environment
let c = CGPoint(x: env["CX"].flatMap(Double.init) ?? main.midX, y: env["CY"].flatMap(Double.init) ?? main.midY)
func post(_ e: CGEvent) { e.post(tap: .cghidEventTap) }
func mouse(_ t: CGEventType, _ p: CGPoint) { post(CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)!) }
func stroke(from a: CGPoint, dx: CGFloat) {
    mouse(.leftMouseDown, a)
    for i in 1...20 { usleep(8_000); mouse(.leftMouseDragged, CGPoint(x: a.x + dx * CGFloat(i) / 20, y: a.y)) }
    mouse(.leftMouseUp, CGPoint(x: a.x + dx, y: a.y))
}
func scroll(_ px: Int32, times: Int) {
    for _ in 0..<times { post(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: px, wheel2: 0, wheel3: 0)!); usleep(16_000) }
}
func shot(_ name: String) { let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); p.arguments = ["-x", "-R\(Int(c.x) - 300),\(Int(c.y) - 300),600,600", name]; try! p.run(); p.waitUntilExit() }
let step = CommandLine.arguments[1]
switch step {
case "move": mouse(.mouseMoved, c)
case "draw": stroke(from: CGPoint(x: c.x - 100, y: c.y), dx: 200)
case "scroll": scroll(-20, times: 10)            // 200 px down the page
case "fastclick": scroll(-20, times: 3); usleep(30_000); stroke(from: CGPoint(x: c.x - 100, y: c.y + 60), dx: 200)
case "scrollup": scroll(20, times: 10)
case "hscroll": for _ in 0..<10 { post(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: -20, wheel3: 0)!); usleep(16_000) }
case "shot": shot(CommandLine.arguments[2])
default: break
}
