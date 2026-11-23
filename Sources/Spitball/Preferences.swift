import AppKit
import ServiceManagement
import Observation
import SwiftUI

// The Spitball app window: History, Styles, Words, Snippets, Settings.
// Retro on purpose (see RetroUI.swift).

final class PreferencesWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let nav = WindowNav()

    private weak var app: AppDelegate?
    private var observer: Any?

    func show(app: AppDelegate, tab: PrefTab = .history) {
        nav.tab = tab
        self.app = app
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: .spitballSkinChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {   // delivered on the main queue
                    guard let self, let w = self.window, let app = self.app else { return }
                    let frame = w.frame
                    w.delegate = nil; w.close(); self.window = nil
                    self.show(app: app, tab: self.nav.tab)
                    self.window?.setFrameOrigin(frame.origin)
                }
            }
        }
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(); return }
        if Skin.isPro {
            let w = Pro.window(size: NSSize(width: 940, height: 700), title: "Spitball")
            w.delegate = self
            w.contentView = NSHostingView(rootView: ProSpitballView(store: .shared, nav: nav, runSetup: { [weak app] in app?.showWelcome() }))
            w.center(); window = w
            w.makeKeyAndOrderFront(nil); NSApp.activate()
            return
        }
        let w = RetroWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 640),
                            styleMask: [.borderless, .miniaturizable], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.title = "Spitball"
        w.setAccessibilityLabel("Spitball")
        w.contentView = NSHostingView(rootView: SpitballView(store: .shared, nav: nav,
                                                              runSetup: { [weak app] in app?.showWelcome() },
                                                              close: { [weak w] in w?.close() }))
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) { window = nil }
}

@Observable final class WindowNav { var tab: PrefTab = .history }

enum PrefTab: String, CaseIterable, Identifiable {
    case history, notes, styles, dictionary, snippets, general
    var id: String { rawValue }
    var title: String {
        switch self {
        case .history: "History"
        case .notes: "Notes"
        case .styles: "Styles"
        case .dictionary: "Words"
        case .snippets: "Snippets"
        case .general: "Settings"
        }
    }
}

struct SpitballView: View {
    var store: Store
    var nav: WindowNav
    let runSetup: () -> Void
    let close: () -> Void
    @AppStorage("theme") private var theme: RetroTheme = .pacific
    @AppStorage("skin") private var skin: Skin = .playful

