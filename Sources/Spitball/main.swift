import Synchronization
import ObjCCatch
// Spitball — double-tap ⌘, talk, text appears wherever your cursor is.
// On-device transcription: NVIDIA Parakeet (via FluidAudio, on the Neural Engine),
// with Apple's SpeechAnalyzer as an always-there fallback. No accounts, no cloud.

import AppKit
import AVFoundation
import Speech
import Observation
import SwiftUI
import ServiceManagement
import ApplicationServices
import FluidAudio
import Sparkle

// MARK: - Settings

enum Trigger: String, CaseIterable {
    case doubleCommand, rightOption, fn, rightCommand
    /// Hold-to-talk keys. Double ⌘ is tap-based instead.
    var holdKeyCode: UInt16? {
        switch self { case .rightOption: 61; case .fn: 63; case .rightCommand: 54; case .doubleCommand: nil }
    }
    var flag: NSEvent.ModifierFlags {
        switch self { case .rightOption: .option; case .fn: .function; case .rightCommand, .doubleCommand: .command }
    }
    var label: String {
        switch self {
        case .doubleCommand: "Double-tap ⌘"
        case .rightOption: "Hold Right Option ⌥"
        case .fn: "Hold Fn / Globe 🌐"
        case .rightCommand: "Hold Right Command ⌘"
        }
    }
}

enum ScreenShape: String, CaseIterable {
    case auto, notch, island, floating
    var label: String {
        switch self {
        case .auto: "Automatic"
        case .notch: "Notch"
        case .island: "Dynamic Island"
        case .floating: "Floating pill"
        }
    }
}

enum NoiseMode: String, CaseIterable {
    case smart, always, off
    var label: String {
        switch self {
        case .smart: "Smart (on during calls)"
        case .always: "Always (best for music, ~1 s slower)"
        case .off: "Off"
        }
    }
}

enum Engine: String, CaseIterable {
    case parakeet, apple
    var label: String { self == .parakeet ? "Parakeet (fastest, best)" : "Apple Speech" }
}

nonisolated enum Settings {
    nonisolated(unsafe) private static let d = UserDefaults.standard   // UserDefaults is thread-safe
    static var trigger: Trigger {
        get { Trigger(rawValue: d.string(forKey: "trigger2") ?? "") ?? .doubleCommand }
        set { d.set(newValue.rawValue, forKey: "trigger2") }
    }
    static var shape: ScreenShape {
        get { ScreenShape(rawValue: d.string(forKey: "shape") ?? "") ?? .auto }
        set { d.set(newValue.rawValue, forKey: "shape") }
    }
    static var engine: Engine {
        get { Engine(rawValue: d.string(forKey: "engine") ?? "") ?? .parakeet }
        set { d.set(newValue.rawValue, forKey: "engine") }
    }
    static var removeFillers: Bool {
        get { d.object(forKey: "removeFillers") as? Bool ?? true }
        set { d.set(newValue, forKey: "removeFillers") }
    }
    static var noise: NoiseMode {
        get { NoiseMode(rawValue: d.string(forKey: "noise") ?? "") ?? .smart }
        set { d.set(newValue.rawValue, forKey: "noise") }
    }
    static var cursorDot: Bool {
        get { d.object(forKey: "cursorDot") as? Bool ?? true }
        set { d.set(newValue, forKey: "cursorDot") }
    }
    /// Style for apps without their own. (Older "polish" switch maps to Polished.)
    static var defaultStyle: WritingStyle {
        get { WritingStyle(rawValue: d.string(forKey: "defaultStyle") ?? "") ?? (d.bool(forKey: "polish") ? .polished : .smart) }
        set { d.set(newValue.rawValue, forKey: "defaultStyle") }
    }
    /// "auto" = Parakeet's 25 languages, detected as you talk (switch mid-sentence).
    /// A locale id ("ja_JP") uses Apple's engine in that language.
    static var language: String {
        get { d.string(forKey: "language") ?? "auto" }
        set { d.set(newValue, forKey: "language") }
    }
    /// Show Spitball in the Dock (it lives in the menu bar either way).
    static var showInDock: Bool {
        get { d.bool(forKey: "showInDock") }
        set { d.set(newValue, forKey: "showInDock") }
    }
    /// Offer meeting notes when a call starts.
    static var meetingPrompt: Bool {
        get { d.object(forKey: "meetingPrompt") as? Bool ?? true }
        set { d.set(newValue, forKey: "meetingPrompt") }
    }
    /// Free-text rules applied to every dictation ("use British English, be concise").
    static var customInstructions: String {
        get { d.string(forKey: "customInstructions") ?? "" }
        set { d.set(newValue, forKey: "customInstructions") }
    }
    /// Read file names and code terms from the focused window to spell them right.
    static var screenContext: Bool {
        get { d.object(forKey: "screenContext") as? Bool ?? true }
        set { d.set(newValue, forKey: "screenContext") }
    }
    static var commandMode: Bool {
        get { d.object(forKey: "commandMode") as? Bool ?? true }
        set { d.set(newValue, forKey: "commandMode") }
    }
    static var keepHistory: Bool {
        get { d.object(forKey: "keepHistory") as? Bool ?? true }
        set { d.set(newValue, forKey: "keepHistory") }
    }
    static var relaxedTiming: Bool {
        get { d.bool(forKey: "relaxedTiming") }
        set { d.set(newValue, forKey: "relaxedTiming") }
    }
    static var onboarded: Bool {
        get { d.bool(forKey: "onboarded") }
        set { d.set(newValue, forKey: "onboarded") }
    }
    static var sounds: Bool { soundPack != .none }
    static var soundPack: SoundPack {
        get {
            if let raw = d.string(forKey: "soundPack"), let p = SoundPack(rawValue: raw) { return p }
            return (d.object(forKey: "sounds") as? Bool ?? true) ? .soft : .none   // older on/off switch (and retired louder sets)
        }
        set { d.set(newValue.rawValue, forKey: "soundPack") }
    }
    static var showIsland: Bool {
        get { d.object(forKey: "showIsland") as? Bool ?? true }
        set { d.set(newValue, forKey: "showIsland") }
    }
}

import os
/// `log show --predicate 'subsystem == "com.nicksimpson.spitball"' --last 1h`
nonisolated enum Timing { static let log = Logger(subsystem: "com.nicksimpson.spitball", category: "timing") }

/// Spitball lives in the menu bar, but while one of its windows is open it acts like a
/// normal app: Dock dot, ⌘-Tab, its own menu bar. Close the last window and it steps
/// back to the menu bar (unless "Show in the Dock" is on).
enum DockPresence {
    static func start() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { n in
            nonisolated(unsafe) let obj = n.object     // delivered on the main queue
            MainActor.assumeIsolated {
                guard let w = obj as? NSWindow, counts(w), NSApp.activationPolicy() != .regular else { return }
                NSApp.setActivationPolicy(.regular)
            }
        }
        nc.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { n in
            nonisolated(unsafe) let obj = n.object     // delivered on the main queue
            MainActor.assumeIsolated {
                let closing = obj as? NSWindow
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    let open = NSApp.windows.contains { $0 !== closing && $0.isVisible && counts($0) }
                    if !open && !Settings.showInDock { NSApp.setActivationPolicy(.accessory) }
                }
            }
        }
    }

    /// Real windows only: not the island, the cursor pill, menus or popovers.
    static func counts(_ w: NSWindow) -> Bool {
        !(w is NSPanel) && w.level == .normal && w.frame.width > 300 && (w.styleMask.contains(.titled) || w is RetroWindow)
    }
}

// MARK: - Island UI

enum IslandStyle { case notch, island, floating }

@Observable final class IslandModel {
    enum Phase: Equatable { case hidden, listening, working, done, message }
    var phase: Phase = .hidden
    var handsFree = false
    var armed = true          // false while the mic is still starting
    var editing = false       // Command Mode: editing selected text
    /// ~50 updates a second: never observed. The pills read it every frame themselves,
    /// so audio never makes any other view redraw.
    @ObservationIgnored var levels: [CGFloat] = Array(repeating: 0, count: 9)
    var message = ""
    var style: IslandStyle = .floating
    var cutoutWidth: CGFloat = 0   // width of the notch / island camera cutout
    var barHeight: CGFloat = 32    // menu bar height on this screen

    /// 5 voice bands (low → high), mirrored so low frequencies sit in the middle.
    func set(bands b: [Float]) {
        guard b.count == 5 else { return }
        let order = [4, 3, 2, 1, 0, 1, 2, 3, 4]
        // Slight taper toward the edges so the shape reads like a voice, not an EQ.
        let taper: [CGFloat] = [0.55, 0.7, 0.85, 0.95, 1, 0.95, 0.85, 0.7, 0.55]
        levels = order.enumerated().map { i, band in CGFloat(b[band]) * taper[i] }
    }
}

struct IslandView: View {
    var m: IslandModel

    var open: Bool { m.phase != .hidden }
    var wing: CGFloat { m.phase == .message ? 112 : (m.editing ? 72 : 64) }   // room for the glow beside the notch
    var core: CGFloat { m.style == .floating ? 34 : m.cutoutWidth }
    var width: CGFloat { open ? core + wing * 2 : max(core, 60) }

