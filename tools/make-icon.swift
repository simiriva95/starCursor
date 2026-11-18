// Renders the StarCursor app icon. Usage: swift tools/make-icon.swift Resources/AppIcon.icns
import AppKit

let S: CGFloat = 1024
func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(px) / S, y: CGFloat(px) / S)
    let rgb = { (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) in CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a) }

    // macOS-style squircle with the standard 100 px margin
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: rgb(0, 0, 0, 0.45))
    ctx.addPath(shape); ctx.setFillColor(rgb(12, 8, 30, 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let bg = CGGradient(colorsSpace: nil, colors: [rgb(38, 14, 74, 1), rgb(10, 8, 28, 1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 200, y: 924), end: CGPoint(x: 820, y: 100), options: [])
    let haze = CGGradient(colorsSpace: nil, colors: [rgb(0, 240, 255, 0.22), rgb(0, 240, 255, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(haze, startCenter: CGPoint(x: 690, y: 690), startRadius: 0, endCenter: CGPoint(x: 690, y: 690), endRadius: 420, options: [])

    // neon trail: magenta -> cyan swoosh, tapering toward the tail
    let tail = CGPoint(x: 210, y: 250), c1 = CGPoint(x: 360, y: 720), c2 = CGPoint(x: 520, y: 330), head = CGPoint(x: 680, y: 680)
    func bez(_ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * u * tail.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * head.x,
                       y: u * u * u * tail.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * head.y)
    }
    ctx.setLineCap(.round)
    for pass in 0..<2 {
        let n = 120
        for i in 1...n {
            let t = CGFloat(i) / CGFloat(n)
            let col = rgb(255 * (1 - t), 240 * t, 212 + 43 * t, 1)
            let w = (pass == 0 ? 54 : 18) * (0.15 + 0.85 * t)
            ctx.saveGState()
            if pass == 0 { ctx.setShadow(offset: .zero, blur: 40, color: col) }
            ctx.setStrokeColor(pass == 0 ? col : rgb(255, 255, 255, 0.85))
            ctx.setLineWidth(w)
            ctx.move(to: bez(CGFloat(i - 1) / CGFloat(n))); ctx.addLine(to: bez(t)); ctx.strokePath()
            ctx.restoreGState()
        }
    }

    // 4-point star at the head + glitter
    func star(_ c: CGPoint, _ r: CGFloat, _ color: CGColor, blur: CGFloat) {
        let p = CGMutablePath()
        for k in 0..<8 {
            let rr = k % 2 == 0 ? r : r * 0.2, a = CGFloat(k) * .pi / 4 + .pi / 2
            let q = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
            k == 0 ? p.move(to: q) : p.addLine(to: q)
        }
        p.closeSubpath()
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: blur, color: color)
        ctx.addPath(p); ctx.setFillColor(rgb(255, 255, 255, 1)); ctx.fillPath()
        ctx.restoreGState()
    }
    star(head, 165, rgb(0, 240, 255, 1), blur: 60)
    star(head, 165, rgb(255, 255, 255, 0.9), blur: 18)
    star(CGPoint(x: 330, y: 760), 40, rgb(255, 0, 212, 1), blur: 20)
    star(CGPoint(x: 800, y: 420), 30, rgb(0, 240, 255, 1), blur: 16)
    star(CGPoint(x: 470, y: 230), 22, rgb(255, 215, 0, 1), blur: 14)
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let set = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for s in [16, 32, 128, 256, 512] {
    try! render(s).write(to: set.appendingPathComponent("icon_\(s)x\(s).png"))
    try! render(s * 2).write(to: set.appendingPathComponent("icon_\(s)x\(s)@2x.png"))
}
try! render(1024).write(to: out.deletingPathExtension().appendingPathExtension("png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", out.path]
try! p.run(); p.waitUntilExit()
print("wrote \(out.path)")
