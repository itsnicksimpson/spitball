import AppKit
import AVFoundation
import Observation
import SwiftUI

// MARK: - Live key state (drives the keycap in the welcome window)

@Observable final class KeyState {
    var commandDown = false
    var optionDown = false
    var fnDown = false
    var taps = 0              // recent ⌘ taps, resets shortly after
    var listening = false
    var working = false
    @ObservationIgnored private var resetWork: DispatchWorkItem?

    func update(_ e: NSEvent) {
        let f = e.modifierFlags
        let wasCommand = commandDown
        commandDown = f.contains(.command)
        optionDown = f.contains(.option)
        fnDown = f.contains(.function)
        if wasCommand && !commandDown {
            taps = min(taps + 1, 2)
            resetWork?.cancel()
            let w = DispatchWorkItem { [weak self] in self?.taps = 0 }
            resetWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: w)
        }
    }
}

// MARK: - Accessibility helper

enum A11y {
    /// Speak a status change to VoiceOver users (no-op for everyone else).
    static func announce(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var voiceOver: Bool { NSWorkspace.shared.isVoiceOverEnabled }
}

// MARK: - Practice (three guided dictations)

@Observable final class Practice {
    enum Phase: Equatable { case waiting, listening, thinking, heard(String, Bool) }

    static let phrases = [
        "Running five minutes late, start without me.",
        "Can you send me the deck by Friday?",
        "Thanks so much, talk soon!",
    ]

    var index = 0
    var phase: Phase = .waiting
    /// How many words of the current phrase you've said so far (for the Siri-style highlight).
    var spoken = 0

    /// Live partial transcript in → highlight the phrase words heard so far, in order.
    func live(_ text: String) {
        let heard = Practice.words(text)
        let target = Practice.words(phrase)
        var i = 0
        for w in heard where i < target.count {
            if let j = target[i...].prefix(3).firstIndex(of: w) { i = j + 1 }   // allow a skipped/misheard word
        }
        if i > spoken { withAnimation(.easeOut(duration: 0.18)) { spoken = i } }
    }

    static func words(_ s: String) -> [String] {
        let numbers = ["0": "zero", "1": "one", "2": "two", "3": "three", "4": "four", "5": "five",
                       "6": "six", "7": "seven", "8": "eight", "9": "nine", "10": "ten"]
        return s.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map { numbers[String($0)] ?? String($0) }
    }
    var finished = false
    @ObservationIgnored private var misses = 0
    var onFinish: (() -> Void)?

    var phrase: String { Practice.phrases[min(index, Practice.phrases.count - 1)] }

    func listening(_ on: Bool) {
        if on { spoken = 0; phase = .listening; A11y.announce("Listening. Say: \(phrase)") }
    }

    func thinking() { if phase == .listening { phase = .thinking } }

    func heard(_ text: String) {
        guard !finished else { return }
        let ok = !text.isEmpty && (Practice.score(text, phrase) >= 0.6 || misses >= 1)
        phase = .heard(text, ok)
        if ok {
            misses = 0
            if index < Practice.phrases.count - 1 { Bloop.chime() }
            A11y.announce(index < 2 ? "Got it. Next phrase." : "All set.")
            DispatchQueue.main.asyncAfter(deadline: .now() + (A11y.reduceMotion ? 0.8 : 1.1)) { self.advance() }
        } else {
            misses += 1
            A11y.announce(text.isEmpty ? "Didn't catch that. Try again." : "Heard \(text). Try once more.")
        }
    }

    private func advance() {
        if index >= Practice.phrases.count - 1 {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { finished = true }
            Bloop.sparkle()
            Member.shared.ensure()
            A11y.announce("You're in. Here's your Spitball ID card.")
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { index += 1; phase = .waiting; spoken = 0 }
        }
    }