    /// Notch: flush with the top edge. Island: a pill wrapped around the camera
    /// cutout, a hair below the edge. Floating: a pill just under the top.
    var topInset: CGFloat {
        switch m.style { case .notch: 0; case .island: 3; case .floating: 6 }
    }
    var baseHeight: CGFloat {
        switch m.style { case .notch: m.barHeight; case .island: m.barHeight - 5; case .floating: 30 }
    }
    var height: CGFloat { baseHeight + (m.phase == .message ? 18 : 0) }
    var corner: CGFloat {
        m.style == .notch ? 12 : min(baseHeight / 2, height / 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(
                    topLeadingRadius: m.style == .notch ? 0 : corner,
                    bottomLeadingRadius: corner,
                    bottomTrailingRadius: corner,
                    topTrailingRadius: m.style == .notch ? 0 : corner,
                    style: .continuous
                )
                .fill(Color.black)
                .overlay {
                    // Same as the cursor pill: black, with rainbow liquid along the bottom
                    // that rises band by band with your voice. Rolls like a wave while it thinks.
                    if open && m.phase != .message && !(m.editing && m.phase == .listening) {
                        LiquidGlow(source: { [m] in m.phase == .listening && m.armed ? m.levels : Array(repeating: m.phase == .working ? 0.35 : 0.06, count: 9) },
                                   thinking: m.phase == .working, hole: m.style == .floating ? 0 : core / width)
                            .frame(height: baseHeight).frame(maxHeight: .infinity, alignment: .top)
                            .clipShape(UnevenRoundedRectangle(
                                topLeadingRadius: m.style == .notch ? 0 : corner, bottomLeadingRadius: corner,
                                bottomTrailingRadius: corner, topTrailingRadius: m.style == .notch ? 0 : corner, style: .continuous))
                            .transition(.opacity)
                    }
                }

                if open {
                    VStack(spacing: 2) {
                        HStack(spacing: 0) {
                            left.frame(width: wing - 14, alignment: .leading).padding(.leading, 14)
                            Spacer(minLength: 0)
                            right.frame(width: wing - 14, alignment: .trailing).padding(.trailing, 14)
                        }
                        .frame(height: baseHeight)
                        if m.phase == .message {
                            Text(m.message)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .padding(.horizontal, 14)
                                .frame(height: 16)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: width, height: height)
            .opacity(open ? 1 : 0)
            .padding(.top, topInset)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(A11y.reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.78), value: m.phase)
        .animation(A11y.reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.78), value: m.handsFree)
    }

    @ViewBuilder var left: some View {
        switch m.phase {
        case .listening:
            if m.editing {
                Label("Edit", systemImage: "pencil").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white).labelStyle(.titleAndIcon).fixedSize()
            }
        case .working:
            if m.editing {
                Label("Edit", systemImage: "pencil").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6)).labelStyle(.titleAndIcon).fixedSize()
            }
        case .done:
            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
        case .message, .hidden: EmptyView()
        }
    }

    func bars(_ levels: [CGFloat]) -> some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<levels.count, id: \.self) { i in
                Capsule().fill(Color.white.opacity(m.armed ? 0.9 : 0.4))
                    .frame(width: 2.5, height: max(3, levels[i] * (baseHeight - 14)))
            }
        }
        .animation(A11y.reduceMotion ? nil : .linear(duration: 0.05), value: levels)
    }

    @ViewBuilder var right: some View {
        switch m.phase {
        default: EmptyView()
        }
    }
}

/// Soft rainbow light that rises from the bottom of the pill as you talk:
/// five blurred blobs drifting and cycling hue, added on top of the glass.
/// Eases toward the voice each frame (fast up, softer down), so motion glides
/// at the display's refresh rate instead of stepping with each audio buffer.
nonisolated final class Smoother {
    private(set) var values: [Double] = []
    private var last = Date()
    func step(toward target: [Double], up: Double = 18, down: Double = 7) -> [Double] {
        let now = Date(), dt = min(0.05, now.timeIntervalSince(last)); last = now
        if values.count != target.count { values = target; return values }
        for i in values.indices {
            let k = target[i] > values[i] ? up : down
            values[i] += (target[i] - values[i]) * (1 - exp(-k * dt))
        }
        return values
    }
}

/// Soft rainbow light that rises from the bottom of the notch pill as you talk:
/// one blob per voice band, drawn on the GPU in a single blurred pass.
struct VoiceGlow: View {
    var level: CGFloat
    var thinking = false      // while transcribing: the light sweeps side to side
    var hole: CGFloat = 0     // share of the width hidden behind the camera notch (keep the light out of it)
    var reach: Double = 1     // how high the light climbs (1 = fills the pill when you're loud)
    var bands: [CGFloat] = [] // your voice, low → high: each blob follows one band
    @State private var smooth = Smoother()
    static let rainbow: [Color] = [
        Color(red: 0.36, green: 0.55, blue: 1), Color(red: 0.69, green: 0.42, blue: 1), Color(red: 1, green: 0.38, blue: 0.62),
        Color(red: 1, green: 0.62, blue: 0.3), Color(red: 0.4, green: 0.9, blue: 0.85), Color(red: 0.45, green: 0.75, blue: 1),
    ]

    /// 0…1 across the visible part of the pill (skipping the notch) → x in points.
    func x(_ u: Double, _ w: Double) -> Double {
        let side = 0.5 - Double(hole) / 2
        guard hole > 0 else { return u * w }
        return (u < 0.5 ? u * 2 * side : 1 - side + (u - 0.5) * 2 * side) * w
    }

    var body: some View {
        TimelineView(.animation(paused: A11y.reduceMotion)) { tl in
            let t = A11y.reduceMotion ? 1.0 : tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
            let target: [Double] = (0..<6).map { i in
                if thinking { return 0.5 }
                if bands.isEmpty { return Double(min(1, max(0, level))) }
                return Double(min(1, bands[min(bands.count - 1, i * bands.count / 6)]))
            }
            let lv = smooth.step(toward: target)
            Canvas { ctx, size in
                let w = size.width, h = size.height
                ctx.addFilter(.blur(radius: h * 0.28))
                for i in 0..<6 {
                    let fi = Double(i)
                    let sweep = 0.5 + 0.45 * sin(t * 2.4)
                    let u = thinking ? min(1, max(0, sweep + (fi - 2.5) * 0.05))
                                     : min(1, max(0, (fi + 0.5) / 6 + 0.025 * sin(t * (0.5 + fi * 0.11) + fi * 1.7)))
                    let rise = reach * (thinking ? 0.7 : 0.18 + 0.82 * lv[i])
                    let bw = max(w * 0.26, h * 1.4), bh = h * 1.1
                    let cy = h * (1.25 - 0.6 * rise)
                    let rect = CGRect(x: x(u, w) - bw / 2, y: cy - bh / 2, width: bw, height: bh)
                    ctx.fill(Path(ellipseIn: rect), with: .color(VoiceGlow.rainbow[(i + Int(t / 2.5)) % 6]))
                }
            }
            .opacity(0.6 + 0.4 * (lv.max() ?? 0))
        }
        .drawingGroup()
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

struct PulseDot: View {
    var armed = true
    @State private var on = false
    var body: some View {
        Circle().fill(armed ? Color(red: 1, green: 0.27, blue: 0.23) : Color(white: 0.55))
            .frame(width: 8, height: 8)
            .opacity(on ? 1 : 0.45)
            .onAppear {
                if A11y.reduceMotion { on = true; return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever()) { on = true }
            }
    }
}

struct ThinkingDots: View {
    var body: some View {
        TimelineView(.animation(paused: A11y.reduceMotion)) { ctx in
            let t = A11y.reduceMotion ? 0.3 : ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<3) { i in
                    Circle().fill(Color.white)
                        .frame(width: 4, height: 4)
                        .opacity(0.35 + 0.65 * max(0, sin(t * 6 - Double(i) * 0.8)))
                }
            }
        }
    }
}

final class IslandPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

enum ScreenInfo {
    /// Hardware model, e.g. "Mac16,12".
    static let model: String = {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [UInt8](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(decoding: buf.prefix { $0 != 0 }, as: UTF8.self)
    }()

    /// Every notched Mac so far is a MacBookPro18,x or Mac14–Mac17. A Mac with a top
    /// cutout from a newer family is assumed to be the OLED Dynamic Island generation.
    /// (macOS has no public API that tells the two apart; the menu lets you override.)
    static var guessesIsland: Bool {
        guard model.hasPrefix("Mac"), !model.hasPrefix("MacBook"),
              let major = Int(model.dropFirst(3).prefix { $0.isNumber }) else { return false }
        return major >= 18
    }

    static func style(for screen: NSScreen) -> (IslandStyle, cutout: CGFloat, bar: CGFloat) {
        let hasCutout = screen.safeAreaInsets.top > 0
        var cutout: CGFloat = 0
        if hasCutout, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            cutout = screen.frame.width - l.width - r.width
        }
        let bar = hasCutout ? screen.safeAreaInsets.top : 30
        let style: IslandStyle
        switch Settings.shape {
        case .notch: style = .notch
        case .island: style = .island
        case .floating: style = .floating
        case .auto: style = hasCutout ? (guessesIsland ? .island : .notch) : .floating
        }
        // Forced notch/island on a screen without a cutout: give it a sensible size.
        if style != .floating && cutout == 0 { cutout = style == .island ? 126 : 185 }
        return (style, cutout, style == .floating ? 30 : (hasCutout ? bar : 32))
    }
}

