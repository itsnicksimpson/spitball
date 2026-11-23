// Spitball app icon: minimal black & white, made to stand out in the Dock.
// `swift scripts/icon.swift out.png [size] [variant]`   variants: pixel (default: aged 1-bit comet), comet, lines, ball
import AppKit
import SwiftUI

let ink = Color(red: 0.04, green: 0.04, blue: 0.05)
let paper = Color.white
let variant = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "pixel"

/// A ball with a tapered tail: the spitball in flight.
struct Comet: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let R = r.height / 2, cx = r.maxX - R, cy = r.midY
        p.addArc(center: CGPoint(x: cx, y: cy), radius: R, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        // tail sweeps back to a point on the left
        p.addCurve(to: CGPoint(x: r.minX, y: cy - R * 0.05),
                   control1: CGPoint(x: cx - R * 0.9, y: cy + R), control2: CGPoint(x: r.minX + r.width * 0.25, y: cy + R * 0.2))
        p.addCurve(to: CGPoint(x: cx, y: cy - R),
                   control1: CGPoint(x: r.minX + r.width * 0.3, y: cy - R * 0.45), control2: CGPoint(x: cx - R * 0.9, y: cy - R))
        p.closeSubpath()
        return p
    }
}

/// The comet, rasterized to a tiny 1-bit grid with Bayer dithering on its soft edge:
/// an "aged" original-Macintosh version of the mark.
struct PixelComet: View {
    let grid = 46
    var cells: [[Bool]] {
        let n = grid
        let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n, space: CGColorSpaceCreateDeviceGray(),
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.setFillColor(gray: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: n, height: n))
        ctx.translateBy(x: 0, y: CGFloat(n)); ctx.scaleBy(x: 1, y: -1)          // top-left origin, like SwiftUI
        ctx.translateBy(x: CGFloat(n) / 2, y: CGFloat(n) / 2); ctx.rotate(by: -18 * .pi / 180)
        let w = CGFloat(n) * 0.8, h = w * 0.55
        let path = Comet().path(in: CGRect(x: -w / 2 + 1, y: -h / 2 - 1, width: w, height: h)).cgPath
        ctx.addPath(path); ctx.setFillColor(gray: 1, alpha: 1); ctx.fillPath()
        let px = ctx.data!.bindMemory(to: UInt8.self, capacity: n * n)
        let bayer: [[Double]] = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
        let raw: [[Bool]] = (0..<n).map { y in (0..<n).map { x in
            // Tail fades out through the dither, like a 1-bit motion trail.
            let fade = min(1, max(0.18, (Double(x) - Double(n) * 0.12) / (Double(n) * 0.42)))
            let v = Double(px[y * n + x]) / 255 * fade
            return v > (bayer[y % 4][x % 4] + 0.5) / 16
        } }
        // Optically center: shift the lit pixels so their bounding box sits in the middle,
        // nudged a touch toward the ball (the heavy end) so it doesn't feel off-balance.
        var minX = n, maxX = 0, minY = n, maxY = 0
        for y in 0..<n { for x in 0..<n where raw[y][x] { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
        let dx = (n - 1 - maxX - minX) / 2 - 1, dy = (n - 1 - maxY - minY) / 2
        return (0..<n).map { y in (0..<n).map { x in
            let sx = x - dx, sy = y - dy
            return sx >= 0 && sy >= 0 && sx < n && sy < n && raw[sy][sx]
        } }
    }
    var body: some View {
        let c = cells
        Canvas { ctx, size in
            let s = size.width / CGFloat(grid)
            for (y, row) in c.enumerated() { for (x, on) in row.enumerated() where on {
                ctx.fill(Path(CGRect(x: CGFloat(x) * s, y: CGFloat(y) * s, width: s + 1, height: s + 1)), with: .color(Color(white: 0.97)))
            } }
        }
    }
}

/// Faint film grain + vignette, for an aged print feel.
struct Grain: View {
    var body: some View {
        Canvas { ctx, size in
            var seed: UInt64 = 0x5eed
            func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) }
            let step: CGFloat = 8
            var y: CGFloat = 0
            while y < size.height { var x: CGFloat = 0
                while x < size.width { let r = rnd(); if r > 0.7 { ctx.fill(Path(CGRect(x: x, y: y, width: step, height: step)), with: .color(.white.opacity((r - 0.7) * 0.12))) }; x += step }
                y += step }
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.35)]),
                center: CGPoint(x: size.width / 2, y: size.height / 2), startRadius: size.width * 0.3, endRadius: size.width * 0.75))
        }
    }
}

struct Icon: View {
    var body: some View {
        let dark = variant != "ball"
        ZStack {
            RoundedRectangle(cornerRadius: 186, style: .continuous)
                .fill(dark ? ink : paper)
                .overlay(
                    // the faintest top sheen, like Linear/Claude icons
                    RoundedRectangle(cornerRadius: 186, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(dark ? 0.10 : 0), .clear], startPoint: .top, endPoint: .center))
                )
                .overlay(Group { if variant == "pixel" { Grain().clipShape(RoundedRectangle(cornerRadius: 186, style: .continuous)) } })
                .overlay(RoundedRectangle(cornerRadius: 186, style: .continuous).strokeBorder(dark ? .white.opacity(0.08) : .black.opacity(0.08), lineWidth: 3))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.28), radius: 20, y: 14)

            switch variant {
            case "lines":
                HStack(spacing: 46) {
                    VStack(alignment: .trailing, spacing: 44) {
                        Capsule().fill(paper).frame(width: 150, height: 44)
                        Capsule().fill(paper).frame(width: 220, height: 44)
                        Capsule().fill(paper).frame(width: 120, height: 44)
                    }
                    Circle().fill(paper).frame(width: 290, height: 290)
                }
                .offset(x: 10)
            case "ball":
                ZStack {
                    Circle().fill(ink).frame(width: 300, height: 300).offset(x: 80)
                    VStack(alignment: .trailing, spacing: 40) {
                        Capsule().fill(ink).frame(width: 140, height: 40)
                        Capsule().fill(ink).frame(width: 200, height: 40)
                        Capsule().fill(ink).frame(width: 110, height: 40)
                    }
                    .offset(x: -210)
                }
            case "pixel":
                PixelComet().frame(width: 700, height: 700)
            default: // comet
                Comet().fill(paper)
                    .frame(width: 600, height: 330)
                    .rotationEffect(.degrees(-18))
                    .offset(x: 10, y: 10)
            }
        }
        .frame(width: 1024, height: 1024)
    }
}

let out = CommandLine.arguments[1]
let size = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2])! : 1024
MainActor.assumeIsolated {
    let r = ImageRenderer(content: Icon())
    r.scale = size / 1024
    let rep = NSBitmapImageRep(data: r.nsImage!.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
}
