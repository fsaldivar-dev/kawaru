import AVFoundation
import AppKit
import Carbon.HIToolbox
import Combine
import QuartzCore
import Vision

/// What a recorded hand position is for: one of the effects, or one of the user's captions.
enum Trigger: Hashable {
    case effect(Effect), caption(UUID)

    /// The name it is stored under.
    var key: String {
        switch self {
        case .effect(let effect): effect.rawValue
        case .caption(let id): "rotulo-" + id.uuidString
        }
    }
}

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
        if next == nil { refining = false; queue.async { self.teaching = nil } }
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
    /// The joints of the hands in view, per hand, in the frame (0...1, y up); nil where Vision is unsure.
    /// Only filled while recording or practising, to draw over the picture what is being read.
    @Published private(set) var joints: [[CGPoint?]] = []
    @Published private(set) var poses: [Trigger: PoseTemplate] = Engine.savedPoses()
    /// A photo of the user holding each recorded position, to remember it by.
    @Published private(set) var posePhotos: [Trigger: NSImage] = Dictionary(uniqueKeysWithValues: Engine.everyTrigger().compactMap { t in PosePhoto.load(t).map { (t, $0) } })
    /// The effect a position is being recorded for, if any.
    @Published private(set) var recording: Trigger?
    /// Seconds left before recording starts; nil once it is recording.
    @Published private(set) var recordCountdown: Int?
    /// Set when the last recording could not be used.
    @Published var recordProblem: String?
    static let recordTime = 1.8

    /// Every take of each recorded position: the first one and the repetitions that taught its variations.
    /// A hand matches the position when it matches any of them.
    private static func savedVariants() -> [Trigger: [PoseTemplate]] {
        var result: [Trigger: [PoseTemplate]] = [:]
        for (effect, first) in savedPoses() {
            let more = UserDefaults.standard.data(forKey: "poses." + effect.key).flatMap { try? JSONDecoder().decode([PoseTemplate].self, from: $0) }
            // Takes that are not the same position as the first are dropped: earlier versions kept whatever the
            // hand was doing during a repetition, and those made the gesture go off for other positions.
            result[effect] = [first] + (more ?? []).dropFirst().filter { first.sameShape(as: $0) }
        }
        return result
    }

    /// True while the repetitions after a recording are teaching variations of the position.
    @Published private(set) var refining = false

    /// Everything a position can have been recorded for: each effect, and each of the user's captions.
    private static func everyTrigger() -> [Trigger] {
        Effect.allCases.map(Trigger.effect) + savedRotulos().map { Trigger.caption($0.id) }
    }

    /// What is shown while recording a position: the name of what it is for.
    func title(of trigger: Trigger) -> String {
        switch trigger {
        case .effect(let effect): effect.title
        case .caption(let id): rotulos.first { $0.id == id }.map { $0.title.isEmpty ? $0.kind.title : $0.title } ?? "el rótulo"
        }
    }

    /// Drops whatever was recorded for a caption that is being deleted.
    func forget(_ trigger: Trigger) {
        poses[trigger] = nil; posePhotos[trigger] = nil
        PosePhoto.delete(trigger)
        UserDefaults.standard.removeObject(forKey: "pose." + trigger.key)
        UserDefaults.standard.removeObject(forKey: "poses." + trigger.key)
        queue.async { self.templates[trigger] = nil }
    }

    private static func savedPoses() -> [Trigger: PoseTemplate] {
        var result: [Trigger: PoseTemplate] = [:]
        for effect in everyTrigger() {
            if let data = UserDefaults.standard.data(forKey: "pose." + effect.key), let pose = try? JSONDecoder().decode(PoseTemplate.self, from: data) {
                result[effect] = pose
            }
        }
        return result
    }

    /// Counts down, then watches the hands for a moment and keeps their position as this effect's gesture.
    func startRecording(for effect: Trigger) {
        guard recording == nil else { return }
        stopPractice()
        recordProblem = nil
        recording = effect
        recordCountdown = 3
        // No effect fires while getting the hands ready, and whatever was on goes off: the user has to see themselves.
        queue.async { self.quiet = true; self.current = .person }
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

    private func finishRecording(_ effect: Trigger, _ pose: PoseTemplate?, photo: Data?) {
        queue.async { self.quiet = false }
        guard recording == effect else { return }
        recording = nil
        guard let pose else {
            recordProblem = "No vi tus manos con claridad mientras grababa. Ponlas frente a la cámara, quietas, e inténtalo de nuevo."
            return
        }
        poses[effect] = pose
        if let photo {
            PosePhoto.save(photo, for: effect)
            posePhotos[effect] = NSImage(data: photo)
        } else {
            PosePhoto.delete(effect); posePhotos[effect] = nil   // never show the photo of an older position
        }
        if let data = try? JSONEncoder().encode(pose) { UserDefaults.standard.set(data, forKey: "pose." + effect.key) }
        UserDefaults.standard.removeObject(forKey: "poses." + effect.key)
        queue.async { self.templates[effect] = [pose]; self.teaching = effect; self.taught = []; self.teachingStarts = true }
        switch effect {
        case .effect(let which): commands[which] = .custom
        case .caption(let id): if let i = rotulos.firstIndex(where: { $0.id == id }) { rotulos[i].gestureName = Gesture.custom.rawValue }
        }
        // Straight into three repetitions. They do not test the first take: each one is kept as a variation,
        // so the position is learnt the way the user really makes it.
        practiceEffect = effect
        refining = true
        startPractice([.custom])
    }

    /// The effect whose recorded position is being practised.
    @Published private(set) var practiceEffect: Trigger? {
        didSet { let e = practiceEffect; queue.async { self.practisingEffect = e } }
    }

    /// Practise the gesture bound to an effect (recorded positions need to know which effect).
    func startPractice(for effects: [Effect]) {
        practiceEffect = effects.first { commands[$0] == .custom }.map(Trigger.effect)
        startPractice(effects.map { commands[$0] ?? .none })
    }

    /// Practise the gesture a caption answers to.
    func startPractice(for rotulo: Rotulo) {
        guard let gesture = rotulo.gestureName.flatMap(Gesture.init(rawValue:)), gesture != .none else { return }
        practiceEffect = gesture == .custom ? .caption(rotulo.id) : nil
        startPractice([gesture])
    }

    /// Start or stop an effect from a keyboard shortcut.
    func toggle(_ effect: Effect) {
        queue.async { self.current = self.current == effect.look ? .person : effect.look }
    }

    private func registerShortcuts() {
        hotkeys.onPress = { [weak self] id in
            guard let self else { return }
            if id >= 100 {
                // Control-Option-Shift and a digit: the captions, in the order they are listed.
                if self.rotulos.indices.contains(id - 100) { self.toggle(self.rotulos[id - 100]) }
                return
            }
            guard Effect.allCases.indices.contains(id) else { return }
            self.toggle(Effect.allCases[id])
        }
        for (i, key) in [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9].enumerated() {
            hotkeys.register(id: 100 + i, keyCode: key, modifiers: controlKey | optionKey | shiftKey)
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
    private var templates = Engine.savedVariants()
    /// The effect whose repetitions are being kept as variations, and the frames of the one in progress.
    private var teaching: Trigger?
    /// Set when the repetitions begin: the hands are still in the first take's position and have to be let
    /// go before a repetition counts, or the first one would be the same take again.
    private var teachingStarts = false
    private var taught: [(hands: [HandShape], face: CGRect?)] = []
    private var practisingEffect: Trigger?
    private var sampling: Trigger?
    private var quiet = false
    private var listening = UserDefaults.standard.object(forKey: "gesturesOn") as? Bool ?? true
    private var sampleUntil = 0.0
    private var samples: [(hands: [HandShape], face: CGRect?)] = []
    private var resetPlate = false
    private var frames = 0, spent = 0.0, windowStart = 0.0
    private var tick = 0
    private var lastHands: [VNHumanHandPoseObservation] = []
    private var handCount = 0, spentVision = 0.0
    private var seenCounts: [Gesture: Int] = [:]
    private var recent: [[HandShape]] = []
    private var jointsShown = false
    /// Per recorded position, this second: frames measured, sums of joint distance, worst finger, place by the
    /// face and raw (unsteadied) joint distance, and frames that matched. For the log.
    private var closeness: [Trigger: (Int, Double, Double, Double, Double, Int)] = [:]
    private var lastMatch: [Trigger: Double] = [:]
    private var matchedThisFrame: [Trigger: Bool] = [:]

    /// Hand gestures start effects. Off from the menu bar when the hands are busy with something else.
    @Published var gesturesOn = UserDefaults.standard.object(forKey: "gesturesOn") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(gesturesOn, forKey: "gesturesOn")
            let on = gesturesOn
            queue.async { self.listening = on }
        }
    }
    /// The camera is on. It is only on while someone is looking: the window is open, or a call shows the camera.
    @Published private(set) var cameraOn = true
    /// Apps showing the Kawaru camera, when the extension can say.
    @Published private(set) var watchers: Int?
    private var wanted = true
    private var pulse: Timer?

    /// Once a second: is anyone looking? If not, the camera goes off, light and all.
    private func watch() {
        pulse = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.access == .granted else { return }
            let windowOpen = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain && !$0.isMiniaturized }
            let count = self.virtualCamera.watchers()
            if self.watchers != count { self.watchers = count }
            // Without a count there is no telling whether a call is using the camera, so it stays on.
            let want = windowOpen || count == nil || (count ?? 0) > 0
            guard want != self.wanted else { return }
            self.wanted = want
            self.cameraOn = want
            print("camara propia: \(want ? "encendida" : "apagada") (ventana \(windowOpen ? "abierta" : "cerrada"), apps mirando \(count.map(String.init) ?? "?"))"); fflush(stdout)
            self.queue.async {
                if want { if !self.session.isRunning { self.session.startRunning() } } else if self.session.isRunning { self.session.stopRunning() }
            }
        }
    }

    // MARK: Captions

    /// The user's captions, in the order they are listed. Remembered between launches.
    @Published var rotulos: [Rotulo] = Engine.savedRotulos() {
        didSet {
            if let data = try? JSONEncoder().encode(rotulos) { UserDefaults.standard.set(data, forKey: "rotulos") }
            let copy = Dictionary(uniqueKeysWithValues: rotulos.map { ($0.id, $0) })
            let order = rotulos.map(\.id)
            queue.async { self.library = copy; self.libraryOrder = order }
        }
    }
    /// The captions that are up right now (not the ones on their way out).
    @Published private(set) var captionsUp: Set<UUID> = []
    private var library = Dictionary(uniqueKeysWithValues: Engine.savedRotulos().map { ($0.id, $0) })
    private var showing: [UUID: Rotulos.Showing] = [:]
    private var libraryOrder = Engine.savedRotulos().map(\.id)

    private static func savedRotulos() -> [Rotulo] {
        if let data = UserDefaults.standard.data(forKey: "rotulos"), let saved = try? JSONDecoder().decode([Rotulo].self, from: data) { return saved }
        // First time: one of each kind, so there is something to try. Saved at once so their identity sticks.
        let first = Rotulo.starters
        if let data = try? JSONEncoder().encode(first) { UserDefaults.standard.set(data, forKey: "rotulos") }
        return first
    }

    /// Puts a caption up, or takes it down if it is up.
    func toggle(_ rotulo: Rotulo) {
        let id = rotulo.id
        queue.async { self.flip(id, now: CACurrentMediaTime()) }
    }

    /// Call on `queue`.
    private func flip(_ id: UUID, now: Double) {
        if var item = showing[id], item.leaving == nil {
            item.leaving = now; showing[id] = item
        } else if let fresh = library[id] {
            showing[id] = Rotulos.Showing(rotulo: fresh, since: now, leaving: nil)
        }
        publishCaptions()
    }

    /// One meter per caption that has a gesture, like the effects have.
    private var captionMeters: [UUID: HoldMeter] = [:]

    /// Call on `queue`.
    private func publishCaptions() {
        let up = Set(showing.filter { $0.value.leaving == nil }.keys)
        DispatchQueue.main.async { if self.captionsUp != up { self.captionsUp = up } }
    }

    private var started = false

    /// Asks for the camera if it has to, and starts. Safe to call again.
    func start() {
        guard !started else { return }
        started = true
        display.videoGravity = .resizeAspect
        watch()
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
            if self.wanted, !self.session.isRunning { self.session.startRunning() }
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
            || bindings.contains { $0.value == .custom && (templates[.effect($0.key)] ?? []).contains { $0.faceOffset != nil } }
            || library.values.contains { $0.gestureName.flatMap(Gesture.init(rawValue:))?.needsFace == true }
            || library.values.contains { $0.gestureName == Gesture.custom.rawValue && (templates[.caption($0.id)] ?? []).contains { $0.faceOffset != nil } }
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
        // What is being read, for drawing over the picture while recording or practising.
        let showJoints = sampling != nil || quiet || practising != nil
        let dots: [[CGPoint?]] = showJoints ? found.map { hand in
            let all = (try? hand.recognizedPoints(.all)) ?? [:]
            return HandShape.joints.map { j in all[j].flatMap { $0.confidence > 0.2 ? $0.location : nil } }
        } : []
        if showJoints || jointsShown {
            jointsShown = showJoints
            DispatchQueue.main.async { self.joints = dots }
        }
        // Recorded positions are compared against the last few frames averaged, not one jittery frame.
        recent.append(shapes.sorted { $0.centre.x < $1.centre.x })
        if recent.count > 5 { recent.removeFirst() }
        let steady = HandShape.steadied(recent)
        // A position that matched a moment ago is held on to a little more loosely, so jitter does not drop it
        // half way through the half second it has to be held.
        func recorded(_ effect: Trigger) -> Bool {
            if let known = matchedThisFrame[effect] { return known }
            let slack: CGFloat = began - (lastMatch[effect] ?? 0) < 0.35 ? 1.3 : 1
            let found = (templates[effect] ?? []).contains { $0.matches(steady, face: lastFace, aspect: aspect, slack: slack) }
            if found { lastMatch[effect] = began }
            matchedThisFrame[effect] = found
            return found
        }
        matchedThisFrame = [:]
        /// The hands are still roughly in this recorded position, wherever they are in the picture.
        func near(_ effect: Trigger) -> Bool { (templates[effect] ?? []).contains { $0.resembles(steady, aspect: aspect) } }
        var customs = bindings.filter { $0.value == .custom }.map { Trigger.effect($0.key) }
        customs += library.values.filter { $0.gestureName == Gesture.custom.rawValue }.map { Trigger.caption($0.id) }
        for effect in customs {
            guard let template = templates[effect]?.first, let now = template.closeness(steady, face: lastFace, aspect: aspect), now.joints.isFinite else { continue }
            let raw = template.closeness(shapes, face: lastFace, aspect: aspect)?.joints ?? .infinity
            var tally = closeness[effect] ?? (0, 0, 0, 0, 0, 0)
            tally.0 += 1; tally.1 += Double(now.joints); tally.2 += Double(now.finger); tally.3 += Double(now.place)
            tally.4 += raw.isFinite ? Double(raw) : 0; tally.5 += recorded(effect) ? 1 : 0
            closeness[effect] = tally
        }

        if let effect = sampling {
            samples.append((hands: shapes, face: lastFace))
            if began >= sampleUntil {
                sampling = nil
                let pose = PoseTemplate.make(from: samples, aspect: aspect)
                let handCounts = (0...2).map { n in "\(n)x\(samples.filter { $0.hands.count == n }.count)" }.joined(separator: " ")
                samples = []
                if let pose { print(String(format: "pose: grabada para %@, %d mano(s), tolerancia %.2f, cara=%@, manos vistas por fotograma: %@", effect.key, pose.hands.count, pose.tolerance, pose.faceOffset == nil ? "no" : "si", handCounts)) }
                else { print("pose: grabación sin manos suficientes") }
                fflush(stdout)
                let photo = pose == nil ? nil : PosePhoto.encode(frame, joints: dots)
                DispatchQueue.main.async { self.finishRecording(effect, pose, photo: photo) }
            }
        }

        var progress = 0.0, held = Gesture.none
        if sampling != nil || quiet {
            // Recording, or about to: nothing fires.
        } else if let target = practising {
            // Practising: the gesture fills its meter and is counted, and nothing else happens.
            var present = target == .custom ? (practisingEffect.map(recorded) ?? false) : seen.contains(target)
            if let effect = teaching, effect == practisingEffect, let first = templates[effect]?.first {
                // Teaching variations: anything roughly like the first take counts, and its frames are kept.
                if teachingStarts { teachingStarts = false; practiceMeter.standDown(now: began) }
                present = first.resembles(shapes, aspect: aspect)
                if present { taught.append((hands: shapes, face: lastFace)) } else if practiceMeter.progress == 0 { taught = [] }
            }
            if practiceMeter.update(present: present, now: began) {
                if let effect = teaching, effect == practisingEffect {
                    if let variant = PoseTemplate.make(from: taught, aspect: aspect, atLeast: 6), let first = templates[effect]?.first, first.sameShape(as: variant) {
                        templates[effect]?.append(variant)
                        let all = templates[effect] ?? []
                        print(String(format: "pose: variante %d para %@, tolerancia %.2f", all.count - 1, effect.key, variant.tolerance)); fflush(stdout)
                        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: "poses." + effect.key) }
                    }
                    taught = []
                    if hits + 1 >= Engine.practiceGoal { teaching = nil }
                }
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
        } else if listening {
            // Each effect has its own meter. Firing an effect that is on turns it off; firing another one switches.
            // Only one fires per frame, and the rest stand down until their hands let go.
            var firedEffect: Effect?
            for effect in Effect.allCases {
                let gesture = bindings[effect] ?? .none
                let present = gesture == .custom ? recorded(.effect(effect)) : (gesture != .none && seen.contains(gesture))
                var meter = meters[effect] ?? HoldMeter()
                let fired = firedEffect == nil && meter.update(present: present, near: gesture == .custom ? near(.effect(effect)) : nil, now: began)
                meters[effect] = meter
                if meter.progress > progress { progress = meter.progress; held = gesture }
                if gesture == .custom, present { seenCounts[.custom, default: 0] += 1 }
                if fired { firedEffect = effect }
            }
            // The captions that have a gesture, after the effects: an effect with the same gesture goes first.
            var firedCaption: UUID?
            for id in libraryOrder {
                guard let rotulo = library[id] else { continue }
                guard let gesture = rotulo.gestureName.flatMap(Gesture.init(rawValue:)), gesture != .none else { captionMeters[id] = nil; continue }
                var meter = captionMeters[id] ?? HoldMeter()
                let present = gesture == .custom ? recorded(.caption(id)) : seen.contains(gesture)
                let fired = firedEffect == nil && firedCaption == nil && meter.update(present: present, near: gesture == .custom ? near(.caption(id)) : nil, now: began)
                captionMeters[id] = meter
                if meter.progress > progress { progress = meter.progress; held = gesture }
                if fired { firedCaption = id }
            }
            if let firedCaption { flip(firedCaption, now: began) }
            if let firedEffect {
                current = current == firedEffect.look ? .person : firedEffect.look
                for effect in Effect.allCases where effect != firedEffect { meters[effect]?.standDown(now: began) }
            }
            if firedEffect != nil || firedCaption != nil {
                for id in captionMeters.keys where id != firedCaption { captionMeters[id]?.standDown(now: began) }
                if firedCaption != nil { for effect in Effect.allCases { meters[effect]?.standDown(now: began) } }
            }
        }
        for g in seen { seenCounts[g, default: 0] += 1 }

        // Captions: the ones that have run their time start to leave, and the ones that have left are dropped.
        if !showing.isEmpty {
            var changed = false
            for (id, item) in showing {
                guard let fresh = library[id] else { showing[id] = nil; changed = true; continue }
                var item = item
                item.rotulo = fresh   // edits show at once
                if item.leaving == nil, fresh.seconds > 0, began - item.since > fresh.seconds + Rotulos.enterTime { item.leaving = began; changed = true }
                if let leaving = item.leaving, began - leaving > Rotulos.leaveTime { showing[id] = nil; changed = true } else { showing[id] = item }
            }
            if changed { publishCaptions() }
        }
        let captions = showing.values.sorted { $0.since < $1.since }
        let shown = compositor.render(frame: frame, mask: needMask ? segmentation.results?.first?.pixelBuffer : nil, look: current,
                                      resetPlate: resetPlate, now: began, captions: captions)
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
            for (effect, t) in closeness.sorted(by: { $0.key.key < $1.key.key }) {
                let n = Double(t.0)
                print(String(format: "  pose %@: coincide %d/%d, dedos %.2f (sin promediar %.2f), peor dedo %.2f, lugar %.2f, tolerancia %.2f", String(effect.key.prefix(18)),
                             t.5, t.0, t.1 / n, t.4 / n, t.2 / n, t.3 / n, templates[effect]?.first?.strictness ?? 0))
            }
            closeness = [:]
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
