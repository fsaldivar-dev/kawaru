import CoreImage
import CoreVideo

/// Turns a camera frame into the frame to show: the person, or a log where the person was.
/// Everything stays in memory; nothing is written to disk.
/// What the outgoing picture shows.
enum Look: Equatable {
    case person, trunk, clones, away, question, confetti, breakTime, spotlight

    /// Shows writing, so the preview must not be mirrored while it is up.
    var hasText: Bool { self == .away || self == .question || self == .confetti || self == .breakTime }
    /// A jutsu: comes and goes in a puff of smoke.
    var hasSmoke: Bool { self == .trunk || self == .clones }
}

final class Compositor {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let trunk = CIImage(cgImage: Trunk.draw())

    /// What the room looks like without the person, learned from the pixels the person is not covering.
    /// Its alpha says which pixels have been seen so far.
    private var plate: CVPixelBuffer?
    private var spare: CVPixelBuffer?
    /// The room photographed without the person in it, on request. While there is one, the log is shown over it
    /// and the live frame is not used at all, so nothing of the person can show. Memory only, never saved.
    private var captured: CVPixelBuffer?
    /// True when the last capture still had someone in it.
    private(set) var capturedWithPerson = false
    var hasCapture: Bool { captured != nil }
    private var pool: CVPixelBufferPool?
    private var size = CGSize.zero

    private var mix: CGFloat = 0          // 0 = the person, 1 = the log
    private var lastTime = 0.0
    private var lastLook = Look.person
    private var awayMix: CGFloat = 0
    private var questionMix: CGFloat = 0, spotMix: CGFloat = 0, breakMix: CGFloat = 0
    private var questionAt = 0.0, breakAt = 0.0
    private var confettiAt: Double?
    private var bubbleText = Wording.question
    private var bubble = Overlays.bubble(Wording.question)
    private var breakCard: CIImage?
    private var breakShown = -1
    private var signText = Wording.sign
    private var sign = CIImage(cgImage: Card.draw(Wording.sign))
    private var signUpAt = 0.0
    private var signDownAt: Double?
    /// How long the sign takes to drop into place; the knock of wood is timed to this.
    static let signFall = 0.42
    private var cloneMix: CGFloat = 0     // 0 = just the person, 1 = the clones fully out
    private var branch = "", lastDebug = 0.0
    private var burstStart: Double?
    private static let burstTime = 2.6
    private static let hangTime = 1.1
    private var clock = 0.0, activatedAt = 0.0
    private var anchor: (x: CGFloat, top: CGFloat)?
    private let puff = CIImage(cgImage: Smoke.draw())
    private var spot: (x: CGFloat, top: CGFloat)?   // where the person is, smoothed, normalized, y up

    /// Share of the frame the person covers, for the log line.
    private(set) var personArea: CGFloat = 0

    /// True while any of the log is on screen (including the fade back to the person).
    /// True while what is on screen is built from the person mask (the sign is not).
    var usesMask: Bool { mix > 0 || cloneMix > 0 || spotMix > 0 }

    var isShowing: Bool { mix > 0 || cloneMix > 0 || awayMix > 0 || overlaysShowing || burstStart != nil }
    private var overlaysShowing: Bool { questionMix > 0 || spotMix > 0 || breakMix > 0 || confettiAt != nil }

    /// True once a filter that ends by itself (the confetti, the break) has run its course.
    private(set) var expired = false

