// Menu bar icon: the pixel comet as a 1-bit template image (18 pt; @1x and @2x).
// `swift scripts/menubar_icon.swift <out-dir>`
import AppKit

struct Comet {
    static func path(in r: CGRect) -> CGPath {
        let p = CGMutablePath()
        let R = r.height / 2, cx = r.maxX - R, cy = r.midY
        p.addArc(center: CGPoint(x: cx, y: cy), radius: R, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
        p.addCurve(to: CGPoint(x: r.minX, y: cy - R * 0.05), control1: CGPoint(x: cx - R * 0.9, y: cy + R), control2: CGPoint(x: r.minX + r.width * 0.25, y: cy + R * 0.2))
        p.addCurve(to: CGPoint(x: cx, y: cy - R), control1: CGPoint(x: r.minX + r.width * 0.3, y: cy - R * 0.45), control2: CGPoint(x: cx - R * 0.9, y: cy - R))
        p.closeSubpath()
        return p
    }
}

/// Rasterize at `grid` pixels with Bayer-dithered tail, return on/off cells.
func cells(grid n: Int) -> [[Bool]] {
    let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.setFillColor(gray: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: n, height: n))
    ctx.translateBy(x: 0, y: CGFloat(n)); ctx.scaleBy(x: 1, y: -1)
    ctx.translateBy(x: CGFloat(n) / 2, y: CGFloat(n) / 2); ctx.rotate(by: -18 * .pi / 180)
    let w = CGFloat(n) * 1.3, h = w * 0.56
    ctx.addPath(Comet.path(in: CGRect(x: -w / 2 - CGFloat(n) * 0.12, y: -h / 2, width: w, height: h))); ctx.setFillColor(gray: 1, alpha: 1); ctx.fillPath()
    let px = ctx.data!.bindMemory(to: UInt8.self, capacity: n * n)
    let bayer: [[Double]] = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
    return (0..<n).map { y in (0..<n).map { x in
        let fade = min(1, max(0.2, (Double(x) - Double(n) * 0.1) / (Double(n) * 0.45)))
        return Double(px[y * n + x]) / 255 * fade > (bayer[y % 4][x % 4] + 0.5) / 16
    } }
}

func write(_ name: String, grid: Int, scale: Int) {
    let c = cells(grid: grid), size = grid * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    for y in 0..<size { for x in 0..<size {
        rep.setColor(c[y / scale][x / scale] ? NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1) : NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0), atX: x, y: y)
    } }
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1] + "/" + name))
}
// 18 pt template: a 18-cell grid at @1x, the same grid doubled at @2x (crisp, pixel-art look).
write("MenuBarIcon.png", grid: 18, scale: 1)
write("MenuBarIcon@2x.png", grid: 18, scale: 2)
print("ok")
