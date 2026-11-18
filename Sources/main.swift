import AppKit
import Carbon
import ImageIO
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

let defaults: [String: Any] = [
    "enabled": true, "preset": 0, "width": 10.0, "length": 600.0, "glow": 14.0, "taper": 0.85,
    "core": 0.35, "follow": 0.55, "linger": 0.45, "effect": 2, "emoji": "✨💖🔥", "gifPath": "",
    "gifSize": 64.0, "gifEcho": true, "highContrast": false,
    "clicks": true, "halo": false, "spotlight": false, "spotRadius": 140.0, "spotDim": 0.55,
    "gestures": true, "gestureModifier": 0,
]

enum Prefs {
    static let d = UserDefaults.standard
    static func toggle(_ key: String, _ label: String) {
        d.set(!d.bool(forKey: key), forKey: key)
        TrailEngine.shared.showFlash("\(label) \(d.bool(forKey: key) ? "on" : "off")")
    }
    static func nextPreset() {
        d.set((d.integer(forKey: "preset") + 1) % Preset.all.count, forKey: "preset")
        TrailEngine.shared.showFlash(Preset.current.name)
    }
    static func nextEffect() {
        d.set((d.integer(forKey: "effect") + 1) % Effect.allCases.count, forKey: "effect")
        TrailEngine.shared.showFlash(Effect.current.label)
    }
}

// MARK: - Global hotkeys (Carbon: no permission needed)

enum HotKeys {
    static let list: [(key: UInt32, label: String, action: () -> Void)] = [
        (UInt32(kVK_ANSI_T), "⌃⌥⌘T  Toggle trail", { Prefs.toggle("enabled", "Trail") }),
        (UInt32(kVK_ANSI_S), "⌃⌥⌘S  Spotlight", { Prefs.toggle("spotlight", "Spotlight") }),
        (UInt32(kVK_ANSI_H), "⌃⌥⌘H  Cursor halo", { Prefs.toggle("halo", "Halo") }),
        (UInt32(kVK_ANSI_E), "⌃⌥⌘E  Next effect", Prefs.nextEffect),
        (UInt32(kVK_ANSI_P), "⌃⌥⌘P  Next preset", Prefs.nextPreset),
    ]

    static func register() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            if Int(id.id) < HotKeys.list.count { HotKeys.list[Int(id.id)].action() }
            return noErr
        }, 1, &spec, nil, nil)
        for (i, h) in list.enumerated() {
            var ref: EventHotKeyRef?
            RegisterEventHotKey(h.key, UInt32(cmdKey | optionKey | controlKey), EventHotKeyID(signature: OSType(0x5354_4152), id: UInt32(i)),
                                GetApplicationEventTarget(), 0, &ref)
        }
    }
}

// MARK: - Settings UI

