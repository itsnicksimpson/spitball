import AppKit
import SwiftUI

// Spitball's look: a 1991 Mac on summer vacation. Pinstriped title bars, chunky
// 1.5 pt borders, offset-shadow buttons, Monaco + Geneva type, halftone
// sunsets, and four themes to swap between.

/// Two looks for the same app: the retro "Playful" one, and a clean, rounded "Pro" one.
enum Skin: String, CaseIterable, Identifiable {
    case playful, pro
    var id: String { rawValue }
    var label: String { self == .playful ? "Playful" : "Pro" }
    static var current: Skin { Skin(rawValue: UserDefaults.standard.string(forKey: "skin") ?? "") ?? .playful }
    static var isPro: Bool { current == .pro }
}

enum RetroTheme: String, CaseIterable, Identifiable {
    case pacific, grape, lagoon, mint
    var id: String { rawValue }

    var name: String {
        switch self {
        case .pacific: "Pacific Breeze"
        case .grape: "Grape Soda"
        case .lagoon: "Lagoon"
        case .mint: "Mint Julep"
        }
    }
    /// Sunset/sky for the LCD panel and halftones.
    var top: Color {
        if Skin.isPro { return Color(white: 0.985) }
        return switch self {
        case .pacific: Color(red: 0.40, green: 0.70, blue: 0.96)
        case .grape: Color(red: 0.42, green: 0.18, blue: 0.86)
        case .lagoon: Color(red: 0.05, green: 0.36, blue: 0.43)
        case .mint: Color(red: 0.07, green: 0.42, blue: 0.30)
        }
    }
    var bottom: Color {
        if Skin.isPro { return Color(white: 0.94) }
        return switch self {
        case .pacific: Color(red: 1.0, green: 0.74, blue: 0.62)
        case .grape: Color(red: 1.0, green: 0.56, blue: 0.82)
        case .lagoon: Color(red: 1.0, green: 0.78, blue: 0.58)
        case .mint: Color(red: 0.62, green: 0.96, blue: 0.74)
        }
    }
    /// Lines, text, borders.
    var ink: Color {
        if Skin.isPro { return Color(red: 0.08, green: 0.08, blue: 0.09) }
        return switch self {
        case .pacific: Color(red: 0.07, green: 0.07, blue: 0.12)
        case .grape: Color(red: 0.20, green: 0.04, blue: 0.42)
        case .lagoon: Color(red: 0.02, green: 0.20, blue: 0.24)
        case .mint: Color(red: 0.03, green: 0.22, blue: 0.15)
        }
    }
    /// Window paper.
    var paper: Color {
        if Skin.isPro { return Color.white }
        return switch self {
        case .pacific: Color(red: 1.0, green: 0.985, blue: 0.955)
        case .grape: Color(red: 1.0, green: 0.95, blue: 0.985)
        case .lagoon: Color(red: 0.99, green: 0.97, blue: 0.93)
        case .mint: Color(red: 0.96, green: 1.0, blue: 0.97)
        }
    }
    var soft: Color { Skin.isPro ? Color(white: 0.95) : paper.mix(with: accent, by: 0.18) }
    /// Highlight / selection.
    var accent: Color {
        if Skin.isPro { return Color(red: 0.2, green: 0.47, blue: 1.0) }
        return switch self {
        case .pacific: Color(red: 1.0, green: 0.52, blue: 0.42)
        case .grape: Color(red: 1.0, green: 0.45, blue: 0.75)
        case .lagoon: Color(red: 1.0, green: 0.66, blue: 0.40)
        case .mint: Color(red: 0.35, green: 0.86, blue: 0.56)
        }
    }

    static var current: RetroTheme {
        RetroTheme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .pacific
    }
}

enum RetroFont {
    /// Registers the bundled fonts (Yellowtail, IBM Plex Mono, Instrument Serif) once.
    /// Same type as the website, so the app and the site feel like one thing.
    static let registered: Bool = {
        let dirs = [Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
                    URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Fonts")]
        for case let dir? in dirs {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for f in files where f.pathExtension == "ttf" { CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil) }
            return true
        }
        return false
    }()
    private static func pick(_ name: String, _ fallback: String, _ size: CGFloat) -> Font {
        _ = registered
        return NSFont(name: name, size: size) != nil ? .custom(name, size: size) : .custom(fallback, size: size)
    }
    static func title(_ size: CGFloat = 12) -> Font { Skin.isPro ? .system(size: size + 1, weight: .semibold) : pick("IBMPlexMono-Bold", "Monaco", size) }
    static func mono(_ size: CGFloat = 11) -> Font { Skin.isPro ? .system(size: size + 1) : pick("IBMPlexMono-Medium", "Monaco", size) }
    static func body(_ size: CGFloat = 13) -> Font { Skin.isPro ? .system(size: size + 2) : .system(size: size, weight: .medium) }
    static func serif(_ size: CGFloat = 28) -> Font { Skin.isPro ? .system(size: size * 0.82, weight: .semibold) : pick("InstrumentSerif-Regular", "Georgia", size) }
    static func serifItalic(_ size: CGFloat = 28) -> Font { Skin.isPro ? .system(size: size * 0.8, weight: .regular) : pick("InstrumentSerif-Italic", "Georgia-Italic", size) }
    static func script(_ size: CGFloat = 34) -> Font { Skin.isPro ? .system(size: size * 0.6, weight: .semibold) : pick("Yellowtail-Regular", "SnellRoundhand-Black", size) }
}

