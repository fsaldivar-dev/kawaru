import AVFoundation
import SwiftUI

/// A silent film played in a loop, with no controls.
struct LoopingFilm: NSViewRepresentable {
    let url: URL

    final class Host: NSView {
        let player = AVQueuePlayer()
        var looper: AVPlayerLooper?
        let film = AVPlayerLayer()

        override func layout() {
            super.layout()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            film.frame = bounds
            CATransaction.commit()
        }
    }

    func makeNSView(context: Context) -> Host {
        let host = Host()
        host.wantsLayer = true
        host.film.player = host.player
        host.film.videoGravity = .resizeAspect
        host.layer?.addSublayer(host.film)
        host.player.isMuted = true
        host.looper = AVPlayerLooper(player: host.player, templateItem: AVPlayerItem(url: url))
        host.player.play()
        return host
    }

    func updateNSView(_ nsView: Host, context: Context) {}

    static func dismantleNSView(_ nsView: Host, coordinator: ()) { nsView.player.pause() }
}

/// A drawn picture of an effect, scaled to fit.
struct PreviewImage: View {
    let image: CGImage

    var body: some View {
        Image(decorative: image, scale: 2).resizable().aspectRatio(16.0 / 9.0, contentMode: .fit)
    }
}

/// The gallery: every effect as a card showing what it does, and beside it everything about the chosen one.
struct EffectsView: View {
    @ObservedObject var engine: Engine
    @Binding var section: Pane
    @State private var selected = Effect.substitution
    /// Bumped when the words change, so the pictures are drawn again with them.
    @AppStorage(Wording.Key.sign1.rawValue) private var sign1 = ""
    @AppStorage(Wording.Key.sign2.rawValue) private var sign2 = ""
    @AppStorage(Wording.Key.question1.rawValue) private var question1 = ""
    @AppStorage(Wording.Key.question2.rawValue) private var question2 = ""
    @AppStorage(Wording.Key.cheer.rawValue) private var cheer = ""
    @AppStorage(Wording.Key.breakMinutes.rawValue) private var minutes = Wording.defaultBreakMinutes

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 300), spacing: 16)], spacing: 16) {
                    ForEach(Effect.allCases) { effect in
                        EffectCard(effect: effect, gesture: engine.commands[effect] ?? Gesture.none, selected: effect == selected,
                                   on: engine.look == effect.look)
                            .onTapGesture { selected = effect }
                    }
                }
                .padding(20)
            }
            .frame(minWidth: 260, maxWidth: .infinity)

            Divider()

            EffectDetail(engine: engine, effect: selected, section: $section)
                .frame(width: 360)
        }
    }
}

