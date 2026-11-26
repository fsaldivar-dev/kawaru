import Combine
import CoreMediaIO
import Foundation
import AppKit
import SystemExtensions

/// The app's side of the virtual camera: asks macOS to install the camera extension that lives inside the app,
/// then finds the "Kawaru" device it publishes and pushes every finished frame into its sink stream.
final class VirtualCamera: NSObject, ObservableObject, OSSystemExtensionRequestDelegate {
    enum State: Equatable {
        case unavailable(String)   // this copy of the app cannot install it (why)
        case notInstalled
        case installing
        case needsApproval
        case ready                 // installed, frames are flowing into it
        case failed(String)
    }

    @Published private(set) var state = State.notInstalled

    // Keep in step with Sources/kawaru-camera/main.swift.
    private static let deviceUID = "6B617761-7275-4B41-9A52-55C0FFEE0001"
    private static let extensionID = "dev.kawaru.app.camera"

    private let lock = NSLock()
    private var device: CMIOObjectID = 0
    private var sink: CMIOStreamID = 0
    private var bufferQueue: CMSimpleQueue?
    private var search: Timer?
    private var replacing = false
    private var attempts = 0
    private var sent = 0, dropped = 0, lastReport = 0.0
    private var checkingForUpdate = false

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        let bundle = Bundle.main
        let inside = bundle.bundleURL.appendingPathComponent("Contents/Library/SystemExtensions/\(Self.extensionID).systemextension")
        if !FileManager.default.fileExists(atPath: inside.path) {
            state = .unavailable(tr("Esta copia de Kawaru se armó sin la extensión de cámara."))
        } else if !bundle.bundlePath.hasPrefix("/Applications/") {
            state = .unavailable(tr("macOS solo instala extensiones de cámara desde la carpeta Aplicaciones. Instala con scripts/build.sh --install."))
        }
        // The extension may already be there from an earlier run. If so, before touching it, hand macOS the copy
        // inside this app so a newer one replaces it; the same version is cancelled in the delegate. The order
        // matters: replacing an extension that is in use made launchd refuse to start the new one ("Operation
        // already in progress") and the camera vanished, so this app only connects once that is settled.
        if Self.findDevice() != nil || UserDefaults.standard.bool(forKey: "cameraInstalled"), bundle.bundlePath.hasPrefix("/Applications/"), FileManager.default.fileExists(atPath: inside.path) {
            checkingForUpdate = true
            submit()
            return
        }
        beginSearching()
    }

    private func beginSearching() {
        if connect() { state = .ready; return }
        // Seen with the real thing: a process that was already running when the extension got approved does not
        // find the new device by polling alone. Listening for device-list changes is what makes CoreMediaIO
        // refresh the list in this process.
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &address, .main) { [weak self] _, _ in
            guard let self, self.state != .ready, self.connect() else { return }
            self.state = .ready
            self.search?.invalidate(); self.search = nil
        }
        search = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, self.connect() else { return }
            self.state = .ready
            self.search?.invalidate(); self.search = nil
        }
    }

    func install() {
        state = .installing
        submit()
    }

    private func submit() {
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: Self.extensionID, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    /// Called for every finished frame, from the frame queue.
    func send(_ buffer: CVPixelBuffer) {
        lock.lock(); let queue = bufferQueue; lock.unlock()
        guard let queue else { return }
        // Its own sample buffer, stamped with the host clock and with no attachments.
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &format)
        guard let format else { return }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var made: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescription: format,
                                                 sampleTiming: &timing, sampleBufferOut: &made)
        guard let sample = made else { return }
        if CMSimpleQueueGetCount(queue) < CMSimpleQueueGetCapacity(queue) {
            let ref = Unmanaged.passRetained(sample)
            if CMSimpleQueueEnqueue(queue, element: ref.toOpaque()) == noErr { sent += 1 } else { ref.release(); dropped += 1 }
        } else {
            dropped += 1
        }
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastReport > 10 {
            lastReport = now
            print("camara: \(CVPixelBufferGetWidth(buffer))x\(CVPixelBufferGetHeight(buffer)) \(sent) enviados, \(dropped) descartados, cola \(CMSimpleQueueGetCount(queue))/\(CMSimpleQueueGetCapacity(queue))"); fflush(stdout)
            sent = 0; dropped = 0
        }
    }

    // MARK: Installing

    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        guard existing.bundleVersion != ext.bundleVersion else { return .cancel }
        print("extension: reemplazo \(existing.bundleVersion) -> \(ext.bundleVersion)"); fflush(stdout)
        replacing = true
        return .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) { state = .needsApproval }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        print("extension: resultado \(result.rawValue)"); fflush(stdout)
        checkingForUpdate = false; replacing = false
        UserDefaults.standard.set(true, forKey: "cameraInstalled")   // remembered, so later launches check for updates first
        if state != .ready { state = .installing }   // the device shows up a moment later; the search picks it up
        if search == nil { beginSearching() }
        // Seen with the real thing, twice: a process that was already running when the extension was installed or
        // replaced keeps an old list of cameras and never finds the new device, while a fresh process finds it at
        // once. So if it has not turned up in a few seconds, start the app again (once).
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.state != .ready, !CommandLine.arguments.contains("--relaunched") else { return }
            print("camara: no aparece en este proceso, relanzando"); fflush(stdout)
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.arguments = ["--relaunched"]
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let e = error as NSError
        print("extension: error \(e.domain) \(e.code) \(e.localizedDescription)"); fflush(stdout)
        if checkingForUpdate {   // same version (cancelled) or the update could not be done: use what is installed
            checkingForUpdate = false
            beginSearching()
            return
        }
        state = .failed("\(e.localizedDescription) (\(e.code))")
    }

    // MARK: Finding the device and its sink

    /// How many apps are showing the Kawaru camera right now, as the extension reports it. Nil when it cannot be
    /// read (no extension, or one from before it reported this): the caller then keeps the camera on, as before.
    func watchers() -> Int? {
        lock.lock(); let device = self.device; lock.unlock()
        guard device != 0 else { return nil }
        var address = CMIOObjectPropertyAddress(mSelector: 0x6B776368 /* 'kwch' */, mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        guard CMIOObjectHasProperty(device, &address) else { return nil }
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size == UInt32(MemoryLayout<CFString?>.size) else { return nil }
        var used: UInt32 = 0
        var text: Unmanaged<CFString>?
        guard CMIOObjectGetPropertyData(device, &address, 0, nil, size, &used, &text) == noErr, let text else { return nil }
        return Int(text.takeRetainedValue() as String)
    }

    private func connect() -> Bool {
        guard let found = Self.findDevice() else {
            attempts += 1
            if attempts % 5 == 1 {
                let all: [CMIOObjectID] = Self.list(CMIOObjectID(kCMIOObjectSystemObject), kCMIOHardwarePropertyDevices)
                print("camara: buscando, CoreMediaIO ve \(all.count) dispositivos"); fflush(stdout)
            }
            return false
        }
        let streams: [CMIOStreamID] = Self.list(found, kCMIODevicePropertyStreams)
        guard streams.count >= 2 else { return false }
        let sinkStream = streams[1]   // the extension adds the source first and the sink second
        var queue: Unmanaged<CMSimpleQueue>?
        let status = CMIOStreamCopyBufferQueue(sinkStream, { _, _, _ in }, nil, &queue)
        guard status == noErr, let queue else { print("camara: sin cola (\(status))"); fflush(stdout); return false }
        let started = CMIODeviceStartStream(found, sinkStream)
        guard started == noErr else { print("camara: no arrancó (\(started))"); fflush(stdout); return false }
        lock.lock(); device = found; sink = sinkStream; bufferQueue = queue.takeRetainedValue(); lock.unlock()
        print("camara: conectada"); fflush(stdout)
        return true
    }

    private static func findDevice() -> CMIOObjectID? {
        let devices: [CMIOObjectID] = list(CMIOObjectID(kCMIOObjectSystemObject), kCMIOHardwarePropertyDevices)
        for d in devices {
            var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID),
                                                    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            var uid: Unmanaged<CFString>?
            var used: UInt32 = 0
            let size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard CMIOObjectGetPropertyData(d, &address, 0, nil, size, &used, &uid) == noErr, let uid else { continue }
            if (uid.takeRetainedValue() as String) == deviceUID { return d }
        }
        return nil
    }

    private static func list(_ object: CMIOObjectID, _ selector: Int) -> [UInt32] {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(selector),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var items = [UInt32](repeating: 0, count: Int(size) / MemoryLayout<UInt32>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(object, &address, 0, nil, size, &used, &items) == noErr else { return [] }
        return items
    }
}
