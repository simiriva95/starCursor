import AppKit
import ImageIO
import QuartzCore

// MARK: - Presets

struct Preset {
    let name: String
    let stops: [NSColor]      // tail -> head
    var rainbow = false

    func color(_ f: CGFloat, time: Double) -> NSColor {
        if rainbow {
            let h = (CGFloat(time * 0.25) + f * 0.6).truncatingRemainder(dividingBy: 1)
            return NSColor(hue: h, saturation: 0.9, brightness: 1, alpha: 1)
        }
        let x = max(0, min(1, f)) * CGFloat(stops.count - 1)
        let i = min(Int(x), stops.count - 2)
        return stops[i].blended(withFraction: x - CGFloat(i), of: stops[i + 1]) ?? stops[i]
    }

    static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    static let all: [Preset] = [
        Preset(name: "Neon", stops: [rgb(0xFF00D4), rgb(0x00F0FF)]),
        Preset(name: "Synthwave", stops: [rgb(0x7B2FF7), rgb(0xF107A3), rgb(0xFFB800)]),
        Preset(name: "Fire", stops: [rgb(0xB00000), rgb(0xFF5A00), rgb(0xFFE600)]),
        Preset(name: "Ice", stops: [rgb(0x2B5BFF), rgb(0x7FDBFF), rgb(0xFFFFFF)]),
        Preset(name: "Toxic", stops: [rgb(0x00A86B), rgb(0x7CFF00), rgb(0xEAFF00)]),
        Preset(name: "Rainbow", stops: [.white, .white], rainbow: true),
        Preset(name: "Gold", stops: [rgb(0x8A5A00), rgb(0xFFC300), rgb(0xFFF3B0)]),
        Preset(name: "Sakura", stops: [rgb(0xFF5C8A), rgb(0xFFB7C5), rgb(0xFFFFFF)]),
        Preset(name: "White", stops: [rgb(0x9AA0A6), rgb(0xFFFFFF)]),
    ]

    static var current: Preset { all[max(0, min(all.count - 1, UserDefaults.standard.integer(forKey: "preset")))] }
}

// MARK: - Engine (polls the cursor, no permissions needed)

struct TrailPoint { var p: CGPoint; var t: Double }
enum Effect: Int, CaseIterable {
    case none, sparks, glitter, confetti, emoji, gif, bubbles, snow   // append only: raw values are persisted
    var label: String { ["None", "Sparks", "Glitter", "Confetti", "Emoji", "GIF", "Bubbles", "Snow"][rawValue] }
    static var current: Effect { Effect(rawValue: UserDefaults.standard.integer(forKey: "effect")) ?? .none }
}

struct Ripple { var p: CGPoint; var born: Double; var right: Bool }

struct Particle {
    var kind: Effect
    var p: CGPoint
    var v: CGVector
    var born: Double
    var life: Double
    var color: NSColor
    var size: CGFloat
    var angle = CGFloat.random(in: 0..<(2 * .pi))
    var spin: CGFloat = 0
    var text = ""
}

/// Animated GIF (or still image) frames, loaded via ImageIO
struct Gif {
    let frames: [CGImage]
    let delays: [Double]
    let total: Double

    init?(path: String) {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        var f: [CGImage] = [], d: [Double] = []
        for i in 0..<CGImageSourceGetCount(src) {
            guard let img = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            f.append(img)
            d.append(delay < 0.02 ? 0.1 : delay)   // browsers treat ~0 delays as 100 ms too
        }
        guard !f.isEmpty else { return nil }
        frames = f; delays = d; total = d.reduce(0, +)
    }

    func frame(at t: Double) -> CGImage {
        var x = t.truncatingRemainder(dividingBy: total)
        for (i, d) in delays.enumerated() { if x < d { return frames[i] }; x -= d }
        return frames[frames.count - 1]
    }
}

final class TrailEngine {
    static let shared = TrailEngine()
    var points: [TrailPoint] = []
    var particles: [Particle] = []
    var ripples: [Ripple] = []
    private(set) var mouse = CGPoint.zero
    private var lastButtons = 0
    private var lastSpot = false
    private var lastMouse = CGPoint.zero
    private(set) var gif: Gif?
    private var gifPath = ""
    private var gifTry = 0.0
    var gesture: [CGPoint]?           // non-nil while the gesture modifier is held
    var flash: (text: String, at: CGPoint, t: Double)?
    var views: [TrailView] = []
    private(set) var head: CGPoint?
    private var lastDirty = CGRect.null
    private var lastMouseRect = CGRect.null
    private var timer: Timer?