    /// Share of the phrase's words we heard (numbers and punctuation forgiven).
    static func score(_ heard: String, _ target: String) -> Double {
        let numbers = ["0": "zero", "1": "one", "2": "two", "3": "three", "4": "four", "5": "five",
                       "6": "six", "7": "seven", "8": "eight", "9": "nine", "10": "ten"]
        func words(_ s: String) -> [String] {
            s.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map { numbers[String($0)] ?? String($0) }
        }
        let h = Set(words(heard)), t = words(target)
        guard !t.isEmpty else { return 0 }
        return Double(t.filter(h.contains).count) / Double(t.count)
    }
}

// MARK: - Window

final class Welcome: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private(set) var practice: Practice?
    private weak var app: AppDelegate?

    var isPracticing: Bool { window != nil && practice?.finished == false }

    func show(app: AppDelegate) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(); return }
        self.app = app
        let practice = Practice()
        practice.onFinish = { [weak self] in self?.finish() }
        self.practice = practice
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: .spitballSkinChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {   // delivered on the main queue
                    guard let self, let w = self.window, let app = self.app else { return }
                    let origin = w.frame.origin
                    w.delegate = nil; w.close(); self.window = nil
                    self.reopen(app: app)
                    self.window?.setFrameOrigin(origin)
                }
            }
        }
        reopen(app: app)
        A11y.announce("Welcome to Spitball. Double-tap the Command key, say the phrase on screen, then tap Command once to finish.")
    }

    private var observer: Any?

    /// Builds the window for the current look (keeps the same practice progress).
    private func reopen(app: AppDelegate) {
        guard let practice else { return }
        let skip: () -> Void = { [weak self] in self?.finish() }
        if Skin.isPro {
            let w = Pro.window(size: NSSize(width: 560, height: 760), title: "Welcome to Spitball", dark: true)
            w.delegate = self
            w.contentView = NSHostingView(rootView: ProWelcomeView(keys: app.keys, island: app.island.model, status: SetupStatus(app: app),
                                                                   practice: practice, trigger: Settings.trigger, skip: skip))
            w.center(); window = w
            w.makeKeyAndOrderFront(nil); NSApp.activate()
            return
        }
        let w = RetroWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 760),
                            styleMask: [.borderless, .miniaturizable], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.setAccessibilityLabel("Welcome to Spitball")
        w.contentView = NSHostingView(rootView: WelcomeView(
            keys: app.keys,
            island: app.island.model,
            status: SetupStatus(app: app),
            practice: practice,
            trigger: Settings.trigger,
            skip: skip))
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Doing the third phrase (or Skip) drops you straight into the product.
    func finish() {
        Settings.onboarded = true
        window?.close()
        app?.island.flash("You're set. Double-tap ⌘ anywhere", seconds: 2.4)
        A11y.announce("You're set. Double-tap Command in any app to dictate.")
    }

    func windowWillClose(_ notification: Notification) {
        Settings.onboarded = true
        window = nil
        practice = nil
    }
}

// MARK: - Setup status (polled)

@Observable final class SetupStatus {
    var mic = false
    var micDenied = false
    var accessibility = false
    var engine = "Getting ready…"
    var engineDone = false
    var progress: Double?
    private weak var app: AppDelegate?
    @ObservationIgnored private var timer: Timer?

    init(app: AppDelegate?) {
        self.app = app
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
    }
    isolated deinit { timer?.invalidate() }

    func refresh() {
        let s = AVCaptureDevice.authorizationStatus(for: .audio)
        mic = s == .authorized
        micDenied = s == .denied || s == .restricted
        accessibility = AXIsProcessTrusted()
        guard let d = app?.dictation else { return }
        if d.parakeetReady {
            engine = "Parakeet ready, on-device"; engineDone = true; progress = nil
        } else if let p = d.parakeetProgress {
            engine = "Downloading Parakeet… \(Int(p * 100))%"; engineDone = false; progress = p
        } else if d.apple.isReady {
            engine = "Apple Speech ready · Parakeet loading"; engineDone = true; progress = nil
        } else {
            engine = "Getting speech ready…"; engineDone = false
        }
    }

    func allowMic() {
        if micDenied { open("Privacy_Microphone") }
        else { AVCaptureDevice.requestAccess(for: .audio) { @Sendable _ in Task { @MainActor in self.refresh() } } }
    }

