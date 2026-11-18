import AppKit

enum GestureAction: String, Codable, CaseIterable, Identifiable {
    case openApp, quitApp, runShortcut, pressKeys, openLink, screenshot, mute, lockScreen, nextPreset, toggleTrail
    var id: String { rawValue }
    var label: String {
        switch self {
        case .openApp: "Open app"
        case .quitApp: "Quit app"
        case .runShortcut: "Run Shortcut"
        case .pressKeys: "Press keys"
        case .openLink: "Open link"
        case .screenshot: "Screenshot"
        case .mute: "Toggle mute"
        case .lockScreen: "Lock screen"
        case .nextPreset: "Next preset"
        case .toggleTrail: "Toggle trail"
        }
    }
    var paramHint: String? {
        switch self {
        case .openApp: "Safari"
        case .quitApp: "empty = frontmost app"
        case .runShortcut: "Shortcut name"
        case .pressKeys: "cmd+shift+4"
        case .openLink: "https://…"
        default: nil
        }
    }
}

struct GestureBinding: Codable, Identifiable {
    var id = UUID()
    var letter = "A"
    var action = GestureAction.openApp
    var param = ""
    var samples: [[CGPoint]] = []
}

// MARK: - Recognizer
// ponytail: template matcher ($1-style, no rotation invariance so "N" != "Z"), trained by the user (3 samples per letter)

enum Recognizer {
    static let n = 48
    static let threshold: CGFloat = 0.16   // calibration knob: lower = stricter

    static func length(_ p: [CGPoint]) -> CGFloat {
        zip(p, p.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    static func normalize(_ raw: [CGPoint]) -> [CGPoint] {
        // resample to n equidistant points
        let step = length(raw) / CGFloat(n - 1)
        var out = [raw[0]], pts = raw, acc: CGFloat = 0, i = 1
        while i < pts.count {
            let d = hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
            if acc + d >= step, d > 0 {
                let t = (step - acc) / d
                let q = CGPoint(x: pts[i - 1].x + t * (pts[i].x - pts[i - 1].x), y: pts[i - 1].y + t * (pts[i].y - pts[i - 1].y))
                out.append(q)
                pts.insert(q, at: i)
                acc = 0
            } else { acc += d }
            i += 1
        }
        while out.count < n { out.append(raw.last!) }
        out = Array(out.prefix(n))
        // translate to centroid, uniform scale (keeps "I" and "-" from exploding)
        let cx = out.map(\.x).reduce(0, +) / CGFloat(n), cy = out.map(\.y).reduce(0, +) / CGFloat(n)
        let w = (out.map(\.x).max()! - out.map(\.x).min()!), h = (out.map(\.y).max()! - out.map(\.y).min()!)
        let s = max(w, h, 1)
        return out.map { CGPoint(x: ($0.x - cx) / s, y: ($0.y - cy) / s) }
    }

    static func distance(_ a: [CGPoint], _ b: [CGPoint]) -> CGFloat {
        zip(a, b).reduce(0) { $0 + hypot($1.0.x - $1.1.x, $1.0.y - $1.1.y) } / CGFloat(n)
    }

    static func best(_ g: [CGPoint], in bindings: [GestureBinding]) -> (GestureBinding, CGFloat)? {
        bindings.compactMap { b in b.samples.map { distance(g, $0) }.min().map { (b, $0) } }.min { $0.1 < $1.1 }
    }
}

// MARK: - Sampler
// Reads cursor + modifiers on its own queue at 250 Hz, so a slow trail frame on the main thread
// can't drop or merge gesture points (that distorted letters into "No match").

final class GestureSampler {
    static let shared = GestureSampler()
    private let queue = DispatchQueue(label: "starcursor.gestures", qos: .userInteractive)
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var stroke: [CGPoint]?          // CG global coords (y down)

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(4))
        t.setEventHandler { [weak self] in self?.sample() }
        t.resume()
        timer = t
    }

    /// Current stroke for display, in CG coords.
    var current: [CGPoint]? { lock.lock(); defer { lock.unlock() }; return stroke }

    private func sample() {
        let raw = CGEventSource.flagsState(.combinedSessionState)
        let flags = NSEvent.ModifierFlags(rawValue: UInt(raw.rawValue)).intersection([.command, .option, .control, .shift])
        let held = UserDefaults.standard.bool(forKey: "gestures") && flags == Gestures.modifier
        lock.lock()
        if held, let p = CGEvent(source: nil)?.location {
            stroke = (stroke ?? []) + [p]
            lock.unlock()
        } else if let done = stroke {
            stroke = nil
            lock.unlock()
            // flip y to AppKit orientation; the recognizer is translation-invariant so the offset doesn't matter
            let pts = done.map { CGPoint(x: $0.x, y: -$0.y) }
            DispatchQueue.main.async { Gestures.shared.finish(pts) }
        } else {
            lock.unlock()
        }
    }
}