final class Island {
    let model = IslandModel()
    private let panel: IslandPanel
    private var hideWork: DispatchWorkItem?
    private let size = NSSize(width: 560, height: 90)

    init() {
        panel = IslandPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: IslandView(m: model))
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
    }

    private func place() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let s = ScreenInfo.style(for: screen)
        model.style = s.0
        model.cutoutWidth = s.cutout
        model.barHeight = s.bar
        let f = screen.frame
        // Center on the cutout (it's centered on every Mac so far, but be exact).
        var midX = f.midX
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
            midX = (l.maxX + r.minX) / 2
        }
        panel.setFrameOrigin(NSPoint(x: midX - size.width / 2, y: f.maxY - size.height))
        panel.orderFrontRegardless()
    }

    func show(_ phase: IslandModel.Phase, handsFree: Bool = false) {
        hideWork?.cancel()
        guard Settings.showIsland else { model.phase = phase; model.handsFree = handsFree; return }   // still drives the caret waveform
        if model.phase == .hidden { place() }
        model.handsFree = handsFree
        if phase == .listening && model.phase != .listening { model.armed = false; model.levels = Array(repeating: 0, count: model.levels.count) }
        model.phase = phase
    }

    func flash(_ message: String, seconds: Double = 2.6) {
        hideWork?.cancel()
        if model.phase == .hidden { place() }
        model.message = message
        model.phase = .message
        A11y.announce(message.replacingOccurrences(of: "⌘", with: "Command"))
        hide(after: seconds)
    }

    func hide(after delay: Double = 0) {
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.model.phase = .hidden
            self.model.handsFree = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if self.model.phase == .hidden { self.panel.orderOut(nil) }
            }
        }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    func bands(_ b: [Float]) { model.set(bands: b) }
    func armed() { model.armed = true }
}

// MARK: - Audio capture (16 kHz mono float)

enum DictationError: LocalizedError {
    case noMic, noEngine, unsupported
    var errorDescription: String? {
        switch self {
        case .noMic: "No microphone found"
        case .noEngine: "Speech engine still loading"
        case .unsupported: "Speech isn't supported for your language"
        }
    }
}

/// Hand-synchronised: samples behind `lock`, engine work on the dictation's audio queue.
nonisolated final class Recorder: @unchecked Sendable {
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var engine: AVAudioEngine?
    /// Prepared engines kept between dictations (stopped = mic off). Reusing one
    /// starts ~3× faster than building a new engine. Dropped whenever the audio
    /// hardware changes, so AirPods / docks still just work.
    private var cache: [Bool: AVAudioEngine] = [:]
    private var deviceListener: AudioObjectPropertyListenerBlock?
    var onDeviceChange: (@Sendable () -> Void)?    // called on a Core Audio thread

    /// Build and prepare engines ahead of time WITHOUT starting them (the mic stays
    /// off). This takes the first dictation from ~1.5 s to ~0.05 s.
    func warmUp() {
        cache.removeAll()
        // Only the plain mic is prepared ahead. Echo cancellation is built when a call needs
        // it: building it while AirPods are mid-handoff raises an exception inside Apple's code.
        guard AudioDevices.hasUsableInput() else { return }
        let e = AVAudioEngine()
        var ok = false
        _ = try? Recorder.objc {
            if let dev = AudioDevices.selected { AudioDevices.use(dev, on: e) }
            guard AudioDevices.tapFormat(e.inputNode).sampleRate > 0 else { return }
            e.prepare(); ok = true
        }
        if ok { cache[false] = e }
    }

    /// Apple's audio code raises Objective-C exceptions when hardware vanishes mid-call;
    /// Swift can't catch those, so they'd kill the app. This turns them into errors.
    static func objc(_ body: () -> Void) throws {
        var err: NSError?
        if !SBTry(body, &err) { throw err ?? DictationError.noMic }
    }
    private let lock = NSLock()
    private var samples: [Float] = []
    private let meter = VoiceMeter()
    var onBands: (([Float]) -> Void)?
    /// Live 16 kHz mono chunks (audio thread), used for live captions during practice.
    var onSamples: (@Sendable ([Float]) -> Void)?   // called on the audio thread
    private(set) var usingVoiceProcessing = false
    /// Echo cancellation can start yet deliver nothing (seen with Continuity calls and AirPods
    /// juggling the route: "failed to run downlink DSP"). After that, skip it for a while.
    nonisolated(unsafe) static var vpBrokenUntil = Date.distantPast

    func start() throws {
        _ = stop()   // never leave an old engine (and the mic) running
        guard AudioDevices.hasUsableInput() else { throw DictationError.noMic }   // fail fast, never hang on "no device"
        lock.withLock { samples.removeAll(keepingCapacity: true) }
        meter.reset()
        // Apple's voice processing (what FaceTime uses): cancels whatever the Mac is
        // playing — the other side of a call, music, videos — and suppresses room noise.
        // Falls back to the raw mic if a device doesn't support it.
        var wantVP: Bool
        switch Settings.noise {
        case .always: wantVP = true
        case .off: wantVP = false
        case .smart: wantVP = AudioActivity.onCall()
        }
        if Date() < Recorder.vpBrokenUntil { wantVP = false }   // echo cancellation failed recently: plain mic
        if wantVP {
            do { try startEngine(voiceProcessing: true); return }
            catch { NSLog("Spitball: voice processing unavailable, using raw mic: \(error)") }
        }
        try startEngine(voiceProcessing: false)
    }

    init() {
        // Default mic changed (AirPods connected, dock unplugged…): forget cached engines.
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.onDeviceChange?() }
        deviceListener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, nil, block)
        // …and when devices come and go (AirPods hopping to your iPhone and back).
        var list = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &list, nil, block)
    }

    /// The engine started but no audio is arriving (a Bluetooth route was rebuilt under us):
    /// throw every cached engine away and start clean.
    func restartFresh() throws {
        _ = stop()
        cache.removeAll()
        try start()
    }

    private func startEngine(voiceProcessing: Bool) throws {
        do { try startEngine(voiceProcessing: voiceProcessing, reuse: true) }
        catch {
            // A cached engine can go stale after a hardware change; retry from scratch.
            cache[voiceProcessing] = nil
            try startEngine(voiceProcessing: voiceProcessing, reuse: false)
        }
    }

    private func startEngine(voiceProcessing: Bool, reuse: Bool) throws {
        let cached = reuse ? cache[voiceProcessing] : nil
        let engine = cached ?? AVAudioEngine()
        if cached == nil, !voiceProcessing, let dev = AudioDevices.selected { AudioDevices.use(dev, on: engine) }
        let node = engine.inputNode
        if voiceProcessing && cached == nil {
            var vpError: Error?
            try Recorder.objc {
                do { try node.setVoiceProcessingEnabled(true) } catch { vpError = error; return }
                // Don't turn the user's call or music down while they dictate.
                node.voiceProcessingOtherAudioDuckingConfiguration =
                    AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: false, duckingLevel: .min)
                // Note: don't touch mainMixerNode here; wiring the mixer breaks VP init (-10875).
            }
            if let vpError { throw vpError }
        }
        usingVoiceProcessing = voiceProcessing
        let inFormat = voiceProcessing ? node.outputFormat(forBus: 0) : AudioDevices.tapFormat(node)
        // Built-in Mac mics are multi-channel arrays (3 ch on a MacBook Air) and
        // AVAudioConverter silently outputs zeros when downmixing them. So we mix
        // to mono ourselves first, then only resample.
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0,
              let monoIn = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inFormat.sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: monoIn, to: Recorder.format) else { throw DictationError.noMic }
        let out = Recorder.format
        try Recorder.objc { node.installTap(onBus: 0, bufferSize: 1024, format: inFormat) { [weak self] buffer, _ in
            guard let self, let mono = Recorder.downmix(buffer, to: monoIn) else { return }
            self.report(mono)
            let cap = AVAudioFrameCount(Double(mono.frameLength) * out.sampleRate / inFormat.sampleRate) + 32
            guard let dst = AVAudioPCMBuffer(pcmFormat: out, frameCapacity: cap) else { return }
            var fed = false
            var err: NSError?
            converter.convert(to: dst, error: &err) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return mono
            }
            guard err == nil, dst.frameLength > 0, let ch = dst.floatChannelData?[0] else { return }
            let chunk = UnsafeBufferPointer(start: ch, count: Int(dst.frameLength))
            self.lock.withLock { self.samples.append(contentsOf: chunk) }
            self.onSamples?(Array(chunk))
        } }
        var startError: Error?
        do {
            try Recorder.objc {
                if cached == nil { engine.prepare() }
                do { try engine.start() } catch { startError = error }
            }
        } catch { startError = error }
        if let startError { _ = try? Recorder.objc { node.removeTap(onBus: 0) }; throw startError }
        self.engine = engine
        cache[voiceProcessing] = engine
    }

    /// Averages every input channel into one. Handles float and int16 input.
    static func downmix(_ b: AVAudioPCMBuffer, to mono: AVAudioFormat) -> AVAudioPCMBuffer? {
        let n = Int(b.frameLength), chans = Int(b.format.channelCount)
        guard n > 0, let dst = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: b.frameLength),
              let o = dst.floatChannelData?[0] else { return nil }
        dst.frameLength = b.frameLength
        if let f = b.floatChannelData {
            let interleaved = b.format.isInterleaved
            for i in 0..<n {
                var sum: Float = 0
                for c in 0..<chans { sum += interleaved ? f[0][i * chans + c] : f[c][i] }
                o[i] = sum / Float(chans)
            }
        } else if let s = b.int16ChannelData {
            let interleaved = b.format.isInterleaved
            for i in 0..<n {
                var sum: Float = 0
                for c in 0..<chans { sum += Float(interleaved ? s[0][i * chans + c] : s[c][i]) / 32768 }
                o[i] = sum / Float(chans)
            }
        } else { return nil }
        return dst
    }

    var sampleCount: Int { lock.withLock { samples.count } }
    func copy(from: Int, to: Int) -> [Float] {
        lock.withLock { from < to && to <= samples.count ? Array(samples[from..<to]) : [] }
    }

    /// Hand back what was heard right now, touching nothing but the buffer (never blocks on
    /// audio hardware, even if a Bluetooth route is hung).
    func drainSamples() -> [Float] { lock.withLock { let s = samples; samples = []; return s } }

    /// Stop listening and hand back what was heard, without waiting for the engine to stop.
    func takeSamples() -> [Float] {
        engine?.inputNode.removeTap(onBus: 0)
        return lock.withLock { let s = samples; samples = []; return s }
    }

    func stop() -> [Float] {
        if let e = engine { _ = try? Recorder.objc { e.inputNode.removeTap(onBus: 0); e.stop() } }
        engine = nil
        return lock.withLock { let s = samples; samples = []; return s }
    }

    /// macOS often delivers mic audio in ~100 ms chunks. Slice each chunk into ~20 ms
    /// hops and release them evenly, so the bars move at ~50 fps instead of 10.
    private func report(_ buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        let total = Int(buffer.frameLength), rate = buffer.format.sampleRate
        let hop = max(256, Int(rate * 0.02))
        var offset = 0, k = 0
        while offset < total {
            let len = min(hop, total - offset)
            let bands = meter.process(ch + offset, count: len, sampleRate: rate)
            let delay = Double(k) * Double(hop) / rate
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.onBands?(bands) }
            offset += len; k += 1
        }
    }
}