    func start() {
        // ponytail: Timer at 120 Hz, swap for CADisplayLink (macOS 14+) if frame pacing looks off on ProMotion
        let t = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func showFlash(_ text: String) { flash = (text, NSEvent.mouseLocation, CACurrentMediaTime()) }

    private func emit(_ effect: Effect, at h: CGPoint, speed: CGFloat, now: Double) {
        let r = { (a: Double, b: Double) in CGFloat(Double.random(in: a...b)) }
        let chance = { (p: Double) in Double.random(in: 0...1) < p }
        switch effect {
        case .sparks where speed > 4 && chance(0.6):
            let a = r(0, 2 * .pi), s = r(40, 160)
            particles.append(Particle(kind: .sparks, p: h, v: CGVector(dx: cos(a) * s, dy: sin(a) * s), born: now, life: 0.6,
                                      color: Preset.current.color(1, time: now), size: 3))
        case .glitter where speed > 1:
            let palette: [NSColor] = [.white, Preset.rgb(0xFFD700), Preset.rgb(0xFFB7F5), Preset.rgb(0x9FF7FF), Preset.current.color(1, time: now)]
            for _ in 0..<(speed > 8 ? 2 : 1) where chance(0.8) {
                let w = UserDefaults.standard.double(forKey: "width")
                particles.append(Particle(kind: .glitter, p: CGPoint(x: h.x + r(-w, w), y: h.y + r(-w, w)),
                                          v: CGVector(dx: r(-25, 25), dy: r(-25, 25)), born: now, life: Double(r(0.5, 1.1)),
                                          color: palette.randomElement()!, size: r(3, 7)))
            }
        case .confetti where speed > 3 && chance(0.7):
            particles.append(Particle(kind: .confetti, p: h, v: CGVector(dx: r(-80, 80), dy: r(40, 140)), born: now, life: 1.6,
                                      color: NSColor(hue: r(0, 1), saturation: 0.85, brightness: 1, alpha: 1),
                                      size: r(4, 7), spin: r(-8, 8)))
        case .emoji where speed > 5 && chance(0.25):
            let chars = (UserDefaults.standard.string(forKey: "emoji") ?? "").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard let e = chars.randomElement() else { return }
            particles.append(Particle(kind: .emoji, p: h, v: CGVector(dx: r(-20, 20), dy: r(30, 70)), born: now, life: 1.1,
                                      color: .white, size: r(18, 28), spin: r(-1.5, 1.5), text: e))
        case .bubbles where speed > 2 && chance(0.25):
            particles.append(Particle(kind: .bubbles, p: h, v: CGVector(dx: r(-15, 15), dy: r(20, 50)), born: now, life: 1.6,
                                      color: Preset.current.color(1, time: now), size: r(5, 14)))
        case .snow where speed > 2 && chance(0.4):
            particles.append(Particle(kind: .snow, p: CGPoint(x: h.x + r(-20, 20), y: h.y + r(-10, 10)),
                                      v: CGVector(dx: r(-10, 10), dy: r(-30, -10)), born: now, life: 2, color: .white, size: r(2, 5)))
        default: break
        }
    }

    private func clicks(_ d: UserDefaults, now: Double) {
        // polling pressedMouseButtons needs no Accessibility / Input Monitoring permission
        let buttons = NSEvent.pressedMouseButtons
        let pressed = buttons & ~lastButtons
        lastButtons = buttons
        ripples.removeAll { now - $0.born > 0.55 }
        guard d.bool(forKey: "clicks"), pressed & 0b11 != 0 else { return }
        let right = pressed & 0b10 != 0
        let color = Preset.current.color(right ? 0 : 1, time: now)
        ripples.append(Ripple(p: mouse, born: now, right: right))
        for _ in 0..<20 {
            let a = Double.random(in: 0..<(2 * .pi)), s = Double.random(in: 120...320)
            particles.append(Particle(kind: .sparks, p: mouse, v: CGVector(dx: cos(a) * s, dy: sin(a) * s), born: now, life: 0.6,
                                      color: color, size: 3))
        }
    }

    private func tick() {
        let d = UserDefaults.standard
        let now = CACurrentMediaTime()
        mouse = NSEvent.mouseLocation
        clicks(d, now: now)

        // gesture capture: modifier held alone => record, release => recognize
        let flags = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift])
        if d.bool(forKey: "gestures") && flags == Gestures.modifier {
            gesture = (gesture ?? []) + [mouse]
        } else if let g = gesture {
            gesture = nil
            Gestures.shared.finish(g)
        }