struct SettingsView: View {
    @AppStorage("enabled") var enabled = true
    @AppStorage("preset") var preset = 0
    @AppStorage("width") var width = 10.0
    @AppStorage("length") var length = 600.0
    @AppStorage("glow") var glow = 14.0
    @AppStorage("taper") var taper = 0.85
    @AppStorage("core") var core = 0.35
    @AppStorage("follow") var follow = 0.55
    @AppStorage("linger") var linger = 0.45
    @AppStorage("effect") var effect = 2
    @AppStorage("emoji") var emoji = "✨💖🔥"
    @AppStorage("gifPath") var gifPath = ""
    @AppStorage("gifSize") var gifSize = 64.0
    @AppStorage("gifEcho") var gifEcho = true
    @AppStorage("highContrast") var highContrast = false
    @AppStorage("clicks") var clicks = true
    @AppStorage("halo") var halo = false
    @AppStorage("spotlight") var spotlight = false
    @AppStorage("spotRadius") var spotRadius = 140.0
    @AppStorage("spotDim") var spotDim = 0.55
    @AppStorage("gestures") var gestures = true
    @AppStorage("gestureModifier") var gestureModifier = 0
    @ObservedObject var store = Gestures.shared
    @State var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Trail") {
                Toggle("Enabled", isOn: $enabled)
                Picker("Preset", selection: $preset) {
                    ForEach(Preset.all.indices, id: \.self) { Text(Preset.all[$0].name).tag($0) }
                }
                slider("Width", $width, 2...40)
                slider("Length", $length, 50...2000)
                slider("Glow", $glow, 0...40)
                slider("Taper", $taper, 0...1)
                slider("Core", $core, 0...1)
                slider("Follow speed", $follow, 0.05...1)
                slider("Linger (s)", $linger, 0.05...2)
                Toggle("High contrast (matte)", isOn: $highContrast)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        _ = try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
            }
            Section("Particles") {
                Picker("Effect", selection: $effect) {
                    ForEach(Effect.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }
                if effect == Effect.emoji.rawValue { TextField("Emoji", text: $emoji) }
                if effect == Effect.gif.rawValue {
                    LabeledContent("GIF") {
                        Text(gifPath.isEmpty ? "none" : (gifPath as NSString).lastPathComponent).foregroundStyle(.secondary)
                        Button("Choose…") {
                            let p = NSOpenPanel()
                            p.allowedContentTypes = [.gif, .png, .webP, .image]
                            NSApp.activate(ignoringOtherApps: true)
                            if p.runModal() == .OK, let u = p.url { gifPath = u.path }
                        }
                    }
                    slider("GIF size", $gifSize, 24...256)
                    Toggle("Echo copies along the trail", isOn: $gifEcho)
                }
            }
            Section("Clicks & presenting") {
                Toggle("Click ripples + burst", isOn: $clicks)
                Toggle("Cursor halo", isOn: $halo)
                Toggle("Spotlight", isOn: $spotlight)
                if spotlight {
                    slider("Spotlight radius", $spotRadius, 60...400)
                    slider("Dim", $spotDim, 0.1...0.9)
                }
                Text(HotKeys.list.map(\.label).joined(separator: "   ·   "))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Section("Letter gestures") {
                Toggle("Enabled", isOn: $gestures)
                Picker("Hold", selection: $gestureModifier) {
                    Text("⌥ Option").tag(0); Text("⌃ Control").tag(1); Text("⌃⌥").tag(2)
                }
                Text("Hold the key, draw a letter with the cursor, release. Train each letter 3 times.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach($store.bindings) { $b in
                    HStack {
                        TextField("", text: $b.letter).frame(width: 34).multilineTextAlignment(.center)
                        Picker("", selection: $b.action) {
                            ForEach(GestureAction.allCases) { Text($0.label).tag($0) }
                        }.frame(width: 170)
                        if let hint = b.action.paramHint { TextField(hint, text: $b.param) } else { Spacer() }
                        Button(store.training == b.id ? "Draw… \(b.samples.count)/3" : "Train (\(min(b.samples.count, 3))/3)") {
                            b.samples = []
                            store.training = b.id
                        }
                        Button(role: .destructive) { store.bindings.removeAll { $0.id == b.id } } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete letter \(b.letter)")
                            .help("Delete letter")
                    }
                }
                Button("Add letter") {
                    let used = Set(store.bindings.map { $0.letter.uppercased() })
                    let next = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init).first { !used.contains($0) } ?? "A"
                    store.bindings.append(GestureBinding(letter: next))
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 640, height: 760)
    }

    func slider(_ label: String, _ v: Binding<Double>, _ r: ClosedRange<Double>) -> some View {
        LabeledContent(label) { Slider(value: v, in: r) }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var status: NSStatusItem!
    var panels: [TrailPanel] = []
    var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        UserDefaults.standard.register(defaults: defaults)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "StarCursor")
        status.menu = NSMenu()
        status.menu?.delegate = self
        buildPanels()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.buildPanels()
        }
        HotKeys.register()
        TrailEngine.shared.start()
    }

    func buildPanels() {
        panels.forEach { $0.close() }
        panels = NSScreen.screens.map { TrailPanel(screen: $0) }
        panels.forEach { $0.orderFrontRegardless() }
        TrailEngine.shared.views = panels.compactMap { $0.contentView as? TrailView }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let d = UserDefaults.standard
        menu.removeAllItems()
        func item(_ title: String, _ key: String) {
            let i = NSMenuItem(title: title, action: #selector(toggle(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = key
            i.state = d.bool(forKey: key) ? .on : .off
            menu.addItem(i)
        }
        func submenu(_ title: String, _ names: [String], selected: Int, action: Selector) {
            let sub = NSMenu()
            for (i, name) in names.enumerated() {
                let m = NSMenuItem(title: name, action: action, keyEquivalent: "")
                m.target = self
                m.tag = i
                m.state = selected == i ? .on : .off
                sub.addItem(m)
            }
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            parent.submenu = sub
            menu.addItem(parent)
        }
        item("Trail", "enabled")
        submenu("Preset", Preset.all.map(\.name), selected: d.integer(forKey: "preset"), action: #selector(pickPreset(_:)))
        submenu("Effect", Effect.allCases.map(\.label), selected: Effect.current.rawValue, action: #selector(pickEffect(_:)))
        menu.addItem(.separator())
        item("Click ripples", "clicks")
        item("Cursor halo", "halo")
        item("Spotlight", "spotlight")
        item("Letter gestures", "gestures")
        item("High contrast", "highContrast")
        menu.addItem(.separator())
        let s = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        s.target = self
        menu.addItem(s)
        menu.addItem(NSMenuItem(title: "Quit StarCursor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc func toggle(_ sender: NSMenuItem) {
        let k = sender.representedObject as! String
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: k), forKey: k)
    }

    @objc func pickEffect(_ sender: NSMenuItem) { UserDefaults.standard.set(sender.tag, forKey: "effect") }

    @objc func pickPreset(_ sender: NSMenuItem) { UserDefaults.standard.set(sender.tag, forKey: "preset") }

    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "StarCursor"
            w.isReleasedWhenClosed = false
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

if CommandLine.arguments.contains("--selftest") {
    // recognizer sanity: same shape matches itself, an L doesn't match a vertical line, key parser works
    let l = (0...20).map { CGPoint(x: 0, y: 100 - $0 * 5) } + (1...20).map { CGPoint(x: $0 * 5, y: 0) }
    let line = (0...40).map { CGPoint(x: 0, y: 200 - $0 * 5) }
    let nl = Recognizer.normalize(l), nline = Recognizer.normalize(line)
    precondition(nl.count == Recognizer.n && nline.count == Recognizer.n)
    precondition(Recognizer.distance(nl, Recognizer.normalize(l.map { CGPoint(x: $0.x * 2 + 300, y: $0.y * 2 - 50) })) < 0.02, "scale/translate invariance")
    precondition(Recognizer.distance(nl, nline) > Recognizer.threshold, "L vs I must differ")
    precondition(Keys.parse("cmd+shift+4")! == (CGEventFlags([.maskCommand, .maskShift]), 21))
    precondition(Keys.parse("cmd+nope") == nil)
    // GIF timing: 2 frames, 0.1s + 0.3s
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("starcursor-selftest.gif")
    let dst = CGImageDestinationCreateWithURL(url as CFURL, "com.compuserve.gif" as CFString, 2, nil)!
    for (delay, gray) in [(0.1, 0.0), (0.3, 1.0)] {
        let c = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(gray: gray, alpha: 1); c.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        CGImageDestinationAddImage(dst, c.makeImage()!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
    }
    precondition(CGImageDestinationFinalize(dst))
    let g = Gif(path: url.path)!
    precondition(g.frames.count == 2 && abs(g.total - 0.4) < 0.01, "gif load")
    precondition(g.frame(at: 0.05) === g.frames[0] && g.frame(at: 0.2) === g.frames[1] && g.frame(at: 0.45) === g.frames[0], "gif timing")
    print("selftest ok")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