    func allowAccessibility() {
        let opts = ["AXTrustedCheckOptionPrompt" as CFString as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) { open("Privacy_Accessibility") }
    }

    private func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - View (retro, matches the website)

struct WelcomeView: View {
    var keys: KeyState
    var island: IslandModel
    var status: SetupStatus
    var practice: Practice
    let trigger: Trigger
    let skip: () -> Void
    var initialStage = 0

    @State private var stage = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("theme") private var theme: RetroTheme = .pacific
    @AppStorage("skin") private var skin: Skin = .playful

    var ready: Bool { status.mic && status.engineDone }

    var body: some View {
        VStack(spacing: 0) {
            RetroTitleBar(title: practice.finished ? "Spitball ID" : "Welcome to Spitball", theme: theme, close: skip)
            ZStack {
                Gingham(theme: theme)
                VStack(spacing: 16) {
                    hero
                        .opacity(stage >= 1 ? 1 : 0)
                        .offset(y: stage >= 1 || reduceMotion ? 0 : 14)
                    if !practice.finished {
                        SkinPicker(theme: theme).opacity(stage >= 1 ? 1 : 0)
                    }
                    Group {
                        if practice.finished { finale } else { practiceCard }
                    }
                    .opacity(stage >= 2 ? 1 : 0)
                    .offset(y: stage >= 2 || reduceMotion ? 0 : 14)
                    if !practice.finished {
                        setup.opacity(stage >= 3 ? 1 : 0)
                        if !status.accessibility && stage >= 3 { PermissionGuide(open: status.allowAccessibility) }
                        Button("Skip for now", action: skip)
                            .buttonStyle(.plain).font(RetroFont.mono(11)).foregroundStyle(theme.ink.opacity(0.6))
                            .accessibilityHint("Closes this window. Spitball keeps running in the menu bar.")
                    }
                }
                .padding(16)
            }
        }
        .background(theme.paper)
        .skinStroke(theme)
        .frame(width: 480, height: 760)
        .tint(theme.ink)
        .id(skin)
        .onAppear {
            if initialStage > 0 || reduceMotion { stage = 3; return }
            for (i, d) in [0.05, 0.35, 0.65].enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + d) {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { stage = i + 1 }
                }
            }
        }
    }

    /// Halftone sunset with the script wordmark, like the website hero.
    @ViewBuilder var hero: some View {
        if Skin.isPro { proHero } else { retroHero }
    }

    /// Pro: the app icon and a clean wordmark on soft grey.
    var proHero: some View {
        VStack(spacing: 8) {
            Image(nsImage: Pro.appIcon).resizable().frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text("Spitball").font(.system(size: 30, weight: .semibold)).tracking(-0.8).foregroundStyle(theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Say it. Ship it.").font(.system(size: 14)).foregroundStyle(theme.ink.opacity(0.55))
        }
        .frame(maxWidth: .infinity).frame(height: 170)
        .background(theme.paper)
        .skinStroke(theme, radius: 18)
        .skinDrop(theme)
    }

    var retroHero: some View {
        ZStack {
            Halftone(theme: theme)
            Circle().fill(theme.accent)
                .frame(width: 210, height: 210)
                .mask(VStack(spacing: 5) { ForEach(0..<9) { i in Rectangle().frame(height: CGFloat(18 - i)) } }.frame(height: 210, alignment: .top))
                .offset(y: 70)
            VStack(spacing: 0) {
                Text("\u{2002}Spitball\u{2002}").font(RetroFont.script(74)).foregroundStyle(.white)   // spaces: room for the swash
                    .shadow(color: theme.ink, radius: 0, x: 3, y: 3)
                    .rotationEffect(.degrees(-5))
                Text("“Say it. Ship it.”").font(RetroFont.serifItalic(20)).foregroundStyle(.white)
                    .shadow(color: theme.ink, radius: 0, x: 1.5, y: 1.5)
            }
            .accessibilityElement(children: .ignore).accessibilityLabel("Spitball. Say it. Ship it.")
            .accessibilityAddTraits(.isHeader)
        }
        .frame(height: 170)
        .clipped()
        .skinStroke(theme)
        .skinDrop(theme)
    }

    var practiceCard: some View {
        VStack(spacing: 0) {
            RetroTitleBar(title: "Practice \(practice.index + 1) of \(Practice.phrases.count)", theme: theme)
            VStack(spacing: 14) {
                highlightedPhrase
                    .font(RetroFont.serif(27))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .id(practice.index)
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    .accessibilityLabel("Say: \(practice.phrase)")
                result.frame(height: 20)
                HStack(spacing: 12) {
                    KeyCap(symbol: "⌘", label: "command", pressed: keys.commandDown)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(headline).font(RetroFont.title(12)).foregroundStyle(theme.ink)
                        Text(subline).font(RetroFont.mono(10)).foregroundStyle(theme.ink.opacity(0.65))
                    }
                    Spacer()
                    if practice.phase == .listening {
                        LiveMiniWave(island: island, animate: !reduceMotion).foregroundStyle(theme.ink).accessibilityHidden(true)
                    } else {
                        HStack(spacing: 5) {
                            ForEach(0..<2) { i in Rectangle().fill(keys.taps > i ? theme.ink : theme.ink.opacity(0.15)).frame(width: 7, height: 7) }
                        }.accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .padding(16)
        }
        .background(theme.paper)
        .skinStroke(theme)
        .skinDrop(theme)
        .opacity(ready ? 1 : 0.5)
        .allowsHitTesting(ready)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: practice.phase)
    }

    /// Siri-setup style: words light up as you say them.
    var highlightedPhrase: Text {
        let words = practice.phrase.split(separator: " ").map(String.init)
        var a = AttributedString("“"); a.foregroundColor = theme.ink
        for (i, w) in words.enumerated() {
            let lit = practice.phase != .listening && practice.phase != .thinking ? true : i < practice.spoken
            var part = AttributedString(w + (i < words.count - 1 ? " " : ""))
            part.foregroundColor = lit ? theme.ink : theme.ink.opacity(0.28)
            a += part
        }
        var close = AttributedString("”"); close.foregroundColor = theme.ink
        return Text(a + close)
    }

    @ViewBuilder var result: some View {
        switch practice.phase {
        case .heard(let text, let ok):
            Text(ok ? "Heard it!" : (text.isEmpty ? "Didn't catch that. Try again." : "Heard “\(text)”. Once more?"))
                .font(RetroFont.title(12)).foregroundStyle(theme.ink.opacity(ok ? 1 : 0.7)).lineLimit(1).truncationMode(.middle)
        case .thinking:
            Text("…").font(RetroFont.title(14)).foregroundStyle(theme.ink).accessibilityLabel("Transcribing")
        default: Color.clear
        }
    }

    var headline: String {
        if !status.mic { return "Allow the microphone below" }
        if !status.engineDone { return "Getting speech ready…" }
        switch practice.phase {
        case .listening: return "Listening… say it now"
        case .thinking: return "One sec…"
        default: return trigger == .doubleCommand ? "Double-tap ⌘ and say it" : "\(trigger.label) and say it"
        }
    }
    var subline: String {
        practice.phase == .listening ? (trigger == .doubleCommand ? "Tap ⌘ once when you're done" : "Let go when you're done") : "Esc cancels"
    }

    /// After the third phrase: your Spitball ID, ready to share.
    var finale: some View {
        VStack(spacing: 14) {
            IDCardView(member: Member.shared)
                .frame(width: 400, height: 252)
                .accessibilityLabel("Your Spitball member card, number \(Member.shared.number)")
            Text("You're in. Double-tap ⌘ in any app.").font(RetroFont.serif(24)).foregroundStyle(theme.ink)
            HStack(spacing: 10) {
                Button("Share on 𝕏") { Member.shared.shareOnX() }.buttonStyle(RetroButtonStyle(theme: theme))
                Button("Save image") { Member.shared.saveImage() }.buttonStyle(RetroButtonStyle(theme: theme))
                Button("Start talking") { skip() }.buttonStyle(RetroButtonStyle(theme: theme, filled: true)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(.vertical, 10)
        .transition(.scale(scale: 0.94).combined(with: .opacity))
    }

    var setup: some View {
        VStack(spacing: 0) {
            SetupRow(icon: "mic.fill", title: "Microphone", detail: status.mic ? "Allowed" : "Needed to hear you",
                     done: status.mic, action: status.mic ? nil : ("Allow", { status.allowMic() }))
            Rectangle().fill(theme.ink.opacity(Skin.isPro ? 0.08 : 0.25)).frame(height: 1)
            SetupRow(icon: "keyboard.fill", title: "Accessibility", detail: status.accessibility ? "Allowed" : "Needed to type into other apps",
                     done: status.accessibility, action: status.accessibility ? nil : ("Open", { status.allowAccessibility() }))
            Rectangle().fill(theme.ink.opacity(Skin.isPro ? 0.08 : 0.25)).frame(height: 1)
            SetupRow(icon: "waveform", title: "Speech", detail: status.engine, done: status.engineDone, action: nil, progress: status.progress)
        }
        .background(theme.paper)
        .skinStroke(theme)
    }
}

/// Small live waveform for the practice card, fed by the real mic.
/// The welcome screen's waveform, reading the live voice levels each frame.
struct LiveMiniWave: View {
    let island: IslandModel
    var animate = true
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !animate)) { _ in
            MiniWave(levels: island.levels, animate: false)
        }
    }
}

struct MiniWave: View {
    let levels: [CGFloat]
    var animate = true
    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<levels.count, id: \.self) { i in
                Capsule().fill(Color.primary).frame(width: 3, height: max(3, levels[i] * 26))
            }
        }
        .frame(height: 28)
        .animation(animate ? .linear(duration: 0.05) : nil, value: levels)
    }
}

