import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO

/// A caption laid over the video: a name plate, a banner, a badge or a full-screen card. Unlike the effects,
/// several can be up at once, and each is the user's own: their words, their theme, where and how it comes in.
struct Rotulo: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case lowerThird, banner, badge, card

        var id: String { rawValue }

        var title: String {
            switch self {
            case .lowerThird: "Tercio inferior"
            case .banner: "Banner"
            case .badge: "Insignia"
            case .card: "Tarjeta completa"
            }
        }

        var symbol: String {
            switch self {
            case .lowerThird: "person.text.rectangle"
            case .banner: "rectangle.topthird.inset.filled"
            case .badge: "tag"
            case .card: "rectangle.inset.filled"
            }
        }

        /// Where this kind can sit. The card fills the picture, so it has no choice.
        var places: [Place] {
            switch self {
            case .lowerThird: [.bottomLeft, .bottomRight, .topLeft, .topRight]
            case .banner: [.top, .bottom]
            case .badge: [.topRight, .topLeft, .bottomRight, .bottomLeft]
            case .card: []
            }
        }

        var hasSubtitle: Bool { self != .badge }

        /// What the two lines of text are called in the editor.
        var labels: (String, String) {
            switch self {
            case .lowerThird: ("Nombre", "Cargo o detalle")
            case .banner: ("Titular", "Texto")
            case .badge: ("Texto", "")
            case .card: ("Título", "Subtítulo")
            }
        }
    }

    enum Theme: String, Codable, CaseIterable, Identifiable {
        case minimal, corporate, neon, wood

        var id: String { rawValue }

        var title: String {
            switch self {
            case .minimal: "Minimal"
            case .corporate: "Corporativo"
            case .neon: "Neón"
            case .wood: "Madera"
            }
        }
    }

    enum Place: String, Codable, CaseIterable, Identifiable {
        case topLeft, top, topRight, bottomLeft, bottom, bottomRight

        var id: String { rawValue }

        var title: String {
            switch self {
            case .topLeft: "Arriba a la izquierda"
            case .top: "Arriba"
            case .topRight: "Arriba a la derecha"
            case .bottomLeft: "Abajo a la izquierda"
            case .bottom: "Abajo"
            case .bottomRight: "Abajo a la derecha"
            }
        }

        var isTop: Bool { self == .topLeft || self == .top || self == .topRight }
        var isLeft: Bool { self == .topLeft || self == .bottomLeft }
        var isRight: Bool { self == .topRight || self == .bottomRight }
    }

    enum Entrance: String, Codable, CaseIterable, Identifiable {
        case slide, fade, pop, wipe

        var id: String { rawValue }

        var title: String {
            switch self {
            case .slide: "Deslizar"
            case .fade: "Aparecer"
            case .pop: "Rebote"
            case .wipe: "Revelar"
            }
        }
    }

    var id = UUID()
    var kind: Kind
    var title: String
    var subtitle: String = ""
    var theme: Theme = .minimal
    var place: Place
    var entrance: Entrance = .slide
    /// Seconds it stays up before leaving by itself; 0 stays until it is taken down.
    var seconds: Double = 0
    var scale: Double = 1
    /// The hand position that puts it up and takes it down (a `Gesture`'s raw value), if it has one.
    var gestureName: String?
    /// Where the user dragged it to: its centre, 0...1 across and down the picture. Nil keeps it at `place`.
    var spot: [Double]?

    /// What a new caption of each kind starts as.
    static func new(_ kind: Kind, theme: Theme = .minimal) -> Rotulo {
        switch kind {
        case .lowerThird: Rotulo(kind: kind, title: "Tu nombre", subtitle: "Tu cargo", theme: theme, place: .bottomLeft)
        case .banner: Rotulo(kind: kind, title: "Tema de hoy", subtitle: "Escribe aquí de qué va la reunión", theme: theme, place: .top)
        case .badge: Rotulo(kind: kind, title: "En vivo", theme: theme, place: .topRight, entrance: .pop)
        case .card: Rotulo(kind: kind, title: "Empezamos pronto", subtitle: "Vuelvo en un momento", theme: theme, place: .top, entrance: .fade)
        }
    }

    /// The four a new user starts with, one of each kind.
    static let starters: [Rotulo] = Kind.allCases.map { new($0) }

    /// Changing the kind keeps the words but moves it somewhere that kind can go.
    mutating func become(_ kind: Kind) {
        self.kind = kind
        if !kind.places.contains(place), let first = kind.places.first { place = first }
    }
}