    func render(frame: CVPixelBuffer, mask: CVPixelBuffer?, look: Look, resetPlate: Bool, now: Double, captions: [Rotulos.Showing] = []) -> CVPixelBuffer {
        let active = look == .trunk
        let w = CVPixelBufferGetWidth(frame), h = CVPixelBufferGetHeight(frame)
        if size != CGSize(width: w, height: h) { resize(w, h) }
        let extent = CGRect(x: 0, y: 0, width: w, height: h)
        let image = CIImage(cvPixelBuffer: frame)
        let space = CVBufferCopyAttachments(frame, .shouldPropagate).flatMap { CVImageBufferCreateColorSpaceFromAttachments($0)?.takeRetainedValue() }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!

        // The person mask, grown a little so no outline of the person survives.
        var person: CIImage?, keepOut: CIImage?, outline: CIImage?
        if let mask {
            let found = locate(mask)
            personArea = found?.area ?? 0
            if let found {
                let k: CGFloat = spot == nil ? 1 : 0.25
                spot = (x: (spot?.x ?? found.x) + (found.x - (spot?.x ?? found.x)) * k,
                        top: (spot?.top ?? found.top) + (found.top - (spot?.top ?? found.top)) * k)
            } else {
                spot = nil
            }
            let small = CIImage(cvPixelBuffer: mask)
            func grown(_ radius: Double) -> CIImage {
                small.clampedToExtent()
                    .applyingFilter("CIMorphologyMaximum", parameters: ["inputRadius": radius])
                    .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 1.5])
                    // Push the mask to exactly 0 or 1 away from its edge. Vision's "certainly a person" is often
                    // 0.97, not 1, and that sliver let the live frame seep into the plate on every frame.
                    .applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 4, y: 0, z: 0, w: 0),
                                                                  "inputBiasVector": CIVector(x: -0.6, y: 0, z: 0, w: 0)])
                    .applyingFilter("CIColorClamp")
                    .cropped(to: small.extent)
                    .transformed(by: CGAffineTransform(scaleX: CGFloat(w) / small.extent.width, y: CGFloat(h) / small.extent.height))
            }
            person = grown(5)
            // For cutting the person out to make clones: the mask as it is, only firmed up at the edge.
            outline = small.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 0.8])
                .applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 3, y: 0, z: 0, w: 0),
                                                              "inputBiasVector": CIVector(x: -1, y: 0, z: 0, w: 0)])
                .applyingFilter("CIColorClamp")
                .cropped(to: small.extent)
                .transformed(by: CGAffineTransform(scaleX: CGFloat(w) / small.extent.width, y: CGFloat(h) / small.extent.height))
            keepOut = grown(9)   // wider still for learning, so hair, hands and soft shadows never get into the plate
        }

        if resetPlate, let shot = makeBuffer() {
            context.render(image, to: shot, bounds: extent, colorSpace: space)
            captured = shot
            capturedWithPerson = personArea > 0.02
        }

        // Learn the background.
        if let spare, resetPlate || keepOut != nil {
            let old = plate.map { stored($0, space) } ?? CIImage.empty()
            let next: CIImage
            if resetPlate {
                next = image
            } else {
                next = old.applyingFilter("CIBlendWithRedMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: keepOut!])
            }
            context.render(next.cropped(to: extent), to: spare, bounds: extent, colorSpace: space)
            self.spare = plate ?? makeBuffer()
            plate = spare
        }

        // Fade between the two.
        let dt = lastTime == 0 ? 0 : min(0.1, now - lastTime)
        lastTime = now
        let step = CGFloat(dt / 0.25)
        mix = active ? min(1, mix + step) : max(0, mix - step)
        questionMix = look == .question ? min(1, questionMix + step) : max(0, questionMix - step)
        spotMix = look == .spotlight ? min(1, spotMix + step * 0.6) : max(0, spotMix - step * 0.6)
        breakMix = look == .breakTime ? min(1, breakMix + step) : max(0, breakMix - step)
        awayMix = look == .away ? min(1, awayMix + step) : max(0, awayMix - step * 0.45)   // slower out: the sign needs time to fall over
        cloneMix = look == .clones ? min(1, cloneMix + step * 0.5) : max(0, cloneMix - step)

        // A puff of smoke every time the switch flips, either way.
        clock = now
        if look != lastLook {
            // Smoke for the jutsus only: the sign just fades in and out.
            if look.hasSmoke || lastLook.hasSmoke { burstStart = now }
            if look == .question { questionAt = now }
            if look == .breakTime { breakAt = now }
            confettiAt = look == .confetti ? now : nil
            if look == .away { signUpAt = now; signDownAt = nil } else if lastLook == .away { signDownAt = now }
            lastLook = look
            if look == .trunk { activatedAt = now; anchor = spot ?? (x: 0.5, top: 0.75) }
        }
        var burst: CGFloat?
        if let start = burstStart {
            let t = CGFloat((now - start) / Self.burstTime)
            if t < 1 { burst = t } else { burstStart = nil }
        }

        expired = (look == .confetti && now - (confettiAt ?? now) > Overlays.confettiTime)
            || (look == .breakTime && now - breakAt > Wording.breakTime + Overlays.backTime)
        guard mix > 0 || cloneMix > 0 || awayMix > 0 || overlaysShowing || burst != nil, let pool else { return frame }
        var out: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
        guard let out else { return frame }

        var scene = image
        branch = cloneMix > 0 ? "clones" : mix > 0 ? (captured != nil ? "capturado" : (person != nil && plate != nil ? "aprendido" : "nada")) : "humo"
        if mix > 0, let captured {
            var hidden = stored(captured, space)
            if let log = placedTrunk(w, h) { hidden = log.composited(over: hidden) }
            scene = mix < 1 ? image.applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: hidden, kCIInputTimeKey: mix]) : hidden
        } else if mix > 0, let person, let plate {
            // The room without the person: what has been seen of it, and for what has not, the seen pixels around it
            // spread inwards, finest first. The live frame is never used to fill: it has the person in it.
            let seen = stored(plate, space)
            func spread(_ factor: CGFloat, _ radius: Double) -> CIImage {
                seen.transformed(by: CGAffineTransform(scaleX: 1 / factor, y: 1 / factor))
                    .clampedToExtent()
                    .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": radius])
                    // Stretch the coverage to opaque, dropping the faintest traces: their colour is rounding noise.
                    .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 40),
                                                                  "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: -0.4)])
                    .applyingFilter("CIColorClamp")
                    .transformed(by: CGAffineTransform(scaleX: factor, y: factor))
            }
            let room = seen.composited(over: spread(4, 6)).composited(over: spread(8, 10)).composited(over: spread(16, 14))
                .composited(over: spread(32, 40)).cropped(to: extent)

            var hidden = room.applyingFilter("CIBlendWithRedMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: person])
            if let log = placedTrunk(w, h) { hidden = log.composited(over: hidden) }
            scene = mix < 1 ? image.applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: hidden, kCIInputTimeKey: mix]) : hidden
        }
        if cloneMix > 0, let outline {
            scene = clones(of: scene, outline: outline, extent: extent)
        }
        if spotMix > 0, let outline {
            // The person as they are; everything else greyed and dimmed.
            let dull = scene.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.12, kCIInputBrightnessKey: -0.2, kCIInputContrastKey: 0.9])
            let lit = scene.applyingFilter("CIBlendWithRedMask", parameters: [kCIInputBackgroundImageKey: dull, kCIInputMaskImageKey: outline])
            scene = spotMix < 1 ? scene.applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: lit, kCIInputTimeKey: spotMix]) : lit
        }
        if breakMix > 0 {
            let total = Wording.breakTime
            let left = Int((total - (now - breakAt)).rounded(.up))
            if breakCard == nil || breakShown != left || breakCard!.extent.size != extent.size {
                breakCard = Overlays.breakCard(w, h, left: left, of: total); breakShown = left
            }
            let card = breakCard!.composited(over: dimmed(scene, extent))
            scene = breakMix < 1 ? scene.applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: card, kCIInputTimeKey: breakMix]) : card
        }
        if awayMix > 0 {
            if signText != Wording.sign { signText = Wording.sign; sign = CIImage(cgImage: Card.draw(signText)) }
            // Whatever is in front of the camera, blurred beyond recognition and dimmed, with the sign over it.
            let dim = dimmed(scene, extent)
            var away = dim
            if let placed = placedSign(w, h, now) { away = placed.composited(over: dim) }
            scene = awayMix < 1 ? scene.applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: away, kCIInputTimeKey: awayMix]) : away
        }
        if questionMix > 0 {
            // The bubble grows out of its tail with a little overshoot, then bobs. It sits in the upper corner
            // on the side the person is not on.
            if bubbleText != Wording.question { bubbleText = Wording.question; bubble = Overlays.bubble(bubbleText) }
            let t = CGFloat(now - questionAt), p = min(1, t / 0.4)
            let grow = p < 1 ? 1 + 2.7 * (p - 1) * (p - 1) * (p - 1) + 1.7 * (p - 1) * (p - 1) : 1
            let scale = CGFloat(w) * 0.4 / Overlays.bubbleSize.width * max(0.02, grow)
            let onLeft = (spot?.x ?? 0.3) > 0.5
            let tip = CGPoint(x: CGFloat(w) * (onLeft ? 0.25 : 0.75), y: CGFloat(h) * 0.52 + sin(t * 2.4) * CGFloat(h) * 0.008)
            let placed = bubble.transformed(by: CGAffineTransform(translationX: -Overlays.bubbleTip.x, y: -Overlays.bubbleTip.y)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: tip.x, y: tip.y)))
            let shown = placed.composited(over: scene).cropped(to: extent)
            scene = questionMix < 1 ? scene.applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: shown, kCIInputTimeKey: questionMix]) : shown
        }
        if let started = confettiAt, now - started <= Overlays.confettiTime {
            scene = Overlays.confetti(w, h, t: now - started, word: Wording.cheer).composited(over: scene)
        }
        if let burst {
            let centre = CGPoint(x: (spot?.x ?? 0.5) * CGFloat(w), y: (spot?.top ?? 0.8) * 0.55 * CGFloat(h))
            scene = smoke(over: scene, t: burst, centre: centre, reach: hypot(CGFloat(w), CGFloat(h)) * 0.62)
        }
        // The captions go over everything, effects included.
        if !captions.isEmpty { scene = Rotulos.apply(captions, to: scene, extent: extent, now: now) }
        context.render(scene.cropped(to: extent), to: out, bounds: extent, colorSpace: space)
        if ProcessInfo.processInfo.environment["KAWARU_DEBUG"] != nil, now - lastDebug > 1 {
            lastDebug = now
            func centre(_ b: CVPixelBuffer?) -> String {
                guard let b else { return "-" }
                CVPixelBufferLockBaseAddress(b, .readOnly); defer { CVPixelBufferUnlockBaseAddress(b, .readOnly) }
                let p = CVPixelBufferGetBaseAddress(b)!.assumingMemoryBound(to: UInt8.self) + (h * 2 / 3) * CVPixelBufferGetBytesPerRow(b) + Int((spot?.x ?? 0.5) * CGFloat(w)) * 4
                return "\(p[2]),\(p[1]),\(p[0]),\(p[3])"
            }
            print("debug: rama=\(branch) mix=\(mix) \(w)x\(h) entrada=\(centre(frame)) salida=\(centre(out)) capturado=\(centre(captured)) aprendido=\(centre(plate))"); fflush(stdout)
        }
        if let attachments = CVBufferCopyAttachments(frame, .shouldPropagate) {
            CVBufferSetAttachments(out, attachments, .shouldPropagate)
        }
        return out
    }

    /// Whatever is in front of the camera, blurred beyond recognition and darkened: the backdrop for a card.
    private func dimmed(_ scene: CIImage, _ extent: CGRect) -> CIImage {
        scene.transformed(by: CGAffineTransform(scaleX: 0.125, y: 0.125)).clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 9.0])
            .applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 0.38, y: 0, z: 0, w: 0),
                                                          "inputGVector": CIVector(x: 0, y: 0.38, z: 0, w: 0),
                                                          "inputBVector": CIVector(x: 0, y: 0, z: 0.38, w: 0)])
            .transformed(by: CGAffineTransform(scaleX: 8, y: 8)).cropped(to: extent)
    }

    /// The sign, where the animation has it at `now`: it drops in from above, lands with a couple of bounces and
    /// a wobble, and when it is dismissed it keels over and falls out of the bottom of the frame.
    private func placedSign(_ w: Int, _ h: Int, _ now: Double) -> CIImage? {
        let W = CGFloat(w), H = CGFloat(h)
        let scale = H * 0.97 / Card.size.height
        var lift: CGFloat = 0, turn: CGFloat = 0
        if let down = signDownAt {
            let t = CGFloat(now - down)
            turn = -1.5 * t * t * 4          // keels over to the right, faster and faster
            lift = -H * 2.2 * t * t
        } else {
            let t = CGFloat(now - signUpAt), fall = CGFloat(Self.signFall)
            if t < fall {
                lift = H * 1.2 * (1 - (t / fall) * (t / fall))
                turn = 0.07
            } else {
                let u = t - fall
                lift = H * 0.07 * exp(-6 * u) * abs(cos(12 * u))
                turn = 0.07 * exp(-5 * u) * cos(10 * u)
            }
        }
        let t = CGAffineTransform(translationX: -Card.foot.x, y: -Card.foot.y)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(rotationAngle: turn))
            .concatenating(CGAffineTransform(translationX: W / 2, y: Card.foot.y * scale - H * 0.035 + lift))
        return sign.transformed(by: t)
    }

    /// Copies of the person to both sides, behind the real one. They slide out from where the person is, the
    /// far pair smaller, as if standing further back, and they follow every movement because they are cut from
    /// the same live frame.
    private func clones(of scene: CIImage, outline: CIImage, extent: CGRect) -> CIImage {
        let cut = scene.applyingFilter("CIBlendWithRedMask", parameters: [kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: extent),
                                                                             kCIInputMaskImageKey: outline])
        let ease = 1 - pow(1 - cloneMix, 3)
        let x = (spot?.x ?? 0.5) * extent.width
        var result = scene
        for (shift, size) in [(-0.46, 0.74), (0.46, 0.74), (-0.25, 0.87), (0.25, 0.87)] as [(CGFloat, CGFloat)] {
            let k = 1 - (1 - size) * ease
            // Shrunk towards the person's feet at the bottom edge, then moved sideways.
            let t = CGAffineTransform(translationX: -x, y: 0)
                .concatenating(CGAffineTransform(scaleX: k, y: k))
                .concatenating(CGAffineTransform(translationX: x + shift * extent.width * ease, y: 0))
            result = cut.transformed(by: t).composited(over: result)
        }
        return cut.composited(over: result).cropped(to: extent)
    }

    /// One of our own buffers, read back in the colour space it was written in. They carry no colour tags, so
    /// without this Core Image takes them for sRGB and converts them again on the way out. For the plate, which
    /// is read and rewritten on every frame, that small shift piled up until the room turned black.
    private func stored(_ buffer: CVPixelBuffer, _ space: CGColorSpace) -> CIImage {
        CIImage(cvPixelBuffer: buffer, options: [.colorSpace: space])
    }

    /// The log where the person was when the seal landed: leaning, from below the bottom edge up to just over the
    /// head. It hangs there for a moment, then topples and drops out of the frame; after that there is no log.
    private func placedTrunk(_ w: Int, _ h: Int) -> CIImage? {
        guard let anchor else { return nil }
        let fall = CGFloat(max(0, clock - activatedAt - Self.hangTime))
        let drop = 2.6 * fall * fall * CGFloat(h)            // gravity, in frame heights
        guard drop < 2.2 * CGFloat(h) else { return nil }
        let topY = max(0.25, min(1.05, anchor.top * 1.04 + 0.03)) * CGFloat(h), baseY = -0.12 * CGFloat(h)
        let scale = (topY - baseY) / Trunk.size.height
        let t = CGAffineTransform(translationX: -260, y: -Trunk.size.height / 2)   // 260: the cylinder's axis in the drawing
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(rotationAngle: -0.17 - 1.9 * fall * fall))
            .concatenating(CGAffineTransform(translationX: anchor.x * CGFloat(w) + 0.25 * fall * CGFloat(w), y: (topY + baseY) / 2 - drop))
        return trunk.transformed(by: t)
    }

    /// Clouds that burst out from `centre`, turning as they go, and fade. `t` runs 0...1.
    private func smoke(over scene: CIImage, t: CGFloat, centre: CGPoint, reach: CGFloat) -> CIImage {
        let ease = 1 - pow(1 - t, 4)
        let alpha = t < 0.5 ? 1 : max(0, 1 - (t - 0.5) / 0.5)
        var result = scene
        func add(angle: CGFloat, distance: CGFloat, size: CGFloat, turn: CGFloat, alpha: CGFloat) {
            guard alpha > 0.01 else { return }
            let k = size * reach / Smoke.size
            let tr = CGAffineTransform(translationX: -Smoke.size / 2, y: -Smoke.size / 2)
                .concatenating(CGAffineTransform(rotationAngle: turn))
                .concatenating(CGAffineTransform(scaleX: k, y: k))
                .concatenating(CGAffineTransform(translationX: centre.x + cos(angle) * distance * reach, y: centre.y + sin(angle) * distance * reach))
            result = puff.transformed(by: tr)
                .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)])
                .composited(over: result)
        }
        // Three rings of clouds that fly apart until they reach the edges of the frame, so the middle clears first.
        for i in 0..<24 {
            let f = CGFloat(i)
            let wobble = sin(f * 12.9898) * 0.5 + 0.5   // 0...1, fixed per cloud
            let ring = CGFloat(i % 3)                    // 0 stays nearest, 2 goes furthest
            add(angle: f * 2.39996 + wobble * 0.4, distance: 0.08 + ease * (0.42 + 0.3 * ring) * (0.85 + wobble * 0.3),
                size: (0.5 + wobble * 0.35) * (0.45 + 0.75 * ease), turn: f * 1.3 + t * (wobble - 0.5) * 3, alpha: alpha)
        }
        // The big one in the middle, which hides the swap itself.
        add(angle: 0, distance: 0, size: 0.8 + 0.7 * ease, turn: t * 0.6, alpha: t < 0.12 ? 1 : max(0, 1 - (t - 0.12) / 0.2))
        return result
    }

    private func resize(_ w: Int, _ h: Int) {
        size = CGSize(width: w, height: h)
        let attrs: [CFString: Any] = [kCVPixelBufferWidthKey: w, kCVPixelBufferHeightKey: h,
                                      kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                                      kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
        var p: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &p)
        pool = p
        plate = nil
        captured = nil
        spare = makeBuffer()
        spot = nil
    }

    private func makeBuffer() -> CVPixelBuffer? {
        guard let pool else { return nil }
        var b: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &b)
        return b
    }

    /// Where the person is in the mask: horizontal centre of mass and top of the head.
    private func locate(_ mask: CVPixelBuffer) -> (x: CGFloat, top: CGFloat, area: CGFloat)? {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let w = CVPixelBufferGetWidth(mask), h = CVPixelBufferGetHeight(mask), stride = CVPixelBufferGetBytesPerRow(mask)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var count = 0, sumX = 0, topRow = -1
        for y in 0..<h {
            let row = bytes + y * stride
            var inRow = 0
            for x in 0..<w where row[x] > 127 { inRow += 1; sumX += x }
            count += inRow
            if topRow < 0, inRow >= max(4, w / 40) { topRow = y }
        }
        let area = CGFloat(count) / CGFloat(w * h)
        guard area > 0.02, topRow >= 0 else { return nil }
        return (CGFloat(sumX) / CGFloat(count) / CGFloat(w), 1 - CGFloat(topRow) / CGFloat(h), area)
    }
}