struct SetupRow: View {
    let icon: String
    let title: String
    let detail: String
    let done: Bool
    let action: (String, () -> Void)?
    var progress: Double? = nil
    @AppStorage("theme") private var theme: RetroTheme = .pacific

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).frame(width: 20).foregroundStyle(theme.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(RetroFont.title(12)).foregroundStyle(theme.ink)
                Text(detail).font(RetroFont.mono(10)).foregroundStyle(theme.ink.opacity(0.65))
                if let progress {
                    ZStack(alignment: .leading) {
                        Rectangle().fill(theme.paper).overlay(Rectangle().strokeBorder(theme.ink, lineWidth: 1))
                        Rectangle().fill(theme.ink).frame(width: 140 * progress)
                    }.frame(width: 140, height: 7)
                }
            }
            Spacer()
            if let action {
                Button(action.0, action: action.1).buttonStyle(RetroButtonStyle(theme: theme, filled: true))
            } else if done {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .black)).foregroundStyle(theme.paper)
                    .frame(width: 20, height: 20).background(Skin.isPro ? AnyView(Circle().fill(theme.ink)) : AnyView(theme.ink))
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title): \(done ? "done" : detail)")
    }
}

struct KeyCap: View {
    let symbol: String
    let label: String
    let pressed: Bool
    @AppStorage("theme") private var theme: RetroTheme = .pacific

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(symbol).font(.system(size: 15))
            Text(label).font(RetroFont.mono(8))
        }
        .foregroundStyle(theme.ink)
        .padding(.trailing, 8).padding(.bottom, 5)
        .frame(width: 60, height: 46, alignment: .bottomTrailing)
        .background(RoundedRectangle(cornerRadius: Skin.isPro ? 10 : 8, style: .continuous).fill(pressed ? theme.soft : theme.paper))
        .overlay(RoundedRectangle(cornerRadius: Skin.isPro ? 10 : 8, style: .continuous).strokeBorder(Skin.isPro ? Color.black.opacity(0.1) : theme.ink, lineWidth: Skin.isPro ? 1 : 1.5))
        .background(RoundedRectangle(cornerRadius: Skin.isPro ? 10 : 8, style: .continuous).fill(Skin.isPro ? Color.black.opacity(0.12) : theme.ink).offset(y: pressed ? 0 : (Skin.isPro ? 2 : 3)))
        .offset(y: pressed ? 3 : 0)
        .animation(.spring(response: 0.15, dampingFraction: 0.6), value: pressed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label.capitalized) key\(pressed ? ", pressed" : "")")
    }
}

