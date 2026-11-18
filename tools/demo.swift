// Records docs/demo.mov: a neutral backdrop, scripted cursor choreography through every feature.
// StarCursor must be running, with a trained "P" gesture bound to Next preset (the default binding).
// Usage: swiftc -O tools/demo.swift -o /tmp/sc-demo && /tmp/sc-demo docs/demo.mov
// The backdrop covers the recorded area, so nothing else on your screen ends up in the video.
// Your own settings are restored afterwards.
import AppKit
import ImageIO

let domain = "io.github.simiriva95.starcursor"
let prefs = UserDefaults(suiteName: domain)!
let keys = ["preset", "effect", "halo", "spotlight", "clicks", "enabled", "emoji", "width", "glow", "length", "taper", "core",
            "follow", "linger", "highContrast", "gifPath", "gifSize", "gifEcho", "gestures", "gestureModifier"]
let saved = Dictionary(uniqueKeysWithValues: keys.compactMap { k in prefs.object(forKey: k).map { (k, $0) } })
func set(_ v: [String: Any]) { v.forEach { prefs.set($1, forKey: $0) }; prefs.synchronize() }

let W: CGFloat = 1280, H: CGFloat = 720
let screen = NSScreen.screens[0].frame
let rect = NSRect(x: screen.midX - W / 2, y: screen.midY - H / 2, width: W, height: H)   // AppKit coords
let topLeftY = screen.height - rect.maxY                                                  // CG coords for warp/capture

// MARK: - A spinning, color-cycling star GIF for the GIF-mode scene

func makeStarGif() -> String {
    let path = NSTemporaryDirectory() + "starcursor-demo-star.gif"
    let n = 16
    let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "com.compuserve.gif" as CFString, n, nil)!
    CGImageDestinationSetProperties(dst, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for i in 0..<n {
        let s = 128, c = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let t = CGFloat(i) / CGFloat(n), color = NSColor(hue: t, saturation: 0.75, brightness: 1, alpha: 1).cgColor
        c.translateBy(x: 64, y: 64); c.rotate(by: t * .pi / 2)
        let r = 44 + 8 * sin(t * 2 * .pi), star = CGMutablePath()
        for k in 0..<8 { let rr = k % 2 == 0 ? r : r * 0.28, a = CGFloat(k) * .pi / 4; k == 0 ? star.move(to: CGPoint(x: cos(a) * rr, y: sin(a) * rr)) : star.addLine(to: CGPoint(x: cos(a) * rr, y: sin(a) * rr)) }
        star.closeSubpath()
        c.setFillColor(color); c.addPath(star); c.fillPath()
        c.setFillColor(CGColor(gray: 1, alpha: 0.9)); c.fillEllipse(in: CGRect(x: -8, y: -8, width: 16, height: 16))
        CGImageDestinationAddImage(dst, c.makeImage()!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.05]] as CFDictionary)
    }
    CGImageDestinationFinalize(dst)
    return path
}

// MARK: - Backdrop

