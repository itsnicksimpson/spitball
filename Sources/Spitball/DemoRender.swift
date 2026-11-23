import AppKit
import Observation
import SwiftUI

/// `Spitball --render-demo <out-dir>`: renders the README/site demo frame by frame from the
/// app's real views (island, caret waveform, keycap). ffmpeg turns the frames into a GIF/MP4.
enum DemoRender {
    struct Scene: View {
        var m: IslandModel
        let typed: String
        let cmdDown: Bool
        let listening: Bool
        let caption: String
        @AppStorage("theme") private var theme: RetroTheme = .pacific

        var body: some View {
            ZStack(alignment: .top) {
                Halftone(theme: theme)
                // menu bar + notch island
                Rectangle().fill(Color.white.opacity(0.55)).frame(height: 28)
                    .overlay(HStack { Text(" Notes   File   Edit   View").font(.system(size: 11, weight: .medium)); Spacer(); Text("Mon 9:41 ").font(.system(size: 11, weight: .medium)) }.padding(.horizontal, 10))
                IslandView(m: m).frame(width: 560, height: 90)
                // a Notes-ish window
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.79, blue: 0.25)], id: \.self) { Circle().fill($0).frame(width: 11, height: 11) }
                        Spacer(); Text("Notes").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary); Spacer(); Color.clear.frame(width: 45)
                    }
                    .padding(.horizontal, 10).frame(height: 30).background(Color(white: 0.96))
                    VStack(alignment: .leading, spacing: 30) {
                        Text("Standup").font(.system(size: 20, weight: .bold))
                        ZStack(alignment: .topLeading) {
                            Text({ var a = AttributedString(typed); var c = AttributedString("|"); c.foregroundColor = .accentColor; a += c; return a }()).font(.system(size: 15)).lineSpacing(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if listening {
                                CaretWaveView(m: m).offset(x: -16, y: -24)
                            }
                        }
                    }
                    .padding(18)
                    Spacer()
                }
                .frame(width: 460, height: 210)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
                .padding(.top, 92)
                // keycap + caption
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        KeyCap(symbol: "⌘", label: "command", pressed: cmdDown)
                        Text(caption).font(RetroFont.title(14)).foregroundStyle(.white).shadow(color: .black.opacity(0.5), radius: 0, x: 1.5, y: 1.5)
                    }
                    .padding(.bottom, 22)
                }
            }
            .frame(width: 720, height: 405)
            .clipped()
        }
    }

    @MainActor static func run(out: String) {
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let m = IslandModel(); m.style = .notch; m.cutoutWidth = 150; m.barHeight = 28
        let fps = 15.0, frames = 100
        let sentence = "Running five minutes late, start standup without me."
        var voiceT = 0.0, env = 0.0, target = 0.0, until = 0.0, gap = 0.0, syll = 0
        var host: NSHostingView<Scene>?
        let win = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 720, height: 405), styleMask: [.borderless], backing: .buffered, defer: false)
        win.orderFrontRegardless()
        for f in 0..<frames {
            let t = Double(f) / fps
            let tap1 = (0.5..<0.65).contains(t), tap2 = (0.8..<0.95).contains(t), tap3 = (4.0..<4.15).contains(t)
            let listening = (0.95..<4.0).contains(t), working = (4.0..<4.35).contains(t), done = (4.35..<4.8).contains(t)
            m.phase = listening ? .listening : (working ? .working : (done ? .done : .hidden))
            m.armed = t > 1.05
            if listening {
                voiceT += 1 / fps
                if voiceT > until {
                    if voiceT < gap { target = 0 } else {
                        syll += 1
                        if syll % 4 == 0 { gap = voiceT + 0.16; target = 0 } else { target = 0.5 + Double((syll * 37) % 50) / 100 }
                        until = voiceT + 0.13
                    }
                }
                env += (target - env) * (target > env ? 0.6 : 0.3)
                let b = (0..<5).map { i in Float(min(1, env * (0.6 + 0.4 * abs(sin(Double(f) * 0.9 + Double(i)))))) }
                m.set(bands: b)
            } else { m.levels = Array(repeating: 0, count: 9) }
            let typed = t >= 4.35 ? sentence : ""
            let caption = t < 0.95 ? "Double-tap ⌘" : (listening ? "Talk…" : (t < 4.8 ? "Tap ⌘" : "Done. In any app."))
            let scene = Scene(m: m, typed: typed, cmdDown: tap1 || tap2 || tap3, listening: listening, caption: caption)
            if host == nil { host = NSHostingView(rootView: scene); host!.frame = NSRect(x: 0, y: 0, width: 720, height: 405); win.contentView = host }
            else { host!.rootView = scene }
            RunLoop.main.run(until: Date() + 0.03)
            host!.layoutSubtreeIfNeeded()
            if let rep = host!.bitmapImageRepForCachingDisplay(in: host!.bounds) {
                host!.cacheDisplay(in: host!.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: String(format: "%@/f%03d.png", out, f)))
            }
        }
        win.orderOut(nil)
        print("rendered \(frames) frames")
    }
}
