import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// The pictures the classroom filters put over the camera, all drawn in code: the speech bubble, the confetti
/// and the break timer.
enum Overlays {
    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    private static func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xff) / 255, CGFloat((hex >> 8) & 0xff) / 255, CGFloat(hex & 0xff) / 255, a])!
    }

    private static func canvas(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> CIImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(ctx)
        return CIImage(cgImage: ctx.makeImage()!)
    }

    /// Text centred on `x`, with its baseline at `y`.
    private static func text(_ ctx: CGContext, _ string: String, font name: String, size: CGFloat, color: CGColor, x: CGFloat, y: CGFloat,
                             fit: CGFloat = .infinity) {
        func set(_ size: CGFloat) -> (CTLine, CGFloat) {
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): lettering(name, size, for: string),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
            return (line, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
        }
        // Text wider than `fit` is set smaller, so the user's own words never run off the picture.
        var (line, width) = set(size)
        if width > fit { (line, width) = set(size * fit / width) }
        ctx.textPosition = CGPoint(x: x - width / 2, y: y)
        CTLineDraw(line, ctx)
    }

    // MARK: Speech bubble

    static let bubbleSize = CGSize(width: 820, height: 500)
    /// The tip of the bubble's tail, in the drawing: the point it grows from.
    static let bubbleTip = CGPoint(x: 410, y: 14)

    static func bubble(_ lines: [String]) -> CIImage {
        canvas(Int(bubbleSize.width), Int(bubbleSize.height)) { ctx in
            let ink = color(0x2b2118)
            let body = CGMutablePath()
            body.addRoundedRect(in: CGRect(x: 14, y: 96, width: 792, height: 390), cornerWidth: 70, cornerHeight: 70)
            let tail = CGMutablePath()
            tail.move(to: CGPoint(x: 330, y: 104)); tail.addLine(to: bubbleTip); tail.addLine(to: CGPoint(x: 480, y: 104)); tail.closeSubpath()
            for path in [tail, body] {
                ctx.addPath(path); ctx.setStrokeColor(ink); ctx.setLineWidth(18); ctx.setLineJoin(.round); ctx.strokePath()
            }
            for path in [tail, body] { ctx.addPath(path); ctx.setFillColor(color(0xfffdf6)); ctx.fillPath() }
            text(ctx, "✋", font: "AppleColorEmoji", size: 150, color: ink, x: 150, y: 232)
            var y: CGFloat = 318
            for line in lines {
                text(ctx, line, font: "MarkerFelt-Wide", size: 88, color: ink, x: 510, y: y, fit: 520)
                y -= 108
            }
        }
    }

    // MARK: Confetti

    static let confettiTime = 3.8

    /// One frame of the celebration, `t` seconds in: paper falling and a word that pops up.
    static func confetti(_ w: Int, _ h: Int, t: Double, word: String) -> CIImage {
        canvas(w, h) { ctx in
            let W = CGFloat(w), H = CGFloat(h), time = CGFloat(t)
            let fade = max(0, min(1, (CGFloat(confettiTime) - time) / 0.6))
            let palette: [UInt32] = [0xf94144, 0xf8961e, 0xf9c74f, 0x90be6d, 0x43aa8b, 0x4d90fe, 0x9b5de5, 0xff70a6]
            var seed: UInt64 = 0x636f6e66
            func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((seed >> 33) % 10_000) / 10_000 }
            for i in 0..<190 {
                let x0 = rnd() * W, delay = rnd() * 2.1, speed = 0.45 + rnd() * 0.5, sway = 20 + rnd() * 40, spin = (rnd() - 0.5) * 9, phase = rnd() * 6.28
                let size = 18 + rnd() * 18
                let life = time - delay
                guard life > 0 else { continue }
                let y = H * 1.05 - life * speed * H - 0.12 * life * life * H
                guard y > -30 else { continue }
                ctx.saveGState()
                ctx.translateBy(x: x0 + sin(life * 3 + phase) * sway, y: y)
                ctx.rotate(by: life * spin + phase)
                ctx.setFillColor(color(palette[i % palette.count], fade))
                // Seen edge-on now and then, the way falling paper turns.
                ctx.fill(CGRect(x: -size / 2, y: -size * 0.3 * abs(cos(life * 5 + phase)), width: size, height: size * 0.6 * abs(cos(life * 5 + phase)) + 2))
                ctx.restoreGState()
            }
            // The word: springs up past its size and settles.
            let p = min(1, time / 0.45)
            let pop = p < 1 ? 1 + 2.2 * (p - 1) * (p - 1) * (p - 1) + 1.2 * (p - 1) * (p - 1) : 1   // ease-out with overshoot
            let size = H * 0.2 * max(0.05, pop)
            for (dx, dy, c) in [(5, -6, color(0x2b2118, fade)), (0, 0, color(0xffffff, fade))] as [(CGFloat, CGFloat, CGColor)] {
                text(ctx, word, font: "MarkerFelt-Wide", size: size, color: c, x: W / 2 + dx, y: H * 0.68 + dy, fit: W * 0.86)
            }
        }
    }

    // MARK: Break

    static let backTime = 3.0

    /// The break card with `left` seconds to go; at zero it says the break is over.
    static func breakCard(_ w: Int, _ h: Int, left: Int, of total: Double) -> CIImage {
        canvas(w, h) { ctx in
            let W = CGFloat(w), H = CGFloat(h), white = color(0xffffff, 0.96)
            if left <= 0 {
                text(ctx, tr("¡Volvemos!"), font: "MarkerFelt-Wide", size: H * 0.2, color: white, x: W / 2, y: H * 0.43)
                return
            }
            text(ctx, tr("Descanso"), font: "MarkerFelt-Wide", size: H * 0.1, color: color(0xffffff, 0.8), x: W / 2, y: H * 0.7)
            text(ctx, String(format: "%d:%02d", left / 60, left % 60), font: "HelveticaNeue-Bold", size: H * 0.3, color: white, x: W / 2, y: H * 0.36)
            // How much of the break is left, as a bar.
            let bar = CGRect(x: W * 0.3, y: H * 0.24, width: W * 0.4, height: 10)
            ctx.setFillColor(color(0xffffff, 0.25)); ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 5, cornerHeight: 5, transform: nil)); ctx.fillPath()
            let part = CGRect(x: bar.minX, y: bar.minY, width: max(10, bar.width * min(1, CGFloat(left) / CGFloat(total))), height: bar.height)
            ctx.setFillColor(white); ctx.addPath(CGPath(roundedRect: part, cornerWidth: 5, cornerHeight: 5, transform: nil)); ctx.fillPath()
        }
    }
}