/// Pink gingham, like the Poolsuite-style desktop on the website.
struct Gingham: View {
    let theme: RetroTheme
    var body: some View {
        if Skin.isPro { Color(white: 0.965) } else { gingham }
    }
    var gingham: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(theme.paper))
            let s: CGFloat = 9, tint = theme.accent.opacity(0.16)
            var x: CGFloat = 0
            while x < size.width { ctx.fill(Path(CGRect(x: x, y: 0, width: s, height: size.height)), with: .color(tint)); x += s * 2 }
            var y: CGFloat = 0
            while y < size.height { ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: s)), with: .color(tint)); y += s * 2 }
        }
        .accessibilityHidden(true)
    }
}

/// The classic striped title bar with a square close box.
struct RetroTitleBar: View {
    let title: String
    let theme: RetroTheme
    var close: (() -> Void)?

    var body: some View {
        if Skin.isPro { pro } else { retro }
    }

    var pro: some View {
        HStack(spacing: 8) {
            if let close {
                Button(action: close) { Circle().fill(Color(white: 0.82)).frame(width: 12, height: 12) }
                    .buttonStyle(.plain).accessibilityLabel("Close").keyboardShortcut("w", modifiers: .command)
            }
            Spacer()
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.ink.opacity(0.85)).accessibilityAddTraits(.isHeader)
            Spacer()
            Color.clear.frame(width: close == nil ? 0 : 12, height: 12)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(theme.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.07)).frame(height: 1) }
    }

    var retro: some View {
        HStack(spacing: 8) {
            if let close {
                Button(action: close) {
                    Rectangle().fill(theme.paper).frame(width: 13, height: 13)
                        .overlay(Rectangle().strokeBorder(theme.ink, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .keyboardShortcut("w", modifiers: .command)
            }
            Pinstripes(color: theme.ink)
            Text(title).font(RetroFont.title(12)).foregroundStyle(theme.ink).fixedSize()
                .accessibilityAddTraits(.isHeader)
            Pinstripes(color: theme.ink)
            Rectangle().fill(.clear).frame(width: close == nil ? 0 : 13, height: 13)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(theme.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.ink).frame(height: 1.5) }
    }
}

struct Pinstripes: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 2
            while y < size.height - 1 {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(color))
                y += 2.5
            }
        }
        .frame(height: 13)
        .accessibilityHidden(true)
    }
}

/// Riso-print halftone: dots that grow toward the bottom, in the theme's sunset.
struct Halftone: View {
    let theme: RetroTheme
    var spacing: CGFloat = 6

    var body: some View {
        if Skin.isPro {
            LinearGradient(colors: [Color(white: 0.99), Color(white: 0.945)], startPoint: .top, endPoint: .bottom)
        } else { dots }
    }
    var dots: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [theme.top, theme.bottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            var row = 0
            var y: CGFloat = 0
            while y < size.height + spacing {
                let t = y / max(size.height, 1)
                let r = spacing * 0.42 * (0.15 + t * 0.85)
                var x: CGFloat = row % 2 == 0 ? 0 : spacing / 2
                while x < size.width + spacing {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(theme.ink.opacity(0.22)))
                    x += spacing
                }
                y += spacing * 0.866
                row += 1
            }
        }
        .accessibilityHidden(true)
    }
}

/// Chunky retro button with an offset shadow that "presses" down.
struct RetroButtonStyle: ButtonStyle {
    let theme: RetroTheme
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        if Skin.isPro {
            return AnyView(configuration.label
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(filled ? Color.white : theme.ink)
                .padding(.horizontal, 18).frame(height: 38)
                .background(Capsule().fill(filled ? theme.ink : Color.white)
                    .overlay(Capsule().strokeBorder(Color.black.opacity(filled ? 0 : 0.1))))
                .scaleEffect(pressed ? 0.97 : 1)
                .opacity(pressed ? 0.85 : 1)
                .contentShape(Capsule()))
        }
        return AnyView(configuration.label
            .font(RetroFont.title(11))
            .foregroundStyle(filled ? theme.paper : theme.ink)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Rectangle().fill(filled ? theme.ink : theme.paper))
            .overlay(Rectangle().strokeBorder(theme.ink, lineWidth: 1.5))
            .background(Rectangle().fill(theme.ink).offset(x: pressed ? 0 : 2, y: pressed ? 0 : 2))
            .offset(x: pressed ? 2 : 0, y: pressed ? 2 : 0)
            .contentShape(Rectangle()))
    }
}

