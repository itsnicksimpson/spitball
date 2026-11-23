import AppKit
import Observation
import SwiftUI

// "Pro" look, after [untitled] (otherkind.design): a white canvas with huge tight
// titles and roomy rows, one black rounded-square action, a floating dark capsule
// for navigation, dark "session" screens with mono type, yellow as the only accent
// and red only for recording. Same data and features as Playful.

enum Pro {
    static let sidebar = Color(white: 0.975)
    static let field = Color(white: 0.955)
    static let hover = Color.black.opacity(0.05)
    static let ink = Color(red: 0.06, green: 0.06, blue: 0.07)
    static let secondary = Color.black.opacity(0.5)
    static let hairline = Color.black.opacity(0.06)
    static let night = Color(red: 0.086, green: 0.086, blue: 0.086)      // dark session background
    static let card = Color(red: 0.16, green: 0.16, blue: 0.16)       // dark card
    static let cardHi = Color(red: 0.2, green: 0.2, blue: 0.2)           // selected / pressed on dark
    static let yellow = Color(red: 0.98, green: 0.88, blue: 0.24)        // the one accent
    static let red = Color(red: 1, green: 0.2, blue: 0.17)

    /// IBM Plex Mono (bundled), else SF Mono.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        NSFont(name: "IBMPlexMono-Medium", size: size) != nil ? .custom("IBMPlexMono-Medium", size: size) : .system(size: size, weight: weight, design: .monospaced)
    }

    /// The real Spitball icon, even when running outside the .app (self-test renders).
    @MainActor static let appIcon: NSImage = {
        if let u = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let i = NSImage(contentsOf: u) { return i }
        if let i = NSImage(contentsOfFile: "Resources/AppIcon.icns") { return i }
        return NSApp.applicationIconImage
    }()

    static func icon(_ tab: PrefTab) -> String {
        switch tab {
        case .history: "text.bubble"
        case .styles: "textformat"
        case .dictionary: "character.book.closed"
        case .snippets: "text.badge.plus"
        case .notes: "waveform.and.mic"
        case .general: "gearshape"
        }
    }

    /// A native-looking window: real traffic lights, transparent title bar, white.
    static func window(size: NSSize, title: String, dark: Bool = false) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.backgroundColor = dark ? NSColor(red: 0.086, green: 0.086, blue: 0.086, alpha: 1) : .white
        w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        w.isReleasedWhenClosed = false
        w.title = title
        return w
    }
}

/// Native macOS translucency (the frosted sidebar in Mail, Notes, Finder).
struct Frosted: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material; v.blendingMode = .behindWindow; v.state = .followsWindowActiveState
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

extension Notification.Name { static let spitballSkinChanged = Notification.Name("spitballSkinChanged") }

// MARK: - Main window

struct ProSpitballView: View {
    var store: Store
    var nav: WindowNav
    var taker = Notetaker.shared
    let runSetup: () -> Void
    @AppStorage("theme") private var theme: RetroTheme = .pacific
    @State private var openNote: Note.ID?

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                sidebar.padding(10)
                VStack(alignment: .leading, spacing: 0) {
                    header
                    content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .background(Color.white)
            if let id = openNote, let note = store.notes.first(where: { $0.id == id }) {
                ProSession(note: note, close: { openNote = nil }, delete: { store.notes.removeAll { $0.id == id }; openNote = nil })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: openNote)
        .frame(minWidth: 820, minHeight: 600)
        .tint(Pro.ink)
    }

