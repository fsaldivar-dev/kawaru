import CoreGraphics
import Foundation
import Vision

/// One hand as Vision sees it, made comparable: every joint relative to the wrist and measured in palm lengths,
/// so the same position matches at any distance from the camera and anywhere in the frame.
struct HandShape {
    static let joints: [VNHumanHandPoseObservation.JointName] = [
        .wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip, .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip, .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip,
    ]

    var points: [CGPoint?]     // one per joint above; nil where Vision was not confident
    var centre: CGPoint        // in the frame, x already multiplied by the aspect ratio
    var palm: CGFloat

    init?(_ observation: VNHumanHandPoseObservation, aspect: CGFloat) {
        guard let all = try? observation.recognizedPoints(.all) else { return nil }
        func p(_ j: VNHumanHandPoseObservation.JointName) -> CGPoint? {
            guard let v = all[j], v.confidence > 0.2 else { return nil }
            return CGPoint(x: v.location.x * aspect, y: v.location.y)
        }
        guard let wrist = p(.wrist), let knuckle = p(.middleMCP) else { return nil }
        let size = hypot(wrist.x - knuckle.x, wrist.y - knuckle.y)
        guard size > 0.02 else { return nil }
        palm = size
        centre = CGPoint(x: (wrist.x + knuckle.x) / 2, y: (wrist.y + knuckle.y) / 2)
        points = Self.joints.map { j in p(j).map { CGPoint(x: ($0.x - wrist.x) / size, y: ($0.y - wrist.y) / size) } }
    }

    init(points: [CGPoint?], centre: CGPoint, palm: CGFloat) { self.points = points; self.centre = centre; self.palm = palm }

    /// Several frames of the same hands averaged into one. Vision's joints jitter from frame to frame, more so
    /// with fingers half hidden by the face; a recorded position is itself an average, so the live hand is
    /// compared the same way. `frames` are the last few, each with its hands ordered left to right.
    static func steadied(_ frames: [[HandShape]]) -> [HandShape] {
        guard let latest = frames.last, !latest.isEmpty else { return [] }
        let same = frames.filter { $0.count == latest.count }
        return latest.indices.map { i in
            let points: [CGPoint?] = joints.indices.map { j in
                let known = same.compactMap { $0[i].points[j] }
                guard known.count * 2 >= same.count else { return nil }
                return CGPoint(x: known.map(\.x).reduce(0, +) / CGFloat(known.count), y: known.map(\.y).reduce(0, +) / CGFloat(known.count))
            }
            return HandShape(points: points, centre: latest[i].centre, palm: latest[i].palm)
        }
    }

    /// The same hand seen in a mirror: what the other hand looks like doing the same thing.
    var mirrored: HandShape { HandShape(points: points.map { $0.map { CGPoint(x: -$0.x, y: $0.y) } }, centre: centre, palm: palm) }

    /// Mean distance between matching joints, in palm lengths. Infinite when too few joints are known in both.
    static func distance(_ a: [CGPoint?], _ b: [CGPoint?]) -> CGFloat {
        var sum: CGFloat = 0, n = 0
        for (p, q) in zip(a, b) {
            guard let p, let q else { continue }
            sum += hypot(p.x - q.x, p.y - q.y); n += 1
        }
        return n >= 14 ? sum / CGFloat(n) : .infinity
    }

    /// The same, for the finger that differs most. The overall mean alone lets one finger be completely wrong
    /// (three fingers up passed for two), because twenty other joints agree.
    static func worstFinger(_ a: [CGPoint?], _ b: [CGPoint?]) -> CGFloat {
        var worst: CGFloat = 0
        for finger in 0..<5 {
            var sum: CGFloat = 0, n = 0
            for j in (1 + finger * 4)...(4 + finger * 4) {
                guard let p = a[j], let q = b[j] else { continue }
                sum += hypot(p.x - q.x, p.y - q.y); n += 1
            }
            if n >= 2 { worst = max(worst, sum / CGFloat(n)) }
        }
        return worst
    }