        if d.bool(forKey: "enabled") {
            let follow = d.double(forKey: "follow")
            let h = head.map { CGPoint(x: $0.x + (mouse.x - $0.x) * follow, y: $0.y + (mouse.y - $0.y) * follow) } ?? mouse
            let prev = head ?? h
            head = h
            if points.last.map({ hypot($0.p.x - h.x, $0.p.y - h.y) > 0.5 }) ?? true {
                points.append(TrailPoint(p: h, t: now))
            }
            emit(Effect.current, at: h, speed: hypot(h.x - prev.x, h.y - prev.y), now: now)
        } else {
            head = nil
            points.removeAll()
        }

        // expire by linger time, then cap by length
        let linger = d.double(forKey: "linger")
        if let cut = points.firstIndex(where: { now - $0.t <= linger }) { points.removeFirst(cut) } else { points.removeAll() }
        let maxLen = d.double(forKey: "length")
        var total = 0.0
        var i = points.count - 1
        while i > 0 {
            total += hypot(points[i].p.x - points[i - 1].p.x, points[i].p.y - points[i - 1].p.y)
            if total > maxLen { points.removeFirst(i - 1); break }
            i -= 1
        }

        let dt = 1.0 / 120
        particles = particles.compactMap { q in
            guard now - q.born < q.life else { return nil }
            var q = q
            q.p.x += q.v.dx * dt; q.p.y += q.v.dy * dt
            q.angle += q.spin * dt
            switch q.kind {
            case .sparks: q.v.dx *= 0.95; q.v.dy = q.v.dy * 0.95 - 6
            case .glitter: q.v.dx *= 0.92; q.v.dy = q.v.dy * 0.92 - 0.6
            case .confetti: q.v.dx = q.v.dx * 0.98 + sin(now * 6 + q.angle) * 3; q.v.dy = max(-120, q.v.dy - 4)
            case .bubbles: q.v.dx = q.v.dx * 0.97 + sin(now * 4 + q.angle) * 2; q.v.dy *= 0.99
            case .snow: q.v.dx = q.v.dx * 0.97 + sin(now * 2 + q.angle) * 1.5
            default: q.v.dx *= 0.98; q.v.dy *= 0.985
            }
            return q
        }
        let path = d.string(forKey: "gifPath") ?? ""
        if path != gifPath, now - gifTry > 1 {   // failed loads retry once a second, not every frame
            gifTry = now
            gif = path.isEmpty ? nil : Gif(path: path)
            if gif != nil || path.isEmpty { gifPath = path }
        }
        if let f = flash, now - f.t > 1.2 { flash = nil }

        // redraw only what changed
        var dirty = CGRect.null
        for p in points { dirty = dirty.union(CGRect(origin: p.p, size: .zero)) }
        for q in particles { dirty = dirty.union(CGRect(origin: q.p, size: .zero)) }
        if Effect.current == .gif, gif != nil, let h = head { dirty = dirty.union(CGRect(origin: h, size: .zero)) }
        if d.bool(forKey: "halo") || !ripples.isEmpty { dirty = dirty.union(CGRect(origin: mouse, size: .zero)).union(lastMouseRect) }
        for rp in ripples { dirty = dirty.union(CGRect(x: rp.p.x - 80, y: rp.p.y - 80, width: 160, height: 160)) }
        for p in gesture ?? [] { dirty = dirty.union(CGRect(origin: p, size: .zero)) }
        if let f = flash { dirty = dirty.union(CGRect(x: f.at.x, y: f.at.y - 20, width: 320, height: 60)) }
        if !dirty.isNull {
            var m = d.double(forKey: "width") + d.double(forKey: "glow") * 2 + 30
            if Effect.current == .gif { m = max(m, d.double(forKey: "gifSize") * 1.5 + 20) }
            dirty = dirty.insetBy(dx: -m, dy: -m)
        }
        let area = dirty.union(lastDirty)
        lastDirty = dirty
        lastMouseRect = CGRect(origin: mouse, size: .zero)

        // spotlight dims whole screens: repaint everything while it is on and the cursor moves
        let spot = d.bool(forKey: "spotlight")
        defer { lastSpot = spot; lastMouse = mouse }
        if spot != lastSpot || (spot && (mouse != lastMouse || !area.isNull)) {
            views.forEach { $0.needsDisplay = true }
            return
        }
        guard !area.isNull else { return }
        for v in views {
            guard let o = v.window?.frame.origin else { continue }
            let local = area.offsetBy(dx: -o.x, dy: -o.y).intersection(v.bounds)
            if !local.isNull && !local.isEmpty { v.setNeedsDisplay(local) }
        }
    }
}

// MARK: - Overlay

