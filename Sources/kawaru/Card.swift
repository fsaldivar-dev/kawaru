import CoreGraphics
import CoreText
import Foundation

/// The sign shown while away: a wooden board on a post, planted in a tuft of grass, with the message and a
/// dog that has found a hydrant. Drawn in code, like the log, so there is no artwork to license or ship.
enum Card {
    static let size = CGSize(width: 1000, height: 900)
    /// Where the post meets the ground, in the drawing: the point the sign swings about.
    static let foot = CGPoint(x: 500, y: 40)

    static func draw(_ lines: [String]) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
            CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xff) / 255, CGFloat((hex >> 8) & 0xff) / 255, CGFloat(hex & 0xff) / 255, a])!
        }
        let ink = color(0x2b2118)
        func shape(_ path: CGPath, fill: CGColor, line: CGFloat = 6) {
            ctx.addPath(path); ctx.setFillColor(fill); ctx.fillPath()
            if line > 0 { ctx.addPath(path); ctx.setStrokeColor(ink); ctx.setLineWidth(line); ctx.setLineJoin(.round); ctx.strokePath() }
        }
        func rounded(_ r: CGRect, _ c: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: c, cornerHeight: c, transform: nil) }

        // Ground.
        shape(CGPath(ellipseIn: CGRect(x: 300, y: 4, width: 400, height: 84), transform: nil), fill: color(0x7e8e2e))
        shape(CGPath(ellipseIn: CGRect(x: 300, y: 22, width: 400, height: 78), transform: nil), fill: color(0xb4c233))

        // Post.
        shape(rounded(CGRect(x: 462, y: 56, width: 76, height: 800), 10), fill: color(0xe9c28a))
        ctx.setFillColor(color(0xd19a4a)); ctx.fill(CGRect(x: 520, y: 62, width: 12, height: 788))

        // Grass around the foot of the post.
        for (x, lean, tall) in [(400, -26, 96), (432, -12, 130), (470, -4, 104), (530, 6, 120), (566, 16, 138), (600, 30, 92)] as [(CGFloat, CGFloat, CGFloat)] {
            let blade = CGMutablePath()
            blade.move(to: CGPoint(x: x - 15, y: 58))
            blade.addQuadCurve(to: CGPoint(x: x + lean, y: 58 + tall), control: CGPoint(x: x - 12, y: 58 + tall * 0.6))
            blade.addQuadCurve(to: CGPoint(x: x + 15, y: 58), control: CGPoint(x: x + 14, y: 58 + tall * 0.5))
            blade.closeSubpath()
            shape(blade, fill: color(0x8fa02f), line: 5)
        }

        // Board: two planks, a little uneven.
        let board = CGMutablePath()
        board.move(to: CGPoint(x: 52, y: 372)); board.addLine(to: CGPoint(x: 946, y: 364)); board.addLine(to: CGPoint(x: 954, y: 560))
        board.addLine(to: CGPoint(x: 938, y: 574)); board.addLine(to: CGPoint(x: 956, y: 590)); board.addLine(to: CGPoint(x: 948, y: 792))
        board.addLine(to: CGPoint(x: 58, y: 800)); board.addLine(to: CGPoint(x: 46, y: 596)); board.addLine(to: CGPoint(x: 62, y: 580))
        board.addLine(to: CGPoint(x: 44, y: 566)); board.closeSubpath()
        ctx.saveGState(); ctx.translateBy(x: 0, y: -14); shape(board, fill: color(0xc98a36), line: 0); ctx.restoreGState()
        shape(board, fill: color(0xecc48e))
        ctx.setStrokeColor(color(0xd7a55e)); ctx.setLineWidth(5); ctx.setLineCap(.round)
        for (x0, x1, y) in [(90, 300, 760), (360, 560, 742), (640, 900, 764), (100, 220, 420), (300, 520, 404), (700, 880, 412), (62, 938, 577)] as [(CGFloat, CGFloat, CGFloat)] {
            ctx.move(to: CGPoint(x: x0, y: y)); ctx.addLine(to: CGPoint(x: x1, y: y + 4)); ctx.strokePath()
        }
        // Nails.
        for p in [CGPoint(x: 500, y: 740)] { shape(CGPath(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18), transform: nil), fill: color(0x8a8f99), line: 4) }

        // Message, hand-lettered and climbing a little.
        ctx.saveGState()
        ctx.translateBy(x: 96, y: 610); ctx.rotate(by: 0.09)
        var y: CGFloat = 0
        for (i, text) in lines.enumerated() {
            // The first line has the whole board; the second stops short of the dog. Longer text is lettered smaller.
            let room: CGFloat = i == 0 ? 790 : 400
            func line(_ size: CGFloat) -> CTLine {
                let attributes: [NSAttributedString.Key: Any] = [
                    NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("MarkerFelt-Wide" as CFString, size, nil),
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink,
                ]
                return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            }
            let width = CGFloat(CTLineGetTypographicBounds(line(96), nil, nil, nil))
            ctx.textPosition = CGPoint(x: CGFloat(i) * 34, y: y)
            CTLineDraw(line(width > room ? 96 * room / width : 96), ctx)
            y -= 112
        }
        ctx.restoreGState()

        // Hydrant.
        let red = color(0xd8412b), yellow = color(0xd8e02c)
        shape(rounded(CGRect(x: 772, y: 392, width: 116, height: 24), 8), fill: red)
        shape(rounded(CGRect(x: 730, y: 500, width: 40, height: 44), 6), fill: yellow)
        shape(rounded(CGRect(x: 890, y: 500, width: 40, height: 44), 6), fill: yellow)
        shape(rounded(CGRect(x: 790, y: 410, width: 80, height: 196), 8), fill: red)
        let cap = CGMutablePath()
        cap.move(to: CGPoint(x: 770, y: 604)); cap.addLine(to: CGPoint(x: 890, y: 604)); cap.addLine(to: CGPoint(x: 866, y: 640)); cap.addLine(to: CGPoint(x: 794, y: 640)); cap.closeSubpath()
        shape(cap, fill: yellow)
        shape(rounded(CGRect(x: 818, y: 638, width: 24, height: 20), 4), fill: color(0x9aa0aa), line: 5)
        shape(CGPath(ellipseIn: CGRect(x: 802, y: 494, width: 56, height: 56), transform: nil), fill: yellow)

        // What the dog is doing about it.
        ctx.setStrokeColor(yellow); ctx.setLineWidth(7); ctx.setLineDash(phase: 0, lengths: [16, 12])
        ctx.move(to: CGPoint(x: 742, y: 470)); ctx.addQuadCurve(to: CGPoint(x: 792, y: 408), control: CGPoint(x: 788, y: 474)); ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
        shape(CGPath(ellipseIn: CGRect(x: 752, y: 378, width: 110, height: 26), transform: nil), fill: yellow, line: 4)

        // Dog, nose down.
        let grey = color(0xb7bac8)
        func leg(_ x: CGFloat) { shape(rounded(CGRect(x: x, y: 388, width: 26, height: 78), 12), fill: grey) }
        leg(596); leg(690)                                             // far side
        let tail = CGMutablePath(); tail.move(to: CGPoint(x: 722, y: 512)); tail.addQuadCurve(to: CGPoint(x: 752, y: 572), control: CGPoint(x: 760, y: 528))
        ctx.addPath(tail); ctx.setStrokeColor(ink); ctx.setLineWidth(20); ctx.setLineCap(.round); ctx.strokePath()
        ctx.addPath(tail); ctx.setStrokeColor(grey); ctx.setLineWidth(9); ctx.strokePath()
        // The leg in the air.
        ctx.saveGState(); ctx.translateBy(x: 716, y: 470); ctx.rotate(by: -0.95)
        shape(rounded(CGRect(x: -13, y: -8, width: 26, height: 66), 12), fill: grey)
        ctx.restoreGState()
        shape(CGPath(ellipseIn: CGRect(x: 574, y: 440, width: 170, height: 92), transform: nil), fill: grey)   // body
        leg(622)                                                       // near front leg
        shape(CGPath(ellipseIn: CGRect(x: 520, y: 404, width: 104, height: 92), transform: nil), fill: grey)   // head
        ctx.saveGState(); ctx.translateBy(x: 596, y: 470); ctx.rotate(by: 0.5)
        shape(CGPath(ellipseIn: CGRect(x: -17, y: -40, width: 34, height: 66), transform: nil), fill: color(0x8c90a2))   // ear
        ctx.restoreGState()
        shape(CGPath(ellipseIn: CGRect(x: 514, y: 420, width: 26, height: 22), transform: nil), fill: ink, line: 0)      // nose
        ctx.setStrokeColor(ink); ctx.setLineWidth(5)
        ctx.addArc(center: CGPoint(x: 560, y: 462), radius: 9, startAngle: 0.2, endAngle: .pi - 0.2, clockwise: true); ctx.strokePath()   // eye, closed in bliss
        return ctx.makeImage()!
    }
}
