import CoreGraphics
import Vision

/// The hand positions Kawaru can read. Each effect is tied to one of them in the Commands window.
enum Gesture: String, CaseIterable, Identifiable {
    case none, browFingers, salute, twoFingers, openPalm, thumbsUp, seal, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: tr("Ninguno")
        case .browFingers: tr("Dos dedos en la frente")
        case .salute: tr("Saludo militar")
        case .twoFingers: tr("Dos dedos arriba")
        case .openPalm: tr("Palma abierta")
        case .thumbsUp: tr("Pulgar arriba")
        case .seal: tr("Sello a dos manos")
        case .custom: tr("Posición grabada")
        }
    }

    /// A stand-in picture of the position, until there is drawn artwork for each one.
    var symbol: String {
        switch self {
        case .none: "🚫"
        case .browFingers: "✌️🙂"
        case .salute: "🫡"
        case .twoFingers: "✌️"
        case .openPalm: "✋"
        case .thumbsUp: "👍"
        case .seal: "🙏"
        case .custom: "⏺️"
        }
    }

    /// Read against the face, so the face has to be looked for while a command uses it.
    var needsFace: Bool { self == .salute || self == .browFingers }

    var hint: String {
        switch self {
        case .none: tr("Este efecto no se activa con las manos.")
        case .browFingers: tr("Índice y medio juntos tocando la frente o la sien; los demás dedos doblados.")
        case .salute: tr("La mano extendida junto a la frente, como un saludo de general.")
        case .twoFingers: tr("Índice y medio juntos hacia arriba; los demás dedos doblados.")
        case .openPalm: tr("La mano abierta hacia la cámara, con los cinco dedos separados y hacia arriba.")
        case .thumbsUp: tr("El puño cerrado con el pulgar hacia arriba.")
        case .seal: tr("Las dos manos juntas frente al pecho, con los dedos hacia arriba. Es el más difícil de leer.")
        case .custom: tr("La posición de manos que grabaste para este efecto.")
        }
    }
}

/// What Kawaru does to the picture.
enum Effect: String, CaseIterable, Identifiable {
    case substitution, clones, away, question, confetti, breakTime, spotlight

    var id: String { rawValue }

    /// What the picture shows while this effect is on.
    var look: Look {
        switch self {
        case .substitution: .trunk
        case .clones: .clones
        case .away: .away
        case .question: .question
        case .confetti: .confetti
        case .breakTime: .breakTime
        case .spotlight: .spotlight
        }
    }

    var title: String {
        switch self {
        case .substitution: tr("Jutsu de sustitución")
        case .clones: tr("Clones de sombra")
        case .away: tr("Cartel de ausencia")
        case .question: tr("Globo de pregunta")
        case .confetti: tr("Confeti")
        case .breakTime: tr("Descanso")
        case .spotlight: tr("Foco")
        }
    }

    var detail: String {
        switch self {
        case .substitution: tr("Desapareces en una nube de humo y queda un tronco que cae.")
        case .clones: tr("Aparecen copias tuyas a los lados, que se mueven contigo.")
        case .away: tr("Tapa la imagen con un cartel de madera mientras no estás.")
        case .question: tr("Un globo de diálogo sobre tu imagen, para pedir la palabra sin interrumpir.")
        case .confetti: tr("Lluvia de confeti y una palabra de ánimo durante unos segundos. Se quita solo.")
        case .breakTime: tr("Tapa la imagen con una cuenta atrás. Se quita sola al terminar.")
        case .spotlight: tr("Te deja a color y apaga el fondo, para pedir atención.")
        }
    }

    var defaultGesture: Gesture {
        switch self {
        case .substitution: .seal
        case .clones: .twoFingers
        case .away: .browFingers
        case .question: .openPalm
        case .confetti: .thumbsUp
        case .breakTime: .none
        case .spotlight: .none
        }
    }
}

/// A gesture has to be held for a moment before it counts. Hands flicker in and out of Vision from frame to
/// frame, so instead of asking for an unbroken hold, time with the gesture fills a meter and time without it
/// drains the meter at half speed. It fires once and re-arms after the hand lets go.
struct HoldMeter {
    static let holdTime = 0.6
    static let releaseTime = 0.5

    private var meter = 0.0
    private var last = 0.0
    private var lastSeen = 0.0
    private var armed = true

    /// 0...1, how full the meter is (for the interface).
    var progress: Double { armed ? min(1, meter / Self.holdTime) : 0 }