final class Backdrop: NSView {
    var caption = ""
    func page(_ r: NSRect, title: String) {
        NSColor(white: 0.97, alpha: 1).setFill()
        NSBezierPath(roundedRect: r, xRadius: 18, yRadius: 18).fill()
        NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 44, weight: .bold), .foregroundColor: NSColor(white: 0.12, alpha: 1)])
            .draw(at: NSPoint(x: r.minX + 60, y: r.maxY - 110))
        for (i, w) in [0.7, 0.55, 0.62, 0.4, 0.66].enumerated() where r.maxY - 190 - CGFloat(i) * 60 > r.minY + 30 {
            NSColor(white: 0.8, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: r.minX + 60, y: r.maxY - 190 - CGFloat(i) * 60, width: r.width * w, height: 22), xRadius: 11, yRadius: 11).fill()
        }
    }
    override func draw(_ r: NSRect) {
        let g = NSGradient(colors: [NSColor(srgbRed: 0.09, green: 0.05, blue: 0.2, alpha: 1), NSColor(srgbRed: 0.02, green: 0.02, blue: 0.06, alpha: 1)])!
        g.draw(in: bounds, angle: -60)
        NSAttributedString(string: "StarCursor", attributes: [.font: NSFont.systemFont(ofSize: 34, weight: .heavy), .foregroundColor: NSColor.white.withAlphaComponent(0.9)])
            .draw(at: NSPoint(x: 40, y: bounds.height - 70))
        if caption.hasPrefix("Spotlight") { page(NSRect(x: 160, y: 110, width: bounds.width - 320, height: bounds.height - 220), title: "Q4 Roadmap") }
        if caption.hasPrefix("High contrast") { page(NSRect(x: 120, y: 90, width: bounds.width - 240, height: bounds.height - 180), title: "Readable on white pages") }
        NSAttributedString(string: caption, attributes: [.font: NSFont.systemFont(ofSize: 20, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.6)])
            .draw(at: NSPoint(x: 40, y: 34))
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let win = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
win.level = .floating
let view = Backdrop(frame: NSRect(origin: .zero, size: rect.size))
win.contentView = view
win.orderFrontRegardless()

// MARK: - Input helpers

let src = CGEventSource(stateID: .hidSystemState)
func warp(_ x: CGFloat, _ y: CGFloat) { CGWarpMouseCursorPosition(CGPoint(x: rect.minX + x, y: topLeftY + y)) }
func click(right: Bool = false) {
    let p = NSEvent.mouseLocation, cg = CGPoint(x: p.x, y: screen.height - p.y)
    let (down, up): (CGEventType, CGEventType) = right ? (.rightMouseDown, .rightMouseUp) : (.leftMouseDown, .leftMouseUp)
    CGEvent(mouseEventSource: src, mouseType: down, mouseCursorPosition: cg, mouseButton: right ? .right : .left)?.post(tap: .cghidEventTap)
    usleep(40_000)
    CGEvent(mouseEventSource: src, mouseType: up, mouseCursorPosition: cg, mouseButton: right ? .right : .left)?.post(tap: .cghidEventTap)
}
func hotkey(_ code: CGKeyCode) {   // ⌃⌥⌘ + key
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)!
        e.flags = [.maskControl, .maskAlternate, .maskCommand]
        e.post(tap: .cghidEventTap)
    }
}
func option(_ down: Bool) {
    let e = CGEvent(keyboardEventSource: src, virtualKey: 58, keyDown: down)!
    e.type = .flagsChanged
    e.flags = down ? .maskAlternate : []
    e.post(tap: .cghidEventTap)
}
/// Draws a "P" while holding ⌥, the way a person would.
func drawP(at o: CGPoint, size s: CGFloat) {
    let arc = (0...14).map { i -> CGPoint in let a = -Double.pi / 2 + Double(i) / 14 * .pi; return CGPoint(x: max(0, 0.25 + 0.35 * cos(a)), y: 0.25 + 0.25 * sin(a)) }
    let pts = [CGPoint(x: 0, y: 1), CGPoint(x: 0, y: 0)] + arc + [CGPoint(x: 0, y: 0.5)]
    warp(o.x, o.y + s); usleep(120_000)
    option(true); usleep(60_000)
    for (a, b) in zip(pts, pts.dropFirst()) {
        let n = max(2, Int(hypot(b.x - a.x, b.y - a.y) * s / 6))
        for k in 1...n { let t = CGFloat(k) / CGFloat(n); warp(o.x + (a.x + (b.x - a.x) * t) * s, o.y + (a.y + (b.y - a.y) * t) * s); usleep(7_000) }
    }
    usleep(40_000); option(false)
}

// MARK: - Scenes

