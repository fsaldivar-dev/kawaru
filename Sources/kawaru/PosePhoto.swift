import AppKit
import CoreImage

/// The picture taken of the user while they record a hand position, so they can look up later what the
/// position was. Kept on this Mac only, in the app's own folder, and replaced when the position is recorded again.
enum PosePhoto {
    private static let context = CIContext()

    private static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Kawaru/poses", isDirectory: true)
    }

    private static func file(_ effect: Effect) -> URL { folder.appendingPathComponent(effect.rawValue + ".jpg") }

    /// A small JPEG of the camera frame, flipped the way the user saw themselves in the preview.
    static func encode(_ frame: CVPixelBuffer) -> Data? {
        let image = CIImage(cvPixelBuffer: frame)
        let scale = 640 / image.extent.width
        let small = image.transformed(by: CGAffineTransform(scaleX: -scale, y: scale))
        let placed = small.transformed(by: CGAffineTransform(translationX: -small.extent.minX, y: -small.extent.minY))
        return context.jpegRepresentation(of: placed, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.8])
    }

    static func save(_ data: Data, for effect: Effect) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: file(effect), options: .atomic)
    }

    static func load(_ effect: Effect) -> NSImage? { NSImage(contentsOf: file(effect)) }

    static func delete(_ effect: Effect) { try? FileManager.default.removeItem(at: file(effect)) }
}
