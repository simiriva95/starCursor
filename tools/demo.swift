// Records docs/demo.mov: a neutral backdrop, scripted cursor choreography through presets/effects.
// StarCursor must be running. Usage: swiftc -O tools/demo.swift -o /tmp/sc-demo && /tmp/sc-demo docs/demo.mov
// The backdrop covers the recorded area, so nothing else on your screen ends up in the video.
import AppKit

let domain = "io.github.simiriva95.starcursor"
let prefs = UserDefaults(suiteName: domain)!
let keys = ["preset", "effect", "halo", "spotlight", "clicks", "enabled", "emoji", "width", "glow", "length"]
let saved = Dictionary(uniqueKeysWithValues: keys.compactMap { k in prefs.object(forKey: k).map { (k, $0) } })
func set(_ v: [String: Any]) { v.forEach { prefs.set($1, forKey: $0) }; prefs.synchronize() }

let W: CGFloat = 1280, H: CGFloat = 720
let screen = NSScreen.main!.frame
let rect = NSRect(x: screen.midX - W / 2, y: screen.midY - H / 2, width: W, height: H)   // AppKit coords
let topLeftY = screen.height - rect.maxY                                                  // CG coords for warp/capture

final class Backdrop: NSView {
    var caption = ""
    override func draw(_ r: NSRect) {
        let g = NSGradient(colors: [NSColor(srgbRed: 0.09, green: 0.05, blue: 0.2, alpha: 1), NSColor(srgbRed: 0.02, green: 0.02, blue: 0.06, alpha: 1)])!
        g.draw(in: bounds, angle: -60)
        let title = NSAttributedString(string: "StarCursor", attributes: [
            .font: NSFont.systemFont(ofSize: 34, weight: .heavy), .foregroundColor: NSColor.white.withAlphaComponent(0.9)])
        title.draw(at: NSPoint(x: 40, y: bounds.height - 70))
        if caption.hasPrefix("Spotlight") {   // a light "slide" so the dimming reads
            let slide = NSRect(x: 160, y: 110, width: bounds.width - 320, height: bounds.height - 220)
            NSColor(white: 0.96, alpha: 1).setFill()
            NSBezierPath(roundedRect: slide, xRadius: 18, yRadius: 18).fill()
            NSAttributedString(string: "Q4 Roadmap", attributes: [.font: NSFont.systemFont(ofSize: 44, weight: .bold), .foregroundColor: NSColor(white: 0.12, alpha: 1)])
                .draw(at: NSPoint(x: slide.minX + 60, y: slide.maxY - 110))
            for (i, w) in [0.7, 0.55, 0.62, 0.4].enumerated() {
                NSColor(white: 0.8, alpha: 1).setFill()
                NSBezierPath(roundedRect: NSRect(x: slide.minX + 60, y: slide.maxY - 190 - CGFloat(i) * 60, width: slide.width * w, height: 22), xRadius: 11, yRadius: 11).fill()
            }
        }
        let cap = NSAttributedString(string: caption, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 20, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.6)])
        cap.draw(at: NSPoint(x: 40, y: 34))
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let win = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
win.level = .floating
let view = Backdrop(frame: NSRect(origin: .zero, size: rect.size))
win.contentView = view
win.orderFrontRegardless()

func warp(_ x: CGFloat, _ y: CGFloat) { CGWarpMouseCursorPosition(CGPoint(x: rect.minX + x, y: topLeftY + y)) }
func click(right: Bool = false) {
    let p = NSEvent.mouseLocation, cg = CGPoint(x: p.x, y: screen.height - p.y)
    let src = CGEventSource(stateID: .hidSystemState)
    let (down, up): (CGEventType, CGEventType) = right ? (.rightMouseDown, .rightMouseUp) : (.leftMouseDown, .leftMouseUp)
    CGEvent(mouseEventSource: src, mouseType: down, mouseCursorPosition: cg, mouseButton: right ? .right : .left)?.post(tap: .cghidEventTap)
    usleep(40_000)
    CGEvent(mouseEventSource: src, mouseType: up, mouseCursorPosition: cg, mouseButton: right ? .right : .left)?.post(tap: .cghidEventTap)
}