final class TrailPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let v = TrailView(frame: NSRect(origin: .zero, size: screen.frame.size))
        v.wantsLayer = true
        contentView = v
        setFrame(screen.frame, display: false)
    }
    override var canBecomeKey: Bool { false }
}

final class TrailView: NSView {
    override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let o = window?.frame.origin else { return }
        ctx.clear(rect)
        let e = TrailEngine.shared, d = UserDefaults.standard, now = CACurrentMediaTime()
        let preset = Preset.current
        let width = d.double(forKey: "width"), glow = d.double(forKey: "glow"), taper = d.double(forKey: "taper")
        let linger = max(0.05, d.double(forKey: "linger"))
        let matte = d.bool(forKey: "highContrast")
        let loc = { (p: CGPoint) in CGPoint(x: p.x - o.x, y: p.y - o.y) }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        if d.bool(forKey: "spotlight") {
            // dim everything, then punch a soft-edged hole around the cursor
            ctx.setFillColor(NSColor.black.withAlphaComponent(d.double(forKey: "spotDim")).cgColor)
            ctx.fill(rect)
            let c = loc(e.mouse), r = d.double(forKey: "spotRadius")
            let clear = NSColor.black.withAlphaComponent(0).cgColor
            let g = CGGradient(colorsSpace: nil, colors: [NSColor.black.cgColor, NSColor.black.cgColor, clear] as CFArray, locations: [0, 0.7, 1])!
            ctx.saveGState()
            ctx.setBlendMode(.destinationOut)
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
            ctx.restoreGState()
        }

        let pts = e.points
        if pts.count > 1 {
            let n = CGFloat(pts.count - 1)
            func segments(widthScale: CGFloat, colorFor: (CGFloat, Double) -> NSColor) {
                for i in 1..<pts.count {
                    let f = CGFloat(i) / n
                    let ageFade = 1 - (now - pts[i].t) / linger
                    ctx.setLineWidth(max(0.5, width * widthScale * (1 - taper * (1 - f))))
                    ctx.setStrokeColor(colorFor(f, max(0, ageFade)).cgColor)
                    ctx.move(to: loc(pts[i - 1].p))
                    ctx.addLine(to: loc(pts[i].p))
                    ctx.strokePath()
                }
            }
            if matte {
                // ponytail: matte = dark outline + solid core, readable on white pages
                segments(widthScale: 1.35) { _, a in NSColor.black.withAlphaComponent(0.55 * a) }
                segments(widthScale: 1) { f, a in preset.color(f, time: now).withAlphaComponent(a) }
            } else {
                ctx.saveGState()
                ctx.setShadow(offset: .zero, blur: glow, color: preset.color(1, time: now).cgColor)
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                segments(widthScale: 1) { f, a in preset.color(f, time: now).withAlphaComponent(a) }
                ctx.endTransparencyLayer()
                ctx.restoreGState()
                let core = d.double(forKey: "core")
                segments(widthScale: core) { f, a in
                    (preset.color(f, time: now).blended(withFraction: 0.65, of: .white) ?? .white).withAlphaComponent(a)
                }
            }
        }