    /// The live hand turned and resized about the wrist to lie as close to the template as it can, within
    /// limits. Nobody holds a hand at exactly the angle they recorded it, and tipping it towards the camera
    /// shortens the palm everything is measured in; without this, real attempts at a recorded position came
    /// out two or three times too far to match (seen in the log). The limits keep "fingers up" from passing
    /// for "fingers sideways".
    static func fitted(_ template: [CGPoint?], _ live: [CGPoint?]) -> [CGPoint?] {
        var dot: CGFloat = 0, cross: CGFloat = 0, sizeT: CGFloat = 0, sizeL: CGFloat = 0
        for (t, l) in zip(template, live) {
            guard let t, let l else { continue }
            dot += l.x * t.x + l.y * t.y; cross += l.x * t.y - l.y * t.x
            sizeT += t.x * t.x + t.y * t.y; sizeL += l.x * l.x + l.y * l.y
        }
        guard sizeL > 0, sizeT > 0 else { return live }
        let turn = max(-0.6, min(0.6, atan2(cross, dot)))               // about 35 degrees either way
        let scale = max(0.75, min(1.3, (sizeT / sizeL).squareRoot()))
        let c = cos(turn) * scale, s = sin(turn) * scale
        return live.map { $0.map { CGPoint(x: $0.x * c - $0.y * s, y: $0.x * s + $0.y * c) } }
    }

    static func fits(_ template: [CGPoint?], _ live: [CGPoint?], tolerance: CGFloat) -> Bool {
        let live = fitted(template, live)
        return distance(template, live) < tolerance && worstFinger(template, live) < tolerance * 1.45
    }
}

/// A hand position someone recorded: the shape of one or two hands, how far apart they were, and, when the
/// hand was by the face, where it was relative to it.
struct PoseTemplate: Codable, Equatable {
    var hands: [[[Double]?]]      // per hand, per joint: [x, y] or null
    var gap: [Double]?            // second hand's centre minus the first's, in palm lengths
    var faceOffset: [Double]?     // first hand's centre minus the face's, in face widths
    var tolerance: Double

    private func shape(_ i: Int) -> [CGPoint?] { hands[i].map { $0.map { CGPoint(x: $0[0], y: $0[1]) } } }

    /// Does what is in front of the camera now match? Either hand may be used: the mirror image counts too.
    /// `slack` above 1 loosens the match: used to hold on to a position that was matching a moment ago, so a
    /// frame or two of jitter does not drop it.
    func matches(_ live: [HandShape], face: CGRect?, aspect: CGFloat, slack: CGFloat = 1) -> Bool {
        let ordered = live.sorted { $0.centre.x < $1.centre.x }
        return matches(ordered, face, aspect, flip: 1, slack: slack) || matches(ordered.reversed().map(\.mirrored), face, aspect, flip: -1, slack: slack)
    }

    /// How strict a match is: what was measured while recording, kept between a floor and a ceiling. A very
    /// steady first take used to come out at 0.20, which the same person rarely met again (seen in the log:
    /// real attempts sit near 0.2 and other positions from 0.4 up, so 0.30 to 0.36 separates them).
    var strictness: Double { min(max(tolerance, Self.tightest), Self.loosest) }
    static let tightest = 0.30

    /// How far the hands are from this position, for the log: joint distance, worst finger, and distance from
    /// the recorded place by the face (0 when the position is not tied to the face). Nil when the number of
    /// hands differs. One-hand positions only measure the closest hand.
    func closeness(_ live: [HandShape], face: CGRect?, aspect: CGFloat) -> (joints: CGFloat, finger: CGFloat, place: CGFloat)? {
        guard live.count == hands.count, !live.isEmpty else { return nil }
        var best: (joints: CGFloat, finger: CGFloat, place: CGFloat)?
        for flip in [CGFloat(1), -1] {
            let ordered = live.sorted { $0.centre.x < $1.centre.x }
            let set = flip == 1 ? ordered : ordered.reversed().map(\.mirrored)
            for (i, hand) in set.enumerated() {
                let template = shape(hands.count == 2 ? i : 0)
                var place: CGFloat = 0
                if hands.count == 1, let faceOffset {
                    if let face {
                        let width = face.width * aspect
                        place = hypot((hand.centre.x - face.midX * aspect) * flip / width - faceOffset[0], (hand.centre.y - face.midY) / width - faceOffset[1])
                    } else { place = 9 }
                }
                let turned = HandShape.fitted(template, hand.points)
                let found = (joints: HandShape.distance(template, turned), finger: HandShape.worstFinger(template, turned), place: place)
                if best == nil || found.joints < best!.joints { best = found }
            }
        }
        return best
    }

    /// Roughly this position: the same number of hands in something like the same shape, wherever they are.
    /// Used while the user repeats a position to teach its variations, where asking for an exact match would
    /// only teach the first take again.
    func resembles(_ live: [HandShape], aspect: CGFloat) -> Bool {
        guard let near = closeness(live, face: nil, aspect: aspect) else { return false }
        return near.joints < 0.6
    }