typealias Path = (Double) -> CGPoint   // t in 0...1 -> point inside the 1280x720 frame
let scenes: [(String, [String: Any], Path, [Double])] = [
    ("Neon · Glitter", ["preset": 0, "effect": 2], { t in CGPoint(x: 640 + 420 * sin(t * 4 * .pi), y: 360 + 200 * sin(t * 8 * .pi)) }, []),
    ("Synthwave · Sparks", ["preset": 1, "effect": 1], { t in let r = 60 + 230 * t; return CGPoint(x: 640 + r * cos(t * 10 * .pi), y: 360 + r * sin(t * 10 * .pi)) }, []),
    ("Fire · Confetti", ["preset": 2, "effect": 3], { t in CGPoint(x: 160 + 960 * t, y: 360 + 180 * sin(t * 6 * .pi)) }, []),
    ("Ice · Snow", ["preset": 3, "effect": 7], { t in CGPoint(x: 1120 - 960 * t + 60 * cos(t * 16 * .pi), y: 300 + 60 * sin(t * 16 * .pi)) }, []),
    ("Rainbow · Bubbles", ["preset": 5, "effect": 6], { t in CGPoint(x: 640 + 380 * cos(t * 4 * .pi), y: 360 + 220 * sin(t * 6 * .pi)) }, []),
    ("Sakura · Emoji", ["preset": 7, "effect": 4, "emoji": "✨💖🌸⭐️"], { t in CGPoint(x: 640 + 400 * sin(t * 2 * .pi), y: 360 + 200 * sin(t * 4 * .pi)) }, []),
    ("Halo + click ripples", ["preset": 4, "effect": 0, "halo": true, "clicks": true],
     { t in CGPoint(x: 300 + 680 * t, y: 360 + 140 * sin(t * 3 * .pi)) }, [0.15, 0.35, 0.55, 0.75, 0.95]),
    ("Spotlight for demos", ["preset": 6, "effect": 2, "halo": false, "spotlight": true],
     { t in CGPoint(x: 640 + 380 * sin(t * 3 * .pi), y: 360 + 160 * cos(t * 2 * .pi)) }, []),
]

DispatchQueue.global().async {
    set(["enabled": true, "spotlight": false, "halo": false, "width": 12.0, "glow": 16.0, "length": 700.0])
    usleep(600_000)
    let rec = Process()
    rec.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    let secs = scenes.count * 3 + 2
    rec.arguments = ["-v", "-C", "-x", "-V", "\(secs)", "-R", "\(Int(rect.minX)),\(Int(topLeftY)),\(Int(W)),\(Int(H))", CommandLine.arguments[1]]
    try! rec.run()
    usleep(800_000)
    for (caption, cfg, path, clicks) in scenes {
        DispatchQueue.main.sync { view.caption = caption; view.needsDisplay = true }
        set(["enabled": false])   // drop the old trail so scenes don't connect with a jump
        let s0 = path(0)
        warp(s0.x, s0.y)
        usleep(150_000)
        set(cfg.merging(["enabled": true]) { a, _ in a })
        var pending = clicks
        let start = Date()
        while case let t = Date().timeIntervalSince(start) / 3, t < 1 {   // wall-clock timed, 3 s per scene
            let p = path(t)
            warp(p.x, p.y)
            if let c = pending.first, t >= c { pending.removeFirst(); click(right: pending.count % 2 == 0) }
            usleep(8_333)
        }
    }
    rec.waitUntilExit()
    // restore the user's own settings
    for k in keys { if let v = saved[k] { prefs.set(v, forKey: k) } else { prefs.removeObject(forKey: k) } }
    prefs.synchronize()
    DispatchQueue.main.async { exit(0) }
}
app.run()
