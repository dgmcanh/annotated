import CoreGraphics
import SwiftUI

// Port of perfect-freehand (github.com/steveruizok/perfect-freehand), the
// library Excalidraw uses for its freedraw strokes. Control flow and constants
// follow the TypeScript source 1:1 so the ink looks the same; keep it that way
// if this ever needs re-syncing.
//
// Simplification: input is mouse-only, so there is no real pressure channel and
// every point uses the library's default pressure. Pressure is simulated from
// velocity instead. Add a pressure field to the input if a tablet ever matters.
// Tapering is also dropped (taperStart/taperEnd are always 0 in Excalidraw's
// options), which removes the taper branches from the outline loop.

private let rateOfPressureChange: CGFloat = 0.275
private let fixedPi = CGFloat.pi + 0.0001
private let startCapSegments = 13
private let endCapSegments = 29
private let cornerCapSegments = 13
private let endNoiseThreshold: CGFloat = 3
private let minStreamlineT: CGFloat = 0.15
private let streamlineTRange: CGFloat = 0.85
private let minRadius: CGFloat = 0.01
private let defaultFirstPressure: CGFloat = 0.25
private let defaultPressure: CGFloat = 0.5
private let unitOffset = CGPoint(x: 1, y: 1)

// MARK: - Vector helpers