/// Square classic-Mac checkbox.
struct RetroCheckStyle: ToggleStyle {
    let theme: RetroTheme
    func makeBody(configuration: Configuration) -> some View {
        if Skin.isPro {
            return AnyView(Button { configuration.isOn.toggle() } label: {
                HStack {
                    configuration.label.font(.system(size: 15)).foregroundStyle(theme.ink)
                    Spacer(minLength: 16)
                    ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                        Capsule().fill(configuration.isOn ? theme.ink : Color(white: 0.8)).frame(width: 42, height: 26)
                        Circle().fill(.white).frame(width: 22, height: 22).padding(2).shadow(color: .black.opacity(0.15), radius: 1.5, y: 1)
                    }
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isOn)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isToggle)
            .accessibilityValue(configuration.isOn ? "on" : "off"))
        }
        return AnyView(Button { configuration.isOn.toggle() } label: {
            HStack(alignment: .top, spacing: 9) {
                ZStack {
                    Rectangle().fill(theme.paper).frame(width: 14, height: 14)
                        .overlay(Rectangle().strokeBorder(theme.ink, lineWidth: 1.5))
                    if configuration.isOn {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .black)).foregroundStyle(theme.ink)
                    }
                }
                .padding(.top, 1)
                configuration.label.font(RetroFont.body(13)).foregroundStyle(theme.ink)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "on" : "off"))
    }
}

/// An inset box with a 1.5 pt border, like a classic Mac panel.
struct RetroBox<Content: View>: View {
    let theme: RetroTheme
    @ViewBuilder let content: Content
    var body: some View {
        content
            .background(theme.paper)
            .skinStroke(theme)
    }
}

/// Retro text field.
struct RetroField: View {
    let theme: RetroTheme
    let placeholder: String
    @Binding var text: String
    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(RetroFont.body(13))
            .foregroundStyle(theme.ink)
            .padding(.horizontal, Skin.isPro ? 10 : 7).padding(.vertical, Skin.isPro ? 7 : 5)
            .background(Skin.isPro ? AnyView(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white).overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.black.opacity(0.07))))
                                   : AnyView(Color.white.opacity(0.7).overlay(Rectangle().strokeBorder(theme.ink, lineWidth: 1.5))))
    }
}

/// A borderless window that can still take keyboard focus (for text fields).
final class RetroWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

extension View {
    /// Playful: a chunky 1.5 pt ink border. Pro: rounded corners and a hairline.
    @ViewBuilder func skinStroke(_ theme: RetroTheme, radius: CGFloat = 14) -> some View {
        if Skin.isPro {
            self.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            self.overlay(Rectangle().strokeBorder(theme.ink, lineWidth: 1.5))
        }
    }
    /// Playful: a hard offset shadow. Pro: a soft, diffuse one.
    @ViewBuilder func skinDrop(_ theme: RetroTheme) -> some View {
        if Skin.isPro { self }
        else { self.background(Rectangle().fill(theme.ink).offset(x: 4, y: 4)) }
    }
}

/// Playful / Pro switch (onboarding + Settings).
struct SkinPicker: View {
    @AppStorage("skin") private var skin: Skin = .playful
    let theme: RetroTheme
    var dark = false      // on the dark welcome screen
    var body: some View {
        if Skin.isPro || dark { capsule } else { retro }
    }

    func choose(_ s: Skin) {
        guard skin != s else { return }
        skin = s
        NotificationCenter.default.post(name: .spitballSkinChanged, object: nil)
    }

    /// [untitled]-style segmented capsule.
    var capsule: some View {
        HStack(spacing: 0) {
            ForEach(Skin.allCases) { s in
                Button { choose(s) } label: {
                    Text(s == .playful ? "Playful" : "Pro").font(.system(size: 14, weight: skin == s ? .medium : .regular))
                        .foregroundStyle(dark ? Color.white.opacity(skin == s ? 1 : 0.6) : Pro.ink.opacity(skin == s ? 1 : 0.55))
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .background(Capsule().fill(skin == s ? (dark ? Pro.cardHi : Color.white) : .clear)
                            .shadow(color: .black.opacity(skin == s && !dark ? 0.08 : 0), radius: 3, y: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(s.label) style")
                .accessibilityAddTraits(skin == s ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(4)
        .background(Capsule().fill(dark ? Pro.card : Color.black.opacity(0.06)))
    }

    var retro: some View {
        HStack(spacing: 0) {
            ForEach(Skin.allCases) { s in
                Button { choose(s) } label: {
                    VStack(spacing: 2) {
                        Text(s == .playful ? "☼ Playful" : "◐ Pro").font(RetroFont.title(12))
                        Text(s == .playful ? "retro, fun" : "clean, minimal").font(RetroFont.mono(9)).opacity(0.65)
                    }
                    .foregroundStyle(skin == s ? theme.paper : theme.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background(skin == s ? theme.ink : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(s.label) style")
                .accessibilityAddTraits(skin == s ? [.isSelected, .isButton] : .isButton)
            }
        }
        .overlay(Rectangle().strokeBorder(theme.ink, lineWidth: 1.5))
    }
}
