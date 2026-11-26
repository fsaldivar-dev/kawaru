// Makes the gallery's preview pictures: runs a still "webcam frame" of a model through the app's own
// compositor, with Vision's real person mask, exactly as a live frame would go, and saves what comes out.
// Built and run by scripts/previews.sh. Usage: previews <fondo.png> <output folder> <persona.png> [more people...]
// With several people in the same room, the effects take turns between them.
import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

let W = 1280, H = 720
let extent = CGRect(x: 0, y: 0, width: W, height: H)
let context = CIContext()

func load(_ path: String) -> CVPixelBuffer {
    guard let image = CIImage(contentsOf: URL(fileURLWithPath: path)) else { fatalError("no se pudo leer \(path)") }
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(nil, W, H, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
    // Tagged the way a camera frame is (Rec. 709), so colour goes through the compositor as it does live.
    CVBufferSetAttachment(buffer!, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
    CVBufferSetAttachment(buffer!, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
    CVBufferSetAttachment(buffer!, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
    let fitted = image.transformed(by: CGAffineTransform(scaleX: CGFloat(W) / image.extent.width, y: CGFloat(H) / image.extent.height))
    context.render(fitted, to: buffer!, bounds: extent, colorSpace: CGColorSpace(name: CGColorSpace.itur_709))
    return buffer!
}

/// The same request the app makes for every frame.
func mask(of frame: CVPixelBuffer) -> CVPixelBuffer {
    let request = VNGeneratePersonSegmentationRequest()
    request.qualityLevel = .balanced
    request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    try! VNImageRequestHandler(cvPixelBuffer: frame).perform([request])
    return request.results!.first!.pixelBuffer
}

func save(_ buffer: CVPixelBuffer, _ path: String) {
    let image = context.createCGImage(CIImage(cvPixelBuffer: buffer), from: extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))!
    let out = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(out, image, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
    CGImageDestinationFinalize(out)
}

let arguments = CommandLine.arguments
guard arguments.count >= 4 else { print("uso: previews <fondo> <carpeta> <persona> [persona...]"); exit(2) }
let room = load(arguments[1]), folder = arguments[2]
let roomMask = mask(of: room)
let people = arguments[3...].map { path -> (frame: CVPixelBuffer, mask: CVPixelBuffer) in let frame = load(path); return (frame, mask(of: frame)) }

/// A short film of the effect being switched on and off again, for the gallery to loop.
final class Film {
    private let writer: AVAssetWriter, input: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var count: Int64 = 0

    init(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
        writer = try! AVAssetWriter(outputURL: URL(fileURLWithPath: path), fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 960, AVVideoHeightKey: 540,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1_400_000],
        ])
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
    }

    func add(_ frame: CVPixelBuffer) {
        while !input.isReadyForMoreMediaData { usleep(2000) }
        adaptor.append(frame, withPresentationTime: CMTime(value: count, timescale: 30))
        count += 1
    }

    func finish() {
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
    }
}

// Each effect: how long it stays on and how long the picture is shown after it is switched off, in frames at
// 30 a second, and the frame that makes the best still for the card.
let shots: [(name: String, look: Look, on: Int, after: Int, still: Int)] = [
    ("substitution", .trunk, 105, 30, 40),   // the smoke thinning, the log about to fall
    ("clones", .clones, 120, 30, 95),
    ("away", .away, 80, 30, 45), ("question", .question, 80, 25, 45), ("confetti", .confetti, 118, 12, 48),
    ("breakTime", .breakTime, 75, 25, 45), ("spotlight", .spotlight, 75, 25, 45),
]
for (index, shot) in shots.enumerated() {
    let person = people[index % people.count].frame, personMask = people[index % people.count].mask
    let compositor = Compositor()
    var now = 1000.0
    func step(_ frame: CVPixelBuffer, _ mask: CVPixelBuffer, _ look: Look, capture: Bool = false) -> CVPixelBuffer {
        now += 1.0 / 30
        return compositor.render(frame: frame, mask: mask, look: look, resetPlate: capture, now: now)
    }
    // As a user would: photograph the empty room, sit down, then start the effect.
    _ = step(room, roomMask, .person, capture: true)
    for _ in 0..<8 { _ = step(room, roomMask, .person) }
    for _ in 0..<20 { _ = step(person, personMask, .person) }
    let film = Film(folder + "/" + shot.name + ".mp4")
    for _ in 0..<18 { film.add(step(person, personMask, .person)) }
    for i in 1...shot.on {
        let out = step(person, personMask, shot.look)
        film.add(out)
        if i == shot.still { save(out, folder + "/" + shot.name + ".jpg") }
    }
    for _ in 0..<shot.after { film.add(step(person, personMask, .person)) }
    film.finish()
    print("hecho:", shot.name)
}