/// Draws the captions and lays them over the picture, with their coming and going.
enum Rotulos {
    /// A caption that is up: when it came in, and when it started to leave, if it has.
    struct Showing {
        var rotulo: Rotulo
        var since: Double
        var leaving: Double?
    }

    static let enterTime = 0.45
    static let leaveTime = 0.3

    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let lock = NSLock()
    private static var cache: [String: CGImage] = [:]

    // MARK: Over the picture

    /// The picture with every caption that is up laid over it, each where its animation has it at `now`.
    static func apply(_ showing: [Showing], to scene: CIImage, extent: CGRect, now: Double) -> CIImage {
        var scene = scene
        // Cards first: they cover the picture, and the rest sits over them.
        for item in showing.sorted(by: { ($0.rotulo.kind == .card ? 0 : 1) < ($1.rotulo.kind == .card ? 0 : 1) }) {
            let shown = visible(item, now: now)
            guard shown > 0.001 else { continue }
            // A fifth larger than drawn: in a call the picture is often a small tile, and the words have to carry.
            let unit = extent.width / 1280 * CGFloat(item.rotulo.scale) * 1.2
            if item.rotulo.kind == .card {
                let dim = scene.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 22.0 * Double(extent.width / 1280)])
                    .applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 0.42, y: 0, z: 0, w: 0),
                                                                  "inputGVector": CIVector(x: 0, y: 0.42, z: 0, w: 0),
                                                                  "inputBVector": CIVector(x: 0, y: 0, z: 0.44, w: 0)]).cropped(to: extent)
                scene = scene.applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: dim, kCIInputTimeKey: shown])
                let words = CIImage(cgImage: image(item.rotulo, unit: unit, frame: extent.size))
                scene = faded(words, shown).composited(over: scene)
                continue
            }
            let picture = image(item.rotulo, unit: unit, frame: extent.size)
            let size = CGSize(width: picture.width, height: picture.height)
            let home = origin(item.rotulo, size: size, extent: extent, unit: unit)
            var layer = CIImage(cgImage: picture)
            var at = home
            switch item.rotulo.entrance {
            case .fade:
                layer = faded(layer, shown)
            case .slide:
                // In from the nearest edge.
                let place = item.rotulo.place
                if let spot = item.rotulo.spot, spot.count == 2 {
                    at.x += (spot[0] > 0.5 ? 1 : -1) * (size.width + 60 * unit) * (1 - shown)
                } else if item.rotulo.kind == .banner {
                    at.y += (place.isTop ? 1 : -1) * (size.height + 60 * unit) * (1 - shown)
                } else {
                    at.x += (place.isRight ? 1 : -1) * (size.width + 60 * unit) * (1 - shown)
                }
                layer = faded(layer, min(1, shown * 2))
            case .pop:
                // Grows from its middle a little past its size, and settles.
                let grow = shown < 1 ? max(0.02, 1 + 2.2 * pow(shown - 1, 3) + 1.2 * pow(shown - 1, 2)) : 1
                layer = layer.transformed(by: CGAffineTransform(translationX: -size.width / 2, y: -size.height / 2)
                    .concatenating(CGAffineTransform(scaleX: grow, y: grow))
                    .concatenating(CGAffineTransform(translationX: size.width / 2, y: size.height / 2)))
                layer = faded(layer, min(1, shown * 3))
            case .wipe:
                layer = layer.cropped(to: CGRect(x: 0, y: 0, width: size.width * shown, height: size.height))
            }
            scene = layer.transformed(by: CGAffineTransform(translationX: at.x.rounded(), y: at.y.rounded())).composited(over: scene)
        }
        return scene.cropped(to: extent)
    }

    /// 0...1: how far in it is, eased. Coming in runs up to 1; leaving runs back down.
    static func visible(_ item: Showing, now: Double) -> CGFloat {
        let p = min(1, max(0, (now - item.since) / enterTime))
        var shown = 1 - pow(1 - p, 3)
        if let leaving = item.leaving {
            let q = min(1, max(0, (now - leaving) / leaveTime))
            shown *= 1 - q * q
        }
        return CGFloat(shown)
    }

    private static func faded(_ image: CIImage, _ alpha: CGFloat) -> CIImage {
        alpha >= 1 ? image : image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)])
    }

    /// Where the caption's picture goes when it is fully in. The pictures carry a margin for their glow.
    private static func origin(_ r: Rotulo, size: CGSize, extent: CGRect, unit: CGFloat) -> CGPoint {
        if let spot = r.spot, spot.count == 2, r.kind != .card {
            // Wherever it was dragged to, kept inside the picture.
            let x = min(max(0, CGFloat(spot[0]) * extent.width - size.width / 2), max(0, extent.width - size.width))
            let y = min(max(0, (1 - CGFloat(spot[1])) * extent.height - size.height / 2), max(0, extent.height - size.height))
            return CGPoint(x: x, y: y)
        }
        let pad = padding * unit
        let wide = r.kind == .banner && (r.theme == .corporate || r.theme == .neon)   // these banners run edge to edge
        let margin = (wide ? 0 : 36) * extent.width / 1280
        let x: CGFloat
        if r.place.isLeft { x = margin - pad } else if r.place.isRight { x = extent.width - margin - size.width + pad } else { x = (extent.width - size.width) / 2 }
        let y = r.place.isTop ? extent.height - margin - size.height + pad : margin - pad
        return CGPoint(x: x, y: y)
    }

    // MARK: For the editor

    private static let context = CIContext()
    private static var photos: [String: CIImage] = [:]

    /// One of the model photos shipped with the app, to show a caption over.
    private static func photo(_ name: String) -> CIImage? {
        if let made = photos[name] { return made }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("modelo/\(name).jpg"), let image = CIImage(contentsOf: url) else { return nil }
        photos[name] = image
        return image
    }

    /// The caption as it will look in a call, over a model's photo. `shown` 0...1 runs its entrance.
    private static var previews: [String: CGImage] = [:]

    static func preview(_ r: Rotulo, width: CGFloat = 960, shown: Double = 1) -> CGImage? {
        // The finished look is kept: the lists redraw often, and each of these is a full composite.
        let key = "\(r.hashValue)|\(width)"
        if shown >= 1, let made = previews[key] { return made }
        if previews.count > 60 { previews.removeAll() }
        let made = compose(r, width: width, shown: shown)
        if shown >= 1 { previews[key] = made }
        return made
    }

    private static func compose(_ r: Rotulo, width: CGFloat, shown: Double) -> CGImage? {
        let extent = CGRect(x: 0, y: 0, width: width, height: (width * 9 / 16).rounded())
        let model = r.theme == .corporate || r.theme == .wood ? "mujer" : "persona"
        let back: CIImage
        if let photo = photo(model) {
            back = photo.transformed(by: CGAffineTransform(scaleX: extent.width / photo.extent.width, y: extent.height / photo.extent.height))
        } else {
            back = CIImage(color: CIColor(red: 0.86, green: 0.84, blue: 0.82)).cropped(to: extent)
        }
        let item = Showing(rotulo: r, since: 0, leaving: nil)
        return context.createCGImage(apply([item], to: back, extent: extent, now: shown >= 1 ? 10 : shown * enterTime), from: extent)
    }

    // MARK: Drawing

    /// Room left round every drawing for glows and shadows, in the 1280-wide reference.
    private static let padding: CGFloat = 26

    /// The caption drawn at its final size, cached until its words or looks change.
    static func image(_ r: Rotulo, unit: CGFloat, frame: CGSize) -> CGImage {
        let key = "\(r.kind.rawValue)|\(r.theme.rawValue)|\(r.title)|\(r.subtitle)|\(unit)|\(frame.width)x\(frame.height)"
        lock.lock(); defer { lock.unlock() }
        if let made = cache[key] { return made }
        if cache.count > 80 { cache.removeAll() }
        let made: CGImage
        switch r.kind {
        case .lowerThird: made = lowerThird(r, unit)
        case .banner: made = banner(r, unit, frame.width)
        case .badge: made = badge(r, unit)
        case .card: made = card(r, unit, frame)
        }
        cache[key] = made
        return made
    }

    private static func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xff) / 255, CGFloat((hex >> 8) & 0xff) / 255, CGFloat(hex & 0xff) / 255, a])!
    }

    private static func line(_ text: String, _ font: String, _ size: CGFloat, _ color: CGColor, tracking: CGFloat = 0) -> CTLine {
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(font as CFString, size, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        if tracking != 0 { attributes[NSAttributedString.Key(kCTKernAttributeName as String)] = tracking }
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    private static func width(_ line: CTLine) -> CGFloat { CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) }

    /// Text set no wider than `fit`: longer text is set smaller, down to a floor, so it always reads.
    private static func fitted(_ text: String, _ font: String, _ size: CGFloat, _ color: CGColor, fit: CGFloat, tracking: CGFloat = 0) -> CTLine {
        let first = line(text, font, size, color, tracking: tracking)
        let wide = width(first)
        guard wide > fit, wide > 0 else { return first }
        return line(text, font, max(size * 0.55, size * fit / wide), color, tracking: tracking)
    }

    private static func put(_ line: CTLine, _ ctx: CGContext, x: CGFloat, y: CGFloat) {
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
    }

    /// A drawing surface of `size` in reference units plus the margin, already scaled, origin at the content's corner.
    private static func canvas(_ size: CGSize, _ unit: CGFloat, _ draw: (CGContext) -> Void) -> CGImage {
        let w = Int(((size.width + padding * 2) * unit).rounded(.up)), h = Int(((size.height + padding * 2) * unit).rounded(.up))
        let ctx = CGContext(data: nil, width: max(2, w), height: max(2, h), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: unit, y: unit)
        ctx.translateBy(x: padding, y: padding)
        draw(ctx)
        return ctx.makeImage()!
    }

    private static func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: min(radius, rect.height / 2, rect.width / 2), cornerHeight: min(radius, rect.height / 2, rect.width / 2), transform: nil)
    }

    private static func fill(_ ctx: CGContext, _ path: CGPath, _ color: CGColor) { ctx.addPath(path); ctx.setFillColor(color); ctx.fillPath() }

    /// A neon tube: the outline drawn with a bloom round it.
    private static func glow(_ ctx: CGContext, _ path: CGPath, _ color: CGColor, width: CGFloat = 3) {
        ctx.saveGState()
        for blur in [22.0, 10.0] as [CGFloat] {
            ctx.setShadow(offset: .zero, blur: blur * ctx.ctm.a, color: color)
            ctx.addPath(path); ctx.setStrokeColor(color); ctx.setLineWidth(width); ctx.strokePath()
        }
        ctx.restoreGState()
        ctx.addPath(path); ctx.setStrokeColor(color); ctx.setLineWidth(width); ctx.strokePath()
    }

    /// A wooden plank: slightly out of square, with a darker edge under it and an ink outline.
    private static func plank(_ ctx: CGContext, _ rect: CGRect) {
        func shape(_ dy: CGFloat) -> CGPath {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: rect.minX + 4, y: rect.minY + 6 + dy)); p.addLine(to: CGPoint(x: rect.maxX - 12, y: rect.minY + dy))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 10 + dy)); p.addLine(to: CGPoint(x: rect.maxX - 5, y: rect.maxY + dy))
            p.addLine(to: CGPoint(x: rect.minX + 2, y: rect.maxY - 8 + dy)); p.addLine(to: CGPoint(x: rect.minX - 4, y: rect.minY + 18 + dy))
            p.closeSubpath()
            return p
        }
        fill(ctx, shape(-8), color(0xc98a36))
        fill(ctx, shape(0), color(0xecc48e))
        ctx.addPath(shape(0)); ctx.setStrokeColor(color(0x2b2118)); ctx.setLineWidth(5); ctx.setLineJoin(.round); ctx.strokePath()
        ctx.setStrokeColor(color(0xd7a55e)); ctx.setLineWidth(3); ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: rect.minX + 26, y: rect.minY + 16)); ctx.addLine(to: CGPoint(x: rect.minX + rect.width * 0.4, y: rect.minY + 18)); ctx.strokePath()
        ctx.move(to: CGPoint(x: rect.maxX - rect.width * 0.35, y: rect.maxY - 16)); ctx.addLine(to: CGPoint(x: rect.maxX - 24, y: rect.maxY - 15)); ctx.strokePath()
    }

    private static var plates: [String: CGImage] = [:]

    /// One of the illustrated plates shipped with the app, if it is there.
    private static func plate(_ name: String) -> CGImage? {
        if let made = plates[name] { return made }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("rotulos/\(name).png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        plates[name] = image
        return image
    }

    /// Draws a plate to fill `rect`: its two ends keep their shape and only the plain middle third is stretched,
    /// which is how the plates were drawn to be used.
    private static func draw(_ plate: CGImage, _ ctx: CGContext, in rect: CGRect) {
        let w = CGFloat(plate.width), h = CGFloat(plate.height), third = (w / 3).rounded()
        let cap = min(third * rect.height / h, rect.width / 2)
        let parts: [(CGRect, CGRect)] = [
            (CGRect(x: 0, y: 0, width: third, height: h), CGRect(x: rect.minX, y: rect.minY, width: cap, height: rect.height)),
            (CGRect(x: third, y: 0, width: w - third * 2, height: h), CGRect(x: rect.minX + cap - 0.5, y: rect.minY, width: rect.width - cap * 2 + 1, height: rect.height)),
            (CGRect(x: w - third, y: 0, width: third, height: h), CGRect(x: rect.maxX - cap, y: rect.minY, width: cap, height: rect.height)),
        ]
        ctx.interpolationQuality = .high
        for (from, to) in parts { if let piece = plate.cropping(to: from) { ctx.draw(piece, in: to) } }
    }

    private static func lowerThird(_ r: Rotulo, _ unit: CGFloat) -> CGImage {
        let has = !r.subtitle.trimmingCharacters(in: .whitespaces).isEmpty
        switch r.theme {
        case .minimal:
            let name = fitted(r.title, "AvenirNext-Bold", 34, color(0x141416), fit: 620)
            let sub = fitted(r.subtitle, "AvenirNext-Regular", 21, color(0x5a5a60), fit: 620)
            let size = CGSize(width: max(280, max(width(name), has ? width(sub) : 0) + 58), height: has ? 108 : 72)
            return canvas(size, unit) { ctx in
                ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: -4 * unit), blur: 16 * unit, color: color(0x000000, 0.22))
                fill(ctx, rounded(CGRect(origin: .zero, size: size), 18), color(0xffffff, 0.94)); ctx.restoreGState()
                ctx.saveGState(); ctx.addPath(rounded(CGRect(origin: .zero, size: size), 18)); ctx.clip()
                ctx.setFillColor(color(0x0a84ff)); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: size.height)); ctx.restoreGState()
                put(name, ctx, x: 30, y: has ? 58 : 24)
                if has { put(sub, ctx, x: 30, y: 24) }
            }
        case .corporate:
            let name = fitted(r.title, "AvenirNext-Bold", 34, color(0xffffff), fit: 620)
            let sub = fitted(r.subtitle, "AvenirNext-Medium", 19, color(0x102a52), fit: 560)
            let top = max(300, width(name) + 70), low = has ? max(top * 0.8, width(sub) + 60) : 0
            let size = CGSize(width: max(top, low), height: has ? 100 : 60)
            return canvas(size, unit) { ctx in
                ctx.setFillColor(color(0x102a52)); ctx.fill(CGRect(x: 0, y: has ? 40 : 0, width: top, height: 60))
                if has { ctx.setFillColor(color(0xffffff, 0.96)); ctx.fill(CGRect(x: 0, y: 0, width: low, height: 40)) }
                ctx.setFillColor(color(0xffb020)); ctx.fill(CGRect(x: 0, y: 0, width: 10, height: size.height))
                put(name, ctx, x: 30, y: (has ? 40 : 0) + 18)
                if has { put(sub, ctx, x: 30, y: 13) }
            }
        case .neon:
            let name = fitted(r.title.uppercased(), "DINCondensed-Bold", 56, color(0xffffff), fit: 620, tracking: 1)
            let sub = fitted(r.subtitle.uppercased(), "AvenirNext-Bold", 17, color(0x00e5ff), fit: 620, tracking: 1.2)
            if let art = plate("neon-placa") {
                let size = CGSize(width: max(330, max(width(name), has ? width(sub) : 0) + 96), height: has ? 136 : 104)
                return canvas(size, unit) { ctx in
                    draw(art, ctx, in: CGRect(origin: .zero, size: size))
                    put(name, ctx, x: 50, y: has ? 58 : 30)
                    if has { put(sub, ctx, x: 51, y: 33) }
                }
            }
            let size = CGSize(width: max(300, max(width(name), has ? width(sub) : 0) + 52), height: has ? 114 : 80)
            return canvas(size, unit) { ctx in
                let box = rounded(CGRect(origin: .zero, size: size), 10)
                fill(ctx, box, color(0x0c061c, 0.86))
                glow(ctx, box, color(0xff2daa))
                put(name, ctx, x: 26, y: has ? 46 : 16)
                if has { put(sub, ctx, x: 27, y: 20) }
            }
        case .wood:
            let name = fitted(r.title, "MarkerFelt-Wide", 44, color(0x2b2118), fit: 600)
            let sub = fitted(r.subtitle, "MarkerFelt-Thin", 27, color(0x6e4a24), fit: 600)
            if let art = plate("madera-placa") {
                let size = CGSize(width: max(340, max(width(name), has ? width(sub) : 0) + 136), height: has ? 140 : 108)
                return canvas(size, unit) { ctx in
                    draw(art, ctx, in: CGRect(origin: .zero, size: size))
                    put(name, ctx, x: 68, y: has ? 74 : 44)
                    if has { put(sub, ctx, x: 70, y: 40) }
                }
            }
            let size = CGSize(width: max(300, max(width(name), has ? width(sub) : 0) + 64), height: has ? 112 : 78)
            return canvas(size, unit) { ctx in
                plank(ctx, CGRect(origin: .zero, size: size))
                put(name, ctx, x: 30, y: has ? 56 : 24)
                if has { put(sub, ctx, x: 32, y: 22) }
            }
        }
    }

    private static func banner(_ r: Rotulo, _ unit: CGFloat, _ frameWidth: CGFloat) -> CGImage {
        let has = !r.subtitle.trimmingCharacters(in: .whitespaces).isEmpty
        let full = frameWidth / unit   // the picture's width in this caption's own units
        switch r.theme {
        case .minimal:
            let head = fitted(r.title, "AvenirNext-DemiBold", 20, color(0xffffff), fit: 420)
            let body = fitted(r.subtitle, "AvenirNext-Regular", 20, color(0xffffff, 0.86), fit: max(200, full - 200 - width(head)))
            let size = CGSize(width: width(head) + (has ? width(body) + 22 : 0) + 48, height: 48)
            return canvas(size, unit) { ctx in
                fill(ctx, rounded(CGRect(origin: .zero, size: size), 24), color(0x141416, 0.8))
                put(head, ctx, x: 24, y: 16)
                if has {
                    ctx.setFillColor(color(0xffffff, 0.35)); ctx.fill(CGRect(x: 24 + width(head) + 10, y: 13, width: 1.5, height: 22))
                    put(body, ctx, x: 24 + width(head) + 22, y: 16)
                }
            }
        case .corporate:
            let head = fitted(r.title.uppercased(), "AvenirNext-Bold", 19, color(0x102a52), fit: 420, tracking: 0.6)
            let body = fitted(r.subtitle, "AvenirNext-Regular", 19, color(0x3c465a), fit: max(200, full - 130 - width(head)))
            let size = CGSize(width: full - padding * 2 + padding * 2, height: 60)
            return canvas(CGSize(width: full, height: size.height), unit) { ctx in
                ctx.translateBy(x: -padding, y: 0)   // edge to edge: the margin is not wanted at the sides
                ctx.setFillColor(color(0xffffff, 0.95)); ctx.fill(CGRect(x: 0, y: 4, width: full + padding * 2, height: 56))
                ctx.setFillColor(color(0xffb020)); ctx.fill(CGRect(x: 0, y: 0, width: full + padding * 2, height: 4))
                put(head, ctx, x: padding + 34, y: 24)
                if has { put(body, ctx, x: padding + 34 + width(head) + 22, y: 24) }
            }
        case .neon:
            let text = has ? "\(r.title)   •   \(r.subtitle)" : r.title
            let words = fitted(text.uppercased(), "AvenirNext-Bold", 17, color(0xff2daa), fit: full - 60, tracking: 1.4)
            return canvas(CGSize(width: full, height: 42), unit) { ctx in
                ctx.translateBy(x: -padding, y: 0)
                ctx.setFillColor(color(0x0c061c, 0.9)); ctx.fill(CGRect(x: 0, y: 0, width: full + padding * 2, height: 42))
                let rule = CGMutablePath(); rule.move(to: CGPoint(x: 0, y: 42)); rule.addLine(to: CGPoint(x: full + padding * 2, y: 42))
                glow(ctx, rule, color(0x00e5ff), width: 2)
                put(words, ctx, x: padding + 24, y: 14)
            }
        case .wood:
            let text = has ? "\(r.title): \(r.subtitle)" : r.title
            let words = fitted(text, "MarkerFelt-Wide", 28, color(0x2b2118), fit: full - 160)
            let size = CGSize(width: width(words) + 52, height: 54)
            return canvas(size, unit) { ctx in
                let box = rounded(CGRect(origin: .zero, size: size), 12)
                fill(ctx, box, color(0xfffdf6, 0.97))
                ctx.addPath(box); ctx.setStrokeColor(color(0x2b2118)); ctx.setLineWidth(4); ctx.strokePath()
                put(words, ctx, x: 26, y: 17)
            }
        }
    }

    private static func badge(_ r: Rotulo, _ unit: CGFloat) -> CGImage {
        switch r.theme {
        case .minimal:
            let words = fitted(r.title.uppercased(), "AvenirNext-Bold", 17, color(0x141416), fit: 320, tracking: 0.6)
            let size = CGSize(width: width(words) + 58, height: 42)
            return canvas(size, unit) { ctx in
                ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: -3 * unit), blur: 12 * unit, color: color(0x000000, 0.2))
                fill(ctx, rounded(CGRect(origin: .zero, size: size), 21), color(0xffffff, 0.95)); ctx.restoreGState()
                ctx.setFillColor(color(0xff3b30)); ctx.fillEllipse(in: CGRect(x: 16, y: 14, width: 14, height: 14))
                put(words, ctx, x: 40, y: 14)
            }
        case .corporate:
            let words = fitted(r.title.uppercased(), "AvenirNext-Bold", 18, color(0xffffff), fit: 320, tracking: 0.8)
            let size = CGSize(width: width(words) + 40, height: 40)
            return canvas(size, unit) { ctx in
                fill(ctx, rounded(CGRect(origin: .zero, size: size), 6), color(0x102a52))
                ctx.setFillColor(color(0xffb020)); ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: 4))
                put(words, ctx, x: 20, y: 14)
            }
        case .neon:
            let words = fitted(r.title.uppercased(), "DINCondensed-Bold", 36, color(0x00e5ff), fit: 320, tracking: 1.5)
            if let art = plate("neon-insignia") {
                let size = CGSize(width: width(words) + 64, height: 66)
                return canvas(size, unit) { ctx in
                    draw(art, ctx, in: CGRect(origin: .zero, size: size))
                    put(words, ctx, x: 32, y: 19)
                }
            }
            let size = CGSize(width: width(words) + 40, height: 48)
            return canvas(size, unit) { ctx in
                let box = rounded(CGRect(origin: .zero, size: size), 8)
                fill(ctx, box, color(0x0c061c, 0.86))
                glow(ctx, box, color(0x00e5ff))
                put(words, ctx, x: 20, y: 10)
            }
        case .wood:
            let words = fitted(r.title, "MarkerFelt-Wide", 32, color(0x2b2118), fit: 320)
            if let art = plate("madera-insignia") {
                let size = CGSize(width: width(words) + 96, height: 76)
                return canvas(size, unit) { ctx in
                    draw(art, ctx, in: CGRect(origin: .zero, size: size))
                    put(words, ctx, x: 48, y: 29)
                }
            }
            let size = CGSize(width: width(words) + 48, height: 58)
            return canvas(size, unit) { ctx in
                plank(ctx, CGRect(origin: .zero, size: size))
                put(words, ctx, x: 24, y: 19)
            }
        }
    }

    /// The words of a full-screen card, centred on a clear picture the size of the frame. The dimming under
    /// them is done where they are laid over the video.
    private static func card(_ r: Rotulo, _ unit: CGFloat, _ frame: CGSize) -> CGImage {
        let w = Int(frame.width), h = Int(frame.height)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: unit, y: unit)
        let W = frame.width / unit, H = frame.height / unit
        let has = !r.subtitle.trimmingCharacters(in: .whitespaces).isEmpty
        let title: CTLine, sub: CTLine
        switch r.theme {
        case .minimal:
            title = fitted(r.title, "AvenirNext-Bold", 68, color(0xffffff), fit: W - 160)
            sub = fitted(r.subtitle, "AvenirNext-Regular", 26, color(0xffffff, 0.85), fit: W - 200)
        case .corporate:
            title = fitted(r.title, "AvenirNext-Bold", 64, color(0xffffff), fit: W - 160)
            sub = fitted(r.subtitle, "AvenirNext-Medium", 25, color(0xffffff, 0.88), fit: W - 200)
        case .neon:
            title = fitted(r.title.uppercased(), "DINCondensed-Bold", 120, color(0xffffff), fit: W - 160, tracking: 2)
            sub = fitted(r.subtitle.uppercased(), "AvenirNext-Bold", 22, color(0x00e5ff), fit: W - 200, tracking: 2)
        case .wood:
            title = fitted(r.title, "MarkerFelt-Wide", 84, color(0xfff3dc), fit: W - 160)
            sub = fitted(r.subtitle, "MarkerFelt-Thin", 32, color(0xfff3dc, 0.9), fit: W - 200)
        }
        let titleY = H / 2 + (has ? 6 : -22)
        ctx.saveGState()
        if r.theme == .neon { ctx.setShadow(offset: .zero, blur: 26 * unit, color: color(0xff2daa)) }
        else if r.theme == .wood { ctx.setShadow(offset: CGSize(width: 4 * unit, height: -5 * unit), blur: 0, color: color(0x2b2118)) }
        else { ctx.setShadow(offset: CGSize(width: 0, height: -3 * unit), blur: 14 * unit, color: color(0x000000, 0.35)) }
        put(title, ctx, x: (W - width(title)) / 2, y: titleY)
        ctx.restoreGState()
        if r.theme == .corporate {
            ctx.setFillColor(color(0xffb020)); ctx.fill(CGRect(x: (W - 120) / 2, y: titleY - 22, width: 120, height: 5))
        }
        if has { put(sub, ctx, x: (W - width(sub)) / 2, y: titleY - (r.theme == .corporate ? 66 : 54)) }
        return ctx.makeImage()!
    }
}
