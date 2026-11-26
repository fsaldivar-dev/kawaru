// The camera other apps see as "Kawaru". A CoreMediaIO camera extension: macOS runs it in its own sandboxed
// process, and Meet, Zoom, FaceTime and the rest talk to it like to any camera.
//
// It does no image work. The Kawaru app captures the real camera, does the swap and pushes the finished frames
// into this device's sink stream; the extension hands each one on through its source stream. While the app is
// not sending, it shows a card saying so.

import CoreGraphics
import CoreMediaIO
import CoreText
import Foundation
import IOKit.audio
import os.log

// Keep in step with Sources/kawaru/VirtualCamera.swift.
let kawaruDeviceID = UUID(uuidString: "6B617761-7275-4B41-9A52-55C0FFEE0001")!
let kawaruSourceID = UUID(uuidString: "6B617761-7275-4B41-9A52-55C0FFEE0002")!
let kawaruSinkID = UUID(uuidString: "6B617761-7275-4B41-9A52-55C0FFEE0003")!
let frameWidth: Int32 = 1280, frameHeight: Int32 = 720, frameRate: Int32 = 30

let log = Logger(subsystem: "dev.kawaru.app.camera", category: "camera")

final class DeviceSource: NSObject, CMIOExtensionDeviceSource {
    private(set) var device: CMIOExtensionDevice!
    private var source: StreamSource!
    private var sink: SinkSource!
    private let format: CMFormatDescription

    private let queue = DispatchQueue(label: "dev.kawaru.camera.frames")
    private var timer: DispatchSourceTimer?
    private var watchers = 0            // apps reading the camera
    private var feeder: CMIOExtensionClient?
    private var feeding = false
    private var lastFed = 0.0
    private var card: CVPixelBuffer?
    private var received = 0, empty = 0, errors = 0, noImage = 0, lastError = 0, lastReport = 0.0

