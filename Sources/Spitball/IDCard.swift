import AppKit
import Observation
import SwiftUI

/// Your Spitball Club membership: a number, a name, a join date.
@Observable final class Member {
    static let shared = Member()
    private let d = UserDefaults.standard

    var number: Int { d.integer(forKey: "memberNo") }
    var name: String { d.string(forKey: "memberName") ?? NSFullUserName() }
    var since: Date { (d.object(forKey: "memberSince") as? Date) ?? Date() }
    var numberText: String { String(format: "NO. %05d", number) }

    func ensure() {
        if d.integer(forKey: "memberNo") == 0 { d.set(Int.random(in: 1000...99999), forKey: "memberNo") }
        if d.object(forKey: "memberSince") == nil { d.set(Date(), forKey: "memberSince") }
    }

    static let site = "https://itsnicksimpson.github.io/spitball/"

    /// Copies the card image (so you can paste it into the post) and opens X.
    @MainActor func shareOnX() {
        ensure()
        copyImage()
        let text = "Just joined the Spitball Club (\(numberText)) ☼ Free, open-source dictation for Mac. Double-tap ⌘, talk, done."
        var c = URLComponents(string: "https://x.com/intent/post")!
        c.queryItems = [URLQueryItem(name: "text", value: text), URLQueryItem(name: "url", value: Member.site)]
        if let url = c.url { NSWorkspace.shared.open(url) }
    }

    @MainActor func png() -> Data? {
        let r = ImageRenderer(content: IDCardView(member: self).frame(width: 600, height: 378))
        r.scale = 2
        guard let tiff = r.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    @MainActor func copyImage() {
        guard let data = png() else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: .png)
    }

    @MainActor func saveImage() {
        ensure()
        guard let data = png() else { return }
        let url = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0].appendingPathComponent("Spitball ID.png")
        try? data.write(to: url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        A11y.announce("Saved your card to the Desktop")
    }
}

/// Holographic foil card with one big debossed wordmark running edge to edge.
struct IDCardView: View {
    let member: Member
    @AppStorage("theme") private var theme: RetroTheme = .pacific

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let shape = RoundedRectangle(cornerRadius: w * 0.04, style: .continuous)
            ZStack {
                shape.fill(LinearGradient(colors: [Color(red: 1, green: 0.99, blue: 0.965), Color(red: 0.957, green: 0.925, blue: 1),
                                                   Color(red: 0.9, green: 0.98, blue: 1), Color(red: 1, green: 0.945, blue: 0.886)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                // Foil stripes
                Canvas { ctx, size in
                    let colors: [Color] = [.init(red: 1, green: 0.6, blue: 0.84), .init(red: 1, green: 0.83, blue: 0.42), .init(red: 0.56, green: 0.94, blue: 0.78),
                                           .init(red: 0.49, green: 0.78, blue: 1), .init(red: 0.71, green: 0.55, blue: 1)]
                    var x = -size.height, i = 0
                    while x < size.width + size.height {
                        var p = Path(); p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height * 0.45, y: 0))
                        ctx.stroke(p, with: .color(colors[i % colors.count].opacity(0.3)), lineWidth: w * 0.006)
                        x += w * 0.014; i += 1
                    }
                }
                // Debossed wordmark, stretched edge to edge.
                // Padded with spaces: the script's swashes overhang its measured width.
                let mark = "\u{2002}Spitball\u{2002}"
                ZStack {
                    Text(mark).foregroundStyle(theme.ink.opacity(0.22)).offset(x: -1.5, y: -1.5)
                    Text(mark).foregroundStyle(.white.opacity(0.95)).offset(x: 1.5, y: 1.5)
                    Text(mark).foregroundStyle(theme.ink.opacity(0.07))
                }
                .font(RetroFont.script(w * 0.36))
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .frame(width: w * 0.98)
                .offset(y: -w * 0.025)
                VStack {
                    HStack { Text("MEMBER"); Spacer(); Text(member.numberText) }
                        .font(RetroFont.title(w * 0.024)).tracking(w * 0.006)
                    Spacer()
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(member.name.uppercased()).font(RetroFont.title(w * 0.032)).tracking(w * 0.005)
                            Text("SINCE " + member.since.formatted(.dateTime.month(.abbreviated).year()).uppercased())
                                .font(RetroFont.mono(w * 0.022)).tracking(w * 0.004).opacity(0.6)
                        }
                        Spacer()
                        HStack(spacing: w * 0.006) {
                            ForEach(Array([2, 1, 3, 1, 2, 2, 1, 3, 1, 1, 2, 3].enumerated()), id: \.offset) { _, n in
                                Rectangle().frame(width: w * 0.004 * CGFloat(n), height: w * 0.05)
                            }
                        }
                        .opacity(0.8)
                    }
                }
                .foregroundStyle(theme.ink)
                .padding(w * 0.045)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(theme.ink, lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 8)
        }
        .aspectRatio(1.586, contentMode: .fit)
    }
}
