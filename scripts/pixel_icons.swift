// 1-bit, 32×32 desktop icons in the spirit of the original Macintosh.
// Drawn with anti-aliasing OFF, then exported pixel-by-pixel as crisp SVG.
// `swift scripts/pixel_icons.swift <out-dir>`
import AppKit

let N = 32
func icon(_ name: String, _ draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: N, height: N, bitsPerComponent: 8, bytesPerRow: N * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setShouldAntialias(false); ctx.setAllowsAntialiasing(false)
    ctx.translateBy(x: 0, y: CGFloat(N)); ctx.scaleBy(x: 1, y: -1)   // top-left origin
    ctx.setLineWidth(2); ctx.setLineCap(.square); ctx.setLineJoin(.miter)
    draw(ctx)
    let px = ctx.data!.bindMemory(to: UInt8.self, capacity: N * N * 4)
    var rects = ""
    for y in 0..<N {
        var x = 0
        while x < N {
            let i = (y * N + x) * 4
            let a = px[i + 3], v = px[i]
            if a > 128 {
                let black = v < 128
                var run = 1
                while x + run < N {
                    let j = (y * N + x + run) * 4
                    if px[j + 3] > 128 && (px[j] < 128) == black { run += 1 } else { break }
                }
                rects += "<rect x=\"\(x)\" y=\"\(y)\" width=\"\(run)\" height=\"1\" fill=\"\(black ? "#111" : "#fff")\"/>"
                x += run
            } else { x += 1 }
        }
    }
    let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 32 32\" shape-rendering=\"crispEdges\">\(rects)</svg>"
    try! svg.write(toFile: CommandLine.arguments[1] + "/\(name).svg", atomically: true, encoding: .utf8)
}
let black = CGColor(gray: 0.05, alpha: 1), white = CGColor(gray: 1, alpha: 1)
func fillStroke(_ c: CGContext, _ p: CGPath) { c.addPath(p); c.setFillColor(white); c.fillPath(); c.addPath(p); c.setStrokeColor(black); c.strokePath() }
func line(_ c: CGContext, _ pts: [(CGFloat, CGFloat)]) { c.move(to: CGPoint(x: pts[0].0, y: pts[0].1)); for p in pts.dropFirst() { c.addLine(to: CGPoint(x: p.0, y: p.1)) }; c.setStrokeColor(black); c.strokePath() }
func dither(_ c: CGContext, _ r: CGRect) { c.setFillColor(black); for y in Int(r.minY)..<Int(r.maxY) { for x in Int(r.minX)..<Int(r.maxX) where (x + y) % 2 == 0 { c.fill(CGRect(x: x, y: y, width: 1, height: 1)) } } }

