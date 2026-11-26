import SwiftUI
import UniformTypeIdentifiers

/// The captions: the list of the user's own, and beside it everything about the chosen one.
struct RotulosView: View {
    @ObservedObject var engine: Engine
    @Binding var section: Pane
    @State private var selected: UUID?

    private var index: Int? { engine.rotulos.firstIndex { $0.id == selected } ?? (engine.rotulos.isEmpty ? nil : 0) }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 16)], spacing: 16) {
                    ForEach(Array(engine.rotulos.enumerated()), id: \.element.id) { i, rotulo in
                        RotuloCard(rotulo: rotulo, number: i + 1, selected: i == index, up: engine.captionsUp.contains(rotulo.id))
                            .onTapGesture { selected = rotulo.id }
                    }
                    Menu {
                        ForEach(Rotulo.Kind.allCases) { kind in
                            Button { add(kind) } label: { Label(kind.title, systemImage: kind.symbol) }
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "plus").font(.system(size: 26, weight: .light))
                            Text(tr("Nuevo rótulo")).font(.callout)
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 150)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                        .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }
                .padding(20)
            }
            .frame(minWidth: 260, maxWidth: .infinity)

            Divider()

            Group {
                if let index {
                    RotuloEditor(engine: engine, rotulo: $engine.rotulos[index], number: index + 1, section: $section,
                                 duplicate: { duplicate(index) }, delete: { delete(index) })
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "textformat").font(.system(size: 34, weight: .light))
                        Text(tr("Crea tu primer rótulo con «Nuevo rótulo».")).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 360)
        }
    }

    private func add(_ kind: Rotulo.Kind) {
        let theme = index.map { engine.rotulos[$0].theme } ?? .minimal   // new ones match what is being worked on
        let made = Rotulo.new(kind, theme: theme)
        engine.rotulos.append(made)
        selected = made.id
    }

    private func duplicate(_ i: Int) {
        var copy = engine.rotulos[i]
        copy.id = UUID()
        if copy.gestureName == Gesture.custom.rawValue { copy.gestureName = nil }   // the recording stays with the original
        copy.iconPath = OwnIcon.copy(of: copy.iconPath)   // its own file, so deleting one does not strip the other
        engine.rotulos.insert(copy, at: i + 1)
        selected = copy.id
    }

    private func delete(_ i: Int) {
        let gone = engine.rotulos[i]
        if engine.captionsUp.contains(gone.id) { engine.toggle(gone) }
        engine.forget(.caption(gone.id))
        OwnIcon.remove(gone.iconPath)
        engine.rotulos.remove(at: i)
        selected = engine.rotulos.indices.contains(i) ? engine.rotulos[i].id : engine.rotulos.last?.id
    }
}