    /// Upper limit on how loose a match may be, whatever was measured while recording. The first real recordings
    /// all came out at the old limit of 0.5, and at that a one-hand position passed for almost any hand.
    static let loosest = 0.36

    /// In words, what was recorded: for showing next to the command.
    var summary: String {
        hands.count == 2 ? "Dos manos" : (faceOffset != nil ? "Una mano, junto a la cara" : "Una mano")
    }

    private func matches(_ live: [HandShape], _ face: CGRect?, _ aspect: CGFloat, flip: CGFloat, slack: CGFloat) -> Bool {
        let tolerance = CGFloat(strictness) * slack
        // The number of hands is part of the position: one hand recorded means one hand showing, so a one-hand
        // position does not go off in the middle of a two-hand one.
        guard live.count == hands.count else { return false }
        if hands.count == 2 {
            guard let gap else { return false }
            let fit = HandShape.fits(shape(0), live[0].points, tolerance: tolerance * 1.15) && HandShape.fits(shape(1), live[1].points, tolerance: tolerance * 1.15)
            let dx = (live[1].centre.x - live[0].centre.x) * flip / live[0].palm, dy = (live[1].centre.y - live[0].centre.y) / live[0].palm
            return fit && hypot(dx - gap[0], dy - gap[1]) < 1.2 * slack
        }
        return live.contains { hand in
            guard HandShape.fits(shape(0), hand.points, tolerance: tolerance) else { return false }
            guard let faceOffset else { return true }
            guard let face else { return false }
            let width = face.width * aspect
            let dx = (hand.centre.x - face.midX * aspect) * flip / width, dy = (hand.centre.y - face.midY) / width
            return hypot(dx - faceOffset[0], dy - faceOffset[1]) < 0.9 * slack
        }
    }

    /// Builds a template from about a second of frames with the position held still. Nil when the hands were
    /// not seen steadily enough.
    static func make(from samples: [(hands: [HandShape], face: CGRect?)], aspect: CGFloat, atLeast: Int = 8) -> PoseTemplate? {
        let seen = samples.filter { !$0.hands.isEmpty }
        guard seen.count >= atLeast else { return nil }
        let count = seen.filter { $0.hands.count >= 2 }.count * 2 > seen.count ? 2 : 1
        let used = seen.filter { $0.hands.count >= count }.map { (hands: Array($0.hands.sorted { $0.centre.x < $1.centre.x }.prefix(count)), face: $0.face) }
        guard used.count >= atLeast else { return nil }

        var shapes: [[CGPoint?]] = []
        for i in 0..<count {
            shapes.append((0..<HandShape.joints.count).map { j in
                let known = used.compactMap { $0.hands[i].points[j] }
                guard known.count * 2 >= used.count else { return nil }
                return CGPoint(x: known.map(\.x).reduce(0, +) / CGFloat(known.count), y: known.map(\.y).reduce(0, +) / CGFloat(known.count))
            })
        }
        // How much the hand wavered while recording sets how strict the match is, within sensible limits.
        let wobble = used.map { s in (0..<count).map { HandShape.distance(shapes[$0], s.hands[$0].points) }.max() ?? 0 }.filter { $0.isFinite }
        guard wobble.count * 2 >= used.count else { return nil }
        let spread = wobble.reduce(0, +) / CGFloat(wobble.count)
        var template = PoseTemplate(hands: shapes.map { $0.map { $0.map { [Double($0.x), Double($0.y)] } } }, gap: nil, faceOffset: nil,
                                    tolerance: min(loosest, max(0.2, Double(spread) * 1.6 + 0.08)))
        func mean(_ v: [CGPoint]) -> [Double] { [Double(v.map(\.x).reduce(0, +)) / Double(v.count), Double(v.map(\.y).reduce(0, +)) / Double(v.count)] }
        if count == 2 {
            template.gap = mean(used.map { CGPoint(x: ($0.hands[1].centre.x - $0.hands[0].centre.x) / $0.hands[0].palm,
                                                   y: ($0.hands[1].centre.y - $0.hands[0].centre.y) / $0.hands[0].palm) })
        } else {
            let byFace = used.compactMap { s -> CGPoint? in
                guard let f = s.face else { return nil }
                let width = f.width * aspect
                return CGPoint(x: (s.hands[0].centre.x - f.midX * aspect) / width, y: (s.hands[0].centre.y - f.midY) / width)
            }
            // Only a hand held by the face is tied to it; anywhere else, the position is free to move.
            if byFace.count * 10 >= used.count * 7 {
                let offset = mean(byFace)
                if hypot(offset[0], offset[1]) < 1.5 { template.faceOffset = offset }
            }
        }
        return template
    }
}