// MARK: - Engines

/// NVIDIA Parakeet TDT (Ultra) on the Apple Neural Engine. ~100 ms for a sentence.
actor ParakeetEngine {
    private var asr: AsrManager?
    var isReady: Bool { asr != nil }

    func load(progress: @escaping @Sendable (Double) -> Void) async throws {
        let models = try await AsrModels.downloadAndLoad(version: .ultra) { p in progress(p.fractionCompleted) }
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        // Warm up so the first real dictation is instant.
        var st = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        _ = try? await manager.transcribe([Float](repeating: 0, count: 16_000), decoderState: &st)
        asr = manager
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard let asr else { throw DictationError.noEngine }
        var padded = samples
        if padded.count < 16_000 { padded += [Float](repeating: 0, count: 16_000 - padded.count) }
        var st = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
        return try await asr.transcribe(padded, decoderState: &st).text
    }
}

/// Apple's on-device SpeechAnalyzer. Ships with macOS, zero download, always there.
/// Prepared once, then only read: safe to share.
nonisolated final class AppleEngine: @unchecked Sendable {
    private(set) var isReady = false
    private(set) var locale = Locale(identifier: "en_US")
    private(set) var format: AVAudioFormat?

    private func transcriber() -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
    }

    func prepare(onDownload: @escaping @Sendable () -> Void) async throws {
        isReady = false
        let wanted = Settings.language == "auto" ? Locale.current : Locale(identifier: Settings.language)
        if let l = await SpeechTranscriber.supportedLocale(equivalentTo: wanted) { locale = l }
        else if await SpeechTranscriber.supportedLocale(equivalentTo: locale) == nil { throw DictationError.unsupported }
        let t = transcriber()
        if let req = try await AssetInventory.assetInstallationRequest(supporting: [t]) {
            await MainActor.run { onDownload() }
            try await req.downloadAndInstall()
        }
        format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [t])
        isReady = format != nil
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard let format, !samples.isEmpty else { throw DictationError.noEngine }
        let src = Recorder.format
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: AVAudioFrameCount(samples.count)),
              let conv = AVAudioConverter(from: src, to: format) else { throw DictationError.noEngine }
        inBuf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { inBuf.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        let cap = AVAudioFrameCount(Double(samples.count) * format.sampleRate / src.sampleRate) + 64
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: cap) else { throw DictationError.noEngine }
        var fed = false
        var err: NSError?
        conv.convert(to: outBuf, error: &err) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true; status.pointee = .haveData; return inBuf
        }
        if let err { throw err }

        let t = transcriber()
        let analyzer = SpeechAnalyzer(modules: [t])
        let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
        cont.yield(AnalyzerInput(buffer: outBuf))
        cont.finish()
        let collect = Task { () throws -> String in
            var s = ""
            for try await r in t.results where r.isFinal { s += String(r.text.characters) }
            return s
        }
        try await analyzer.start(inputSequence: stream)
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await collect.value
    }
}

/// Text already transcribed while you were still talking, and how far it got.
actor PartialTranscript {
    private(set) var consumed = 0
    private var texts: [String] = []
    func reset() { consumed = 0; texts = [] }
    func append(_ text: String, upTo: Int) { texts.append(text); consumed = upTo }
    func take() -> ([String], Int) { defer { reset() }; return (texts, consumed) }
}

