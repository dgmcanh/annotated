import Foundation
import CoreGraphics

struct Case: Decodable { let input: [[Double]]; let out: [[Double]] }
let cases = try! JSONDecoder().decode([String: Case].self, from: Data(contentsOf: URL(fileURLWithPath: "ref.json")))

var failed = false
for name in cases.keys.sorted() {
    let c = cases[name]!
    var o = FreehandOptions()
    o.size = 8.5; o.thinning = 0.6; o.smoothing = 0.5; o.streamline = 0.5; o.last = true
    let mine = strokeOutline(strokePoints(c.input.map { CGPoint(x: $0[0], y: $0[1]) }, o), o)
    if mine.count != c.out.count {
        print("\(name): COUNT MISMATCH ref=\(c.out.count) swift=\(mine.count)"); failed = true; continue
    }
    var worst = 0.0
    for (i, p) in mine.enumerated() { worst = max(worst, hypot(p.x - c.out[i][0], p.y - c.out[i][1])) }
    print(String(format: "%-7s %4d pts   max deviation %.10f", (name as NSString).utf8String!, mine.count, worst))
    if worst >= 1e-6 { failed = true }
}
exit(failed ? 1 : 0)
