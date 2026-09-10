// Rasterises an SVG to PNGs at exact pixel sizes by snapshotting it in WebKit.
// Usage: render-icon <svg> <out-prefix> <size> [<size> ...]
import AppKit
import WebKit

let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write("usage: render-icon <svg> <out-prefix> <size>...\n".data(using: .utf8)!)
    exit(2)
}
let svgPath = args[1]
let prefix = args[2]
let sizes = args[3...].compactMap { Int($0) }
let svg = try! String(contentsOfFile: svgPath, encoding: .utf8)

// Render once at 1024pt (2048px on a retina backing) and downsample from that,
// which is what a high-res master is for.
let canvas = 1024.0

final class Shot: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    var done = false

    override init() {
        let cfg = WKWebViewConfiguration()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: canvas, height: canvas), configuration: cfg)
        webView.setValue(false, forKey: "drawsBackground")   // keep the corners transparent
        super.init()
        webView.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // one runloop turn so gradients and the shadow filter are composited
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.snapshot() }
    }

    func snapshot() {
        let cfg = WKSnapshotConfiguration()
        cfg.rect = CGRect(x: 0, y: 0, width: canvas, height: canvas)
        webView.takeSnapshot(with: cfg) { image, error in
            guard let image, let master = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                FileHandle.standardError.write("snapshot failed: \(error.map(String.init(describing:)) ?? "no image")\n".data(using: .utf8)!)
                exit(1)
            }
            for size in sizes {
                guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
                ctx.interpolationQuality = .high
                ctx.draw(master, in: CGRect(x: 0, y: 0, width: size, height: size))
                guard let out = ctx.makeImage(),
                      let data = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
                else { exit(1) }
                let path = "\(prefix)\(size).png"
                try! data.write(to: URL(fileURLWithPath: path))
                print("wrote \(path) (\(size)x\(size)) from \(master.width)px master")
            }
            exit(0)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let shot = Shot()
let html = """
<html><head><meta charset="utf-8"><style>
html,body{margin:0;padding:0;background:transparent}
svg{display:block;width:100vw;height:100vw}
</style></head><body>\(svg)</body></html>
"""
shot.webView.loadHTMLString(html, baseURL: nil)
app.run()
