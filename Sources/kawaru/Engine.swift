import AVFoundation
import AppKit
import Carbon.HIToolbox
import Combine
import QuartzCore
import Vision

/// Camera in, Vision, compositor, preview out.
final class Engine: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum Access { case asking, granted, denied, noCamera }

    @Published var access = Access.asking
    @Published var cameraName = ""
    @Published var fps = 0
    @Published var milliseconds = 0.0
    @Published var look = Look.person
    @Published var hold = 0.0
    /// The gesture being held right now, while its meter fills.
    @Published var holding = Gesture.none
    /// Which hand position starts each effect. Edited in the Commands window, remembered between launches.
    @Published var commands: [Effect: Gesture] = Engine.savedCommands() {
        didSet {
            for (effect, gesture) in commands { UserDefaults.standard.set(gesture.rawValue, forKey: "command." + effect.rawValue) }
            let copy = commands
            queue.async { self.bindings = copy }
        }
    }

    // MARK: Practice

    /// The gesture being practised, if any. While practising, gestures do not start effects.
    @Published private(set) var practice: Gesture?
    /// Times the practised gesture has been read so far.
    @Published private(set) var practiceHits = 0
    /// What to change to get it read, when it is not being read.
    @Published private(set) var practiceTip: String?
    /// How many of the gestures in this round are still to come after the current one.
    @Published private(set) var practiceLeft = 0
    static let practiceGoal = 3
    private var practiceQueue: [Gesture] = []

    /// Practise these gestures one after another.
    func startPractice(_ gestures: [Gesture]) {
        var seen = Set<Gesture>()
        practiceQueue = gestures.filter { $0 != .none && seen.insert($0).inserted }
        nextPractice()
    }

    func nextPractice() {
        let next = practiceQueue.isEmpty ? nil : practiceQueue.removeFirst()
        practice = next
        practiceHits = 0
        practiceTip = nil
        practiceLeft = practiceQueue.count
        if next == nil { UserDefaults.standard.set(true, forKey: "practised") }
        queue.async { self.practising = next; self.practiceMeter = HoldMeter(); self.hits = 0; self.shownTip = nil }
    }

    func stopPractice() { practiceQueue = []; nextPractice() }

    // MARK: Recording a position

    /// The positions recorded so far, one per effect at most. Remembered between launches.
    @Published private(set) var poses: [Effect: PoseTemplate] = Engine.savedPoses()
    /// The effect a position is being recorded for, if any.
    @Published private(set) var recording: Effect?
    /// Seconds left before recording starts; nil once it is recording.
    @Published private(set) var recordCountdown: Int?
    /// Set when the last recording could not be used.
    @Published var recordProblem: String?
    static let recordTime = 1.3

    private static func savedPoses() -> [Effect: PoseTemplate] {
        var result: [Effect: PoseTemplate] = [:]
        for effect in Effect.allCases {
            if let data = UserDefaults.standard.data(forKey: "pose." + effect.rawValue), let pose = try? JSONDecoder().decode(PoseTemplate.self, from: data) {
                result[effect] = pose
            }
        }
        return result
    }

    /// Counts down, then watches the hands for a moment and keeps their position as this effect's gesture.
    func startRecording(for effect: Effect) {
        guard recording == nil else { return }
        stopPractice()
        recordProblem = nil
        recording = effect
        recordCountdown = 3
        queue.async { self.quiet = true }   // no effect fires while getting the hands ready
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            guard self.recording == effect else { timer.invalidate(); return }
            let left = (self.recordCountdown ?? 1) - 1
            if left > 0 { self.recordCountdown = left; return }
            timer.invalidate()
            self.recordCountdown = nil
            self.queue.async { self.samples = []; self.sampling = effect; self.sampleUntil = CACurrentMediaTime() + Engine.recordTime }
        }
    }

    func cancelRecording() {
        recording = nil; recordCountdown = nil
        queue.async { self.sampling = nil; self.quiet = false }
    }

    private func finishRecording(_ effect: Effect, _ pose: PoseTemplate?) {
        queue.async { self.quiet = false }
        guard recording == effect else { return }
        recording = nil
        guard let pose else {
            recordProblem = "No vi tus manos con claridad mientras grababa. Ponlas frente a la cámara, quietas, e inténtalo de nuevo."
            return
        }
        poses[effect] = pose
        if let data = try? JSONEncoder().encode(pose) { UserDefaults.standard.set(data, forKey: "pose." + effect.rawValue) }
        let copy = poses
        queue.async { self.templates = copy }
        commands[effect] = .custom
        // Straight into practice, to find out at once whether it reads well.
        practiceEffect = effect
        startPractice([.custom])
    }

    /// The effect whose recorded position is being practised.
    private var practiceEffect: Effect? {
        didSet { let e = practiceEffect; queue.async { self.practisingEffect = e } }
    }

    /// Practise the gesture bound to an effect (recorded positions need to know which effect).
    func startPractice(for effects: [Effect]) {
        practiceEffect = effects.first { commands[$0] == .custom }
        startPractice(effects.map { commands[$0] ?? .none })
    }

    /// Start or stop an effect from a keyboard shortcut.
    func toggle(_ effect: Effect) {
        queue.async { self.current = self.current == effect.look ? .person : effect.look }
    }

    private func registerShortcuts() {
        hotkeys.onPress = { [weak self] id in
            guard let self, Effect.allCases.indices.contains(id) else { return }
            self.toggle(Effect.allCases[id])
        }
        for (i, effect) in Effect.allCases.enumerated() {
            if !hotkeys.register(id: i, keyCode: effect.keyCode, modifiers: controlKey | optionKey) {
                print("atajo: \(effect.shortcut) no se pudo registrar"); fflush(stdout)
            }
        }
    }

    private static func savedCommands() -> [Effect: Gesture] {
        var result: [Effect: Gesture] = [:]
        for effect in Effect.allCases {
            let saved = UserDefaults.standard.string(forKey: "command." + effect.rawValue).flatMap(Gesture.init(rawValue:))
            result[effect] = saved ?? effect.defaultGesture
        }
        return result
    }
    /// Seconds left before the background is photographed, while counting down.
    @Published var countdown: Int?
    @Published var hasBackground = false
    /// The last background photo still had someone in it.
    @Published var backgroundHasPerson = false

    let display = AVSampleBufferDisplayLayer()
    private let poof = Poof()
    private let hotkeys = Hotkeys()
    private let knock = Poof(air: false)
    let virtualCamera = VirtualCamera()

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "dev.kawaru.frames", qos: .userInteractive)

    // Only touched on `queue`.
    private let vision = VNSequenceRequestHandler()
    private let hands: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest(); r.maximumHandCount = 2; return r
    }()
    private let segmentation: VNGeneratePersonSegmentationRequest = {
        let r = VNGeneratePersonSegmentationRequest()
        r.qualityLevel = .balanced
        r.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return r
    }()
    private let compositor = Compositor()
    private let faces = VNDetectFaceRectanglesRequest()
    private var bindings = Engine.savedCommands()
    private var meters: [Effect: HoldMeter] = [:]
    private var current = Look.person
    private var lastFace: CGRect?
    private var practising: Gesture?
    private var practiceMeter = HoldMeter()
    private var hits = 0
    private var shownTip: String?
    private var templates = Engine.savedPoses()
    private var practisingEffect: Effect?
    private var sampling: Effect?
    private var quiet = false
    private var sampleUntil = 0.0
    private var samples: [(hands: [HandShape], face: CGRect?)] = []
    private var resetPlate = false
    private var frames = 0, spent = 0.0, windowStart = 0.0
    private var tick = 0
    private var lastHands: [VNHumanHandPoseObservation] = []
    private var handCount = 0, spentVision = 0.0
    private var seenCounts: [Gesture: Int] = [:]

    func start() {
        display.videoGravity = .resizeAspect
        registerShortcuts()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async { if ok { self.configure() } else { self.access = .denied } }
            }
        default: access = .denied
        }
    }

    /// Counts down so there is time to step out of the frame, then photographs the room.
    func captureBackground() {
        guard countdown == nil else { return }
        countdown = 3
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            let left = (self.countdown ?? 1) - 1
            if left > 0 { self.countdown = left; return }
            timer.invalidate()
            self.countdown = nil
            self.queue.async { self.resetPlate = true }
        }
    }

    /// A camera Kawaru can take its picture from.
    struct Source: Identifiable, Hashable { let id: String; let name: String }
    @Published private(set) var sources: [Source] = []
    @Published private(set) var sourceID = ""

    /// Every real camera: built in, plugged in, or an iPhone. Not Kawaru's own virtual camera.
    private static func devices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera], mediaType: .video, position: .unspecified)
            .devices.filter { $0.localizedName != "Kawaru" }
    }

    /// Switch to another camera. Remembered for the next launch.
    func selectSource(_ id: String) {
        guard id != sourceID, access == .granted else { return }
        UserDefaults.standard.set(id, forKey: "camera.id")
        configure()
    }

    private var hasOutput = false

    private func configure() {
        let all = Engine.devices()
        sources = all.map { Source(id: $0.uniqueID, name: $0.localizedName) }
        let saved = UserDefaults.standard.string(forKey: "camera.id")
        let chosen = all.first { $0.uniqueID == saved } ?? all.first { $0.deviceType == .builtInWideAngleCamera } ?? all.first
        guard let device = chosen ?? AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device) else {
            if access != .granted { access = .noCamera }
            return
        }
        access = .granted
        cameraName = device.localizedName
        sourceID = device.uniqueID
        queue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .hd1280x720
            for old in self.session.inputs { self.session.removeInput(old) }
            if self.session.canAddInput(input) { self.session.addInput(input) }
            if !self.hasOutput {
                self.hasOutput = true
                let output = AVCaptureVideoDataOutput()
                // The size is asked for here as well: the preset alone left this Mac's camera at 1920x1080 (seen in the
                // log), which more than doubles the work and does not match the virtual camera's 1280x720.
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                        kCVPixelBufferWidthKey as String: 1280, kCVPixelBufferHeightKey as String: 720]
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: self.queue)
                if self.session.canAddOutput(output) { self.session.addOutput(output) }
            }
            self.session.commitConfiguration()
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let frame = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let began = CACurrentMediaTime()
        // Vision is most of the cost, so each request runs only as often as it is needed: hands on every frame
        // while waiting for a gesture, the person mask on every frame while an effect is on screen, and the face
        // only if some command uses the salute.
        tick += 1
        let needMask = resetPlate || current == .trunk || current == .clones || current == .spotlight || compositor.usesMask || tick % 3 == 0
        let needHands = current == .person || tick % 2 == 0
        // The face is looked for when a command is read against it, when a recorded position is tied to it, and
        // always while recording, to find out whether the hand is by the face.
        let usesFace = sampling != nil || practising?.needsFace ?? bindings.values.contains(where: \.needsFace)
            || bindings.contains { $0.value == .custom && templates[$0.key]?.faceOffset != nil }
        let needFace = needHands && usesFace
        var requests: [VNRequest] = []
        if needHands { requests.append(hands) }
        if needFace { requests.append(faces) }
        if needMask { requests.append(segmentation) }
        try? vision.perform(requests, on: frame)

        let afterVision = CACurrentMediaTime()
        if needHands { lastHands = hands.results ?? [] }
        if needFace { lastFace = faces.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width })?.boundingBox }
        let found = lastHands
        let aspect = CGFloat(CVPixelBufferGetWidth(frame)) / CGFloat(CVPixelBufferGetHeight(frame))
        let seen = GestureReader.read(hands: found, face: usesFace ? lastFace : nil, aspect: aspect)

        // Recorded positions, compared against what the hands are doing now.
        let shapes = found.compactMap { HandShape($0, aspect: aspect) }
        func recorded(_ effect: Effect) -> Bool { templates[effect]?.matches(shapes, face: lastFace, aspect: aspect) ?? false }

        if let effect = sampling {
            samples.append((hands: shapes, face: lastFace))
            if began >= sampleUntil {
                sampling = nil
                let pose = PoseTemplate.make(from: samples, aspect: aspect)
                let handCounts = (0...2).map { n in "\(n)x\(samples.filter { $0.hands.count == n }.count)" }.joined(separator: " ")
                samples = []
                if let pose { print(String(format: "pose: grabada para %@, %d mano(s), tolerancia %.2f, cara=%@, manos vistas por fotograma: %@", effect.rawValue, pose.hands.count, pose.tolerance, pose.faceOffset == nil ? "no" : "si", handCounts)) }
                else { print("pose: grabación sin manos suficientes") }
                fflush(stdout)
                DispatchQueue.main.async { self.finishRecording(effect, pose) }
            }
        }

        var progress = 0.0, held = Gesture.none
        if sampling != nil || quiet {
            // Recording, or about to: nothing fires.
        } else if let target = practising {
            // Practising: the gesture fills its meter and is counted, and nothing else happens.
            let present = target == .custom ? (practisingEffect.map(recorded) ?? false) : seen.contains(target)
            if practiceMeter.update(present: present, now: began) {
                hits += 1
                let count = hits
                DispatchQueue.main.async {
                    guard self.practice == target else { return }
                    self.practiceHits = count
                    NSSound(named: "Tink")?.play()
                }
            }
            progress = practiceMeter.progress; held = target
            let tip = present ? nil : GestureReader.advice(for: target, hands: found, face: lastFace, aspect: aspect)
            if tip != shownTip {
                shownTip = tip
                DispatchQueue.main.async { if self.practice == target { self.practiceTip = tip } }
            }
        } else {
            // Each effect has its own meter. Firing an effect that is on turns it off; firing another one switches.
            // Only one fires per frame, and the rest stand down until their hands let go.
            var firedEffect: Effect?
            for effect in Effect.allCases {
                let gesture = bindings[effect] ?? .none
                let present = gesture == .custom ? recorded(effect) : (gesture != .none && seen.contains(gesture))
                var meter = meters[effect] ?? HoldMeter()
                let fired = firedEffect == nil && meter.update(present: present, now: began)
                meters[effect] = meter
                if meter.progress > progress { progress = meter.progress; held = gesture }
                if gesture == .custom, present { seenCounts[.custom, default: 0] += 1 }
                if fired { firedEffect = effect }
            }
            if let firedEffect {
                current = current == firedEffect.look ? .person : firedEffect.look
                for effect in Effect.allCases where effect != firedEffect { meters[effect]?.standDown(now: began) }
            }
        }
        for g in seen { seenCounts[g, default: 0] += 1 }

        let shown = compositor.render(frame: frame, mask: needMask ? segmentation.results?.first?.pixelBuffer : nil, look: current,
                                      resetPlate: resetPlate, now: began)
        if compositor.expired { current = .person }   // the confetti and the break end by themselves
        if resetPlate {
            resetPlate = false
            let withPerson = compositor.capturedWithPerson, has = compositor.hasCapture
            DispatchQueue.main.async { self.hasBackground = has; self.backgroundHasPerson = withPerson }
        }
        show(shown, at: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))

        let on = current
        DispatchQueue.main.async {
            if self.hold != progress { self.hold = progress }
            if self.holding != held { self.holding = held }
            if self.look != on {
                // The poof belongs to the jutsus, not to putting the sign up or taking it down.
                if on.hasSmoke || self.look.hasSmoke { self.poof.play() }
                if on == .question { NSSound(named: "Pop")?.play() }
                if on == .confetti { NSSound(named: "Hero")?.play() }
                if on == .away { DispatchQueue.main.asyncAfter(deadline: .now() + Compositor.signFall) { self.knock.play() } }
                self.look = on
            }
        }

        // Once a second: numbers for the status line and for the log (numbers only, never images).
        let ended = CACurrentMediaTime()
        frames += 1; spent += ended - began; spentVision += afterVision - began
        handCount = max(handCount, found.count)
        if windowStart == 0 { windowStart = began }
        if ended - windowStart >= 1 {
            let rate = Int((Double(frames) / (ended - windowStart)).rounded()), ms = spent / Double(frames) * 1000
let gestures = seenCounts.map { "\($0.key.rawValue)=\($0.value)" }.sorted().joined(separator: " ")
            print(String(format: "fps=%d ms=%.1f vision=%.1f manos=%d cara=%@ persona=%.2f modo=%@ gestos[%@]", rate, ms,
                         spentVision / Double(frames) * 1000, handCount, lastFace == nil ? "no" : "si",
                         Double(compositor.personArea), "\(on)", gestures))
            fflush(stdout)
            DispatchQueue.main.async { self.fps = rate; self.milliseconds = ms }
            frames = 0; spent = 0; windowStart = ended; handCount = 0; spentVision = 0; seenCounts = [:]
        }
    }

    private func show(_ buffer: CVPixelBuffer, at time: CMTime) {
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format)
        guard let format else { return }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer, formatDescription: format,
                                                 sampleTiming: &timing, sampleBufferOut: &sample)
        guard let sample else { return }
        if let list = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true), CFArrayGetCount(list) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(list, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        virtualCamera.send(buffer)
        let renderer = display.sampleBufferRenderer
        if renderer.status == .failed { renderer.flush() }
        renderer.enqueue(sample)
    }
}
