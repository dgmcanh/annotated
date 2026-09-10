import AppKit
import SwiftUI
import Carbon.HIToolbox

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String) {
    print("\(ok ? "PASS" : "FAIL")  \(name)  — \(detail)")
    if !ok { failures += 1 }
}

func render(_ strokes: [Stroke], _ size: CGSize, _ file: String) {
    let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fill(CGRect(origin: .zero, size: size))
    ctx.translateBy(x: 0, y: size.height)
    ctx.scaleBy(x: 1, y: -1)   // canvas uses a top-left origin
    for s in strokes {
        ctx.addPath(s.path.cgPath)
        ctx.setFillColor(s.color.cgColor)
        ctx.fillPath()
    }
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: file))
}

func keyEvent(_ chars: String, _ flags: NSEvent.ModifierFlags, keyCode: UInt16) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                     windowNumber: 0, context: nil, characters: chars,
                     charactersIgnoringModifiers: chars, isARepeat: false, keyCode: keyCode)!
}

func wave(_ x0: CGFloat, _ y0: CGFloat, _ n: Int) -> [CGPoint] {
    (0...n).map { CGPoint(x: x0 + CGFloat($0) * 8, y: y0 + 40 * sin(CGFloat($0) / 5)) }
}

MainActor.assumeIsolated {
    let screen = NSScreen.screens[0]
    let window = OverlayWindow(screen: screen)
    let board = window.board

    // --- drawing + undo/redo -------------------------------------------------
    board.commit(Stroke(points: wave(60, 100, 40), color: .systemRed, width: 2, finished: true))
    board.commit(Stroke(points: wave(60, 220, 40), color: .systemRed, width: 2, finished: true))
    let afterDraw = board.strokes.count
    render(board.strokes, CGSize(width: 460, height: 320), "run/01-two-strokes.png")
    check("C1 two drags commit two strokes", afterDraw == 2, "strokes before=0 after=\(afterDraw)")

    board.undo()
    let afterUndo = board.strokes.count
    render(board.strokes, CGSize(width: 460, height: 320), "run/02-after-undo.png")
    check("C2 undo removes the last stroke", afterUndo == 1, "strokes \(afterDraw) -> \(afterUndo)")

    board.redo()
    let afterRedo = board.strokes.count
    check("C3 redo puts it back", afterRedo == 2, "strokes \(afterUndo) -> \(afterRedo)")

    // --- eraser --------------------------------------------------------------
    board.beginErase()
    board.erase(at: CGPoint(x: 60, y: 100))     // on the first stroke
    board.erase(at: CGPoint(x: 100, y: 220 + 40 * sin(5.0 / 5)))   // on the second, same drag
    board.endErase()
    let afterErase = board.strokes.count
    render(board.strokes, CGSize(width: 460, height: 320), "run/03-after-erase.png")
    check("C4 one drag erases both strokes it touches", afterErase == 0, "strokes \(afterRedo) -> \(afterErase)")

    board.undo()
    let afterEraseUndo = board.strokes.count
    render(board.strokes, CGSize(width: 460, height: 320), "run/04-erase-undone.png")
    check("C5 one undo restores the whole erase drag", afterEraseUndo == 2, "strokes \(afterErase) -> \(afterEraseUndo)")

    let missBoard = Board()
    missBoard.commit(Stroke(points: wave(60, 100, 40), color: .systemRed, width: 2, finished: true))
    missBoard.beginErase()
    missBoard.erase(at: CGPoint(x: 400, y: 300))   // nowhere near the ink
    missBoard.endErase()
    missBoard.undo()   // must undo the draw, not an empty erase step
    check("C6 an eraser drag that hits nothing takes no undo slot", missBoard.strokes.count == 0,
          "after a miss, one undo removed the drawn stroke: count=\(missBoard.strokes.count)")

    // --- hit-test boundary ---------------------------------------------------
    let hitBoard = Board()
    hitBoard.commit(Stroke(points: [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0)], color: .systemRed, width: 2, finished: true))
    let tolerance = 2 * 4.25 / 2 + 6      // 10.25 px
    let inside = hitBoard.hit(CGPoint(x: 100, y: tolerance - 0.5))
    let outside = hitBoard.hit(CGPoint(x: 100, y: tolerance + 0.5))
    check("C7 hit test bites inside the tolerance and not outside",
          inside == 0 && outside == nil, "at \(tolerance - 0.5)px -> \(String(describing: inside)), at \(tolerance + 0.5)px -> \(String(describing: outside))")

    // --- overlay shortcuts are global hot keys ------------------------------
    let center = HotkeyCenter.shared
    var tokens: [UInt32] = []
    for (name, code, mods) in [("esc", UInt32(kVK_Escape), UInt32(0)),
                               ("cmd-Z", UInt32(kVK_ANSI_Z), UInt32(cmdKey)),
                               ("shift-cmd-Z", UInt32(kVK_ANSI_Z), UInt32(cmdKey | shiftKey)),
                               ("shift-cmd-C", UInt32(kVK_ANSI_C), UInt32(cmdKey | shiftKey))] {
        let token = center.register(keyCode: code, modifiers: mods) { }
        check("C8 \(name) registers as a global hot key", token != nil, "token=\(String(describing: token))")
        if let token { tokens.append(token) }
    }
    tokens.forEach(center.unregister)
    check("C9 the overlay's hot keys can be handed back",
          center.register(keyCode: UInt32(kVK_Escape), modifiers: 0, handler: {}) != nil,
          "esc could be registered again after unregister")

    // --- pointer input through the real AppKit view ------------------------
    let pointerWindow = OverlayWindow(screen: screen)      // a clean board for the pointer cases
    let view = pointerWindow.contentView as! CanvasHostingView
    let h = screen.frame.height

    check("C11 the canvas claims every point instead of letting clicks through",
          view.hitTest(NSPoint(x: 500, y: 500)) === view, "hitTest returned \(String(describing: view.hitTest(NSPoint(x: 500, y: 500))))")

    func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: flags, timestamp: 0,
                           windowNumber: pointerWindow.windowNumber, context: nil, eventNumber: 0,
                           clickCount: 1, pressure: 1)!
    }

    let drawBoard = pointerWindow.board
    // a drag near the TOP of the screen: window coords are bottom-left, canvas is top-left
    view.mouseDown(with: mouse(.leftMouseDown, 200, h - 100))
    for i in 1...30 { view.mouseDragged(with: mouse(.leftMouseDragged, 200 + CGFloat(i) * 10, h - 100)) }
    let liveCount = drawBoard.live.count
    view.mouseUp(with: mouse(.leftMouseUp, 500, h - 100))

    check("C12 a mouse drag on the view commits one stroke",
          drawBoard.strokes.count == 1 && drawBoard.live.isEmpty,
          "live during drag=\(liveCount), strokes after=\(drawBoard.strokes.count), live after=\(drawBoard.live.count)")

    let firstPoint = drawBoard.strokes.last!.points.first!
    check("C13 window coordinates are flipped into canvas space",
          abs(firstPoint.y - 100) < 1, "a click 100 px below the top of the screen landed at canvas y=\(firstPoint.y)")

    // option-drag over that stroke erases it and commits nothing
    view.mouseDown(with: mouse(.leftMouseDown, 250, h - 100, [.option]))
    view.mouseDragged(with: mouse(.leftMouseDragged, 300, h - 100, [.option]))
    view.mouseUp(with: mouse(.leftMouseUp, 350, h - 100, [.option]))
    check("C14 an option-drag erases and commits nothing",
          drawBoard.strokes.isEmpty, "strokes after the option-drag=\(drawBoard.strokes.count)")

    check("C15 the canvas takes the first click", view.acceptsFirstMouse(for: nil), "acceptsFirstMouse=\(view.acceptsFirstMouse(for: nil))")

    pointerWindow.close()
    window.close()
    print(failures == 0 ? "\nall cases passed" : "\n\(failures) case(s) FAILED")
    exit(failures == 0 ? 0 : 1)
}