    /// Another gesture just fired: this one waits until its own hand position has been let go, so two effects
    /// whose positions overlap do not go off one after the other.
    mutating func standDown(now: Double) { armed = false; meter = 0; lastSeen = now }

    /// Returns true on the frame it fires. `near` is a looser reading of the same position: while the hands
    /// are still roughly there the gesture has not been let go, even if it stopped matching exactly, so it
    /// cannot fire a second time and undo itself.
    mutating func update(present: Bool, near: Bool? = nil, now: Double) -> Bool {
        let dt = last == 0 ? 0 : min(0.1, now - last)
        last = now
        if present || near == true { lastSeen = now }
        meter = present ? min(Self.holdTime, meter + dt) : max(0, meter - dt * 0.5)
        if armed {
            if meter >= Self.holdTime { armed = false; meter = 0; return true }
        } else {
            meter = 0
            if now - lastSeen > Self.releaseTime { armed = true }
        }
        return false
    }
}

enum GestureReader {
    /// One hand, reduced to what the tests below need. Distances are in palm lengths (wrist to middle knuckle).
    private struct Hand {
        var wrist: CGPoint, centre: CGPoint, palm: CGFloat
        var tips: [CGPoint?]        // thumb, index, middle, ring, little
        var straight: [Bool]        // same order
        var reach: [CGFloat]        // how far above the palm's centre each fingertip is
    }

