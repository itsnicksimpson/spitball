import AppKit
import ApplicationServices
import Synchronization
import Observation
import SwiftUI

/// A tiny live waveform that hovers right above the text caret while Spitball
/// listens, so you see your voice exactly where the words will land.
/// Never follows the mouse: if an app won't say where its caret is, we anchor to
/// the focused text field instead, and if even that's unknown we stay hidden
/// (the island still shows you're listening).
final class CursorDot {
    private let panel: NSPanel
    private var timer: Timer?
    static let size = NSSize(width: 58, height: 34)      // pill 46×24 + room for its shadow

    init(model: IslandModel) {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: CaretWaveView(m: model))
    }

    private let axQueue = DispatchQueue(label: "spitball.caret", qos: .userInteractive)
    private var generation = 0      // bumps on every show/hide, so a late callback can't undo a newer one
    private var found = false
    private var lookingUp = false
    private var tries = 0

    func show() {
        guard Settings.cursorDot else { return }
        generation += 1
        found = false
        panel.alphaValue = 0
        timer?.invalidate()
        axQueue.async { Caret.wakeAccessibility() }
        locate()
        // Quick retries until the app tells us where the caret is (Electron apps need a moment
        // after being woken), then a calmer follow.
        tries = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tries += 1
                if self.found && self.tries % 4 != 0 { return }   // found: follow every ~0.3 s
                self.locate()
            }
        }
    }

    func hide() {
        generation += 1
        timer?.invalidate(); timer = nil
        let gen = generation
        NSAnimationContext.runAnimationGroup({ $0.duration = A11y.reduceMotion ? 0 : 0.12; panel.animator().alphaValue = 0 },
                                             completionHandler: { [weak self] in
            MainActor.assumeIsolated {   // AppKit calls this on the main thread
                guard let self, self.generation == gen else { return }   // a new dictation started meanwhile
                self.panel.orderOut(nil)
            }
        })
    }

    /// Ask where the caret is off the main thread; move there on the main thread.
    /// A failed ask keeps the pill where it was (no flicker, no vanishing).
    private func locate() {
        guard !lookingUp else { return }
        lookingUp = true
        let gen = generation
        axQueue.async { [weak self] in
            let caret = Caret.rect()
            DispatchQueue.main.async {
                guard let self else { return }
                self.lookingUp = false
                guard self.generation == gen, let caret else { return }
                let s = Self.size
                self.panel.setFrameOrigin(NSPoint(x: caret.midX - s.width / 2, y: caret.maxY + 4))
                if !self.found {
                    self.found = true
                    self.panel.orderFrontRegardless()
                    NSAnimationContext.runAnimationGroup { $0.duration = A11y.reduceMotion ? 0 : 0.12; self.panel.animator().alphaValue = 1 }
                }
            }
        }
    }
}

/// Where's the text insertion point? Asked through Accessibility.
nonisolated enum Caret {
    private static let woken = Mutex(Set<pid_t>())   // touched from the caret queue

    /// Chromium and Electron apps (Chrome, Slack, Notion, VS Code…) hide their text
    /// fields from Accessibility until asked. Ask once per app.
    static func wakeAccessibility() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              woken.withLock({ $0.insert(app.processIdentifier).inserted }) else { return }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(el, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        let chromium = ["com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser",
                        "com.vivaldi.Vivaldi", "com.operasoftware.Opera"]
        if chromium.contains(app.bundleIdentifier ?? "") {
            AXUIElementSetAttributeValue(el, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }

    /// The focused element, asked of the front app first: the system-wide question fails
    /// outright for some apps (Messages, many Catalyst and SwiftUI apps).
    static func focusedElement() -> AXUIElement? {
        func focused(in el: AXUIElement) -> AXUIElement? {
            AXUIElementSetMessagingTimeout(el, 0.15)
            var f: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, kAXFocusedUIElementAttribute as CFString, &f) == .success,
                  let f, CFGetTypeID(f) == AXUIElementGetTypeID() else { return nil }
            return (f as! AXUIElement)
        }
        if let app = NSWorkspace.shared.frontmostApplication, let el = focused(in: AXUIElementCreateApplication(app.processIdentifier)) {
            return el
        }
        return focused(in: AXUIElementCreateSystemWide())
    }

    /// The caret in Cocoa screen coordinates.
    static func rect() -> NSRect? {
        guard let el = focusedElement() else { return nil }
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rr = rangeRef, CFGetTypeID(rr) == AXValueGetTypeID() {
            var range = CFRange()
            AXValueGetValue(rr as! AXValue, .cfRange, &range)
            // An empty range often reports no bounds; try it, then the character before the caret.
            var candidates = [range]
            if range.length == 0 && range.location > 0 { candidates.append(CFRange(location: range.location - 1, length: 1)) }
            for (i, c) in candidates.enumerated() {
                var cr = c
                guard let v = AXValueCreate(.cfRange, &cr), var r = bounds(el, v) else { continue }
                if i == 1 { r = NSRect(x: r.maxX, y: r.minY, width: 0, height: r.height) }   // right edge of previous char
                return r
            }
        }
        // No caret: use the start of the focused text field, if it is one.
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
        let textRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField"]
        guard let r = role as? String, textRoles.contains(r), let frame = frame(el) else { return nil }
        let lineHeight = min(frame.height, 20)
        return NSRect(x: frame.minX + 12, y: frame.maxY - lineHeight - 4, width: 0, height: lineHeight)
    }

    private static func bounds(_ el: AXUIElement, _ range: AXValue) -> NSRect? {
        var b: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(el, kAXBoundsForRangeParameterizedAttribute as CFString, range, &b) == .success,
              let bv = b, CFGetTypeID(bv) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(bv as! AXValue, .cgRect, &rect), rect.height > 2, rect.height < 200 else { return nil }
        return toCocoa(rect)
    }

    private static func frame(_ el: AXUIElement) -> NSRect? {
        var p: CFTypeRef?, s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &s) == .success else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &pt)
        AXValueGetValue(s as! AXValue, .cgSize, &sz)
        guard sz.width > 0, sz.height > 0 else { return nil }
        return toCocoa(CGRect(origin: pt, size: sz))
    }

    /// AX uses a top-left origin on the primary screen; Cocoa uses bottom-left.
    private static func toCocoa(_ r: CGRect) -> NSRect? {
        guard let primary = NSScreen.screens.first else { return nil }
        let c = NSRect(x: r.minX, y: primary.frame.maxY - r.maxY, width: r.width, height: r.height)
        return NSScreen.screens.contains(where: { $0.frame.intersects(c.insetBy(dx: -1, dy: -1)) }) ? c : nil
    }

    /// Selected text in the focused field (for Command Mode), if the app exposes it.
    static func selectedText() -> String? {
        guard let el = focusedElement() else { return nil }
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextAttribute as CFString, &v) == .success,
              let s = v as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }
}

