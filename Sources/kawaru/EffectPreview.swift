import CoreGraphics
import CoreImage
import Foundation

/// A small picture of what each effect does, for the gallery: a drawn room with a drawn figure in it, and the
/// effect's own artwork over them. Nothing from the camera is used, so the gallery never shows the user.
enum EffectPreview {
    static let size = CGSize(width: 640, height: 360)
    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let context = CIContext()
    private static var cache: [String: CGImage] = [:]

    private static func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xff) / 255, CGFloat((hex >> 8) & 0xff) / 255, CGFloat(hex & 0xff) / 255, a])!
    }

    /// The room with the figure in it and no effect: what the camera shows before.
    static var before: CGImage { cached("before") { ctx in room(ctx); figure(ctx, at: 320) } }

    /// The same room with the effect on. Redrawn when the words the effect shows change.
    static func after(_ effect: Effect) -> CGImage {
        let W = size.width, H = size.height
        switch effect {
        case .substitution:
            return cached("substitution") { ctx in
                room(ctx)
                let puff = Smoke.draw()
                for (x, y, s) in [(150, 60, 190), (410, 40, 210), (60, 190, 120), (500, 200, 130)] as [(CGFloat, CGFloat, CGFloat)] {
                    ctx.setAlpha(0.92); ctx.draw(puff, in: CGRect(x: x, y: y, width: s, height: s))
                }
                ctx.setAlpha(1)
                ctx.saveGState()
                ctx.translateBy(x: 330, y: 20); ctx.rotate(by: -0.16)
                ctx.draw(Trunk.draw(), in: CGRect(x: -80, y: 0, width: 160, height: 286))
                ctx.restoreGState()
                for (x, y, s) in [(215, 0, 150), (345, 10, 130)] as [(CGFloat, CGFloat, CGFloat)] { ctx.draw(puff, in: CGRect(x: x, y: y, width: s, height: s)) }
            }
        case .clones:
            return cached("clones") { ctx in
                room(ctx)
                figure(ctx, at: 90, alpha: 0.55, scale: 0.84); figure(ctx, at: 550, alpha: 0.55, scale: 0.84)
                figure(ctx, at: 195, alpha: 0.8, scale: 0.92); figure(ctx, at: 445, alpha: 0.8, scale: 0.92)
                figure(ctx, at: 320)
            }
        case .away:
            return cached("away|" + Wording.sign.joined(separator: "|")) { ctx in
                room(ctx); figure(ctx, at: 320); dim(ctx)
                let h = H * 0.92, w = h * Card.size.width / Card.size.height
                ctx.draw(Card.draw(Wording.sign), in: CGRect(x: (W - w) / 2, y: 6, width: w, height: h))
            }
        case .question:
            return cached("question|" + Wording.question.joined(separator: "|")) { ctx in
                room(ctx); figure(ctx, at: 220)
                let w: CGFloat = 270, h = w * Overlays.bubbleSize.height / Overlays.bubbleSize.width
                draw(Overlays.bubble(Wording.question), ctx, in: CGRect(x: 345, y: 170, width: w, height: h))
            }
        case .confetti:
            return cached("confetti|" + Wording.cheer) { ctx in
                room(ctx); figure(ctx, at: 320)
                draw(Overlays.confetti(Int(W) * 2, Int(H) * 2, t: 1.7, word: Wording.cheer), ctx, in: CGRect(origin: .zero, size: size))
            }
        case .breakTime:
            return cached("break|\(Wording.breakMinutes)") { ctx in
                room(ctx); figure(ctx, at: 320); dim(ctx)
                let total = Wording.breakTime
                draw(Overlays.breakCard(Int(W) * 2, Int(H) * 2, left: Int(total) - 18, of: total), ctx, in: CGRect(origin: .zero, size: size))
            }
        case .spotlight:
            return cached("spotlight") { ctx in
                room(ctx)
                ctx.setFillColor(color(0x8d8d8d)); ctx.setBlendMode(.saturation); ctx.fill(CGRect(origin: .zero, size: size))
                ctx.setBlendMode(.normal); ctx.setFillColor(color(0x000000, 0.45)); ctx.fill(CGRect(origin: .zero, size: size))
                figure(ctx, at: 320)
            }
        }
    }

    private static func cached(_ key: String, _ draw: (CGContext) -> Void) -> CGImage {
        if let image = cache[key] { return image }
        // Drawn at twice the size so it stays crisp on a Retina screen.
        let ctx = CGContext(data: nil, width: Int(size.width) * 2, height: Int(size.height) * 2, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: 2, y: 2)
        draw(ctx)
        let image = ctx.makeImage()!
        cache[key] = image
        return image
    }

    private static func draw(_ image: CIImage, _ ctx: CGContext, in rect: CGRect) {
        if let rendered = context.createCGImage(image, from: image.extent) { ctx.draw(rendered, in: rect) }
    }

    private static func dim(_ ctx: CGContext) {
        ctx.setFillColor(color(0x1c1a22, 0.62)); ctx.fill(CGRect(origin: .zero, size: size))
    }

    /// A home-office wall: a shelf with books, a framed picture, a plant.
    private static func room(_ ctx: CGContext) {
        let W = size.width, H = size.height
        ctx.setFillColor(color(0xdfe7ee)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.setFillColor(color(0xcdd8e2)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: 54))
        // Shelf and books.
        ctx.setFillColor(color(0xb98a56)); ctx.fill(CGRect(x: 40, y: 236, width: 190, height: 10))
        for (x, w, h, c) in [(54, 18, 62, 0xd9695a), (74, 14, 52, 0x5b8fd0), (90, 20, 68, 0xe8b84a), (112, 15, 56, 0x6fae7c), (150, 46, 22, 0x8d7bc4)] as [(CGFloat, CGFloat, CGFloat, UInt32)] {
            ctx.setFillColor(color(c)); ctx.fill(CGRect(x: x, y: 246, width: w, height: h))
        }
        // Picture.
        ctx.setFillColor(color(0xffffff)); ctx.fill(CGRect(x: 452, y: 210, width: 120, height: 92))
        ctx.setFillColor(color(0xf2c9a0)); ctx.fill(CGRect(x: 462, y: 220, width: 100, height: 72))
        ctx.setFillColor(color(0xe8935f)); ctx.fillEllipse(in: CGRect(x: 520, y: 252, width: 26, height: 26))
        ctx.setFillColor(color(0x7fae8a)); ctx.fill(CGRect(x: 462, y: 220, width: 100, height: 22))
        // Plant.
        ctx.setFillColor(color(0xc77b53)); ctx.fill(CGRect(x: 566, y: 54, width: 44, height: 40))
        ctx.setFillColor(color(0x5f9a5a))
        for (dx, tall, lean) in [(-14, 70, -22), (0, 96, 2), (14, 76, 24)] as [(CGFloat, CGFloat, CGFloat)] {
            let leaf = CGMutablePath()
            leaf.move(to: CGPoint(x: 588 + dx - 9, y: 92))
            leaf.addQuadCurve(to: CGPoint(x: 588 + dx + lean, y: 92 + tall), control: CGPoint(x: 588 + dx - 16, y: 92 + tall * 0.6))
            leaf.addQuadCurve(to: CGPoint(x: 588 + dx + 9, y: 92), control: CGPoint(x: 588 + dx + 18, y: 92 + tall * 0.5))
            ctx.addPath(leaf); ctx.fillPath()
        }
    }

    /// Head and shoulders, the way a webcam frames someone.
    private static func figure(_ ctx: CGContext, at x: CGFloat, alpha: CGFloat = 1, scale: CGFloat = 1) {
        ctx.saveGState()
        ctx.translateBy(x: x, y: 0); ctx.scaleBy(x: scale, y: scale); ctx.setAlpha(alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        let body = CGMutablePath()
        body.move(to: CGPoint(x: -118, y: 0)); body.addLine(to: CGPoint(x: -118, y: 62))
        body.addQuadCurve(to: CGPoint(x: -36, y: 150), control: CGPoint(x: -114, y: 140))
        body.addLine(to: CGPoint(x: 36, y: 150))
        body.addQuadCurve(to: CGPoint(x: 118, y: 62), control: CGPoint(x: 114, y: 140))
        body.addLine(to: CGPoint(x: 118, y: 0)); body.closeSubpath()
        ctx.addPath(body); ctx.setFillColor(color(0x4f7fc4)); ctx.fillPath()
        ctx.setFillColor(color(0xe9b98f)); ctx.fill(CGRect(x: -22, y: 136, width: 44, height: 40))
        ctx.fillEllipse(in: CGRect(x: -58, y: 150, width: 116, height: 134))
        // Hair, eyes, smile.
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: -58, y: 150, width: 116, height: 134)); ctx.clip()
        ctx.setFillColor(color(0x4a3426)); ctx.fill(CGRect(x: -60, y: 244, width: 120, height: 44))
        ctx.restoreGState()
        ctx.setFillColor(color(0x2b2118))
        ctx.fillEllipse(in: CGRect(x: -27, y: 212, width: 11, height: 13)); ctx.fillEllipse(in: CGRect(x: 16, y: 212, width: 11, height: 13))
        ctx.setStrokeColor(color(0x2b2118)); ctx.setLineWidth(4); ctx.setLineCap(.round)
        ctx.addArc(center: CGPoint(x: 0, y: 196), radius: 17, startAngle: .pi + 0.5, endAngle: -0.5, clockwise: false); ctx.strokePath()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
}