    override init() {
        var description: CMFormatDescription?
        CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: kCVPixelFormatType_32BGRA, width: frameWidth,
                                       height: frameHeight, extensions: nil, formatDescriptionOut: &description)
        format = description!
        super.init()
        device = CMIOExtensionDevice(localizedName: "Kawaru", deviceID: kawaruDeviceID, legacyDeviceID: nil, source: self)
        let duration = CMTime(value: 1, timescale: frameRate)
        let streamFormat = CMIOExtensionStreamFormat(formatDescription: format, maxFrameDuration: duration, minFrameDuration: duration,
                                                     validFrameDurations: nil)
        source = StreamSource(localizedName: "Kawaru", streamID: kawaruSourceID, format: streamFormat, device: self)
        sink = SinkSource(localizedName: "Kawaru (entrada)", streamID: kawaruSinkID, format: streamFormat, device: self)
        do {
            try device.addStream(source.stream)   // order matters: the app takes the second stream as the sink
            try device.addStream(sink.stream)
        } catch {
            fatalError("Kawaru: no se pudieron crear los flujos: \(error.localizedDescription)")
        }
        card = Self.drawCard()
    }

    /// How many apps are reading the camera, as text, for the Kawaru app: it only needs its own camera on while
    /// someone is looking. Keep the name in step with Sources/kawaru/VirtualCamera.swift.
    static let watchersProperty = CMIOExtensionProperty(rawValue: "4cc_kwch_glob_0000")
    private let watchersLock = NSLock()
    private var watchersNow = 0

    private func publish(_ count: Int) {
        watchersLock.lock(); watchersNow = count; watchersLock.unlock()
        device.notifyPropertiesChanged([Self.watchersProperty: CMIOExtensionPropertyState<AnyObject>(value: "\(count)" as NSString)])
    }

    var availableProperties: Set<CMIOExtensionProperty> { [.deviceTransportType, .deviceModel, Self.watchersProperty] }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let p = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) { p.transportType = kIOAudioDeviceTransportTypeVirtual }
        if properties.contains(.deviceModel) { p.model = "Kawaru" }
        if properties.contains(Self.watchersProperty) {
            watchersLock.lock(); let count = watchersNow; watchersLock.unlock()
            p.setPropertyState(CMIOExtensionPropertyState<AnyObject>(value: "\(count)" as NSString), forProperty: Self.watchersProperty)
        }
        return p
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    // MARK: Out, to the apps

    func startWatching() {
        queue.async {
            self.watchers += 1
            self.publish(self.watchers)
            log.info("source: \(self.watchers) app(s) viendo la cámara")
            guard self.timer == nil else { return }
            let t = DispatchSource.makeTimerSource(flags: .strict, queue: self.queue)
            t.schedule(deadline: .now(), repeating: 1.0 / Double(frameRate), leeway: .milliseconds(2))
            t.setEventHandler { [weak self] in self?.tick() }
            t.resume()
            self.timer = t
        }
    }

    func stopWatching() {
        queue.async {
            self.watchers = max(0, self.watchers - 1)
            self.publish(self.watchers)
            if self.watchers == 0 { self.timer?.cancel(); self.timer = nil }
        }
    }

    /// Thirty times a second: if the app has gone quiet, send the card so the picture never freezes on a stale frame.
    private func tick() {
        guard CACurrentMediaTimeCompat() - lastFed > 0.5, let card else { return }
        send(card)
    }

    private func send(_ buffer: CVPixelBuffer) {
        guard watchers > 0 else { return }
        var description: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &description)
        guard let description else { return }
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: frameRate), presentationTimeStamp: now, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescription: description,
                                                 sampleTiming: &timing, sampleBufferOut: &sample)
        guard let sample else { return }
        source.stream.send(sample, discontinuity: [], hostTimeInNanoseconds: UInt64(now.seconds * 1_000_000_000))
    }

    // MARK: In, from the Kawaru app

    func startFeeding(from client: CMIOExtensionClient) {
        queue.async {
            self.feeder = client
            self.feeding = true
            log.info("sink: empieza a recibir")
            self.pull()
        }
    }

    func stopFeeding() {
        queue.async { self.feeding = false; self.feeder = nil; log.info("sink: deja de recibir") }
    }

    private func pull() {
        guard feeding, let feeder else { return }
        sink.stream.consumeSampleBuffer(from: feeder) { [weak self] sample, sequence, _, _, error in
            guard let self else { return }
            self.queue.async {
                if let sample, let buffer = CMSampleBufferGetImageBuffer(sample) {
                    self.received += 1
                    self.lastFed = CACurrentMediaTimeCompat()
                    self.send(buffer)
                    let now = UInt64(CMClockGetTime(CMClockGetHostTimeClock()).seconds * 1_000_000_000)
                    self.sink.stream.notifyScheduledOutputChanged(CMIOExtensionScheduledOutput(sequenceNumber: sequence, hostTimeInNanoseconds: now))
                    self.pull()
                } else {
                    if let error { self.errors += 1; self.lastError = (error as NSError).code } else if sample != nil { self.noImage += 1 } else { self.empty += 1 }
                    // Nothing queued (or the app went away): look again shortly instead of spinning.
                    self.queue.asyncAfter(deadline: .now() + 0.005) { self.pull() }
                }
                let t = CACurrentMediaTimeCompat()
                if t - self.lastReport > 30 {
                    self.lastReport = t
                    log.info("sink: \(self.received) fotogramas, \(self.empty) vacíos, \(self.errors) errores (último \(self.lastError)), \(self.noImage) sin imagen, \(self.watchers) mirando")
                    self.received = 0; self.empty = 0; self.errors = 0; self.noImage = 0
                }
            }
        }
    }

    // MARK: The card

    private static func drawCard() -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
                                      kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true]
        CVPixelBufferCreate(kCFAllocatorDefault, Int(frameWidth), Int(frameHeight), kCVPixelFormatType_32BGRA, attrs as CFDictionary, &buffer)
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(frameWidth), height: Int(frameHeight),
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.setFillColor(CGColor(colorSpace: space, components: [0.09, 0.08, 0.07, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: Int(frameWidth), height: Int(frameHeight)))
        func line(_ text: String, size: CGFloat, weight: CGFloat, alpha: CGFloat, y: CGFloat) {
            let font = CTFontCreateUIFontForLanguage(weight > 0 ? .emphasizedSystem : .system, size, nil)!
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(colorSpace: space, components: [1, 1, 1, alpha])!,
            ]
            let l = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            let width = CTLineGetTypographicBounds(l, nil, nil, nil)
            ctx.textPosition = CGPoint(x: (CGFloat(frameWidth) - CGFloat(width)) / 2, y: y)
            CTLineDraw(l, ctx)
        }
        line("Kawaru", size: 64, weight: 1, alpha: 0.92, y: 372)
        line("Abre la app Kawaru para encender la cámara", size: 28, weight: 0, alpha: 0.6, y: 306)
        return buffer
    }
}

