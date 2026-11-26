import CoreImage
import SwiftUI

/// The hand as Kawaru reads it: a dot on every joint and a line along every finger. Shown over the picture
/// while recording or practising, and drawn into the photo kept of a recorded position.
enum HandMarks {
    /// Joint indices along each finger, starting from the wrist (see `HandShape.joints`).
    static let fingers: [[Int]] = (0..<5).map { f in [0] + (1...4).map { $0 + f * 4 } }

    /// The marks as a picture the size of the camera frame, for the saved photo. Nil when there are no hands.
    static func image(_ hands: [[CGPoint?]], size: CGSize) -> CIImage? {
        guard !hands.isEmpty else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let unit = size.width / 320
        func at(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }
        for hand in hands {
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9)); ctx.setLineWidth(unit); ctx.setLineCap(.round); ctx.setLineJoin(.round)
            for finger in fingers {
                let known = finger.compactMap { hand[$0] }.map(at)
                guard known.count > 1 else { continue }
                ctx.addLines(between: known); ctx.strokePath()
            }
            for point in hand.compactMap({ $0 }).map(at) {
                ctx.setFillColor(CGColor(red: 0.2, green: 0.85, blue: 0.45, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: point.x - unit * 1.6, y: point.y - unit * 1.6, width: unit * 3.2, height: unit * 3.2))
                ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.setLineWidth(unit * 0.5)
                ctx.strokeEllipse(in: CGRect(x: point.x - unit * 1.6, y: point.y - unit * 1.6, width: unit * 3.2, height: unit * 3.2))
            }
        }
        return ctx.makeImage().map { CIImage(cgImage: $0) }
    }
}

/// The same marks drawn live over the preview.
struct HandMarksView: View {
    let hands: [[CGPoint?]]
    let mirrored: Bool

    var body: some View {
        Canvas { context, size in
            func at(_ p: CGPoint) -> CGPoint { CGPoint(x: (mirrored ? 1 - p.x : p.x) * size.width, y: (1 - p.y) * size.height) }
            let unit = max(1.5, size.width / 320)
            for hand in hands {
                for finger in HandMarks.fingers {
                    let known = finger.compactMap { hand[$0] }.map(at)
                    guard known.count > 1 else { continue }
                    var path = Path(); path.addLines(known)
                    context.stroke(path, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: unit, lineCap: .round, lineJoin: .round))
                }
                for point in hand.compactMap({ $0 }).map(at) {
                    let dot = Path(ellipseIn: CGRect(x: point.x - unit * 1.6, y: point.y - unit * 1.6, width: unit * 3.2, height: unit * 3.2))
                    context.fill(dot, with: .color(Color(red: 0.2, green: 0.85, blue: 0.45)))
                    context.stroke(dot, with: .color(.white), lineWidth: unit * 0.5)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
