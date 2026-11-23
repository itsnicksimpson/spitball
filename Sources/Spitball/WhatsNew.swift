import AppKit
import SwiftUI

/// A little retro "What's new" window, shown once after each update.
enum WhatsNew {
    static let notes: [(String, String, String)] = [
        ("Faster and steadier", "Long dictations are transcribed while you talk, so 90 seconds pastes as fast as 3. The bubble shows up every time.", "bolt.fill"),
        ("AirPods-proof", "Spitball uses your Mac's mic when AirPods are connected, so they stay in high-quality mode and dictation never goes silent when they hop to your iPhone.", "airpods"),
        ("A real Mac app", "A new Liquid Glass icon, and a Dock dot and ⌘-Tab while Spitball's window is open.", "macwindow"),
        ("A new Pro look", "Big type, roomy rows, a floating sidebar and dark note screens. Smooth scrolling, even with a long history.", "sparkles"),
        ("Notes and meetings, no bot", "⌃⌘N records a voice note. ⌃⌘M takes meeting notes from your mic and your Mac's audio, with a summary and action items.", "waveform.and.mic"),
        ("Smart formatting", "Lists become lists, \"scratch that\" takes it back, emails get paragraphs, and file names on screen come out exact.", "text.badge.checkmark"),
        ("Your instructions", "Tell it \"use British English\" once, for every app or just one.", "text.quote"),
        ("Your agents can read your notes", "Copy the MCP config into Claude, Cursor or Codex, or use the spitball command. All local.", "terminal"),
        ("25 languages, plus more", "Switch languages mid-sentence, or pick Japanese, Korean, Chinese, Hindi and more.", "globe"),
        ("One clean voice pill", "The notch, the Dynamic Island and your cursor share one black pill with rainbow light that rises with your voice.", "circle.lefthalf.filled"),
    ]

    @MainActor private static var window: NSWindow?
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    /// Shows the window if this version hasn't been seen yet (never on a brand-new install).
    @MainActor static func showIfNeeded() {
        let d = UserDefaults.standard
        defer { d.set(version, forKey: "lastSeenVersion") }
        guard Settings.onboarded, let last = d.string(forKey: "lastSeenVersion"), last != version else { return }
        show()
    }

    @MainActor static func show() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(); return }
        let w = RetroWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 640), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = true; w.isMovableByWindowBackground = true; w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: WhatsNewView(close: { window?.close(); window = nil }))
        w.center(); window = w
        w.makeKeyAndOrderFront(nil); NSApp.activate()
        A11y.announce("What's new in Spitball \(version)")
    }
}

struct WhatsNewView: View {
    let close: () -> Void
    @AppStorage("theme") private var theme: RetroTheme = .pacific
    @AppStorage("skin") private var skin: Skin = .playful

    var body: some View {
        VStack(spacing: 0) {
            RetroTitleBar(title: "What's new in Spitball \(WhatsNew.version)", theme: theme, close: close)
            ZStack {
                Gingham(theme: theme)
                ScrollView { VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(WhatsNew.notes.enumerated()), id: \.offset) { i, n in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: n.2).font(.system(size: 14, weight: .bold)).foregroundStyle(theme.paper)
                                .frame(width: 30, height: 30).background(theme.ink)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(n.0).font(RetroFont.title(13)).foregroundStyle(theme.ink)
                                Text(n.1).font(RetroFont.body(12)).foregroundStyle(theme.ink.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(12)
                        .accessibilityElement(children: .combine)
                        if i < WhatsNew.notes.count - 1 { Rectangle().fill(theme.ink.opacity(0.2)).frame(height: 1) }
                    }
                }
                .background(theme.paper)
                .skinStroke(theme)
                .skinDrop(theme)
                .padding(16) }
            }
            HStack {
                Text("Say it. Ship it.").font(RetroFont.serifItalic(16)).foregroundStyle(theme.ink)
                Spacer()
                Button("Nice", action: close).buttonStyle(RetroButtonStyle(theme: theme, filled: true)).keyboardShortcut(.defaultAction)
            }
            .padding(14)
            .background(theme.paper)
            .overlay(alignment: .top) { Rectangle().fill(Skin.isPro ? Color.black.opacity(0.08) : theme.ink).frame(height: Skin.isPro ? 1 : 1.5) }
        }
        .background(theme.paper)
        .skinStroke(theme)
        .frame(width: 460, height: 640)
        .id(skin)
    }
}