struct EffectCard: View {
    let effect: Effect
    let gesture: Gesture
    let selected: Bool
    let on: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PreviewImage(image: EffectPreview.illustration(effect) ?? EffectPreview.after(effect))
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(effect.title).font(.headline).lineLimit(1)
                    Text(gesture == .none ? "Solo con atajo" : gesture.title).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                if on {
                    Text("Activo").font(.caption.weight(.semibold)).foregroundStyle(.green)
                        .padding(.horizontal, 7).padding(.vertical, 2).background(.green.opacity(0.14), in: Capsule())
                } else {
                    Text(effect.shortcut).font(.callout.monospaced()).foregroundStyle(.tertiary)
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

/// Everything about one effect: what it looks like, how it is started, what it says.
struct EffectDetail: View {
    @ObservedObject var engine: Engine
    let effect: Effect
    @Binding var section: Pane
    /// The picture alternates between the room as it is and the room with the effect on.
    @State private var showingAfter = true
    private let flip = Timer.publish(every: 1.8, on: .main, in: .common).autoconnect()

    private var gesture: Gesture { engine.commands[effect] ?? Gesture.none }

    var body: some View {
        Form {
            SwiftUI.Section {
                VStack(alignment: .leading, spacing: 10) {
                    ZStack {
                        if let film = EffectPreview.film(effect) {
                            // The real effect on the model, switched on and off, over and over.
                            LoopingFilm(url: film).aspectRatio(16.0 / 9.0, contentMode: .fit).id(effect)
                        } else if let art = EffectPreview.illustration(effect) {
                            PreviewImage(image: art)
                        } else {
                            // No illustration shipped: the drawn stand-in, alternating before and after.
                            PreviewImage(image: EffectPreview.before)
                            PreviewImage(image: EffectPreview.after(effect)).opacity(showingAfter ? 1 : 0)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onReceive(flip) { _ in withAnimation(.easeInOut(duration: 0.45)) { showingAfter.toggle() } }
                    .accessibilityLabel("Vista previa de \(effect.title)")
                    Text(effect.title).font(.title3.weight(.semibold))
                    Text(effect.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(engine.look == effect.look ? "Quitar" : "Probar en vivo") {
                            engine.toggle(effect)
                            section = .live
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Practicar el gesto") { engine.startPractice(for: [effect]) }
                            .disabled(gesture == Gesture.none)
                    }
                    .padding(.top, 2)
                }
                .padding(.vertical, 4)
            }

            SwiftUI.Section("Cómo se activa") {
                Picker("Posición de manos", selection: Binding(get: { gesture }, set: { engine.commands[effect] = $0 })) {
                    // The recorded one is offered only once there is a recording for this effect.
                    ForEach(Gesture.allCases.filter { $0 != .custom || engine.poses[effect] != nil }) { gesture in Text(gesture.title).tag(gesture) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(gesture.symbol).font(.system(size: 26))
                    Text(gesture.hint).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if gesture == .custom, let photo = engine.posePhotos[effect] {
                    Image(nsImage: photo).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityLabel("Foto de ti haciendo la posición grabada")
                }
                LabeledContent(engine.poses[effect].map { "Tu posición: \($0.summary.lowercased())" } ?? "Tu propia posición") {
                    Button(engine.poses[effect] == nil ? "Grabar…" : "Volver a grabar…") { engine.startRecording(for: effect) }
                }
                LabeledContent("Atajo de teclado") {
                    Text(effect.shortcut).font(.body.monospaced()).foregroundStyle(.secondary)
                }
                if let other = clash {
                    Label("«\(other.title)» usa la misma posición: se activará ese y no este.", systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }
            }

            if [.away, .question, .confetti, .breakTime].contains(effect) {
                SwiftUI.Section(effect == .breakTime ? "Duración" : "Texto") {
                    WordingFields(effect: effect)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: effect) { _, _ in showingAfter = true }
    }

    /// An earlier effect bound to the same gesture wins; say so instead of failing silently.
    private var clash: Effect? {
        guard gesture != Gesture.none else { return nil }
        return Effect.allCases.prefix(while: { $0 != effect }).first { engine.commands[$0] == gesture }
    }
}

/// Which camera Kawaru looks through, the photo of the empty room, and the camera the other apps see.
struct CameraView: View {
    @ObservedObject var engine: Engine
    @ObservedObject var camera: VirtualCamera
    @Binding var section: Pane

    var body: some View {
        Form {
            SwiftUI.Section {
                if engine.sources.isEmpty {
                    LabeledContent("Cámara", value: engine.access == .denied ? "Sin permiso" : "No se encontró ninguna")
                } else {
                    Picker("Cámara", selection: Binding(get: { engine.sourceID }, set: { engine.selectSource($0) })) {
                        ForEach(engine.sources) { source in Text(source.name).tag(source.id) }
                    }
                }
                if engine.fps > 0 {
                    LabeledContent("Rendimiento", value: "\(engine.fps) fps · \(Int(engine.milliseconds.rounded())) ms por fotograma")
                }
            } header: {
                Text("Tu cámara")
            } footer: {
                Text("La imagen se procesa en tu Mac y no se envía a ningún lado. Lo único que se guarda, y solo en este Mac, es la foto que se toma al grabar una posición de manos.").frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }

            SwiftUI.Section {
                LabeledContent {
                    Button(engine.hasBackground ? "Volver a capturar" : "Capturar fondo") { engine.captureBackground() }
                        .disabled(engine.access != .granted || engine.countdown != nil)
                } label: {
                    Text(backgroundState)
                }
            } header: {
                Text("Fondo")
            } footer: {
                Text("Los efectos que te quitan de la imagen necesitan una foto del fondo sin ti. Pulsa y sal del cuadro: se toma a los tres segundos y solo vive en memoria. Repítela si mueves la cámara o cambias de cámara.").frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }

            SwiftUI.Section {
                LabeledContent("Estado") { VirtualCameraControl(camera: camera) }
            } header: {
                Text("Cámara virtual")
            } footer: {
                Text("En Meet, Zoom, Teams o cualquier app de video, elige la cámara «Kawaru». Los demás verán lo mismo que la sección En vivo.").frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }
        }
        .formStyle(.grouped)
    }

    private var backgroundState: String {
        if !engine.hasBackground { return "Sin capturar" }
        return engine.backgroundHasPerson ? "Capturado, pero saliste en la foto" : "Capturado"
    }
}

/// The app's icon in its own colours. `NSApp.applicationIconImage` comes back restyled by the system (grey
/// glass when the Mac's icon style is Clear or Tinted), which is right for the Dock but not for our own pages.
enum AppIcon {
    static let image: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) { return icon }
        return NSApp.applicationIconImage
    }()
}

/// Who made this, and where to find them.
struct AboutView: View {
    var tour: () -> Void = {}
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(nsImage: AppIcon.image).resizable().frame(width: 128, height: 128)
            Text("Kawaru").font(.system(size: 34, weight: .bold, design: .rounded)).padding(.top, 10)
            Text("Versión \(version)").font(.callout).foregroundStyle(.secondary).padding(.top, 2)
            Text("Efectos para tus videollamadas, con un gesto de la mano.")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 14)

            VStack(spacing: 4) {
                Text("Creado por").font(.callout).foregroundStyle(.secondary)
                Text("Francisco Javier Saldivar Rubio").font(.title3.weight(.semibold))
            }
            .padding(.top, 34)

            HStack(spacing: 12) {
                link("LinkedIn", "person.crop.square", "https://www.linkedin.com/in/fsaldivar-dev/")
                link("GitHub", "chevron.left.forwardslash.chevron.right", "https://github.com/fsaldivar-dev")
                link("fsaldivar.dev@gmail.com", "envelope", "mailto:fsaldivar.dev@gmail.com")
            }
            .padding(.top, 16)
            Button("Ver el tutorial de bienvenida", action: tour).buttonStyle(.link).padding(.top, 22)
            Spacer()
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func link(_ title: String, _ symbol: String, _ address: String) -> some View {
        Link(destination: URL(string: address)!) { Label(title, systemImage: symbol) }
            .buttonStyle(.bordered)
            .controlSize(.large)
    }
}
