import CoreGraphics

/// One cartoon cloud, white with a soft grey rim. The compositor scatters copies of it.
enum Smoke {
    static let size: CGFloat = 512

    static func draw() -> CGImage {
        let n = Int(size)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: size / 256, y: size / 256)   // the lobes below are laid out on a 256 grid
        // Lobes: centre x, centre y, radius.
        let lobes: [(CGFloat, CGFloat, CGFloat)] = [(128, 122, 62), (84, 104, 44), (174, 108, 46), (106, 160, 42), (158, 158, 40),
                                                    (62, 142, 28), (196, 146, 26), (132, 76, 40)]
        func fill(_ grow: CGFloat, _ color: [CGFloat], dx: CGFloat = 0, dy: CGFloat = 0) {
            ctx.setFillColor(CGColor(colorSpace: space, components: color)!)
            for (x, y, r) in lobes { ctx.fillEllipse(in: CGRect(x: x + dx - r - grow, y: y + dy - r - grow, width: (r + grow) * 2, height: (r + grow) * 2)) }
        }
        fill(5, [0.62, 0.66, 0.72, 1])           // rim
        fill(0, [0.86, 0.89, 0.93, 1])           // shaded underside
        fill(-5, [1, 1, 1, 1], dx: -3, dy: 7)    // lit top
        return ctx.makeImage()!
    }
}