    /// Floating dark panel: logo, tabs as pills, then the live note, stats and Settings.
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear.frame(height: 34)                      // the window buttons sit here
            SpitballLogo(dark: true).padding(.horizontal, 12).padding(.bottom, 18)
            ForEach([PrefTab.history, .notes, .styles, .dictionary, .snippets]) { t in tab(t) }
            Spacer(minLength: 12)
            if let live = taker.current {
                RecordingCard(note: live, elapsed: taker.elapsed, finishing: taker.finishing) { taker.stop() }
                    .padding(.bottom, 8)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(store.totalWords.formatted()) words").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Text(store.streak > 1 ? "\(store.wordsPerMinute) wpm • \(store.streak)-day streak" : "\(store.wordsPerMinute) wpm")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 12).padding(.bottom, 10)
            .accessibilityElement(children: .combine)
            tab(.general)
        }
        .padding(8)
        .frame(width: 208)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Pro.night))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: taker.current?.id)
        .environment(\.colorScheme, .dark)
    }

    func tab(_ t: PrefTab) -> some View {
        Button { nav.tab = t } label: {
            HStack(spacing: 12) {
                Image(systemName: Pro.icon(t)).font(.system(size: 14, weight: .medium)).frame(width: 20)
                Text(t == .general ? "Settings" : t.title).font(.system(size: 15, weight: nav.tab == t ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(.white.opacity(nav.tab == t ? 1 : 0.62))
            .padding(.horizontal, 12).frame(height: 40)
            .background(Capsule().fill(nav.tab == t ? Pro.cardHi : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: nav.tab)
        .accessibilityAddTraits(nav.tab == t ? [.isSelected, .isButton] : .isButton)
    }

    var title: String { nav.tab == .general ? "Settings" : nav.tab.title }

    var subtitle: String {
        switch nav.tab {
        case .history: return "\(store.history.count) dictations"
        case .notes: return "\(store.notes.count) notes • no bot joins your calls"
        case .styles: return "how you sound in each app"
        case .dictionary: return "\(store.dictionary.count) words spelled your way"
        case .snippets: return "\(store.snippets.count) snippets"
        case .general: return "version \(WhatsNew.version)"
        }
    }

    var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 40, weight: .bold)).tracking(-1.6).foregroundStyle(Pro.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.system(size: 17)).foregroundStyle(Pro.secondary)
            }
            Spacer()
            // The one big black button: record a voice note from anywhere in the app.
            Button { taker.toggle(.voice) } label: {
                Image(systemName: taker.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(taker.isRecording ? Pro.red : Pro.ink))
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
            }
            .buttonStyle(PressScale())
            .disabled(taker.finishing || (taker.isRecording && taker.current?.kind == .meeting))
            .help(taker.isRecording ? "Stop recording (⌃⌘N)" : "New voice note (⌃⌘N)")
            .accessibilityLabel(taker.isRecording ? "Stop recording" : "New voice note")
        }
        .padding(.leading, 28).padding(.trailing, 28).padding(.top, 34).padding(.bottom, 18)
    }

    @ViewBuilder var content: some View {
        switch nav.tab {
        case .history: ProHistory(store: store)
        case .notes: ProNotes(store: store, open: { openNote = $0 })
        case .styles: pane { StylesPane(store: store, theme: theme) }
        case .dictionary: pane { DictionaryPane(store: store, theme: theme) }
        case .snippets: pane { SnippetsPane(store: store, theme: theme) }
        case .general: GeneralPane(theme: $theme, runSetup: runSetup).padding(.horizontal, 16)
        }
    }

    func pane<V: View>(@ViewBuilder _ v: () -> V) -> some View {
        v().padding(.horizontal, 20).padding(.bottom, 20)
    }
}

/// A note in progress, in the sidebar: red dot, timer, live waveform with a yellow playhead, stop.
struct RecordingCard: View {
    let note: Note
    let elapsed: Double
    let finishing: Bool
    let stop: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(finishing ? Color.gray : Pro.red).frame(width: 8, height: 8)
                Text(finishing ? "Writing it up…" : (note.kind == .meeting ? "Meeting" : "Voice note")).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Text(Note.clock(elapsed)).font(Pro.mono(12)).foregroundStyle(.white.opacity(0.7))
            }
            Waveform(seed: note.id.hashValue, progress: 1, live: !finishing).frame(height: 22)
            Button(action: stop) {
                Text("stop").font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 32).background(Capsule().fill(Pro.cardHi))
            }
            .buttonStyle(PressScale()).disabled(finishing)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Pro.card))
        .accessibilityElement(children: .combine)
    }
}