typealias Path = (Double) -> CGPoint   // t in 0...1 -> point inside the 1280x720 frame
struct Scene {
    var caption: String
    var cfg: [String: Any]
    var secs = 3.0
    var path: Path = { _ in CGPoint(x: 640, y: 360) }
    var clicks: [Double] = []
    var hotkeys: [(Double, CGKeyCode)] = []
    var script: (() -> Void)? = nil        // replaces the path loop
}
let gif = makeStarGif()
let scenes: [Scene] = [
    Scene(caption: "Neon · Glitter", cfg: ["preset": 0, "effect": 2], path: { t in CGPoint(x: 640 + 420 * sin(t * 4 * .pi), y: 360 + 200 * sin(t * 8 * .pi)) }),
    Scene(caption: "Synthwave · Sparks", cfg: ["preset": 1, "effect": 1], path: { t in let r = 60 + 230 * t; return CGPoint(x: 640 + r * cos(t * 10 * .pi), y: 360 + r * sin(t * 10 * .pi)) }),
    Scene(caption: "Fire · Confetti", cfg: ["preset": 2, "effect": 3], path: { t in CGPoint(x: 160 + 960 * t, y: 360 + 180 * sin(t * 6 * .pi)) }),
    Scene(caption: "Ice · Snow", cfg: ["preset": 3, "effect": 7], path: { t in CGPoint(x: 1120 - 960 * t + 60 * cos(t * 16 * .pi), y: 300 + 60 * sin(t * 16 * .pi)) }),
    Scene(caption: "Rainbow · Bubbles", cfg: ["preset": 5, "effect": 6], path: { t in CGPoint(x: 640 + 380 * cos(t * 4 * .pi), y: 360 + 220 * sin(t * 6 * .pi)) }),
    Scene(caption: "Sakura · Emoji", cfg: ["preset": 7, "effect": 4, "emoji": "✨💖🌸⭐️"], path: { t in CGPoint(x: 640 + 400 * sin(t * 2 * .pi), y: 360 + 200 * sin(t * 4 * .pi)) }),
    Scene(caption: "GIF mode · any animated GIF follows you", cfg: ["preset": 0, "effect": 5, "gifPath": gif, "gifSize": 80.0, "gifEcho": true], secs: 3.5,
          path: { t in CGPoint(x: 600 + 360 * sin(t * 3 * .pi), y: 330 + 170 * sin(t * 4 * .pi)) }),
    Scene(caption: "Halo + click ripples", cfg: ["preset": 4, "effect": 0, "halo": true, "clicks": true],
          path: { t in CGPoint(x: 300 + 680 * t, y: 360 + 140 * sin(t * 3 * .pi)) }, clicks: [0.15, 0.35, 0.55, 0.75, 0.95]),
    Scene(caption: "Letter gestures · hold ⌥, draw P → next preset", cfg: ["preset": 0, "effect": 0, "halo": false, "gestures": true, "gestureModifier": 0],
          secs: 5, script: {
              drawP(at: CGPoint(x: 330, y: 190), size: 300); usleep(1_100_000)
              drawP(at: CGPoint(x: 780, y: 210), size: 280); usleep(1_100_000)
          }),
    Scene(caption: "Hotkeys · ⌃⌥⌘E next effect · ⌃⌥⌘P next preset", cfg: ["preset": 1, "effect": 1], secs: 4.5,
          path: { t in CGPoint(x: 640 + 420 * cos(t * 3 * .pi), y: 360 + 150 * sin(t * 6 * .pi)) },
          hotkeys: [(0.2, 14), (0.4, 14), (0.6, 35), (0.8, 14)]),
    Scene(caption: "High contrast · matte trail", cfg: ["preset": 1, "effect": 0, "highContrast": true],
          path: { t in CGPoint(x: 220 + 840 * t, y: 420 + 120 * sin(t * 5 * .pi)) }),
    Scene(caption: "Spotlight for demos", cfg: ["preset": 6, "effect": 2, "highContrast": false, "spotlight": true],
          path: { t in CGPoint(x: 640 + 380 * sin(t * 3 * .pi), y: 360 + 160 * cos(t * 2 * .pi)) }),
]

DispatchQueue.global().async {
    set(["enabled": true, "spotlight": false, "halo": false, "highContrast": false, "width": 12.0, "glow": 16.0, "length": 700.0,
         "taper": 0.85, "core": 0.35, "follow": 0.55, "linger": 0.45])
    usleep(600_000)
    let rec = Process()
    rec.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    let secs = Int(scenes.map { $0.secs + 0.2 }.reduce(0, +)) + 2
    rec.arguments = ["-v", "-C", "-x", "-V", "\(secs)", "-R", "\(Int(rect.minX)),\(Int(topLeftY)),\(Int(W)),\(Int(H))", CommandLine.arguments[1]]
    try! rec.run()
    usleep(800_000)
    for s in scenes {
        DispatchQueue.main.sync { view.caption = s.caption; view.needsDisplay = true }
        set(["enabled": false])   // drop the old trail so scenes don't connect with a jump
        let s0 = s.path(0)
        warp(s0.x, s0.y)
        usleep(150_000)
        set(s.cfg.merging(["enabled": true]) { a, _ in a })
        if let script = s.script { script(); continue }
        var clicks = s.clicks, keys = s.hotkeys
        let start = Date()
        while case let t = Date().timeIntervalSince(start) / s.secs, t < 1 {   // wall-clock timed
            let p = s.path(t)
            warp(p.x, p.y)
            if let c = clicks.first, t >= c { clicks.removeFirst(); click(right: clicks.count % 2 == 0) }
            if let k = keys.first, t >= k.0 { keys.removeFirst(); hotkey(k.1) }
            usleep(8_333)
        }
    }
    rec.waitUntilExit()
    // restore the user's own settings
    for k in keys { if let v = saved[k] { prefs.set(v, forKey: k) } else { prefs.removeObject(forKey: k) } }
    prefs.synchronize()
    try? FileManager.default.removeItem(atPath: gif)
    DispatchQueue.main.async { exit(0) }
}
app.run()