        for q in e.particles {
            let life = 1 - (now - q.born) / q.life
            let c = loc(q.p)
            ctx.saveGState()
            ctx.translateBy(x: c.x, y: c.y)
            ctx.rotate(by: q.angle)
            switch q.kind {
            case .sparks:
                let r = 1.5 + 2 * life
                ctx.setShadow(offset: .zero, blur: 6, color: q.color.cgColor)
                ctx.setFillColor(q.color.withAlphaComponent(life).cgColor)
                ctx.fillEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
            case .glitter:
                // 4-point star that twinkles
                let tw = 0.45 + 0.55 * abs(sin(now * 18 + q.angle * 7))
                let r = q.size * (0.6 + 0.4 * tw)
                let star = CGMutablePath()
                for k in 0..<8 {
                    let rr = k % 2 == 0 ? r : r * 0.22, a = CGFloat(k) * .pi / 4
                    k == 0 ? star.move(to: CGPoint(x: cos(a) * rr, y: sin(a) * rr)) : star.addLine(to: CGPoint(x: cos(a) * rr, y: sin(a) * rr))
                }
                star.closeSubpath()
                ctx.setShadow(offset: .zero, blur: 5, color: q.color.cgColor)
                ctx.setFillColor(q.color.withAlphaComponent(min(1, life * 1.5) * tw).cgColor)
                ctx.addPath(star)
                ctx.fillPath()
            case .confetti:
                ctx.scaleBy(x: cos(q.angle * 1.7), y: 1)   // fake 3D flip
                ctx.setFillColor(q.color.withAlphaComponent(min(1, life * 3)).cgColor)
                ctx.fill(CGRect(x: -q.size / 2, y: -q.size / 4, width: q.size, height: q.size / 2))
            case .bubbles:
                let r = q.size, box = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
                ctx.setFillColor(q.color.withAlphaComponent(0.15 * life).cgColor)
                ctx.fillEllipse(in: box)
                ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.7 * life).cgColor)
                ctx.setLineWidth(1.2)
                ctx.strokeEllipse(in: box)
                ctx.setFillColor(NSColor.white.withAlphaComponent(0.8 * life).cgColor)
                ctx.fillEllipse(in: CGRect(x: -r * 0.5, y: r * 0.2, width: r * 0.35, height: r * 0.35))
            case .snow:
                ctx.setShadow(offset: .zero, blur: 4, color: NSColor.white.cgColor)
                ctx.setFillColor(NSColor.white.withAlphaComponent(min(1, life * 2)).cgColor)
                ctx.fillEllipse(in: CGRect(x: -q.size / 2, y: -q.size / 2, width: q.size, height: q.size))
            case .emoji:
                ctx.setAlpha(min(1, life * 2))
                let s = NSAttributedString(string: q.text, attributes: [.font: NSFont.systemFont(ofSize: q.size)])
                let sz = s.size()
                s.draw(at: NSPoint(x: -sz.width / 2, y: -sz.height / 2))
            default: break
            }
            ctx.restoreGState()
        }

        for rp in e.ripples {
            let t = (now - rp.born) / 0.55, ease = 1 - (1 - t) * (1 - t)
            let r = 10 + 50 * ease, c = loc(rp.p), box = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            let color = preset.color(rp.right ? 0 : 1, time: now)
            ctx.saveGState()
            ctx.setFillColor(color.withAlphaComponent(0.22 * (1 - t)).cgColor)
            ctx.fillEllipse(in: box)
            ctx.setShadow(offset: .zero, blur: 12, color: color.cgColor)
            ctx.setStrokeColor(color.withAlphaComponent(1 - t).cgColor)
            ctx.setLineWidth(1.5 + 4.5 * (1 - t))
            ctx.strokeEllipse(in: box)
            ctx.restoreGState()
        }

        if d.bool(forKey: "halo") {
            let c = loc(e.mouse), r: CGFloat = NSEvent.pressedMouseButtons != 0 ? 15 : 22
            let color = preset.color(1, time: now)
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 10, color: color.cgColor)
            ctx.setFillColor(color.withAlphaComponent(0.12).cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.setStrokeColor(color.withAlphaComponent(0.9).cgColor)
            ctx.setLineWidth(2.5)
            ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.restoreGState()
        }

        if Effect.current == .gif, let gif = e.gif, let head = e.head {
            // GIF rides just below-right of the cursor, faded copies echo along the trail
            let size = d.double(forKey: "gifSize")
            let img = gif.frame(at: now)
            let aspect = CGFloat(img.width) / CGFloat(max(1, img.height))
            func stamp(_ p: CGPoint, scale: CGFloat, alpha: CGFloat) {
                let w = size * scale * min(1, aspect), h = size * scale / max(1, aspect)
                let c = loc(p)
                ctx.saveGState()
                ctx.setAlpha(alpha)
                ctx.interpolationQuality = .high
                ctx.draw(img, in: CGRect(x: c.x + 14, y: c.y - h - 14, width: w, height: h))
                ctx.restoreGState()
            }
            if d.bool(forKey: "gifEcho"), pts.count > 8 {
                for k in stride(from: 1, through: 4, by: 1) {
                    let i = pts.count - 1 - k * pts.count / 5
                    if i >= 0 { stamp(pts[i].p, scale: 1 - CGFloat(k) * 0.15, alpha: 0.5 - CGFloat(k) * 0.1) }
                }
            }
            stamp(head, scale: 1, alpha: 1)
        }

        if let g = e.gesture, g.count > 1 {
            ctx.setShadow(offset: .zero, blur: 10, color: NSColor.systemTeal.cgColor)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(4)
            ctx.addLines(between: g.map(loc))
            ctx.strokePath()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
        }

        if let f = e.flash {
            let a = max(0, 1 - (now - f.t) / 1.2)
            let shadow = NSShadow()
            shadow.shadowColor = preset.color(1, time: now)
            shadow.shadowBlurRadius = 8
            let s = NSAttributedString(string: f.text, attributes: [
                .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(a),
                .shadow: shadow,
            ])
            s.draw(at: NSPoint(x: f.at.x - o.x + 16, y: f.at.y - o.y))
        }
    }
}