/// The comet icon and the name, set like the rest of the app's type.
struct SpitballLogo: View {
    var dark = false
    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: Pro.appIcon).resizable().interpolation(.high).frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(dark ? 0.18 : 0), lineWidth: 0.75))
            Text("Spitball").font(.system(size: 16, weight: .bold)).tracking(-0.4).foregroundStyle(dark ? .white : Pro.ink)
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("Spitball")
    }
}

/// A row of thin bars with a yellow playhead, like [untitled]'s scrubber.
struct Waveform: View {
    var seed: Int
    var progress: Double         // 0…1, where the yellow playhead sits
    var live = false
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !live || A11y.reduceMotion)) { tl in
            let t = live ? tl.date.timeIntervalSinceReferenceDate : 0
            GeometryReader { g in
                let n = Int(g.size.width / 3)
                HStack(alignment: .center, spacing: 1.2) {
                    ForEach(0..<max(1, n), id: \.self) { i in
                        let x = Double(i) + Double(seed % 997)
                        let v = abs(sin(x * 0.37) * cos(x * 0.13 + t * (live ? 3 : 0))) * 0.85 + 0.12
                        Capsule().fill(Double(i) / Double(n) <= progress ? Color.white.opacity(0.9) : Color.white.opacity(0.35))
                            .frame(width: 1.6, height: max(2, g.size.height * v))
                    }
                }
                .frame(maxHeight: .infinity)
                .overlay(alignment: .leading) {
                    Capsule().fill(Pro.yellow).frame(width: 2.5, height: g.size.height)
                        .offset(x: g.size.width * min(1, max(0, progress)) - 1.25)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// "•••": a plain button that pops a real menu only when clicked
/// (a SwiftUI Menu per row is heavy and makes long lists stutter).
struct DotsButton: View {
    let items: [(String, Bool, () -> Void)]     // title, destructive, action
    var body: some View {
        Button { pop() } label: {
            Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).foregroundStyle(Pro.ink)
                .frame(width: 36, height: 36).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More")
    }

    func pop() {
        let menu = NSMenu()
        for (title, destructive, action) in items {
            if title == "-" { menu.addItem(.separator()); continue }
            let item = ClosureMenuItem(title: title, action: action)
            if destructive { item.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.systemRed]) }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

nonisolated final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void
    init(title: String, action: @escaping () -> Void) {
        run = action
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { run() }
}

// MARK: - History

struct ProHistory: View {
    var store: Store
    @State private var query = ""
    @State private var copied: UUID?

    var items: [HistoryItem] {
        query.isEmpty ? store.history : store.history.filter { $0.text.localizedCaseInsensitiveContains(query) || ($0.app ?? "").localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).foregroundStyle(Pro.secondary)
                TextField("Search what you said", text: $query).textFieldStyle(.plain).font(.system(size: 16))
            }
            .padding(.horizontal, 18).frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Pro.field))
            .padding(.horizontal, 28)

            if items.isEmpty {
                VStack(spacing: 8) {
                    Text(store.history.isEmpty ? "Nothing yet" : "No matches").font(.system(size: 22, weight: .bold)).tracking(-0.6).foregroundStyle(Pro.ink)
                    Text(store.history.isEmpty ? "Double-tap ⌘ in any app and say something." : "Try another word.")
                        .font(.system(size: 15)).foregroundStyle(Pro.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(items) { h in
                        row(h)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .contentMargins(.top, 14, for: .scrollContent)
                .contentMargins(.bottom, 40, for: .scrollContent)
            }
        }
    }

    func row(_ h: HistoryItem) -> some View {
        HoverRow {
            HStack(alignment: .top, spacing: 16) {
                AppIconView(bundleID: h.bundleID ?? "", name: h.app).frame(width: 30, height: 30).padding(.top, 2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(h.text).font(.system(size: 17, weight: .semibold)).tracking(-0.3).foregroundStyle(Pro.ink)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    Text([h.app, h.date.formatted(.relative(presentation: .named))].compactMap { $0 }.joined(separator: " • "))
                        .font(.system(size: 14)).foregroundStyle(Pro.secondary)
                }
                Spacer(minLength: 12)
                Button { copy(h) } label: {
                    Image(systemName: copied == h.id ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(copied == h.id ? Pro.ink : Pro.secondary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(PressScale()).accessibilityLabel("Copy")
                DotsButton(items: [("Copy", false, { copy(h) }), ("-", false, {}),
                                   ("Delete", true, { store.history.removeAll { $0.id == h.id } })])
            }
        }
    }

    func copy(_ h: HistoryItem) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(h.text, forType: .string)
        copied = h.id; A11y.announce("Copied")
    }
}

/// A row that softly highlights on hover.
struct HoverRow<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var hovering = false
    var body: some View {
        content
            .padding(.horizontal, 12).padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(hovering ? Pro.field : .clear))
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
            .accessibilityElement(children: .contain)
    }
}

// MARK: - Notes

struct ProNotes: View {
    var store: Store
    var taker = Notetaker.shared
    let open: (Note.ID) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    slab("New voice note", "plus", key: "⌃⌘N") { taker.toggle(.voice) }
                    slab("Meeting notes", "person.2", key: "⌃⌘M") { taker.toggle(.meeting) }
                }
                .disabled(taker.current != nil)
                .padding(.horizontal, 12).padding(.bottom, 14)
                if let e = taker.lastError { Text(e).font(.system(size: 13)).foregroundStyle(Pro.red).padding(.horizontal, 12) }
                ForEach(Array(store.notes.enumerated()), id: \.element.id) { i, n in
                    Button { open(n.id) } label: {
                        HoverRow {
                            HStack(alignment: .top, spacing: 18) {
                                Text("\(i + 1)").font(.system(size: 17)).foregroundStyle(Pro.secondary).frame(width: 22).padding(.top, 1)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(n.title).font(.system(size: 19, weight: .bold)).tracking(-0.5).foregroundStyle(Pro.ink).lineLimit(1)
                                    Text("\(n.date.formatted(date: .long, time: .omitted)) • \(Note.clock(n.duration))\((n.app.map { " • " + $0 }) ?? "")")
                                        .font(.system(size: 15)).foregroundStyle(Pro.secondary)
                                }
                                Spacer()
                                DotsButton(items: [("Open", false, { open(n.id) }),
                                                   ("Copy as Markdown", false, { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(n.markdown, forType: .string) }),
                                                   ("-", false, {}), ("Delete", true, { store.notes.removeAll { $0.id == n.id } })])
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if store.notes.isEmpty && taker.current == nil {
                    Text("Your notes and meetings land here, with a summary and action items.")
                        .font(.system(size: 15)).foregroundStyle(Pro.secondary).padding(.horizontal, 12).padding(.top, 10)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
        .scrollIndicators(.never)
    }

    func slab(_ title: String, _ icon: String, key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                Text(title).font(.system(size: 17, weight: .semibold)).tracking(-0.3)
                Text(key).font(Pro.mono(12)).foregroundStyle(Pro.secondary)
            }
            .foregroundStyle(Pro.ink)
            .frame(maxWidth: .infinity).frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Pro.field))
        }
        .buttonStyle(PressScale())
    }
}

/// A note opened: the dark "session" screen. Mono type, one card, Done pill.
struct ProSession: View {
    let note: Note
    let close: () -> Void
    let delete: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(note.title).font(Pro.mono(16)).foregroundStyle(.white).lineLimit(1)
                Spacer()
                Button("Done", action: close).buttonStyle(DarkPill()).keyboardShortcut(.cancelAction)
            }
            .padding(.leading, 84).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !note.summary.isEmpty { block("Summary", note.summary) }
                    if !note.actions.isEmpty { block("Action items", note.actions.map { "☐ " + $0 }) }
                    Text("Transcript").font(Pro.mono(13)).foregroundStyle(.white.opacity(0.45))
                    ForEach(note.lines) { l in
                        VStack(alignment: .leading, spacing: 3) {
                            if note.kind == .meeting { Text(l.speaker).font(Pro.mono(12)).foregroundStyle(l.speaker == "You" ? Pro.yellow : .white.opacity(0.5)) }
                            Text(l.text).font(Pro.mono(15)).foregroundStyle(.white.opacity(0.92)).lineSpacing(5).textSelection(.enabled)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Pro.card))
            Waveform(seed: note.id.hashValue, progress: 0.35).frame(height: 30).padding(.horizontal, 30)
            Text("\(note.date.formatted(date: .abbreviated, time: .shortened))  •  \(Note.clock(note.duration))  •  \(note.words) words")
                .font(Pro.mono(12)).foregroundStyle(.white.opacity(0.55)).frame(maxWidth: .infinity)
            HStack(spacing: 10) {
                Bezel {
                    HStack(spacing: 0) {
                        Button { copyMD() } label: { Label(copied ? "copied" : "copy", systemImage: "doc.on.doc") }.buttonStyle(BezelItem())
                        Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 22)
                        Button { export() } label: { Label("export", systemImage: "square.and.arrow.up") }.buttonStyle(BezelItem())
                    }
                }
                Bezel {
                    Button(role: .destructive) { delete() } label: { Label("delete", systemImage: "trash") }.buttonStyle(BezelItem())
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 22).padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Pro.night)
        .environment(\.colorScheme, .dark)
    }

    func block(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Pro.mono(13)).foregroundStyle(.white.opacity(0.45))
            ForEach(lines, id: \.self) { Text($0).font(Pro.mono(15)).foregroundStyle(.white).lineSpacing(4).textSelection(.enabled) }
        }
    }

    func copyMD() {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(note.markdown, forType: .string)
        copied = true; DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
    }

    func export() {
        let p = NSSavePanel()
        p.nameFieldStringValue = note.title.replacingOccurrences(of: "/", with: "-") + ".md"
        if p.runModal() == .OK, let url = p.url { try? note.markdown.write(to: url, atomically: true, encoding: .utf8) }
    }
}