private func add(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
private func sub(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
private func mul(_ a: CGPoint, _ s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
private func neg(_ a: CGPoint) -> CGPoint { CGPoint(x: -a.x, y: -a.y) }
private func per(_ a: CGPoint) -> CGPoint { CGPoint(x: a.y, y: -a.x) }
private func dpr(_ a: CGPoint, _ b: CGPoint) -> CGFloat { a.x * b.x + a.y * b.y }
private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
private func dist2(_ a: CGPoint, _ b: CGPoint) -> CGFloat { let dx = a.x - b.x, dy = a.y - b.y; return dx * dx + dy * dy }
private func lrp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { add(a, mul(sub(b, a), t)) }
private func prj(_ a: CGPoint, _ b: CGPoint, _ c: CGFloat) -> CGPoint { add(a, mul(b, c)) }
private func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }

private func uni(_ a: CGPoint) -> CGPoint {
    let l = hypot(a.x, a.y)
    return l == 0 ? .zero : mul(a, 1 / l)   // JS returns NaN here; zero keeps the outline finite
}

private func rotAround(_ a: CGPoint, _ c: CGPoint, _ r: CGFloat) -> CGPoint {
    let s = sin(r), co = cos(r)
    let px = a.x - c.x, py = a.y - c.y
    return CGPoint(x: px * co - py * s + c.x, y: px * s + py * co + c.y)
}

// MARK: - Options

struct FreehandOptions {
    var size: CGFloat = 16
    var thinning: CGFloat = 0.6
    var smoothing: CGFloat = 0.5
    var streamline: CGFloat = 0.5
    var simulatePressure = true
    var last = false
    var easing: (CGFloat) -> CGFloat = { sin($0 * .pi / 2) }   // easeOutSine, what Excalidraw uses
}

struct StrokePoint {
    var point: CGPoint
    var pressure: CGFloat
    var vector: CGPoint
    var distance: CGFloat
    var runningLength: CGFloat
}

private func simulatePressure(_ prevPressure: CGFloat, _ distance: CGFloat, _ size: CGFloat) -> CGFloat {
    let sp = min(1, distance / size)
    let rp = min(1, 1 - sp)
    return min(1, prevPressure + (rp - prevPressure) * (sp * rateOfPressureChange))
}

private func strokeRadius(_ size: CGFloat, _ thinning: CGFloat, _ pressure: CGFloat, _ easing: (CGFloat) -> CGFloat) -> CGFloat {
    size * easing(0.5 - thinning * (0.5 - pressure))
}

// MARK: - Centerline

func strokePoints(_ input: [CGPoint], _ options: FreehandOptions) -> [StrokePoint] {
    guard !input.isEmpty else { return [] }
    let t = minStreamlineT + (1 - options.streamline) * streamlineTRange

    var pts = input
    if pts.count == 2 {
        let last = pts[1]
        pts = [pts[0]]
        for i in 1...4 { pts.append(lrp(pts[0], last, CGFloat(i) / 4)) }
    }
    if pts.count == 1 { pts.append(add(pts[0], unitOffset)) }

    var out = [StrokePoint(point: pts[0], pressure: defaultFirstPressure, vector: unitOffset, distance: 0, runningLength: 0)]
    var reachedMinimumLength = false
    var runningLength: CGFloat = 0
    var prev = out[0]
    let maxIndex = pts.count - 1

    for i in 1...maxIndex {
        let point = (options.last && i == maxIndex) ? pts[i] : lrp(prev.point, pts[i], t)
        if point == prev.point { continue }
        let distance = dist(point, prev.point)
        runningLength += distance
        if i < maxIndex && !reachedMinimumLength {
            if runningLength < options.size { continue }
            reachedMinimumLength = true
        }
        prev = StrokePoint(point: point,
                           pressure: defaultPressure,
                           vector: uni(sub(prev.point, point)),
                           distance: distance,
                           runningLength: runningLength)
        out.append(prev)
    }

    out[0].vector = out.count > 1 ? out[1].vector : .zero
    return out
}

// MARK: - Outline

private func drawDot(_ center: CGPoint, _ radius: CGFloat) -> [CGPoint] {
    let start = prj(center, uni(per(sub(center, add(center, unitOffset)))), -radius)
    var pts: [CGPoint] = []
    let step = 1 / CGFloat(startCapSegments)
    var t = step
    while t <= 1 {
        pts.append(rotAround(start, center, fixedPi * 2 * t))
        t += step
    }
    return pts
}

func strokeOutline(_ points: [StrokePoint], _ options: FreehandOptions) -> [CGPoint] {
    guard let first = points.first, let lastStrokePoint = points.last, options.size > 0 else { return [] }

    let totalLength = lastStrokePoint.runningLength
    let minDistance = pow(options.size * options.smoothing, 2)
    var leftPts: [CGPoint] = []
    var rightPts: [CGPoint] = []

    // Average the first few points so a slow start doesn't render fat.
    var prevPressure = first.pressure
    for p in points.prefix(10) {
        let pressure = options.simulatePressure ? simulatePressure(prevPressure, p.distance, options.size) : p.pressure
        prevPressure = (prevPressure + pressure) / 2
    }

    var radius = strokeRadius(options.size, options.thinning, lastStrokePoint.pressure, options.easing)
    var firstRadius: CGFloat?
    var prevVector = first.vector
    var prevLeft = first.point
    var prevRight = first.point
    var tempLeft = prevLeft
    var tempRight = prevRight
    var isPrevPointSharpCorner = false

    for i in points.indices {
        var pressure = points[i].pressure
        let point = points[i].point
        let vector = points[i].vector
        let distance = points[i].distance
        let runningLength = points[i].runningLength
        let isLast = i == points.count - 1

        if !isLast && totalLength - runningLength < endNoiseThreshold { continue }

        if options.thinning != 0 {
            if options.simulatePressure { pressure = simulatePressure(prevPressure, distance, options.size) }
            radius = strokeRadius(options.size, options.thinning, pressure, options.easing)
        } else {
            radius = options.size / 2
        }
        if firstRadius == nil { firstRadius = radius }
        radius = max(minRadius, radius)

        let nextVector = (isLast ? points[i] : points[i + 1]).vector
        let nextDpr = isLast ? 1.0 : dpr(vector, nextVector)
        let prevDpr = dpr(vector, prevVector)
        let isPointSharpCorner = prevDpr < 0 && !isPrevPointSharpCorner
        let isNextPointSharpCorner = nextDpr < 0

        if isPointSharpCorner || isNextPointSharpCorner {
            // Sharp corner: cap it with an arc rather than letting the offsets cross.
            let offset = mul(per(prevVector), radius)
            let step = 1 / CGFloat(cornerCapSegments)
            var t: CGFloat = 0
            while t <= 1 {
                tempLeft = rotAround(sub(point, offset), point, fixedPi * t)
                leftPts.append(tempLeft)
                tempRight = rotAround(add(point, offset), point, fixedPi * -t)
                rightPts.append(tempRight)
                t += step
            }
            prevLeft = tempLeft
            prevRight = tempRight
            if isNextPointSharpCorner { isPrevPointSharpCorner = true }
            continue
        }
        isPrevPointSharpCorner = false

        if isLast {
            let offset = mul(per(vector), radius)
            leftPts.append(sub(point, offset))
            rightPts.append(add(point, offset))
            continue
        }

        let offset = mul(per(lrp(nextVector, vector, nextDpr)), radius)
        tempLeft = sub(point, offset)
        if i <= 1 || dist2(prevLeft, tempLeft) > minDistance {
            leftPts.append(tempLeft)
            prevLeft = tempLeft
        }
        tempRight = add(point, offset)
        if i <= 1 || dist2(prevRight, tempRight) > minDistance {
            rightPts.append(tempRight)
            prevRight = tempRight
        }
        prevPressure = pressure
        prevVector = vector
    }

    let firstPoint = first.point
    if points.count == 1 { return drawDot(firstPoint, firstRadius ?? radius) }

    let lastPoint = lastStrokePoint.point
    var startCap: [CGPoint] = []
    var endCap: [CGPoint] = []

    if let firstRight = rightPts.first {
        let step = 1 / CGFloat(startCapSegments)
        var t = step
        while t <= 1 {
            startCap.append(rotAround(firstRight, firstPoint, fixedPi * t))
            t += step
        }
    }

    let direction = per(neg(lastStrokePoint.vector))
    let capStart = prj(lastPoint, direction, radius)
    let step = 1 / CGFloat(endCapSegments)
    var t = step
    while t < 1 {
        endCap.append(rotAround(capStart, lastPoint, fixedPi * 3 * t))
        t += step
    }

    return leftPts + endCap + rightPts.reversed() + startCap
}

// MARK: - Path

/// Excalidraw's `getSvgPathFromStroke`: a closed loop of quadratics through the
/// midpoints, using SVG `T` (each control point mirrors the previous one).
func strokePath(_ points: [CGPoint]) -> Path {
    var path = Path()
    guard points.count >= 4 else { return path }

    path.move(to: points[0])
    var current = mid(points[1], points[2])
    path.addQuadCurve(to: current, control: points[1])
    var prevControl = points[1]

    for i in 2..<(points.count - 1) {
        let control = CGPoint(x: 2 * current.x - prevControl.x, y: 2 * current.y - prevControl.y)
        let to = mid(points[i], points[i + 1])
        path.addQuadCurve(to: to, control: control)
        prevControl = control
        current = to
    }

    path.closeSubpath()
    return path
}

/// `width` is Excalidraw's strokeWidth; the 4.25 factor is theirs too.
func freehandPath(_ input: [CGPoint], width: CGFloat, finished: Bool) -> Path {
    var options = FreehandOptions()
    options.size = width * 4.25
    options.last = finished
    return strokePath(strokeOutline(strokePoints(input, options), options))
}