// Spitball: a lumpy crumpled ball with fold lines and a speed streak.
icon("spitball") { c in
    let p = CGMutablePath()
    let pts: [(CGFloat, CGFloat)] = [(16,4),(22,5),(27,10),(28,16),(26,23),(20,28),(13,28),(7,24),(4,17),(6,10),(10,6)]
    p.move(to: CGPoint(x: pts[0].0, y: pts[0].1)); for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0, y: q.1)) }; p.closeSubpath()
    fillStroke(c, p)
    c.setLineWidth(1)
    line(c, [(10,11),(16,14),(22,10)]); line(c, [(16,14),(15,21),(22,23)]); line(c, [(15,21),(9,19)])
    dither(c, CGRect(x: 20, y: 16, width: 6, height: 6))
}
// Read me: a document with a folded corner and text lines.
icon("readme") { c in
    let p = CGMutablePath(); p.move(to: CGPoint(x: 7, y: 3)); p.addLine(to: CGPoint(x: 20, y: 3)); p.addLine(to: CGPoint(x: 26, y: 9))
    p.addLine(to: CGPoint(x: 26, y: 29)); p.addLine(to: CGPoint(x: 7, y: 29)); p.closeSubpath(); fillStroke(c, p)
    c.setLineWidth(1); line(c, [(20,3),(20,9),(26,9)])
    for y in stride(from: 13, through: 25, by: 3) { line(c, [(10, CGFloat(y)), (y == 25 ? 17 : 23, CGFloat(y))]) }
}
// ID card with a photo square and a dithered stripe.
icon("idcard") { c in
    fillStroke(c, CGPath(rect: CGRect(x: 3, y: 8, width: 26, height: 17), transform: nil))
    dither(c, CGRect(x: 4, y: 9, width: 25, height: 4))
    fillStroke(c, CGPath(rect: CGRect(x: 6, y: 15, width: 7, height: 7), transform: nil))
    c.setLineWidth(1); line(c, [(16,16),(26,16)]); line(c, [(16,19),(24,19)]); line(c, [(16,22),(22,22)])
}
// Trophy.
icon("trophy") { c in
    let cup = CGMutablePath(); cup.move(to: CGPoint(x: 9, y: 4)); cup.addLine(to: CGPoint(x: 23, y: 4)); cup.addLine(to: CGPoint(x: 23, y: 11))
    cup.addQuadCurve(to: CGPoint(x: 9, y: 11), control: CGPoint(x: 16, y: 21)); cup.closeSubpath(); fillStroke(c, cup)
    line(c, [(9,6),(5,6),(5,9),(9,12)]); line(c, [(23,6),(27,6),(27,9),(23,12)])
    line(c, [(16,17),(16,23)]); fillStroke(c, CGPath(rect: CGRect(x: 10, y: 23, width: 12, height: 5), transform: nil))
    dither(c, CGRect(x: 11, y: 5, width: 4, height: 6))
}
// Floppy disk (install).
icon("floppy") { c in
    let p = CGMutablePath(); p.move(to: CGPoint(x: 4, y: 4)); p.addLine(to: CGPoint(x: 25, y: 4)); p.addLine(to: CGPoint(x: 28, y: 7))
    p.addLine(to: CGPoint(x: 28, y: 28)); p.addLine(to: CGPoint(x: 4, y: 28)); p.closeSubpath(); fillStroke(c, p)
    c.setFillColor(black); c.fill(CGRect(x: 9, y: 4, width: 13, height: 8)); c.setFillColor(white); c.fill(CGRect(x: 17, y: 5, width: 3, height: 6))
    fillStroke(c, CGPath(rect: CGRect(x: 8, y: 17, width: 16, height: 11), transform: nil))
    c.setLineWidth(1); line(c, [(11,21),(21,21)]); line(c, [(11,24),(19,24)])
}
// Compare: a balance scale.
icon("scale") { c in
    line(c, [(16,4),(16,26)]); line(c, [(5,9),(27,9)])
    c.setLineWidth(1); line(c, [(5,9),(3,18)]); line(c, [(5,9),(8,18)]); line(c, [(27,9),(24,18)]); line(c, [(27,9),(30,18)])
    c.setLineWidth(2)
    fillStroke(c, CGPath(rect: CGRect(x: 2, y: 18, width: 7, height: 3), transform: nil)); fillStroke(c, CGPath(rect: CGRect(x: 23, y: 18, width: 8, height: 3), transform: nil))
    fillStroke(c, CGPath(rect: CGRect(x: 10, y: 26, width: 12, height: 3), transform: nil))
}
// Star (GitHub).
icon("star") { c in
    let p = CGMutablePath()
    for i in 0..<10 { let a = Double(i) * .pi / 5 - .pi / 2; let r: Double = i % 2 == 0 ? 13 : 5.5
        let pt = CGPoint(x: 16 + cos(a) * r, y: 17 + sin(a) * r); i == 0 ? p.move(to: pt) : p.addLine(to: pt) }
    p.closeSubpath(); fillStroke(c, p); dither(c, CGRect(x: 13, y: 15, width: 6, height: 5))
}
print("ok")