/// Synchronised by hand: the recorder runs on `audioQueue`, engines are actors, UI state hops to main.
nonisolated final class Dictation: @unchecked Sendable {
    let recorder = Recorder()
    let parakeet = ParakeetEngine()
    let apple = AppleEngine()
    private(set) var parakeetReady = false
    private(set) var parakeetProgress: Double?   // non-nil while downloading
    private(set) var lastEngine = ""
    private(set) var lastDuration: Double = 0
    private(set) var lastSamples: [Float] = []   // for "Retry Last Dictation"
    private var chunkTask: Task<Void, Never>?
    private var lastDevices = ""      // audioQueue only
    private let partial = PartialTranscript()

    /// Long dictations: while you're still talking, transcribe every finished stretch
    /// (cut at a real pause) in the background. When you stop, only the last few seconds
    /// are left, so 90 seconds pastes as fast as 3.
    private func startChunking() {
        chunkTask?.cancel()
        guard Settings.engine == .parakeet, parakeetReady, Languages.parakeetSpeaks(Settings.language) else { chunkTask = nil; return }
        let rec = recorder, eng = parakeet, part = partial
        chunkTask = Task.detached(priority: .userInitiated) {
            await part.reset()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                if Task.isCancelled { break }
                let done = await part.consumed
                let total = rec.sampleCount
                guard total - done >= 16_000 * 12 else { continue }
                let window = rec.copy(from: done, to: total - 8_000)          // leave the last 0.5 s alone
                guard let cut = Dictation.pause(in: window, atLeast: 16_000 * 8) else { continue }
                if let text = try? await eng.transcribe(Array(window[..<cut])) {
                    await part.append(text, upTo: done + cut)
                }
            }
        }
    }

    /// Where to cut: the quietest 300 ms in the last 4 s of `window`, but only if it's a
    /// real pause (well below the speech around it). nil = keep listening.
    nonisolated static func pause(in window: [Float], atLeast minimum: Int) -> Int? {
        let hop = 800, win = 4_800
        guard window.count >= minimum + win else { return nil }
        func energy(_ i: Int) -> Float {
            var e: Float = 0
            var j = i
            while j < i + win { e += window[j] * window[j]; j += 4 }
            return e
        }
        let from = max(minimum, window.count - 16_000 * 4)
        var best = Float.greatestFiniteMagnitude, at = -1, total: Float = 0, n = 0
        var i = from
        while i + win <= window.count { let e = energy(i); total += e; n += 1; if e < best { best = e; at = i }; i += hop }
        guard at >= 0, n > 2, best < (total / Float(n)) * 0.15 else { return nil }
        return at + win / 2
    }

    /// Offline version of the same thing, for the self-test.
    nonisolated static func transcribeInPieces(_ samples: [Float], with eng: ParakeetEngine) async throws -> (text: String, pieces: Int, tailStart: Int) {
        var texts: [String] = [], done = 0
        while samples.count - done >= 16_000 * 12 {
            let window = Array(samples[done..<(samples.count - 8_000)])
            guard let cut = Dictation.pause(in: window, atLeast: 16_000 * 8) else { break }
            texts.append(try await eng.transcribe(Array(window[..<cut]))); done += cut
        }
        let pieces = texts.count
        texts.append(try await eng.transcribe(Array(samples[done...])))
        return (texts.filter { !$0.isEmpty }.joined(separator: " "), pieces, done)
    }

    /// Run the last recording through the other engine (when a word came out wrong).
    func retryLast() async throws -> String {
        guard !lastSamples.isEmpty else { return "" }
        if lastEngine == "Parakeet" { lastEngine = "Apple"; return try await apple.transcribe(lastSamples) }
        if parakeetReady { lastEngine = "Parakeet"; return try await parakeet.transcribe(lastSamples) }
        return try await apple.transcribe(lastSamples)
    }

    var ready: Bool { parakeetReady || apple.isReady }

    func prepare(notify: @escaping @Sendable (String) -> Void, changed: @escaping @Sendable () -> Void) {
        Task {
            do { try await apple.prepare { notify("Getting speech ready… one time only") } }
            catch { notify(error.localizedDescription) }
            await MainActor.run { changed() }
        }
        Task {
            do {
                try await parakeet.load { p in
                    DispatchQueue.main.async { self.parakeetProgress = p; changed() }
                }
                parakeetReady = true
            } catch {
                NSLog("Spitball: Parakeet failed to load: \(error)")
            }
            await MainActor.run { self.parakeetProgress = nil; changed() }
        }
    }

    /// A mic that "starts" but delivers nothing (AirPods mid-handoff) used to give an empty
    /// dictation. Check after 0.4 s: rebuild once, then fall back to the Mac's own mic.
    private func watchForSilentMic(attempt: Int) {
        audioQueue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.recording, self.recorder.sampleCount == 0 else { return }
            // Step 1: if echo cancellation is on, it's the likeliest culprit: drop it.
            // Step 2: the mic itself didn't answer: use the Mac's own.
            if self.recorder.usingVoiceProcessing { Recorder.vpBrokenUntil = Date() + 15 * 60 }
            if attempt == 2 { AudioDevices.forceBuiltIn = true }
            Timing.log.error("mic silent after start (attempt \(attempt, privacy: .public)); restarting fresh\(attempt == 2 ? " on the Mac mic" : "", privacy: .public)")
            do { try self.recorder.restartFresh() } catch { Timing.log.error("restart failed: \(error.localizedDescription, privacy: .public)") }
            if attempt == 2 { DispatchQueue.main.async { self.onFallback?() } }
            if attempt < 2 { self.watchForSilentMic(attempt: attempt + 1) }
        }
    }
    var onFallback: (@MainActor @Sendable () -> Void)?

    /// The language changed: get Apple's engine ready for it (downloads once if needed).
    func reloadLanguage(notify: @escaping @Sendable (String) -> Void) {
        Task {
            do { try await apple.prepare { notify("Getting the new language ready…") } }
            catch { notify(error.localizedDescription) }
        }
    }

    private let audioQueue = DispatchQueue(label: "spitball.audio", qos: .userInteractive)
    private var prearmed = false        // audioQueue only
    private var recording = false       // audioQueue only

    /// First ⌘ tap of a possible double-tap: start the mic now so it's already
    /// running when the second tap lands, and your first word isn't clipped.
    func prewarm() {
        if Settings.noise == .always || (Settings.noise == .smart && AudioActivity.onCall()) { return }
        audioQueue.async {
            guard !self.recording, !self.prearmed else { return }
            if (try? self.recorder.start()) != nil { self.prearmed = true }
        }
    }

    /// No second tap came: turn the mic back off and throw the audio away.
    func abortPrewarm() {
        audioQueue.async {
            guard self.prearmed, !self.recording else { return }
            _ = self.recorder.stop()
            self.prearmed = false
        }
    }

    /// Starts the mic off the main thread (voice processing can take ~1 s to spin up).
    /// Called at launch and whenever the default mic changes.
    func warmUp() {
        recorder.onDeviceChange = { [weak self] in
            guard let me = self else { return }
            me.audioQueue.asyncAfter(deadline: .now() + 0.5) { [weak me] in
                guard let me else { return }
                // React only when the real mics (or the default one) changed. Echo cancellation
                // and macOS create hidden aggregate devices of their own; rebuilding on those
                // fed back into itself and kept Core Audio churning (2.3.3).
                let now = AudioDevices.signature()
                guard now != me.lastDevices else { return }
                me.lastDevices = now
                AudioDevices.forceBuiltIn = false        // real change: give the default mic another chance
                guard !me.recording, !me.prearmed else { return }
                me.recorder.warmUp()
            }
        }
        audioQueue.async { self.lastDevices = AudioDevices.signature() }
        audioQueue.async { self.recorder.warmUp() }
    }

    func start(ready: @escaping @MainActor @Sendable (Error?) -> Void) {
        audioQueue.async {
            do {
                if self.prearmed { self.prearmed = false } else { try self.recorder.start() }
                self.recording = true
                DispatchQueue.main.async { self.startChunking() }
                self.watchForSilentMic(attempt: 1)
                DispatchQueue.main.async { ready(nil) }
            } catch { DispatchQueue.main.async { ready(error) } }
        }
    }

    func finish() async throws -> String {
        // Take the words straight from the buffer: never wait in line behind the audio queue,
        // which can stall for seconds when a Bluetooth route is being rebuilt.
        recording = false
        let samples = recorder.drainSamples()
        audioQueue.async {
            _ = self.recorder.stop()                               // shut the mic off meanwhile
            DispatchQueue.main.async { Bloop.stop() }              // after the mic is off, so call-mode processing can't duck it
        }
        lastDuration = Double(samples.count) / 16_000
        lastSamples = samples
        let streamer = chunkTask; chunkTask = nil
        streamer?.cancel(); await streamer?.value                 // let a piece in flight land, in order
        guard samples.count > 4_000 else { return "" }   // < 0.25 s: nothing said
        if Settings.engine == .parakeet && parakeetReady && Languages.parakeetSpeaks(Settings.language) {
            do {
                let (pieces, done) = await partial.take()
                let tail = done < samples.count ? Array(samples[done...]) : []
                let t = tail.count > 4_000 ? try await parakeet.transcribe(tail) : ""
                lastEngine = pieces.isEmpty ? "Parakeet" : "Parakeet+\(pieces.count)"
                return (pieces + [t]).filter { !$0.isEmpty }.joined(separator: " ")
            } catch {
                NSLog("Spitball: Parakeet failed, falling back to Apple: \(error)")
            }
        }
        lastEngine = "Apple"
        return try await apple.transcribe(samples)
    }

    /// Long audio (notes): Parakeet chunks it itself; Apple's engine as a backup.
    func transcribeLong(_ samples: [Float]) async throws -> String {
        if parakeetReady && Languages.parakeetSpeaks(Settings.language) {
            if let t = try? await parakeet.transcribe(samples) { return t }
        }
        return try await apple.transcribe(samples)
    }

    func cancel() {
        chunkTask?.cancel(); chunkTask = nil
        audioQueue.async { self.recording = false; self.prearmed = false; _ = self.recorder.stop(); DispatchQueue.main.async { Bloop.stop() } }
    }
}

// MARK: - Typing into the focused app

nonisolated enum Typer {
    @MainActor static func paste(_ text: String) {
        if NSApp.isActive, let tv = NSApp.keyWindow?.firstResponder as? NSTextView {
            tv.insertText(text, replacementRange: tv.selectedRange())
            return
        }
        let pb = NSPasteboard.general
        let saved: [NSPasteboardItem] = (pb.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for t in item.types { if let d = item.data(forType: t) { copy.setData(d, forType: t) } }
            return copy
        }
        pb.clearContents()
        pb.setString(text, forType: .string)
        // Tell clipboard managers to ignore this.
        pb.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        let ourChange = pb.changeCount

        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard pb.changeCount == ourChange else { return }
            pb.clearContents()
            if !saved.isEmpty { pb.writeObjects(saved) }
        }
    }

    static func clean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if Settings.removeFillers {
            s = s.replacingOccurrences(of: #"(?i)(^|[\s,])(u+m+|u+h+|e+r+m+|a+h+|h+m+)[,.]?(?=\s|$)"#,
                                       with: "$1", options: .regularExpression)
            s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            s = s.replacingOccurrences(of: #"\s+([,.!?])"#, with: "$1", options: .regularExpression)
            s = s.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
            // Re-capitalize sentence starts a removed filler may have exposed.
            // Skips abbreviations like "p.m." / "e.g." (single letters between dots).
            var out = "", cap = true
            let chars = Array(s)
            for (i, ch) in chars.enumerated() {
                if cap, ch.isLetter { out += ch.uppercased(); cap = false; continue }
                if ch == "." {
                    let abbrev = i >= 1 && chars[i - 1].isLetter && (i < 2 || chars[i - 2] == "." || chars[i - 2].isWhitespace)
                    cap = !abbrev
                } else if "!?".contains(ch) { cap = true }
                else if !ch.isWhitespace { cap = false }
                out.append(ch)
            }
            s = out
        }
        return s
    }
}

// MARK: - Double-tap detector (pure logic, unit-tested)

/// Fires on two quick, clean taps of a modifier: no other key, click or modifier in between.
struct DoubleTapDetector {
    var maxTap: TimeInterval = 0.30     // press → release
    var maxGap: TimeInterval = 0.40     // first release → second press
    private var downAt: TimeInterval?
    private var clean = false
    private var lastTapUp: TimeInterval?

