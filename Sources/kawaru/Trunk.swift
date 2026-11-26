import CoreGraphics
import Foundation

/// The log that takes the person's place. Drawn in code so there is no asset to license or ship.
enum Trunk {
    static let size = CGSize(width: 560, height: 1000)

    static func draw() -> CGImage {
        let w = Int(size.width), h = Int(size.height)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
            CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xff) / 255, CGFloat((hex >> 8) & 0xff) / 255,
                                                    CGFloat(hex & 0xff) / 255, a])!
        }

        let left: CGFloat = 70, right: CGFloat = 450, top: CGFloat = 915
        let mid = (left + right) / 2, rx = (right - left) / 2, ry: CGFloat = 52

        // A stub of a branch with one leaf, behind the body.
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setStrokeColor(color(0x4f3319)); ctx.setLineWidth(46)
        ctx.move(to: CGPoint(x: right - 30, y: 560)); ctx.addLine(to: CGPoint(x: right + 44, y: 628)); ctx.strokePath()
        ctx.setStrokeColor(color(0x7a5028)); ctx.setLineWidth(30)
        ctx.move(to: CGPoint(x: right - 30, y: 564)); ctx.addLine(to: CGPoint(x: right + 42, y: 630)); ctx.strokePath()
        ctx.translateBy(x: right + 52, y: 650); ctx.rotate(by: -0.5)
        let leaf = CGMutablePath()
        leaf.move(to: .zero)
        leaf.addQuadCurve(to: CGPoint(x: 0, y: 92), control: CGPoint(x: 46, y: 46))
        leaf.addQuadCurve(to: .zero, control: CGPoint(x: -46, y: 46))
        ctx.addPath(leaf); ctx.setFillColor(color(0x5f9a3a)); ctx.fillPath()
        ctx.setStrokeColor(color(0x3d6b22)); ctx.setLineWidth(3)
        ctx.move(to: .zero); ctx.addLine(to: CGPoint(x: 0, y: 80)); ctx.strokePath()
        ctx.restoreGState()

        // Body: a cylinder, lit from the upper left.
        ctx.saveGState()
        ctx.clip(to: CGRect(x: left, y: 0, width: right - left, height: top))
        let shade = CGGradient(colorsSpace: space, colors: [color(0x4a2f17), color(0x80532a), color(0xa3703c), color(0x7c5028),
                                                           color(0x452b14)] as CFArray, locations: [0, 0.22, 0.4, 0.7, 1])!
        ctx.drawLinearGradient(shade, start: CGPoint(x: left, y: 0), end: CGPoint(x: right, y: 0), options: [])

        // Bark: wavy grooves, the same on every run.
        var seed: UInt64 = 0x6b617761
        func rnd() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) % 10_000) / 10_000
        }
        ctx.setLineCap(.round)
        for i in 0..<34 {
            let x = left + 10 + rnd() * (right - left - 20)
            var y = rnd() * top
            let length = 90 + rnd() * 260
            let light = i % 5 == 0
            ctx.setStrokeColor(light ? color(0xc08a50, 0.35) : color(0x2e1c0c, 0.55))
            ctx.setLineWidth(light ? 3 : 3 + rnd() * 5)
            ctx.move(to: CGPoint(x: x, y: y))
            var cx = x
            let end = y + length
            while y < end {
                let nx = cx + (rnd() - 0.5) * 16
                ctx.addQuadCurve(to: CGPoint(x: nx, y: y + 44), control: CGPoint(x: cx + (rnd() - 0.5) * 22, y: y + 22))
                cx = nx; y += 44
            }
            ctx.strokePath()
        }
        // A knot.
        ctx.setFillColor(color(0x2e1c0c, 0.8)); ctx.fillEllipse(in: CGRect(x: 150, y: 330, width: 64, height: 86))
        ctx.setFillColor(color(0x6b4522)); ctx.fillEllipse(in: CGRect(x: 162, y: 346, width: 40, height: 54))
        ctx.setFillColor(color(0x2e1c0c, 0.7)); ctx.fillEllipse(in: CGRect(x: 174, y: 362, width: 16, height: 22))
        // The shadow the cut casts on the bark right under it.
        let under = CGGradient(colorsSpace: space, colors: [color(0x000000, 0.35), color(0x000000, 0)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(under, start: CGPoint(x: 0, y: top - ry), end: CGPoint(x: 0, y: top - ry - 90), options: [])
        ctx.restoreGState()

        // The cut on top, with its rings.
        let cut = CGRect(x: left, y: top - ry, width: rx * 2, height: ry * 2)
        ctx.setFillColor(color(0x4a2f17)); ctx.fillEllipse(in: cut.insetBy(dx: 0, dy: -3))
        ctx.setFillColor(color(0xe6c088)); ctx.fillEllipse(in: cut.insetBy(dx: 12, dy: 4))
        ctx.setStrokeColor(color(0xb5864a)); ctx.setLineWidth(3)
        for k in 1...4 {
            let f = CGFloat(k) / 5
            ctx.strokeEllipse(in: CGRect(x: mid - (rx - 12) * f, y: top - (ry - 4) * f, width: (rx - 12) * 2 * f, height: (ry - 4) * 2 * f))
        }
        return ctx.makeImage()!
    }
}