struct RotuloCard: View {
    let rotulo: Rotulo
    let number: Int
    let selected: Bool
    let up: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image = Rotulos.preview(rotulo, width: 640) { PreviewImage(image: image) }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rotulo.title.isEmpty ? rotulo.kind.title : rotulo.title).font(.headline).lineLimit(1)
                    Text("\(rotulo.kind.title) · \(rotulo.theme.title)").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                if up {
                    Text(tr("Al aire")).font(.caption.weight(.semibold)).foregroundStyle(.green)
                        .padding(.horizontal, 7).padding(.vertical, 2).background(.green.opacity(0.14), in: Capsule())
                } else if number <= 9 {
                    Text("⌃⌥⇧\(number)").font(.callout.monospaced()).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2.5 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Everything about one caption: its words, its looks, how it comes in and how long it stays.
struct RotuloEditor: View {
    @ObservedObject var engine: Engine
    @Binding var rotulo: Rotulo
    let number: Int
    @Binding var section: Pane
    var duplicate: () -> Void
    var delete: () -> Void
    /// 0...1 while the entrance is being played back in the preview.
    @State private var shown = 1.0
    @State private var playing: Timer?

    private var up: Bool { engine.captionsUp.contains(rotulo.id) }

    /// A binding into the caption's own style, which only exists once something in it is changed.
    private func style<T>(_ path: WritableKeyPath<Rotulo.Style, T>) -> Binding<T> {
        Binding(get: { rotulo.look[keyPath: path] }, set: { var look = rotulo.look; look[keyPath: path] = $0; rotulo.style = look })
    }

    /// One of the style's colours as SwiftUI wants it. The background also carries how see-through it is.
    private func colour(_ path: WritableKeyPath<Rotulo.Style, Int>, alpha: Bool = false) -> Binding<Color> {
        Binding(get: {
            let hex = rotulo.look[keyPath: path]
            return Color(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255,
                         opacity: alpha ? rotulo.look.backgroundAlpha : 1)
        }, set: { new in
            guard let c = NSColor(new).usingColorSpace(.sRGB) else { return }
            var look = rotulo.look
            look[keyPath: path] = (Int((c.redComponent * 255).rounded()) << 16) | (Int((c.greenComponent * 255).rounded()) << 8) | Int((c.blueComponent * 255).rounded())
            if alpha { look.backgroundAlpha = Double(c.alphaComponent) }
            rotulo.style = look
        })
    }
    private var gesture: Gesture { rotulo.gestureName.flatMap(Gesture.init(rawValue:)) ?? Gesture.none }

    /// Whatever else answers to the same gesture and would go first: an effect, or a caption listed earlier.
    private var clash: String? {
        guard gesture != Gesture.none else { return nil }
        if gesture == .custom { return engine.twin(of: .caption(rotulo.id)) }
        if let effect = Effect.allCases.first(where: { engine.commands[$0] == gesture }) { return effect.title }
        return engine.rotulos.prefix(number - 1).first { $0.gestureName == gesture.rawValue }.map { $0.title.isEmpty ? $0.kind.title : $0.title }
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    if let image = Rotulos.preview(rotulo, width: 960, shown: shown) {
                        PreviewImage(image: image).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .accessibilityLabel(tr("Vista previa del rótulo"))
                            .overlay(GeometryReader { proxy in
                                // Drag anywhere on the picture to put the caption there.
                                Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                                    guard rotulo.kind != .card else { return }
                                    rotulo.spot = [Double(min(1, max(0, drag.location.x / proxy.size.width))),
                                                   Double(min(1, max(0, drag.location.y / proxy.size.height)))]
                                })
                            })
                    }
                    if rotulo.kind != .card {
                        Text(tr("Arrastra sobre la imagen para colocar el rótulo donde quieras.")).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button(up ? tr("Quitar") : tr("Poner en vivo")) {
                            engine.toggle(rotulo)
                            if !up { section = .live }
                        }
                        .buttonStyle(.borderedProminent)
                        Button(tr("Ver animación"), action: play)
                    }
                }
                .padding(.vertical, 4)
            }

            Section(tr("Texto")) {
                Picker(tr("Tipo"), selection: Binding(get: { rotulo.kind }, set: { rotulo.become($0) })) {
                    ForEach(Rotulo.Kind.allCases) { Text($0.title).tag($0) }
                }
                if rotulo.kind == .social {
                    Picker(tr("Red"), selection: Binding(get: { rotulo.network }, set: { rotulo.networkName = $0.rawValue })) {
                        ForEach(Rotulo.Network.allCases) { Text($0.title).tag($0) }
                    }
                }
                TextField(rotulo.kind.labels.0, text: $rotulo.title, prompt: rotulo.kind == .social ? Text(rotulo.network.example) : nil)
                if rotulo.kind == .social {
                    LabeledContent(tr("Icono")) {
                        HStack(spacing: 10) {
                            Text(rotulo.iconPath == nil ? tr("Logo de la red") : tr("Tu imagen")).foregroundStyle(.secondary)
                            if rotulo.iconPath != nil { Button(tr("Quitar")) { OwnIcon.remove(rotulo.iconPath); rotulo.iconPath = nil } }
                            Button(tr("Elegir imagen…")) { if let path = OwnIcon.choose() { OwnIcon.remove(rotulo.iconPath); rotulo.iconPath = path } }
                        }
                    }
                }
                if rotulo.kind.hasSubtitle { TextField(rotulo.kind.labels.1, text: $rotulo.subtitle) }
            }

            Section(tr("Aspecto")) {
                Picker(tr("Tema"), selection: $rotulo.theme) {
                    ForEach(Rotulo.Theme.allCases) { Text($0.title).tag($0) }
                }
                if rotulo.theme == .custom {
                    // The user's own looks: any colours, any of the letterings, any roundness.
                    ColorPicker(tr("Fondo"), selection: colour(\.background, alpha: true), supportsOpacity: true)
                    ColorPicker(tr("Texto"), selection: colour(\.text), supportsOpacity: false)
                    ColorPicker(tr("Acento"), selection: colour(\.accent), supportsOpacity: false)
                    Picker(tr("Letra"), selection: style(\.lettering)) {
                        ForEach(Rotulo.Style.Lettering.allCases) { Text($0.title).tag($0) }
                    }
                    if rotulo.kind != .card {
                        LabeledContent(tr("Esquinas")) {
                            Slider(value: style(\.corner), in: 0...1) { Text(tr("Esquinas")) } minimumValueLabel: { Image(systemName: "square") } maximumValueLabel: { Image(systemName: "capsule") }
                                .labelsHidden()
                        }
                    }
                }
                if rotulo.spot != nil, rotulo.kind != .card {
                    LabeledContent(tr("Posición")) {
                        HStack(spacing: 10) {
                            Text(tr("Colocado a mano")).foregroundStyle(.secondary)
                            Button(tr("Restablecer")) { rotulo.spot = nil }
                        }
                    }
                } else if !rotulo.kind.places.isEmpty {
                    Picker(tr("Posición"), selection: $rotulo.place) {
                        ForEach(rotulo.kind.places) { Text($0.title).tag($0) }
                    }
                }
                LabeledContent(tr("Tamaño")) {
                    Slider(value: $rotulo.scale, in: 0.7...1.6) { Text(tr("Tamaño")) } minimumValueLabel: { Text("A").font(.caption) } maximumValueLabel: { Text("A").font(.title3) }
                        .labelsHidden()
                }
            }

            Section(tr("Animación")) {
                Picker(tr("Entrada"), selection: $rotulo.entrance) {
                    ForEach(Rotulo.Entrance.allCases) { Text($0.title).tag($0) }
                }
                Picker(tr("Se queda"), selection: $rotulo.seconds) {
                    Text(tr("Hasta que lo quite")).tag(0.0)
                    Text(tr("5 segundos")).tag(5.0)
                    Text(tr("10 segundos")).tag(10.0)
                    Text(tr("30 segundos")).tag(30.0)
                    Text(tr("1 minuto")).tag(60.0)
                }
            }

            Section(tr("Cómo se activa")) {
                Picker(tr("Posición de manos"), selection: Binding(get: { gesture }, set: { rotulo.gestureName = $0 == Gesture.none ? nil : $0.rawValue })) {
                    // The recorded one is offered only once there is a recording for this caption.
                    ForEach(Gesture.allCases.filter { $0 != .custom || engine.poses[.caption(rotulo.id)] != nil }) { Text($0.title).tag($0) }
                }
                if gesture == .custom, let photo = engine.posePhotos[.caption(rotulo.id)] {
                    Image(nsImage: photo).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityLabel(tr("Foto de ti haciendo la posición grabada"))
                } else if gesture != Gesture.none {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(gesture.symbol).font(.system(size: 26))
                        Text(gesture.hint).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                LabeledContent(engine.poses[.caption(rotulo.id)].map { tr("Tu posición: %@", $0.summary.lowercased()) } ?? tr("Tu propia posición")) {
                    Button(engine.poses[.caption(rotulo.id)] == nil ? tr("Grabar…") : tr("Volver a grabar…")) { engine.startRecording(for: .caption(rotulo.id)) }
                }
                if gesture != Gesture.none {
                    Button(tr("Practicar el gesto")) { engine.startPractice(for: rotulo) }
                }
                if let clash {
                    Label(gesture == .custom ? tr("Tu posición se parece demasiado a la de «%@»: Kawaru no las distingue. Graba una distinta.", clash) : tr("«%@» usa la misma posición: se activará ese y no este.", clash), systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }
                if number <= 9 {
                    LabeledContent(tr("Atajo de teclado")) { Text("⌃⌥⇧\(number)").font(.body.monospaced()).foregroundStyle(.secondary) }
                }
            }

            Section {
                HStack {
                    Button(tr("Duplicar"), action: duplicate)
                    Spacer()
                    Button(tr("Eliminar"), role: .destructive, action: delete)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: rotulo.entrance) { _, _ in play() }
        .onChange(of: rotulo.id) { _, _ in playing?.invalidate(); shown = 1 }
        .onDisappear { playing?.invalidate() }
    }

    /// Runs the entrance once in the preview.
    private func play() {
        playing?.invalidate()
        shown = 0
        let began = Date()
        playing = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { timer in
            let p = Date().timeIntervalSince(began) / Rotulos.enterTime
            shown = min(1, p)
            if p >= 1 { timer.invalidate() }
        }
    }
}

/// The user's own picture for a social caption, kept as a small PNG in the app's folder.
enum OwnIcon {
    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Kawaru/iconos", isDirectory: true)
    }

    /// Asks for a picture and keeps a copy. Returns where the copy is, or nil if nothing usable was chosen.
    static func choose() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .pdf, .svg]
        panel.allowsMultipleSelection = false
        panel.message = tr("Elige el icono para este rótulo: un PNG con fondo transparente es lo que mejor queda.")
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return nil }
        // Drawn into a square, whole, so nothing of a wide logo is cut off.
        let side = 256
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let scale = min(CGFloat(side) / max(1, image.size.width), CGFloat(side) / max(1, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        image.draw(in: CGRect(x: (CGFloat(side) - size.width) / 2, y: (CGFloat(side) - size.height) / 2, width: size.width, height: size.height))
        NSGraphicsContext.restoreGraphicsState()
        guard let made = ctx.makeImage(), let data = NSBitmapImageRep(cgImage: made).representation(using: .png, properties: [:]) else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(UUID().uuidString + ".png")
        do { try data.write(to: file, options: .atomic) } catch { return nil }
        return file.path
    }

    static func copy(of path: String?) -> String? {
        guard let path else { return nil }
        let file = folder.appendingPathComponent(UUID().uuidString + ".png")
        do { try FileManager.default.copyItem(atPath: path, toPath: file.path) } catch { return nil }
        return file.path
    }

    /// Only ever deletes inside the app's own icon folder.
    static func remove(_ path: String?) {
        guard let path, path.hasPrefix(folder.path) else { return }
        try? FileManager.default.removeItem(atPath: path)
    }
}
