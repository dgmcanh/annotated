import AppKit
import SwiftUI

struct Stroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]
    var color: NSColor
    var width: CGFloat
    var path: Path

    init(points: [CGPoint], color: NSColor, width: CGFloat, finished: Bool) {
        self.points = points
        self.color = color
        self.width = width
        self.path = freehandPath(points, width: width, finished: finished)
    }
}

final class Board: ObservableObject {
    @Published private(set) var strokes: [Stroke] = []
    /// The stroke under the pointer right now, rebuilt every mouse event.
    @Published private(set) var live: [CGPoint] = []

    /// Set between the first and second esc, so the HUD can say so.
    @Published var confirmingExit = false

    var color: NSColor = .systemRed
    var width: CGFloat = 0.85

    // Snapshot undo: strokes are value types and a stroke list is small, so a
    // copy is cheap and draw / erase / clear are all undoable through one
    // mechanism. Swap in a command stack only if snapshots show up in a profile.
    private var undoStack: [[Stroke]] = []
    private var redoStack: [[Stroke]] = []
    private var eraseCheckpointed = false
    private var isErasing = false
    private let undoLimit = 50

    private func checkpoint() {
        undoStack.append(strokes)
        redoStack.removeAll()
        if undoStack.count > undoLimit { undoStack.removeFirst() }
    }

    func commit(_ stroke: Stroke) {
        checkpoint()
        strokes.append(stroke)
    }

    // MARK: - Pointer input

    func beginInput(at point: CGPoint, erasing shouldErase: Bool) {
        isErasing = shouldErase
        if shouldErase {
            beginErase()
            erase(at: point)
        } else {
            live = [point]
        }
    }

    func extendInput(to point: CGPoint) {
        if isErasing { erase(at: point) } else { live.append(point) }
    }

    func endInput(at point: CGPoint) {
        if isErasing {
            endErase()
            isErasing = false
            return
        }
        live.append(point)
        commit(Stroke(points: live, color: color, width: width, finished: true))
        live = []
    }

    func beginErase() { eraseCheckpointed = false }

    /// Object eraser: removes whole strokes the point touches. One checkpoint
    /// per drag, so a single undo puts back everything that drag erased.
    func erase(at point: CGPoint) {
        guard let index = hit(point) else { return }
        if !eraseCheckpointed {
            checkpoint()
            eraseCheckpointed = true
        }
        strokes.remove(at: index)
    }

    func endErase() { eraseCheckpointed = false }

    /// Wipes the canvas. Checkpointed, so undo brings it back; a no-op on an
    /// empty board so it never eats an undo slot.
    func clear() {
        guard !strokes.isEmpty else { return }
        checkpoint()
        strokes.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(strokes)
        strokes = previous
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(strokes)
        strokes = next
    }

    /// Hit tests the raw centerline, not the rendered outline. Topmost first.
    func hit(_ point: CGPoint) -> Int? {
        strokes.indices.reversed().first { index in
            let stroke = strokes[index]
            let tolerance = stroke.width * 4.25 / 2 + 6
            if stroke.points.count == 1 { return distance(point, stroke.points[0], stroke.points[0]) <= tolerance }
            return zip(stroke.points, stroke.points.dropFirst()).contains { distance(point, $0, $1) <= tolerance }
        }
    }
}

func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = b.x - a.x, dy = b.y - a.y
    let squaredLength = dx * dx + dy * dy
    guard squaredLength > 0 else { return hypot(p.x - a.x, p.y - a.y) }
    let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / squaredLength))
    return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
}

/// `Annotated --self-check`. Uses precondition, not assert, so it also bites in
/// a release build.
func selfCheck() {
    let board = Board()
    board.commit(Stroke(points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)], color: .systemRed, width: 2, finished: true))
    precondition(board.hit(CGPoint(x: 50, y: 2)) == 0, "point on the line should hit")
    precondition(board.hit(CGPoint(x: 50, y: 80)) == nil, "point far from the line should miss")

    board.beginErase()
    board.erase(at: CGPoint(x: 50, y: 0))
    board.endErase()
    precondition(board.strokes.isEmpty, "erase should remove the stroke")
    board.undo()
    precondition(board.strokes.count == 1, "erase should be undoable")
    board.redo()
    precondition(board.strokes.isEmpty, "redo should re-erase")

    // A straight drag should produce a closed outline roughly a stroke wide.
    let size: CGFloat = 8.5
    var options = FreehandOptions()
    options.size = size
    options.last = true
    let drag = (0...50).map { CGPoint(x: CGFloat($0) * 4, y: 0) }
    let outline = strokeOutline(strokePoints(drag, options), options)
    precondition(outline.count > 8, "outline should have points, got \(outline.count)")
    let ys = outline.map(\.y)
    let spread = ys.max()! - ys.min()!
    precondition(spread > 1 && spread < 2 * size * 1.05, "outline width out of range: \(spread)")
    precondition(!strokePath(outline).isEmpty, "outline should build a path")

    // A full pointer drag commits exactly one stroke.
    let dragBoard = Board()
    dragBoard.beginInput(at: CGPoint(x: 0, y: 0), erasing: false)
    for i in 1...20 { dragBoard.extendInput(to: CGPoint(x: CGFloat(i) * 5, y: 0)) }
    precondition(dragBoard.live.count == 21, "live stroke should track the drag, got \(dragBoard.live.count)")
    dragBoard.endInput(at: CGPoint(x: 105, y: 0))
    precondition(dragBoard.strokes.count == 1, "a drag should commit one stroke, got \(dragBoard.strokes.count)")
    precondition(dragBoard.live.isEmpty, "the live stroke should clear on mouse up")

    // An erasing drag commits nothing.
    dragBoard.beginInput(at: CGPoint(x: 50, y: 0), erasing: true)
    dragBoard.endInput(at: CGPoint(x: 50, y: 0))
    precondition(dragBoard.strokes.isEmpty, "an erasing drag should remove the stroke, not add one")

    // A single click should still render a dot.
    let dot = strokeOutline(strokePoints([CGPoint(x: 5, y: 5)], options), options)
    precondition(dot.count > 4, "a single point should render a dot, got \(dot.count)")
}