/// Seconds on a clock that keeps running; QuartzCore is not worth linking for one call.
func CACurrentMediaTimeCompat() -> Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

/// The stream apps read from.
final class StreamSource: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private let format: CMIOExtensionStreamFormat
    private unowned let device: DeviceSource

    init(localizedName: String, streamID: UUID, format: CMIOExtensionStreamFormat, device: DeviceSource) {
        self.format = format
        self.device = device
        super.init()
        stream = CMIOExtensionStream(localizedName: localizedName, streamID: streamID, direction: .source, clockType: .hostTime, source: self)
    }

    var formats: [CMIOExtensionStreamFormat] { [format] }
    var activeFormatIndex = 0
    var availableProperties: Set<CMIOExtensionProperty> { [.streamActiveFormatIndex, .streamFrameDuration] }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let p = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) { p.activeFormatIndex = 0 }
        if properties.contains(.streamFrameDuration) { p.frameDuration = CMTime(value: 1, timescale: frameRate) }
        return p
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}
    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool { true }
    func startStream() throws { device.startWatching() }
    func stopStream() throws { device.stopWatching() }
}

/// The stream the Kawaru app writes to.
final class SinkSource: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private let format: CMIOExtensionStreamFormat
    private unowned let device: DeviceSource
    private var client: CMIOExtensionClient?

    init(localizedName: String, streamID: UUID, format: CMIOExtensionStreamFormat, device: DeviceSource) {
        self.format = format
        self.device = device
        super.init()
        stream = CMIOExtensionStream(localizedName: localizedName, streamID: streamID, direction: .sink, clockType: .hostTime, source: self)
    }

    var formats: [CMIOExtensionStreamFormat] { [format] }
    var activeFormatIndex = 0
    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration, .streamSinkBufferQueueSize, .streamSinkBuffersRequiredForStartup,
         .streamSinkBufferUnderrunCount, .streamSinkEndOfData]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let p = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) { p.activeFormatIndex = 0 }
        if properties.contains(.streamFrameDuration) { p.frameDuration = CMTime(value: 1, timescale: frameRate) }
        if properties.contains(.streamSinkBufferQueueSize) { p.sinkBufferQueueSize = 1 }
        if properties.contains(.streamSinkBuffersRequiredForStartup) { p.sinkBuffersRequiredForStartup = 1 }
        if properties.contains(.streamSinkBufferUnderrunCount) { p.sinkBufferUnderrunCount = 0 }
        if properties.contains(.streamSinkEndOfData) { p.sinkEndOfData = 0 }
        return p
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        self.client = client
        return true
    }

    func startStream() throws {
        guard let client else { log.error("sink: arrancó sin cliente"); return }
        device.startFeeding(from: client)
    }

    func stopStream() throws { device.stopFeeding() }
}

final class ProviderSource: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    private var deviceSource: DeviceSource!

    override init() {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: nil)
        deviceSource = DeviceSource()
        do {
            try provider.addDevice(deviceSource.device)
        } catch {
            fatalError("Kawaru: no se pudo crear el dispositivo: \(error.localizedDescription)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {}
    func disconnect(from client: CMIOExtensionClient) {}

    var availableProperties: Set<CMIOExtensionProperty> { [.providerManufacturer] }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let p = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) { p.manufacturer = "Kawaru" }
        return p
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}

let providerSource = ProviderSource()
log.info("extensión en marcha")
CMIOExtensionProvider.startService(provider: providerSource.provider)
CFRunLoopRun()