    var body: some View {
        VStack(spacing: 0) {
            RetroTitleBar(title: "Spitball", theme: theme, close: close)
            VStack(spacing: 14) {
                Marquee(store: store, theme: theme)
                tabs
                RetroBox(theme: theme) {
                    Group {
                        switch nav.tab {
                        case .history: HistoryPane(store: store, theme: theme)
                        case .styles: StylesPane(store: store, theme: theme)
                        case .dictionary: DictionaryPane(store: store, theme: theme)
                        case .snippets: SnippetsPane(store: store, theme: theme)
                        case .notes: NotesPane(store: store, theme: theme)
                        case .general: GeneralPane(theme: $theme, runSetup: runSetup)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                HStack {
                    Text("Say it. Ship it.").font(RetroFont.serifItalic(15))
                    Spacer()
                    Text("Free · open source · on-device").font(RetroFont.mono(9))
                }
                .foregroundStyle(theme.ink.opacity(0.6))
            }
            .padding(14)
            .background(Gingham(theme: theme))
        }
        .background(theme.paper)
        .skinStroke(theme)
        .frame(width: 600, height: 640)
        .tint(theme.ink)
        .id(skin)
        .animation(A11y.reduceMotion ? nil : .easeOut(duration: 0.15), value: nav.tab)
    }

    @ViewBuilder var tabs: some View {
        if Skin.isPro { proTabs } else { retroTabs }
    }

    /// Pro: an Apple-style segmented control.
    var proTabs: some View {
        HStack(spacing: 0) {
            ForEach(PrefTab.allCases) { t in
                Button { nav.tab = t } label: {
                    Text(t.title).font(.system(size: 12, weight: nav.tab == t ? .semibold : .medium))
                        .foregroundStyle(theme.ink.opacity(nav.tab == t ? 1 : 0.6))
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(nav.tab == t ? AnyView(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white).shadow(color: .black.opacity(0.1), radius: 3, y: 1)) : AnyView(Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(nav.tab == t ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(white: 0.92)))
    }

    var retroTabs: some View {
        HStack(spacing: 0) {
            ForEach(PrefTab.allCases) { t in
                Button { nav.tab = t } label: {
                    Text(t.title.uppercased())
                        .font(RetroFont.title(10))
                        .tracking(0.5)
                        .foregroundStyle(nav.tab == t ? theme.paper : theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(nav.tab == t ? theme.ink : theme.paper)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(nav.tab == t ? [.isSelected, .isButton] : .isButton)
                if t != PrefTab.allCases.last { Rectangle().fill(Skin.isPro ? Color.black.opacity(0.08) : theme.ink).frame(width: Skin.isPro ? 1 : 1.5) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .skinStroke(theme)
    }
}

/// The "now playing" display: wordmark on a halftone sunset, your stats on an LCD.
struct Marquee: View {
    var store: Store
    let theme: RetroTheme

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Halftone(theme: theme)
                Text(Skin.isPro ? "Spitball" : "Spitball\u{2002}")
                    .font(Skin.isPro ? .system(size: 26, weight: .semibold) : RetroFont.script(40))
                    .tracking(Skin.isPro ? -0.6 : 0)
                    .foregroundStyle(Skin.isPro ? theme.ink : theme.paper)
                    .shadow(color: Skin.isPro ? .clear : theme.ink.opacity(0.5), radius: 0, x: 2, y: 2)
                    .padding(.leading, 14).padding(.bottom, 6)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(width: 230)
            .clipped()
            Rectangle().fill(Skin.isPro ? Color.black.opacity(0.08) : theme.ink).frame(width: Skin.isPro ? 1 : 1.5)
            VStack(alignment: .leading, spacing: 8) {
                LCDWave(seed: store.history.count, theme: theme).frame(height: 30)
                HStack(spacing: 14) {
                    lcd(store.totalWords.formatted(), "words")
                    lcd("\(store.wordsPerMinute)", "wpm")
                    lcd("\(store.minutesSaved)", "min saved")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(theme.ink)
        }
        .frame(height: 104)
        .skinStroke(theme)
        .accessibilityElement(children: .combine)
    }

    func lcd(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(RetroFont.title(18)).monospacedDigit().foregroundStyle(theme.bottom)
            Text(label.uppercased()).font(RetroFont.mono(8)).foregroundStyle(theme.bottom.opacity(0.7))
        }
    }
}

/// Little LCD waveform strip (deterministic, so it doesn't flicker).
struct LCDWave: View {
    let seed: Int
    let theme: RetroTheme
    var body: some View {
        Canvas { ctx, size in
            let n = Int(size.width / 4)
            for i in 0..<n {
                let x = CGFloat(i) * 4
                let v = abs(sin(Double(i) * 0.37 + Double(seed)) * sin(Double(i) * 0.11 + 1.3))
                let h = max(2, CGFloat(v) * size.height)
                ctx.fill(Path(CGRect(x: x, y: (size.height - h) / 2, width: 2, height: h)), with: .color(theme.bottom.opacity(0.85)))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - History

struct HistoryPane: View {
    var store: Store
    let theme: RetroTheme
    @State private var copied: UUID?
    @State private var query = ""

    var items: [HistoryItem] {
        query.isEmpty ? store.history : store.history.filter { $0.text.localizedCaseInsensitiveContains(query) || ($0.app ?? "").localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                RetroField(theme: theme, placeholder: "Search what you said…", text: $query)
                Button("Clear all") { store.history.removeAll() }
                    .buttonStyle(RetroButtonStyle(theme: theme))
                    .disabled(store.history.isEmpty)
            }
            .padding(12)
            Rectangle().fill(Skin.isPro ? Color.black.opacity(0.08) : theme.ink).frame(height: Skin.isPro ? 1 : 1.5)
            if items.isEmpty {
                RetroEmpty(theme: theme, title: store.history.isEmpty ? "Nothing yet" : "No matches",
                           text: store.history.isEmpty ? "Double-tap ⌘ anywhere and say something.\nIt'll show up here." : "Try another word.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { h in
                            row(h)
                            Rectangle().fill(theme.ink.opacity(Skin.isPro ? 0.08 : 0.25)).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    func row(_ h: HistoryItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AppIconView(bundleID: h.bundleID ?? "", name: h.app).frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(h.app ?? "Unknown app").font(RetroFont.title(10)).foregroundStyle(theme.ink)
                    Text("·").foregroundStyle(theme.ink.opacity(0.4))
                    Text(h.date.formatted(.relative(presentation: .named))).font(RetroFont.mono(10)).foregroundStyle(theme.ink.opacity(0.55))
                }
                Text(h.text).font(RetroFont.body(13)).foregroundStyle(theme.ink)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(copied == h.id ? "Copied!" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(h.text, forType: .string)
                copied = h.id
                A11y.announce("Copied")
            }
            .buttonStyle(RetroButtonStyle(theme: theme, filled: copied == h.id))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Styles

struct StylesPane: View {
    @Bindable var store: Store
    let theme: RetroTheme
    @AppStorage("defaultStyle") private var defaultStyle: WritingStyle = .smart
    @AppStorage("customInstructions") private var instructions = ""

    var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .filter { app in !store.styles.contains { $0.bundleID == app.bundleIdentifier } }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneIntro(theme: theme, text: Polisher.available
                      ? "How your words read in each app. Rewritten on your Mac by Apple Intelligence."
                      : "Turn on Apple Intelligence in System Settings to use styles.")
            HStack {
                Text("Everywhere else").font(RetroFont.title(11)).foregroundStyle(theme.ink)
                Spacer()
                StylePicker(style: $defaultStyle)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            RetroField(theme: theme, placeholder: "Your instructions, e.g. use British English, keep it short", text: $instructions)
                .padding(.horizontal, 12).padding(.bottom, 10)
                .accessibilityLabel("Instructions for every dictation")
            Rectangle().fill(Skin.isPro ? Color.black.opacity(0.08) : theme.ink).frame(height: Skin.isPro ? 1 : 1.5)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach($store.styles) { $s in
                        HStack(spacing: 10) {
                            AppIconView(bundleID: s.bundleID, name: s.name).frame(width: 20, height: 20)
                            Text(s.name).font(RetroFont.body(13)).foregroundStyle(theme.ink)
                            Spacer()
                            StylePicker(style: $s.style)
                            RemoveButton(theme: theme) { store.styles.removeAll { $0.bundleID == s.bundleID } }
                        }
                        .padding(.horizontal, 12).padding(.top, 7)
                        TextField("Instructions for \(s.name) (optional)", text: Binding(get: { s.instructions ?? "" }, set: { s.instructions = $0.isEmpty ? nil : $0 }))
                            .textFieldStyle(.plain).font(RetroFont.body(11)).foregroundStyle(theme.ink.opacity(0.75))
                            .padding(.leading, 42).padding(.trailing, 12).padding(.top, 2).padding(.bottom, 8)
                        Rectangle().fill(theme.ink.opacity(Skin.isPro ? 0.08 : 0.25)).frame(height: 1)
                    }
                }
            }
            HStack {
                Menu("+ Add an app") {
                    ForEach(runningApps, id: \.processIdentifier) { app in
                        Button(app.localizedName ?? "App") {
                            store.styles.append(AppStyle(bundleID: app.bundleIdentifier!, name: app.localizedName ?? "App", style: .polished))
                        }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize()
                .font(RetroFont.title(11))
                Spacer()
                Text("adds ~½ second").font(RetroFont.mono(9)).foregroundStyle(theme.ink.opacity(0.5))
            }
            .padding(12)
        }
        .disabled(!Polisher.available)
    }
}

struct StylePicker: View {
    @Binding var style: WritingStyle
    var body: some View {
        Picker("", selection: $style) {
            ForEach(WritingStyle.allCases) { Text($0.label).tag($0) }
        }
        .labelsHidden().fixedSize()
        .help(style.example)
    }
}

// MARK: - Words (dictionary)

struct DictionaryPane: View {
    var store: Store
    let theme: RetroTheme
    @State private var word = ""
    @State private var heard = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneIntro(theme: theme, text: "Names, brands and jargon, spelled your way. Add “TestFlight” and “test flight” gets fixed.")
            HStack(spacing: 8) {
                RetroField(theme: theme, placeholder: "Word, e.g. GraphQL", text: $word)
                RetroField(theme: theme, placeholder: "Often heard as (optional)", text: $heard)
                Button("Add") {
                    store.dictionary.insert(DictEntry(word: word.trimmingCharacters(in: .whitespaces), heardAs: heard), at: 0)
                    word = ""; heard = ""
                }
                .buttonStyle(RetroButtonStyle(theme: theme, filled: true))
                .disabled(word.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 12).padding(.bottom, 12)
            Rectangle().fill(Skin.isPro ? Color.black.opacity(0.08) : theme.ink).frame(height: Skin.isPro ? 1 : 1.5)
            if store.dictionary.isEmpty {
                RetroEmpty(theme: theme, title: "Teach it your words", text: "Add the names and jargon it gets wrong.\nThey'll be right from then on.")
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.dictionary) { e in
                            HStack {
                                Text(e.word).font(Skin.isPro ? .system(size: 18, weight: .bold) : RetroFont.title(12)).tracking(Skin.isPro ? -0.4 : 0).foregroundStyle(theme.ink)
                                if !e.heardAs.isEmpty { Text("← \(e.heardAs)").font(Skin.isPro ? .system(size: 14) : RetroFont.mono(10)).foregroundStyle(theme.ink.opacity(0.55)) }
                                Spacer()
                                RemoveButton(theme: theme) { store.dictionary.removeAll { $0.id == e.id } }
                            }
                            .padding(.horizontal, 12).padding(.vertical, Skin.isPro ? 16 : 8)
                            Rectangle().fill(theme.ink.opacity(Skin.isPro ? 0.08 : 0.25)).frame(height: 1)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Snippets

struct SnippetsPane: View {
    var store: Store
    let theme: RetroTheme
    @State private var trigger = ""
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneIntro(theme: theme, text: "Say a short phrase, get the full text. Say “my email” and your address appears.")
            HStack(spacing: 8) {
                RetroField(theme: theme, placeholder: "When I say…", text: $trigger).frame(width: 150)
                RetroField(theme: theme, placeholder: "…type this", text: $text)
                Button("Add") {
                    store.snippets.insert(Snippet(trigger: trigger, text: text), at: 0)
                    trigger = ""; text = ""
                }
                .buttonStyle(RetroButtonStyle(theme: theme, filled: true))
                .disabled(trigger.trimmingCharacters(in: .whitespaces).isEmpty || text.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 12).padding(.bottom, 12)
            Rectangle().fill(Skin.isPro ? Color.black.opacity(0.08) : theme.ink).frame(height: Skin.isPro ? 1 : 1.5)
            if store.snippets.isEmpty {
                RetroEmpty(theme: theme, title: "Shortcuts for your mouth", text: "Your email, a calendar link,\nthe sign-off you type ten times a day.")
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.snippets) { s in
                            HStack(alignment: .firstTextBaseline) {
                                Text("“\(s.trigger)”").font(Skin.isPro ? .system(size: 17, weight: .bold) : RetroFont.title(11)).foregroundStyle(theme.ink).frame(width: Skin.isPro ? 180 : 140, alignment: .leading)
                                Text(s.text).font(RetroFont.body(13)).foregroundStyle(theme.ink.opacity(0.75)).lineLimit(2)
                                Spacer()
                                RemoveButton(theme: theme) { store.snippets.removeAll { $0.id == s.id } }
                            }
                            .padding(.horizontal, 12).padding(.vertical, Skin.isPro ? 16 : 8)
                            Rectangle().fill(theme.ink.opacity(Skin.isPro ? 0.08 : 0.25)).frame(height: 1)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Settings

struct GeneralPane: View {
    @Binding var theme: RetroTheme
    let runSetup: () -> Void
    @AppStorage("trigger2") private var trigger: Trigger = .doubleCommand
    @AppStorage("engine") private var engine: Engine = .parakeet
    @AppStorage("language") private var language = "auto"
    @AppStorage("screenContext") private var screenContext = true
    @AppStorage("meetingPrompt") private var meetingPrompt = true
    @AppStorage("avoidBluetoothMic") private var avoidBT = true
    @State private var mcpCopied = false
    @State private var cliStatus: String?
    @AppStorage("noise") private var noise: NoiseMode = .smart
    @AppStorage("shape") private var shape: ScreenShape = .auto
    @AppStorage("removeFillers") private var fillers = true
    @AppStorage("commandMode") private var commandMode = true
    @AppStorage("soundPack") private var soundPack: SoundPack = .soft
    @AppStorage("showIsland") private var showIsland = true
    @AppStorage("cursorDot") private var cursorDot = true
    @AppStorage("relaxedTiming") private var relaxed = false
    @AppStorage("keepHistory") private var keepHistory = true
    @AppStorage("joinClub") private var joinClub = false
    @AppStorage("clubHandle") private var clubHandle = ""
    @State private var login = SMAppService.mainApp.status == .enabled
    @AppStorage("micUID") private var micUID = ""
    @State private var meter = MicMeter()
    @State private var devices = AudioDevices.inputs()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Skin.isPro ? 40 : 18) {
                section("Look") {
                    SkinPicker(theme: theme)
                }
                if !Skin.isPro { section("Theme") {
                    HStack(spacing: 10) {
                        ForEach(RetroTheme.allCases) { t in
                            Button { theme = t } label: {
                                ZStack {
                                    LinearGradient(colors: [t.top, t.bottom], startPoint: .top, endPoint: .bottom)
                                    if theme == t {
                                        Image(systemName: "checkmark").font(.system(size: 12, weight: .black)).foregroundStyle(t.paper)
                                    }
                                }
                                .frame(width: 34, height: 34)
                                .overlay(Rectangle().strokeBorder(t.ink, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(t.name)
                            .accessibilityAddTraits(theme == t ? [.isSelected, .isButton] : .isButton)
                        }
                        Text(theme.name).font(RetroFont.title(11)).foregroundStyle(theme.ink).padding(.leading, 4)
                    }
                } }
                section("Microphone") {
                    HStack {
                        Text("Record from").font(RetroFont.body(13)).foregroundStyle(theme.ink)
                        Spacer()
                        Picker("Record from", selection: $micUID) {
                            Text("System default").tag("")
                            ForEach(devices) { d in Text(d.name).tag(d.uid) }
                        }
                        .labelsHidden().fixedSize()
                        .onChange(of: micUID) { _, _ in
                            NotificationCenter.default.post(name: .spitballMicChanged, object: nil)
                            if meter.running { meter.start() }
                        }
                    }
                    HStack(spacing: 10) {
                        Button(meter.running ? "Stop test" : "Test mic") { meter.running ? meter.stop() : meter.start() }
                            .buttonStyle(RetroButtonStyle(theme: theme))
                        LevelMeter(level: meter.level, theme: theme)
                    }
                    Toggle("Use the Mac's mic when AirPods are connected", isOn: $avoidBT)
                        .onChange(of: avoidBT) { NotificationCenter.default.post(name: .spitballMicChanged, object: nil) }
                    Text("Keeps AirPods in high-quality mode and stops dictation breaking when they hop to your iPhone. Calls use the system default mic so echo cancellation works.").font(Skin.isPro ? .system(size: 13) : RetroFont.mono(10)).foregroundStyle(theme.ink.opacity(0.55))
                }
                section("Dictation") {
                    picker("Talk key", $trigger, Trigger.allCases) { $0.label }
                    picker("Speech engine", $engine, Engine.allCases) { $0.label }
                    picker("Language", $language, Languages.choices) { Languages.name($0) }
                        .onChange(of: language) { NotificationCenter.default.post(name: .spitballLanguageChanged, object: nil) }
                    picker("Cancel call & music audio", $noise, NoiseMode.allCases) { $0.label }
                    Toggle("Relaxed double-tap timing", isOn: $relaxed)
                }
                section("Words") {
                    Toggle("Remove “um” and “uh”", isOn: $fillers)
                    Toggle("Edit selected text by voice (Command Mode)", isOn: $commandMode).disabled(!Polisher.available)
                    Toggle("Spell file names and code terms from your screen", isOn: $screenContext)
                }
                section("Notes & agents") {
                    Toggle("Offer meeting notes when a call starts", isOn: $meetingPrompt)
                    Text("Give Claude, Cursor, Codex or ChatGPT read-only access to your notes and dictations. Runs on your Mac, no account or key.")
                        .font(RetroFont.body(11)).foregroundStyle(theme.ink.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button(mcpCopied ? "Copied" : "Copy MCP config") {
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(AgentAccess.mcpConfig, forType: .string)
                            mcpCopied = true; DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { mcpCopied = false }
                        }
                        .buttonStyle(RetroButtonStyle(theme: theme, filled: mcpCopied))
                        Button("Install spitball command") { cliStatus = AgentAccess.installCLI() }
                            .buttonStyle(RetroButtonStyle(theme: theme))
                    }
                    if let cliStatus { Text(cliStatus).font(RetroFont.body(11)).foregroundStyle(theme.ink.opacity(0.7)) }
                }
                section("Look & feel") {
                    Toggle("Show the island in the notch / Dynamic Island", isOn: $showIsland)
                    Toggle("Show my voice above the text caret", isOn: $cursorDot)
                    HStack {
                        Text("Sound").font(RetroFont.body(13)).foregroundStyle(theme.ink)
                        Spacer()
                        Picker("Sound", selection: $soundPack) { ForEach(SoundPack.allCases) { Text($0.label).tag($0) } }
                            .labelsHidden().fixedSize()
                            .onChange(of: soundPack) { _, p in Bloop.preview(p) }
                        Button("▶︎") { Bloop.preview(soundPack) }.buttonStyle(RetroButtonStyle(theme: theme)).accessibilityLabel("Play sound")
                    }
                    picker("Screen shape", $shape, ScreenShape.allCases) { $0.label }
                }
                section("App") {
                    Toggle("Show in the Dock", isOn: Binding(get: { Settings.showInDock }, set: { v in
                        Settings.showInDock = v; NSApp.setActivationPolicy(v ? .regular : .accessory) }))
                    Toggle("Open at login", isOn: $login)
                        .onChange(of: login) { _, on in try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
                    Toggle("Keep dictation history", isOn: $keepHistory)
                    if Club.available {
                        Toggle("Join the Spitball Club leaderboard (shares word counts only)", isOn: $joinClub)
                            .onChange(of: joinClub) { _, on in if on { Club.report() } }
                        if joinClub {
                            HStack {
                                Text("Nickname").font(RetroFont.body(13)).foregroundStyle(theme.ink)
                                RetroField(theme: theme, placeholder: "@you", text: $clubHandle).frame(width: 180)
                            }
                        }
                    }
                    Button("Run setup & practice again", action: runSetup).buttonStyle(RetroButtonStyle(theme: theme))
                }
            }
            .toggleStyle(RetroCheckStyle(theme: theme))
            .padding(.horizontal, Skin.isPro ? 12 : 16).padding(.top, Skin.isPro ? 6 : 16).padding(.bottom, Skin.isPro ? 40 : 16)
        }
        .scrollIndicators(.never)
        .onAppear { devices = AudioDevices.inputs() }
        .onDisappear { meter.stop() }
    }

    @ViewBuilder func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        if Skin.isPro {
            // [untitled]-style: a big bold title over one soft grey card with roomy rows.
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(.system(size: 24, weight: .bold)).tracking(-0.7).foregroundStyle(theme.ink)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 20) { content() }
                    .padding(.horizontal, 24).padding(.vertical, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Pro.field))
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(title.uppercased()).font(RetroFont.title(10)).tracking(1).foregroundStyle(theme.ink.opacity(0.6))
                    .accessibilityAddTraits(.isHeader)
                content()
            }
        }
    }

    func picker<T: Hashable>(_ label: String, _ value: Binding<T>, _ options: [T], _ name: @escaping (T) -> String) -> some View {
        HStack {
            Text(label).font(RetroFont.body(13)).foregroundStyle(theme.ink)
            Spacer()
            Picker(label, selection: value) { ForEach(options, id: \.self) { Text(name($0)).tag($0) } }
                .labelsHidden().fixedSize()
        }
    }
}

// MARK: - Pieces

struct PaneIntro: View {
    let theme: RetroTheme
    let text: String
    var body: some View {
        Text(text).font(RetroFont.body(12)).foregroundStyle(theme.ink.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
    }
}

struct RetroEmpty: View {
    let theme: RetroTheme
    let title: String
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(RetroFont.script(30)).foregroundStyle(theme.ink)
            Text(text).font(RetroFont.mono(11)).foregroundStyle(theme.ink.opacity(0.6)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

struct RemoveButton: View {
    let theme: RetroTheme
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 9, weight: .black)).foregroundStyle(theme.ink)
                .frame(width: 18, height: 18)
                .skinStroke(theme)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove")
    }
}

struct AppIconView: View {
    let bundleID: String
    var name: String? = nil
    /// Looking up an app's icon is slow; do it once per app, not on every redraw.
    @MainActor private static var cache: [String: NSImage] = [:]
    @MainActor static func icon(_ id: String) -> NSImage? {
        if let i = cache[id] { return i }
        guard !id.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        let big = NSWorkspace.shared.icon(forFile: url.path)
        let small = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { r in big.draw(in: r); return true }
        cache[id] = small
        return small
    }

    var body: some View {
        Group {
            if let img = AppIconView.icon(bundleID) {
                Image(nsImage: img).resizable().interpolation(.high)
            } else {
                Image(systemName: "app.dashed").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
    }
}