    enum Event { case none, tap, doubleTap }

    mutating func press(at t: TimeInterval, otherModifiers: Bool) {
        downAt = t
        clean = !otherModifiers
        if let last = lastTapUp, t - last > maxGap { lastTapUp = nil }
    }

    mutating func release(at t: TimeInterval) -> Event {
        defer { downAt = nil }
        guard let d = downAt, clean, t - d <= maxTap else { lastTapUp = nil; return .none }
        if let last = lastTapUp, d - last <= maxGap {
            lastTapUp = nil
            return .doubleTap
        }
        lastTapUp = t
        return .tap
    }

    /// Any other key, click or modifier: this isn't a tap.
    mutating func interrupt() { clean = false; lastTapUp = nil }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let island = Island()
    let welcome = Welcome()
    let prefs = PreferencesWindow()
    let liveCaption = LiveCaption()
    /// Sparkle: checks https://itsnicksimpson.github.io/spitball/appcast.xml daily, verifies the EdDSA signature.
    var updater: SPUStandardUpdaterController?
    lazy var cursorDot = CursorDot(model: island.model)
    let keys = KeyState()
    let dictation = Dictation()
    var statusItem: NSStatusItem!
    var monitors: [Any] = []
    lazy var menu: NSMenu = { let m = NSMenu(); m.delegate = self; return m }()

    enum State { case idle, holding(Date), handsFree }
    var state: State = .idle
    var busy = false            // finishing a transcription
    var queuedStart = false     // double-tapped while finishing: start right after the paste