// MARK: - Store + dispatcher

final class Gestures: ObservableObject {
    static let shared = Gestures()
    static let samplesNeeded = 3

    @Published var bindings: [GestureBinding] { didSet { save() } }
    @Published var training: UUID?

    static var modifier: NSEvent.ModifierFlags {
        switch UserDefaults.standard.integer(forKey: "gestureModifier") {
        case 1: .control
        case 2: [.control, .option]
        default: .option
        }
    }

    private init() {
        let data = UserDefaults.standard.data(forKey: "bindings")
        bindings = data.flatMap { try? JSONDecoder().decode([GestureBinding].self, from: $0) } ?? [
            GestureBinding(letter: "S", action: .screenshot),
            GestureBinding(letter: "P", action: .nextPreset),
        ]
    }

    private func save() { UserDefaults.standard.set(try? JSONEncoder().encode(bindings), forKey: "bindings") }

    func finish(_ raw: [CGPoint]) {
        guard raw.count > 5, Recognizer.length(raw) > 60 else { return }
        let g = Recognizer.normalize(raw)
        if let id = training, let i = bindings.firstIndex(where: { $0.id == id }) {
            bindings[i].samples.append(g)
            let c = bindings[i].samples.count
            TrailEngine.shared.showFlash("\(bindings[i].letter) recorded \(c)/\(Self.samplesNeeded)")
            if c >= Self.samplesNeeded { training = nil }
            return
        }
        guard let (b, d) = Recognizer.best(g, in: bindings), d < Recognizer.threshold else {
            TrailEngine.shared.showFlash("No match")
            return
        }
        TrailEngine.shared.showFlash("\(b.letter) · \(b.action.label)")
        run(b)
    }

    func run(_ b: GestureBinding) {
        let p = b.param.trimmingCharacters(in: .whitespaces)
        if p.isEmpty, b.action.paramHint != nil, b.action != .quitApp {
            TrailEngine.shared.showFlash("\(b.letter) · \(b.action.label): set a value in Settings")
            return
        }
        switch b.action {
        case .openApp: shell("/usr/bin/open", "-a", p)
        case .quitApp:
            let app = p.isEmpty ? NSWorkspace.shared.frontmostApplication
                : NSWorkspace.shared.runningApplications.first { $0.localizedName?.caseInsensitiveCompare(p) == .orderedSame }
            app?.terminate()
        case .runShortcut: shell("/usr/bin/shortcuts", "run", p)
        case .pressKeys: Keys.press(p)
        case .openLink: if let u = URL(string: p) { NSWorkspace.shared.open(u) }
        case .screenshot:
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/StarCursor \(f.string(from: Date())).png").path
            shell("/usr/sbin/screencapture", "-x", path)
        case .mute:
            NSAppleScript(source: "set volume output muted not (output muted of (get volume settings))")?.executeAndReturnError(nil)
        case .lockScreen: Keys.press("ctrl+cmd+q")
        case .nextPreset:
            let d = UserDefaults.standard
            d.set((d.integer(forKey: "preset") + 1) % Preset.all.count, forKey: "preset")
        case .toggleTrail:
            let d = UserDefaults.standard
            d.set(!d.bool(forKey: "enabled"), forKey: "enabled")
        }
    }

    private func shell(_ args: String...) {
        let t = Process()
        t.executableURL = URL(fileURLWithPath: args[0])
        t.arguments = Array(args.dropFirst())
        try? t.run()
    }
}

// MARK: - Synthetic key presses (needs Accessibility)

enum Keys {
    static let codes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34,
        "p": 35, "return": 36, "enter": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
        "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50, "delete": 51, "esc": 53,
        "escape": 53, "left": 123, "right": 124, "down": 125, "up": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101,
        "f10": 109, "f11": 103, "f12": 111,
    ]
    static let mods: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand, "shift": .maskShift, "alt": .maskAlternate,
        "opt": .maskAlternate, "option": .maskAlternate, "ctrl": .maskControl, "control": .maskControl,
    ]

    /// "cmd+shift+4" -> (flags, keycode); nil if the key is unknown
    static func parse(_ s: String) -> (CGEventFlags, CGKeyCode)? {
        var flags = CGEventFlags()
        var key: CGKeyCode?
        for part in s.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if let m = mods[part] { flags.insert(m) } else if let k = codes[part] { key = k } else { return nil }
        }
        return key.map { (flags, $0) }
    }

    static func press(_ s: String) {
        guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) else {
            TrailEngine.shared.showFlash("Accessibility access needed")
            return
        }
        guard let (flags, key) = parse(s) else { TrailEngine.shared.showFlash("Invalid keys: \(s)"); return }
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }
}