/// Little black pill with your live waveform, hovering over the caret.
struct CaretWaveView: View {
    var m: IslandModel
    var body: some View {
        ZStack {
            Capsule().fill(Color.black)
            LiquidGlow(source: { [m] in m.phase == .listening && m.armed ? Array(m.levels[1...7]) : Array(repeating: m.phase == .working ? 0.35 : 0.08, count: 7) },
                       thinking: m.phase == .working)
                .clipShape(Capsule())
        }
        .frame(width: 46, height: 24)
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))      // an edge on dark backgrounds
        .shadow(color: .black.opacity(0.28), radius: 4, y: 2)                        // lifts it off light ones
        .frame(width: CursorDot.size.width, height: CursorDot.size.height)
        .scaleEffect(m.phase == .hidden ? 0.6 : 1)      // springs in when you start talking
        .animation(A11y.reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: m.phase)
        .accessibilityHidden(true)
    }
}

/// A black pill with rainbow liquid along its bottom edge. Each bump is one band
/// of your voice, so the crest ripples as you talk. While transcribing, a wave
/// rolls across.
struct LiquidGlow: View {
    var levels: [CGFloat] = []
    /// Pulled once per frame (live voice levels aren't observed, so nothing else redraws).
    var source: (() -> [CGFloat])? = nil
    var thinking = false
    var hole: CGFloat = 0     // share of the width hidden by the camera notch: keep the bumps beside it
    @State private var smooth = Smoother()
    var body: some View {
        TimelineView(.animation(paused: A11y.reduceMotion)) { tl in
            let t = A11y.reduceMotion ? 1.0 : tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
            let target = (source?() ?? levels).map { min(1, pow(Double($0), 0.85)) }
            let lv = smooth.step(toward: target, up: 22, down: 9)
            Canvas { ctx, size in
                let w = size.width, h = size.height, n = max(1, lv.count)
                let d = h * 0.62
                // One soft shape: a floor plus a bump per voice band, in a flowing rainbow.
                var shape = Path(CGRect(x: 0, y: h * 0.78, width: w, height: h * 0.3))
                for i in 0..<n {
                    let fi = Double(i)
                    let wave = 0.5 + 0.5 * sin(t * 6 - fi * 0.9)
                    let v = thinking ? 0.2 + 0.4 * wave : lv[i]
                    let crest = h * (0.92 - 0.8 * v + 0.03 * sin(t * 3 + fi * 1.4))
                    let u = (fi + 0.5) / Double(n)
                    let side = 0.5 - Double(hole) / 2
                    let ux = hole > 0 ? (u < 0.5 ? u * 2 * side : 1 - side + (u - 0.5) * 2 * side) : u
                    shape.addEllipse(in: CGRect(x: w * ux - d / 2, y: crest, width: d, height: d))
                }
                let shift = CGFloat((t * 0.25).truncatingRemainder(dividingBy: 1))
                let colors = VoiceGlow.rainbow + VoiceGlow.rainbow
                ctx.drawLayer { l in
                    l.addFilter(.blur(radius: h * 0.07))
                    l.fill(shape, with: .linearGradient(Gradient(colors: colors),
                                                        startPoint: CGPoint(x: -w * shift, y: 0),
                                                        endPoint: CGPoint(x: w * (2 - shift), y: 0)))
                }
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}