    func startQueued() {
        guard queuedStart else { return }
        queuedStart = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, case .idle = self.state, !self.busy else { return }
            self.begin(handsFree: true)
        }
    }
    var lastEnd = Date.distantPast
    var targetApp: String?       // app you were in when dictation started
    var screenTerms: [String] = []   // file names / code terms visible when dictation started
    var editTarget: String?      // Command Mode: the selected text being edited
    var session = 0             // bumps on every start/end so late mic callbacks are ignored
    var swallowRelease = false  // release after the press that ended hands-free
    var holdKeyDown = false
    var taps = DoubleTapDetector()
    var commandDown = false

    /// Clicking Spitball in Applications / Launchpad / Spotlight while it's running opens the app window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openApp()   // the island panel always counts as "visible", so don't trust the flag
        return false
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        dictation.recorder.onBands = { [weak self] b in self?.island.bands(b) }
        NSApp.mainMenu = Self.editMenu()
        setupMenu()
        setupMonitors()
        requestPermissions()
        dictation.prepare(
            notify: { [weak self] msg in DispatchQueue.main.async { self?.island.flash(msg, seconds: 4) } },
            changed: { [weak self] in Task { @MainActor in self?.updateIcon() } })
        _ = Store.shared   // loads data (and brings it over from Murmur, once)
        if Bundle.main.bundleURL.pathExtension == "app" {
            updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        }
        if Settings.showInDock { NSApp.setActivationPolicy(.regular) }
        DockPresence.start()
        dictation.onFallback = { [weak self] in self?.island.flash("Your headphones' mic didn't answer. Using the Mac's mic.", seconds: 2.6) }
        dictation.warmUp()
        applyTiming()
        if Polisher.available { Polisher.prewarm() }
        if !Settings.onboarded { welcome.show(app: self) } else { WhatsNew.showIfNeeded() }
        NotificationCenter.default.addObserver(forName: .spitballMicChanged, object: nil, queue: .main) { [weak self] _ in self?.dictation.warmUp() }
        MainActor.assumeIsolated {
            let notes = Notetaker.shared
            let dict = dictation
            notes.transcribe = { samples in try await dict.transcribeLong(samples) }
            notes.onChange = { [weak self] in self?.updateIcon() }
        }
        startMeetingWatch()
        NotificationCenter.default.addObserver(forName: .spitballLanguageChanged, object: nil, queue: .main) { [weak self] _ in
            self?.dictation.reloadLanguage { msg in DispatchQueue.main.async { self?.island.flash(msg) } }
        }
    }

    /// Everything that happens to your words between the engine and the paste.
    nonisolated static func format(_ raw: String, app: String?, terms: [String]) async -> String {
        var text = raw
        let (style, mine) = await MainActor.run { (Store.shared.style(for: app), Store.shared.instructions(for: app)) }
        let kind = AppKind.of(app)
        text = SpokenFormat.scratchThat(text)
        if !terms.isEmpty { text = ScreenContext.fix(text, terms: terms) }
        if style == .texting && mine.isEmpty {
            text = SpokenFormat.texting(text)                  // instant, no model needed
        } else if AppDelegate.needsAI(text, style: style, kind: kind, instructions: mine) {
            text = await Polisher.polish(text, style: style, kind: kind, instructions: mine, terms: terms)
        } else if style != .asSpoken || kind == .notes {
            text = SpokenFormat.lists(text)   // instant, no model needed
        }
        if !terms.isEmpty { text = ScreenContext.fix(text, terms: terms) }
        return await MainActor.run { Store.shared.apply(text) }
    }

    /// Speed first: Smart only waits for Apple Intelligence when it would actually change
    /// something. Everything else pastes the moment Parakeet is done (~100 ms).
    nonisolated static func needsAI(_ text: String, style: WritingStyle, kind: AppKind, instructions: String) -> Bool {
        guard Polisher.available, style != .asSpoken, text.split(separator: " ").count >= 3 else { return false }
        if style != .smart || !instructions.isEmpty { return true }   // a style or rules you chose
        return kind == .email                                           // greeting, paragraphs, sign-off
    }

    @objc func retryLast() {
        guard !busy, case .idle = state else { return }
        busy = true
        island.show(.working)
        let (app, terms) = (targetApp, screenTerms)
        Task {
            let raw = (try? await dictation.retryLast()) ?? ""
            let text = await AppDelegate.format(Typer.clean(raw), app: app, terms: terms)
            await MainActor.run {
                self.busy = false
                guard !text.isEmpty else { self.island.flash("Nothing to retry", seconds: 1.4); return }
                if !Store.shared.history.isEmpty { Store.shared.history[0].text = text }
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                self.island.flash("Retried with \(self.dictation.lastEngine). ⌘V to paste", seconds: 2.2)
            }
        }
    }

    @objc func toggleDock() {
        Settings.showInDock.toggle()
        NSApp.setActivationPolicy(Settings.showInDock ? .regular : .accessory)
    }

    // MARK: Notes

    @objc func toggleVoiceNote() { MainActor.assumeIsolated { Notetaker.shared.toggle(.voice); noteFeedback() } }
    @objc func toggleMeeting() { MainActor.assumeIsolated { Notetaker.shared.toggle(.meeting); noteFeedback() } }

    @MainActor func noteFeedback() {
        let n = Notetaker.shared
        if n.isRecording { island.flash(n.current?.kind == .meeting ? "Taking meeting notes. ⌃⌘M to stop" : "Recording a note. ⌃⌘N to stop", seconds: 2.2) }
        else if n.finishing { island.flash("Writing up your note…", seconds: 1.6) }
        if let e = n.lastError { island.flash(e, seconds: 3.5) }
    }

    private var callWasOn = false
    /// When a call starts, offer bot-free notes once (never records on its own).
    func startMeetingWatch() {
        Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, Settings.meetingPrompt else { return }
                let on = AudioActivity.onCall()
                if on && !self.callWasOn && !Notetaker.shared.isRecording, case .idle = self.state {
                    self.island.flash("On a call? ⌃⌘M takes notes. No bot joins.", seconds: 4)
                }
                self.callWasOn = on
            }
        }
    }

    /// Accessory apps have no menu bar, but key equivalents (⌘C/⌘V/⌘A/⌘Z) still
    /// route through the main menu, so the welcome window's text box needs one.
    static func editMenu() -> NSMenu {
        let main = NSMenu()
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        return main
    }

    // MARK: Permissions

    func requestPermissions() {
        // These answer on a background thread: the handlers must not be main-actor code.
        AVCaptureDevice.requestAccess(for: .audio) { @Sendable _ in }
        SFSpeechRecognizer.requestAuthorization { @Sendable _ in }
        let opts = ["AXTrustedCheckOptionPrompt" as CFString as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    var hasAccessibility: Bool { AXIsProcessTrusted() }
    var hasMic: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }

    // MARK: Hotkeys

    func setupMonitors() {
        let flags: (NSEvent) -> Void = { [weak self] e in self?.handleFlags(e) }
        let keys: (NSEvent) -> Void = { [weak self] e in self?.handleKeyDown(e) }
        let clicks: (NSEvent) -> Void = { [weak self] _ in
            self?.taps.interrupt()
            if case .idle = self?.state { self?.dictation.abortPrewarm() }
        }
        for m in [
            NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags),
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: keys),
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel], handler: clicks),
            NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { flags($0); return $0 },
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { keys($0); return $0 },
        ] { if let m { monitors.append(m) } }
    }

    func handleFlags(_ e: NSEvent) {
        keys.update(e)
        applyTiming()
        let trigger = Settings.trigger
        if trigger == .doubleCommand {
            guard e.keyCode == 55 || e.keyCode == 54 else { taps.interrupt(); return }
            let down = e.modifierFlags.contains(.command)
            guard down != commandDown else { return }
            commandDown = down
            let others = e.modifierFlags.intersection([.shift, .option, .control, .function]).isEmpty == false
            if down {
                // One press finishes, on key-down for speed. Swallow the rest of that
                // tap so a habitual second tap can't start a new recording.
                if case .handsFree = state, !others {
                    taps.interrupt()
                    end()
                    return
                }
                taps.press(at: e.timestamp, otherModifiers: others)
            } else {
                switch taps.release(at: e.timestamp) {
                case .doubleTap:
                    if case .idle = state, Date().timeIntervalSince(lastEnd) > 0.3 {
                        if busy { queuedStart = true; island.flash("One sec, finishing the last one…", seconds: 0.8) }   // starts the moment it's pasted
                        else { begin(handsFree: true) }
                    }
                case .tap:
                    if case .idle = state, !busy, dictation.ready, Date().timeIntervalSince(lastEnd) > 0.3 {
                        dictation.prewarm()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            if case .idle = self.state { self.dictation.abortPrewarm() }
                        }
                    }
                case .none: break
                }
            }
            return
        }
        guard let code = trigger.holdKeyCode, e.keyCode == code else { return }
        let down = e.modifierFlags.contains(trigger.flag)
        guard down != holdKeyDown else { return }
        holdKeyDown = down
        down ? holdPressed() : holdReleased()
    }

    func handleKeyDown(_ e: NSEvent) {
        taps.interrupt()
        let cc = e.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.control, .command]
        if cc && e.keyCode == 9 { pasteLast(); return }          // ⌃⌘V
        if cc && e.keyCode == 45 { toggleVoiceNote(); return }   // ⌃⌘N
        if cc && e.keyCode == 46 { toggleMeeting(); return }     // ⌃⌘M
        if case .idle = state { dictation.abortPrewarm() }
        switch state {
        case .holding: cancel()                       // a real shortcut, not dictation
        case .handsFree: if e.keyCode == 53 { cancel() }  // Esc
        case .idle: break
        }
    }

    func holdPressed() {
        switch state {
        case .idle: if !busy { begin(handsFree: false) }
        case .handsFree: swallowRelease = true; end()
        case .holding: break
        }
    }

    func holdReleased() {
        switch state {
        case .holding(let t):
            if Date().timeIntervalSince(t) < 0.28 {
                state = .handsFree                     // quick tap = hands-free; tap again to finish
                island.show(.listening, handsFree: true)
            } else {
                end()
            }
        default:
            swallowRelease = false
        }
    }

    func begin(handsFree: Bool) {
        guard hasMic else { island.flash("Allow microphone access in System Settings"); openPrivacy("Privacy_Microphone"); return }
        guard dictation.ready else { island.flash("Speech is still getting ready…"); return }
        Bloop.start()
        targetApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        screenTerms = []
        if !welcome.isPracticing, AppKind.of(targetApp) == .email || Store.shared.style(for: targetApp) != .smart || !Store.shared.instructions(for: targetApp).isEmpty {
            let app = targetApp
            Polisher.prepare(style: Store.shared.style(for: app), kind: AppKind.of(app), instructions: Store.shared.instructions(for: app))
        }
        if Settings.screenContext && !welcome.isPracticing && AppKind.of(targetApp) == .code {   // only where file names matter
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let t = ScreenContext.terms()
                DispatchQueue.main.async { self?.screenTerms = t }
            }
        }
        // Command Mode: is text selected? Asked in the background so the mic starts instantly.
        editTarget = nil
        island.model.editing = false
        if Settings.commandMode && Polisher.available && !welcome.isPracticing {
            let mine = session + 1
            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                let sel = Caret.selectedText()
                DispatchQueue.main.async {
                    guard let self, self.session == mine, let sel, !sel.isEmpty else { return }
                    self.editTarget = sel
                    self.island.model.editing = true
                }
            }
        }
        state = handsFree ? .handsFree : .holding(Date())
        keys.listening = true
        welcome.practice?.listening(true)
        if let p = welcome.practice, welcome.isPracticing {
            liveCaption.start(engine: dictation.apple) { [weak p] text in p?.live(text) }
            let caption = liveCaption
            dictation.recorder.onSamples = { chunk in caption.feed(chunk) }
        }
        if !welcome.isPracticing { cursorDot.show() }
        island.show(.listening, handsFree: handsFree)
        session += 1
        let mine = session
        dictation.start { [weak self] error in
            guard let self, mine == self.session else { return }
            if let error {
                self.state = .idle
                self.island.flash(error.localizedDescription)
                return
            }
            self.island.armed()
            if self.welcome.practice == nil { A11y.announce("Listening") }
            self.updateIcon()
        }
    }

    func end() {
        dictation.recorder.onSamples = nil
        liveCaption.stop()
        lastEnd = Date()
        session += 1
        keys.listening = false
        keys.working = true
        welcome.practice?.thinking()
        state = .idle
        busy = true
        island.show(.working)
        let (practicing, target, app, terms) = (welcome.isPracticing, editTarget, targetApp, screenTerms)
        Task.detached(priority: .userInitiated) {
            do {
                let t0 = Date()
                var text = Typer.clean(try await self.dictation.finish())
                let tHeard = Date()
                var editFailed = false
                if let target, !text.isEmpty {
                    // Command Mode: what you said is an instruction for the selected text.
                    if let edited = await Polisher.edit(target, instruction: text) { text = edited } else { editFailed = true }
                } else if !practicing {
                    text = await AppDelegate.format(text, app: app, terms: terms)
                }
                let ms = { (a: Date, b: Date) in Int(b.timeIntervalSince(a) * 1000) }
                Timing.log.notice("dictation: \(text.count, privacy: .public) chars, \(self.dictation.lastEngine, privacy: .public) \(ms(t0, tHeard), privacy: .public) ms, format \(ms(tHeard, Date()), privacy: .public) ms")
                await MainActor.run {
                    self.cursorDot.hide()
                    self.island.model.editing = false
                    self.editTarget = nil
                    if editFailed {
                        self.busy = false; self.keys.working = false; self.updateIcon()
                        self.island.flash("Couldn't make that edit", seconds: 2)
                        self.startQueued()
                        return
                    }
                    self.busy = false
                    self.keys.working = false
                    self.updateIcon()
                    // Practice in the welcome window: hand the words to it, don't paste.
                    if self.welcome.isPracticing, let p = self.welcome.practice {
                        self.island.hide()
                        p.heard(text)
                        return
                    }
                    guard !text.isEmpty else {
                        self.island.flash("Didn't catch that", seconds: 1.4)
                        A11y.announce("Didn't catch that")
                        self.startQueued()
                        return
                    }
                    if !self.hasAccessibility {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        self.island.flash("Copied. Allow Accessibility to auto-paste", seconds: 3.5)
                        return
                    }
                    Typer.paste(text)                       // words first, bookkeeping after
                    self.island.show(.done)
                    self.island.hide(after: 0.35)
                    let front = NSWorkspace.shared.frontmostApplication
                    Store.shared.record(text, seconds: self.dictation.lastDuration,
                                        app: front?.localizedName, bundleID: front?.bundleIdentifier)
                    Club.report()
                    A11y.announce("Inserted: \(text)")
                    self.startQueued()
                }
            } catch {
                await MainActor.run {
                    self.cursorDot.hide()
                    self.island.model.editing = false
                    self.editTarget = nil
                    self.busy = false
                    self.keys.working = false
                    self.updateIcon()
                    A11y.announce("Couldn't transcribe")
                    self.island.flash("Couldn't transcribe: \(error.localizedDescription)")
                    self.startQueued()
                }
            }
        }
    }

    func cancel() {
        dictation.recorder.onSamples = nil
        liveCaption.stop()
        cursorDot.hide()
        island.model.editing = false
        editTarget = nil
        session += 1
        keys.listening = false
        if let p = welcome.practice, p.phase == .listening { p.phase = .waiting }
        A11y.announce("Cancelled")
        dictation.cancel()
        state = .idle
        island.hide()
    }

    // MARK: Menu

    func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.menu = menu
        updateIcon()
    }

    /// The pixel comet, as a template image so it adapts to light/dark menu bars.
    static let menuBarIcon: NSImage? = {
        let dirs = [Bundle.main.resourceURL, URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")]
        for case let d? in dirs {
            if let img = NSImage(contentsOf: d.appendingPathComponent("MenuBarIcon.png")) {
                if let rep2 = NSImageRep(contentsOf: d.appendingPathComponent("MenuBarIcon@2x.png")) { rep2.size = NSSize(width: 18, height: 18); img.addRepresentation(rep2) }
                img.size = NSSize(width: 18, height: 18)
                img.isTemplate = true
                return img
            }
        }
        return nil
    }()

    func updateIcon() {
        let listening: Bool = { if case .idle = state { return false }; return true }()
        let noting = MainActor.assumeIsolated { Notetaker.shared.isRecording }
        let label = noting ? "Spitball, recording a note" : listening ? "Spitball, listening" : (busy ? "Spitball, transcribing" : (dictation.ready ? "Spitball, ready" : "Spitball, getting ready"))
        statusItem.button?.image = noting ? NSImage(systemSymbolName: "record.circle", accessibilityDescription: label) : (Self.menuBarIcon ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: label))
        statusItem.button?.appearsDisabled = !dictation.ready
        statusItem.button?.setAccessibilityLabel(label)
    }

    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu() }

    func rebuildMenu() {
        menu.removeAllItems()
        let status: String
        if case .idle = state {
            if let p = dictation.parakeetProgress { status = "Downloading speech model… \(Int(p * 100))%" }
            else if !dictation.ready { status = "Getting ready…" }
            else { status = Settings.trigger == .doubleCommand ? "Double-tap ⌘ to talk" : "\(Settings.trigger.label) to talk" }
        } else { status = "Listening…" }
        let open = item("Open Spitball", #selector(openApp), key: "o")
        open.image = Self.menuBarIcon
        menu.addItem(open)
        let head = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        if !hasMic { menu.addItem(item("Allow Microphone…", #selector(openMic))) }
        if !hasAccessibility { menu.addItem(item("Allow Accessibility…", #selector(openAX))) }
        menu.addItem(.separator())
        let last = item("Paste Last Dictation", #selector(pasteLast), key: "v")
        last.keyEquivalentModifierMask = [.control, .command]
        last.isEnabled = !Store.shared.history.isEmpty
        menu.addItem(last)
        let retry = item("Retry Last Dictation", #selector(retryLast))
        retry.isEnabled = !dictation.lastSamples.isEmpty
        menu.addItem(retry)
        let (rec, kind, elapsed, finishing) = MainActor.assumeIsolated { let n = Notetaker.shared; return (n.isRecording, n.current?.kind, n.elapsed, n.finishing) }
        let vn = item(rec && kind == .voice ? "Stop Voice Note (\(Note.clock(elapsed)))" : "New Voice Note", #selector(toggleVoiceNote), key: "n")
        vn.keyEquivalentModifierMask = [.control, .command]
        vn.isEnabled = !(rec && kind == .meeting) && !finishing
        menu.addItem(vn)
        let mt = item(rec && kind == .meeting ? "Stop Meeting Notes (\(Note.clock(elapsed)))" : "Take Meeting Notes", #selector(toggleMeeting), key: "m")
        mt.keyEquivalentModifierMask = [.control, .command]
        mt.isEnabled = !(rec && kind == .voice) && !finishing
        menu.addItem(mt)
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        if let updater {
            let up = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
            up.target = updater
            menu.addItem(up)
        }
        menu.addItem(.separator())
        menu.addItem(item("Quit Spitball", #selector(quit), key: "q"))
    }

    func item(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        return i
    }

    func applyTiming() {
        taps.maxTap = Settings.relaxedTiming ? 0.5 : 0.3
        taps.maxGap = Settings.relaxedTiming ? 0.75 : 0.4
    }
    @objc func showWelcome() { welcome.show(app: self) }
    @objc func showSettings() { prefs.show(app: self) }
    @objc func showHistory() { prefs.show(app: self, tab: .history) }
    @objc func openApp() { Settings.onboarded ? prefs.show(app: self) : welcome.show(app: self) }
    @objc func pasteLast() {
        guard let text = Store.shared.history.first?.text else { return }
        Typer.paste(text)
        A11y.announce("Pasted last dictation")
    }
    @objc func openMic() { openPrivacy("Privacy_Microphone") }
    @objc func openAX() { openPrivacy("Privacy_Accessibility") }
    @objc func quit() { NSApp.terminate(nil) }

    func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Entry

let cliArgs = Array(CommandLine.arguments.dropFirst())
if cliArgs.first == "--mcp" {
    MainActor.assumeIsolated { AgentAccess.runMCP() }
    exit(0)
} else if let c = cliArgs.first, AgentAccess.commands.contains(c) {
    exit(MainActor.assumeIsolated { AgentAccess.runCLI(cliArgs) })
} else if let i = CommandLine.arguments.firstIndex(of: "--render-demo") {
    _ = NSApplication.shared
    MainActor.assumeIsolated { DemoRender.run(out: CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "shots/demo") }
} else if let i = CommandLine.arguments.firstIndex(of: "--bench"), i + 1 < CommandLine.arguments.count {
    let path = CommandLine.arguments[i + 1]
    MainActor.assumeIsolated {
        var finished = false
        Task { await SelfTest.bench(path); finished = true }
        while !finished { RunLoop.main.run(until: Date() + 0.02) }   // keep the main actor free to run it
    }
} else if CommandLine.arguments.contains("--mic-test") {
    MicTest.run()
} else if CommandLine.arguments.contains("--self-test") {
    SelfTest.run()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

/// The sounds when recording starts and stops, in a few organic flavours.
enum SoundPack: String, CaseIterable, Identifiable {
    case soft, bowl, felt, rain, breath, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .soft: "Soft"
        case .bowl: "Singing bowl"
        case .felt: "Felt piano"
        case .rain: "Raindrop"
        case .breath: "Breath"
        case .none: "None"
        }
    }
}

enum Bloop {
    private static let cache = Mutex<[String: NSSound]>([:])
    private static func sound(_ name: String) -> NSSound? {
        if let s = cache.withLock({ $0[name] }) { return s }
        let dirs = [Bundle.main.resourceURL?.appendingPathComponent("Sounds"),
                    URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Sounds")]
        for case let d? in dirs {
            let url = d.appendingPathComponent(name + ".wav")
            if FileManager.default.fileExists(atPath: url.path), let s = NSSound(contentsOf: url, byReference: false) { cache.withLock { $0[name] = s }; return s }
        }
        return nil
    }
    /// VoiceOver users always get audio cues (falls back to Bloop if sounds are off).
    private static var pack: SoundPack? {
        let p = Settings.soundPack
        if p != .none { return p }
        return A11y.voiceOver ? .soft : nil
    }
    private static func play(_ name: String) { let s = sound(name); s?.stop(); s?.play() }
    static func start() { if let p = pack { play("\(p.rawValue)-start") } }
    static func stop() { if let p = pack { play("\(p.rawValue)-stop") } }
    static func chime() { if pack != nil { play("chime") } }
    static func sparkle() { if pack != nil { play("sparkle") } }
    /// Settings preview: start, then stop.
    static func preview(_ p: SoundPack) {
        guard p != .none else { return }
        play("\(p.rawValue)-start")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { play("\(p.rawValue)-stop") }
    }
}

/// Streams partial ("volatile") transcripts while you talk, using Apple's on-device
/// SpeechAnalyzer. Only used for the practice phrases, so words can light up as you say them.
/// Fed from the audio thread; its own queue serialises the work.
nonisolated final class LiveCaption: @unchecked Sendable {
    private var cont: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzer: SpeechAnalyzer?
    private var converter: AVAudioConverter?
    private var outFormat: AVAudioFormat?
    private var resultsTask: Task<Void, Never>?
    private let queue = DispatchQueue(label: "spitball.livecaption")

    func start(engine: AppleEngine, onText: @escaping @MainActor @Sendable (String) -> Void) {
        stop()
        guard engine.isReady, let fmt = engine.format,
              let conv = AVAudioConverter(from: Recorder.format, to: fmt) else { return }
        let t = SpeechTranscriber(locale: engine.locale, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
        let a = SpeechAnalyzer(modules: [t])
        let (stream, c) = AsyncStream<AnalyzerInput>.makeStream()
        cont = c; analyzer = a; converter = conv; outFormat = fmt
        resultsTask = Task {
            var final = ""
            do {
                for try await r in t.results {
                    let text = String(r.text.characters)
                    if r.isFinal { final += text }
                    let shown = final + (r.isFinal ? "" : text)
                    await MainActor.run { onText(shown) }
                }
            } catch { NSLog("Spitball: live caption results error: \(error)") }
        }
        Task {
            do {
                try await a.prepareToAnalyze(in: fmt)
                try await a.start(inputSequence: stream)
            } catch { NSLog("Spitball: live caption start error: \(error)") }
        }
    }

    func feed(_ samples: [Float]) {
        queue.async { [weak self] in
            guard let self, let cont = self.cont, let conv = self.converter, let out = self.outFormat, !samples.isEmpty,
                  let inBuf = AVAudioPCMBuffer(pcmFormat: Recorder.format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
            inBuf.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { inBuf.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
            let cap = AVAudioFrameCount(Double(samples.count) * out.sampleRate / Recorder.format.sampleRate) + 32
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: out, frameCapacity: cap) else { return }
            var fed = false
            conv.convert(to: outBuf, error: nil) { _, st in
                if fed { st.pointee = .noDataNow; return nil }
                fed = true; st.pointee = .haveData; return inBuf
            }
            if outBuf.frameLength > 0 { cont.yield(AnalyzerInput(buffer: outBuf)) }
        }
    }

    func stop() {
        cont?.finish(); cont = nil
        let a = analyzer; analyzer = nil
        resultsTask?.cancel(); resultsTask = nil
        Task { await a?.cancelAndFinishNow() }
    }
}

extension Notification.Name { static let spitballMicChanged = Notification.Name("spitballMicChanged") }