/// [untitled]'s nested controls: a button inside a second, outlined bezel.
struct Bezel<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(.horizontal, 6).frame(height: 50)
            .background(Capsule().fill(Pro.card).overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1)))
            .padding(5)
            .background(Capsule().strokeBorder(.white.opacity(0.07), lineWidth: 1))
    }
}

struct BezelItem: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 15, weight: .light)).foregroundStyle(.white)
            .padding(.horizontal, 18).frame(height: 44).contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct DarkPill: ButtonStyle {
    var accent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .semibold)).foregroundStyle(accent ? Color.black : .white)
            .padding(.horizontal, 18).frame(height: 36)
            .background(Capsule().fill(accent ? Pro.yellow : Pro.cardHi))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

// MARK: - Welcome (dark session, lyrics-style phrase)

struct ProWelcomeView: View {
    var keys: KeyState
    var island: IslandModel
    var status: SetupStatus
    var practice: Practice
    let trigger: Trigger
    let skip: () -> Void
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var ready: Bool { status.mic && status.engineDone }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SpitballLogo(dark: true)
                Spacer()
                if !practice.finished { Button("Skip", action: skip).buttonStyle(DarkPill()) }
            }
            .padding(.leading, 70).padding(.top, 6)

            if practice.finished { finale } else { session }
        }
        .padding(.horizontal, 22).padding(.bottom, 22)
        .frame(width: 560, height: 760)
        .background(Pro.night)
        .environment(\.colorScheme, .dark)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { appeared = true } }
    }

    var session: some View {
        VStack(alignment: .leading, spacing: 18) {
            // The card: all three phrases like lyrics. Said words are white, the rest wait in grey.
            VStack(alignment: .leading, spacing: 22) {
                Text("Say these, one at a time").font(Pro.mono(14)).foregroundStyle(.white.opacity(0.45))
                ForEach(Array(Practice.phrases.enumerated()), id: \.offset) { i, p in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(i < practice.index ? "✓ \(i + 1)" : "\(i + 1)").font(Pro.mono(13)).foregroundStyle(i == practice.index ? Pro.yellow : .white.opacity(0.35))
                        lyric(p, index: i).font(Pro.mono(21)).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(26)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Pro.card))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Practice \(practice.index + 1) of \(Practice.phrases.count). Say: \(practice.phrase)")

            // Live voice + status, like the scrubber.
            VStack(spacing: 8) {
                ZStack {
                    if practice.phase == .listening {
                        LiveMiniWave(island: island, animate: !reduceMotion).foregroundStyle(.white).frame(height: 30)
                    } else {
                        Waveform(seed: 7, progress: Double(practice.index) / Double(Practice.phrases.count)).frame(height: 30).padding(.horizontal, 40)
                    }
                }
                .frame(height: 34)
                Text(headline).font(Pro.mono(13)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                Bezel {
                    HStack(spacing: 0) {
                        setupItem("mic", ok: status.mic, action: status.allowMic)
                        Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 22)
                        setupItem("access", ok: status.accessibility, action: status.allowAccessibility)
                        Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 22)
                        setupItem(status.engineDone ? "speech" : "speech…", ok: status.engineDone, action: nil)
                    }
                }
                Spacer(minLength: 0)
                Bezel {
                    HStack(spacing: 8) {
                        ForEach(0..<2, id: \.self) { i in
                            Text("⌘").font(.system(size: 15, weight: .medium))
                                .foregroundStyle(keys.taps > i || keys.commandDown ? Color.black : .white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(keys.taps > i || keys.commandDown ? Pro.yellow : Pro.cardHi))
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .accessibilityHidden(true)
            }
            if !status.accessibility { PermissionGuide(open: status.allowAccessibility).colorScheme(.light) }
            SkinPicker(theme: .pacific, dark: true).frame(width: 220)
        }
    }

    func setupItem(_ title: String, ok: Bool, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            HStack(spacing: 8) {
                Circle().fill(ok ? Pro.yellow : Color.white.opacity(0.25)).frame(width: 8, height: 8)
                Text(title)
            }
        }
        .buttonStyle(BezelItem())
        .disabled(ok || action == nil)
        .accessibilityLabel("\(title): \(ok ? "done" : "needed")")
    }

    func lyric(_ phrase: String, index: Int) -> Text {
        let words = phrase.split(separator: " ").map(String.init)
        let live = index == practice.index && (practice.phase == .listening || practice.phase == .thinking)
        var a = AttributedString()
        for (i, w) in words.enumerated() {
            let lit = index < practice.index || (live && i < practice.spoken)
            var part = AttributedString(w + (i < words.count - 1 ? " " : ""))
            part.foregroundColor = lit ? .white : (index == practice.index ? Color.white.opacity(0.42) : Color.white.opacity(0.2))
            a += part
        }
        return Text(a)
    }

    var headline: String {
        if !status.mic { return "allow the microphone" }
        if !status.engineDone { return "getting speech ready…" }
        switch practice.phase {
        case .listening: return trigger == .doubleCommand ? "listening… tap ⌘ when you're done" : "listening…"
        case .thinking: return "one sec…"
        case .heard(let text, let ok): return ok ? "got it" : (text.isEmpty ? "didn't catch that, try again" : "heard “\(text)”, once more?")
        default: return trigger == .doubleCommand ? "double-tap ⌘ and say phrase \(practice.index + 1)" : "\(trigger.label.lowercased()) and say it"
        }
    }

    var finale: some View {
        VStack(spacing: 22) {
            Spacer()
            Text("You're in.").font(.system(size: 40, weight: .bold)).tracking(-1.5).foregroundStyle(.white)
            Text("Double-tap ⌘ in any app.").font(Pro.mono(14)).foregroundStyle(.white.opacity(0.6))
            IDCardView(member: Member.shared).frame(width: 400, height: 252)
                .accessibilityLabel("Your Spitball member card, number \(Member.shared.number)")
            HStack(spacing: 10) {
                Button("Share on 𝕏") { Member.shared.shareOnX() }.buttonStyle(DarkPill())
                Button("Save image") { Member.shared.saveImage() }.buttonStyle(DarkPill())
                Button("Start talking") { skip() }.buttonStyle(DarkPill(accent: true)).keyboardShortcut(.defaultAction)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct ProButton: ButtonStyle {
    var filled = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(filled ? Color.white : Pro.ink)
            .padding(.horizontal, 18).frame(height: 38)
            .background(Capsule().fill(filled ? Pro.ink : Pro.field))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}