    /// The gestures present in this frame. `face` is the face box in Vision's normalized coordinates (y up), if
    /// one was looked for; `aspect` is width / height of the frame, because those coordinates are per axis.
    static func read(hands: [VNHumanHandPoseObservation], face: CGRect?, aspect: CGFloat) -> Set<Gesture> {
        let read = hands.compactMap { hand($0, aspect) }
        var found = Set<Gesture>()
        func d(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

        // Two hands joined in front of the body, fingers up. Vision cannot tell which fingers are laced once the
        // hands touch (measured with the real camera), so joined, upright hands are the seal.
        if read.count == 2 {
            let gap = d(read[0].centre, read[1].centre) / max(read[0].palm, read[1].palm)
            if gap < 2.2, read.contains(where: { max($0.reach[1], $0.reach[2]) > 1.0 }) { found.insert(.seal) }
        }
        let joined = found.contains(.seal)

        for h in read {
            let fingersStraight = h.straight[1...4].filter { $0 }.count

            // By the forehead: fingertips at the upper half of the face or just beside it. Not while the hands are
            // joined: seen with the real camera, the seal held high was also read as a salute.
            if let face, !joined, let tip = h.tips[2] ?? h.tips[1] {
                let f = CGRect(x: face.minX * aspect, y: face.minY, width: face.width * aspect, height: face.height)
                let centre = CGPoint(x: f.midX, y: f.midY)
                let nearBrow = tip.y > f.midY - f.height * 0.1 && tip.y < f.maxY + f.height * 0.45
                    && tip.x > f.minX - f.width * 0.7 && tip.x < f.maxX + f.width * 0.7
                if nearBrow {
                    if h.straight[1], h.straight[2], !h.straight[3], !h.straight[4] {
                        // Index and middle out, the other two folded.
                        found.insert(.browFingers)
                    } else if fingersStraight >= 3, d(h.wrist, centre) > d(tip, centre) + h.palm * 0.5, abs(h.wrist.x - f.midX) > f.width * 0.45 {
                        // The whole hand flat, the wrist further from the face than the fingertips.
                        found.insert(.salute)
                    }
                    continue   // a hand at the forehead is not also an open palm or two fingers up
                }
            }
            if joined { continue }

            let up = { (i: Int) in h.straight[i] && h.reach[i] > 1.0 }
            let folded = { (i: Int) in !h.straight[i] && h.reach[i] < 0.95 }
            if up(1), up(2), folded(3), folded(4), let a = h.tips[1], let b = h.tips[2], d(a, b) < h.palm * 0.5 {
                found.insert(.twoFingers)
            } else if up(1), up(2), up(3), up(4), h.straight[0] {
                found.insert(.openPalm)
            } else if h.straight[0], h.reach[0] > 0.9, folded(1), folded(2), folded(3), folded(4) {
                found.insert(.thumbsUp)
            }
        }
        return found
    }

    /// What to change to get `gesture` read, for someone practising it. Nil when there is nothing useful to say.
    static func advice(for gesture: Gesture, hands: [VNHumanHandPoseObservation], face: CGRect?, aspect: CGFloat) -> String? {
        let read = hands.compactMap { hand($0, aspect) }
        func d(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
        guard let h = read.first else { return tr("No veo tu mano. Súbela frente a la cámara.") }
        func nearBrow(_ h: Hand) -> Bool? {
            guard let face, let tip = h.tips[2] ?? h.tips[1] else { return nil }
            let f = CGRect(x: face.minX * aspect, y: face.minY, width: face.width * aspect, height: face.height)
            return tip.y > f.midY - f.height * 0.1 && tip.y < f.maxY + f.height * 0.45 && tip.x > f.minX - f.width * 0.7 && tip.x < f.maxX + f.width * 0.7
        }
        switch gesture {
        case .none: return nil
        case .seal:
            guard read.count == 2 else { return tr("Necesito ver las dos manos a la vez.") }
            if d(read[0].centre, read[1].centre) / max(read[0].palm, read[1].palm) >= 2.2 { return tr("Junta más las manos.") }
            return tr("Apunta los dedos hacia arriba.")
        case .browFingers:
            guard let near = nearBrow(h) else { return tr("No veo tu cara. Ponte de frente a la cámara.") }
            if !near { return tr("Acerca los dedos a la frente o a la sien.") }
            return tr("Estira solo índice y medio; dobla los otros dos.")
        case .salute:
            guard let near = nearBrow(h) else { return tr("No veo tu cara. Ponte de frente a la cámara.") }
            if !near { return tr("Lleva la punta de los dedos junto a la frente.") }
            if h.straight[1...4].filter({ $0 }).count < 3 { return tr("Estira toda la mano, con los dedos juntos.") }
            return tr("Pon la mano de lado, con el codo hacia afuera.")
        case .twoFingers:
            if nearBrow(h) == true { return tr("Aleja la mano de la cara.") }
            if h.straight[3] || h.straight[4] { return tr("Dobla el anular y el meñique.") }
            if !(h.straight[1] && h.straight[2]) { return tr("Estira el índice y el medio.") }
            if max(h.reach[1], h.reach[2]) <= 1.0 { return tr("Apunta los dos dedos hacia arriba.") }
            return tr("Junta los dos dedos.")
        case .openPalm:
            if nearBrow(h) == true { return tr("Aleja la mano de la cara.") }
            return tr("Abre la mano con los cinco dedos estirados hacia arriba.")
        case .custom: return tr("Repite la posición tal como la grabaste.")
        case .thumbsUp:
            if h.straight[1...4].contains(true) { return tr("Cierra el puño; solo el pulgar estirado.") }
            return tr("Apunta el pulgar hacia arriba.")
        }
    }

    private static func hand(_ observation: VNHumanHandPoseObservation, _ aspect: CGFloat) -> Hand? {
        guard let all = try? observation.recognizedPoints(.all) else { return nil }
        func p(_ j: VNHumanHandPoseObservation.JointName) -> CGPoint? {
            guard let v = all[j], v.confidence > 0.2 else { return nil }
            return CGPoint(x: v.location.x * aspect, y: v.location.y)
        }
        func d(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
        guard let wrist = p(.wrist), let knuckle = p(.middleMCP) else { return nil }
        let palm = d(wrist, knuckle)
        guard palm > 0.02 else { return nil }
        let centre = CGPoint(x: (wrist.x + knuckle.x) / 2, y: (wrist.y + knuckle.y) / 2)

        let joints: [(tip: VNHumanHandPoseObservation.JointName, mid: VNHumanHandPoseObservation.JointName, base: VNHumanHandPoseObservation.JointName)] = [
            (.thumbTip, .thumbIP, .thumbCMC), (.indexTip, .indexPIP, .indexMCP), (.middleTip, .middlePIP, .middleMCP),
            (.ringTip, .ringPIP, .ringMCP), (.littleTip, .littlePIP, .littleMCP),
        ]
        var tips: [CGPoint?] = [], straight: [Bool] = [], reach: [CGFloat] = []
        for (i, j) in joints.enumerated() {
            let tip = p(j.tip), mid = p(j.mid), base = p(j.base)
            tips.append(tip)
            if let tip, let mid, let base {
                // A straight finger ends well beyond its middle joint, seen from the wrist. The thumb is shorter.
                straight.append(d(tip, wrist) > d(mid, wrist) * (i == 0 ? 1.08 : 1.15) && d(tip, base) > palm * (i == 0 ? 0.5 : 0.6))
            } else {
                straight.append(false)
            }
            reach.append(tip.map { ($0.y - centre.y) / palm } ?? 0)
        }
        return Hand(wrist: wrist, centre: centre, palm: palm, tips: tips, straight: straight, reach: reach)
    }
}