struct GlowBackdrop: View {
    var animate = true
    var body: some View {
        TimelineView(.animation(paused: !animate)) { ctx in
            let t = animate ? ctx.date.timeIntervalSinceReferenceDate : 0
            ZStack {
                blob(Color(red: 0.42, green: 0.66, blue: 1.0), x: -110 + 18 * sin(t * 0.5), y: -280 + 10 * cos(t * 0.4), r: 190)
                blob(Color(red: 0.74, green: 0.56, blue: 1.0), x: 120 + 16 * cos(t * 0.45), y: -300 + 12 * sin(t * 0.5), r: 180)
                blob(Color(red: 1.0, green: 0.70, blue: 0.62), x: 10 + 14 * sin(t * 0.35), y: -220, r: 150)
            }
        }
    }

    func blob(_ c: Color, x: Double, y: Double, r: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [c.opacity(0.28), c.opacity(0)], center: .center, startRadius: 0, endRadius: r))
            .frame(width: r * 2, height: r * 2)
            .offset(x: x, y: y)
    }
}


/// A tiny animated System Settings: shows exactly which switch to flip for Accessibility.
struct PermissionGuide: View {
    let open: () -> Void
    @AppStorage("theme") private var theme: RetroTheme = .pacific
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            RetroTitleBar(title: "Privacy & Security › Accessibility", theme: theme)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(["General", "Privacy & Security", "Keyboard"], id: \.self) { item in
                        Text(item).font(RetroFont.mono(9))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(item == "Privacy & Security" ? theme.ink : .clear)
                            .foregroundStyle(item == "Privacy & Security" ? theme.paper : theme.ink)
                    }
                }
                .padding(10)
                .frame(width: 140, alignment: .leading)
                Rectangle().fill(Skin.isPro ? Color.black.opacity(0.08) : theme.ink).frame(width: Skin.isPro ? 1 : 1.5)
                TimelineView(.animation(paused: reduceMotion)) { ctx in
                    let t = reduceMotion ? 2.0 : ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.2)
                    let on = t > 1.4
                    HStack(spacing: 8) {
                        Image(nsImage: Pro.appIcon).resizable().frame(width: 20, height: 20)
                        Text("Spitball").font(RetroFont.title(11)).foregroundStyle(theme.ink)
                        Spacer()
                        ZStack(alignment: on ? .trailing : .leading) {
                            Capsule().fill(on ? theme.ink : theme.ink.opacity(0.2)).frame(width: 34, height: 18)
                            Circle().fill(theme.paper).frame(width: 14, height: 14).padding(2)
                        }
                        .animation(.spring(response: 0.3), value: on)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "cursorarrow").font(.system(size: 16, weight: .bold)).foregroundStyle(theme.ink)
                                .offset(x: on ? 12 : 30, y: on ? 12 : 26).opacity(t < 2.6 ? 1 : 0)
                                .animation(.easeInOut(duration: 0.6), value: on)
                        }
                    }
                    .padding(10)
                }
            }
            .frame(height: 74)
            HStack {
                Text("Turn on Spitball so it can type for you.").font(RetroFont.mono(10)).foregroundStyle(theme.ink.opacity(0.7))
                Spacer()
                Button("Open Settings", action: open).buttonStyle(RetroButtonStyle(theme: theme, filled: true))
            }
            .padding(10)
            .overlay(alignment: .top) { Rectangle().fill(theme.ink.opacity(0.2)).frame(height: 1) }
        }
        .background(theme.paper)
        .skinStroke(theme)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("To finish setup, open System Settings, Privacy and Security, Accessibility, and turn on Spitball.")
    }
}
