import AVFoundation
import SwiftUI

@main
struct KawaruApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var engine = Engine()

    var body: some Scene {
        Window("Kawaru", id: "main") {
            ContentView(engine: engine, camera: engine.virtualCamera).onAppear { engine.start(); engine.virtualCamera.start() }
        }
        .defaultSize(width: 900, height: 620)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct ContentView: View {
    @ObservedObject var engine: Engine
    @ObservedObject var camera: VirtualCamera
    @State private var showingCommands = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                switch engine.access {
                case .granted:
                    Preview(layer: engine.display, mirrored: !engine.look.hasText)
                    if let effect = engine.recording {
                        RecordingCard(engine: engine, effect: effect)
                    } else if let gesture = engine.practice, engine.countdown == nil {
                        VStack {
                            PracticeCard(engine: engine, gesture: gesture)
                            Spacer()
                        }
                        .padding(16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if let left = engine.countdown {
                        VStack(spacing: 10) {
                            Text("\(left)").font(.system(size: 96, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text("Sal del cuadro").font(.title3.weight(.medium))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black.opacity(0.45))
                    } else if let hint, engine.practice == nil {
                        VStack {
                            Spacer()
                            Label(hint, systemImage: "photo")
                                .font(.callout)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(.regularMaterial, in: Capsule())
                                .padding(16)
                        }
                    }
                case .asking:
                    notice("video", "Esperando el permiso de cámara")
                case .denied:
                    notice("video.slash", "Kawaru no tiene permiso de cámara. Actívalo en Configuración del Sistema, Privacidad y seguridad, Cámara.")
                case .noCamera:
                    notice("video.slash", "No se encontró ninguna cámara")
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 14) {
                StatePill(look: engine.look, hold: engine.hold, holding: engine.holding)
                Text(status).font(.callout).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                Spacer(minLength: 20)
                VirtualCameraControl(camera: camera)
                Button(engine.hasBackground ? "Volver a capturar" : "Capturar fondo") { engine.captureBackground() }
                    .help("Pulsa y sal del cuadro: a los tres segundos Kawaru fotografía el fondo sin ti. Solo se guarda en memoria.")
                    .disabled(engine.access != .granted || engine.countdown != nil)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(minWidth: 680, minHeight: 480)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingCommands = true } label: { Label("Comandos", systemImage: "hand.raised") }
                    .help("Elige qué posición de manos activa cada efecto")
            }
        }
        .sheet(isPresented: $showingCommands) { CommandsView(engine: engine) }
        .animation(.easeOut(duration: 0.25), value: engine.practice)
        .alert("No se pudo grabar la posición", isPresented: Binding(get: { engine.recordProblem != nil }, set: { if !$0 { engine.recordProblem = nil } })) {
            Button("Entendido", role: .cancel) {}
        } message: {
            Text(engine.recordProblem ?? "")
        }
        .onChange(of: engine.access) { _, access in
            // The first time the camera is on: walk through the gesture of each effect.
            if access == .granted, !UserDefaults.standard.bool(forKey: "practised") {
                engine.startPractice(for: Effect.allCases)
            }
        }
    }

    /// What is missing before the swap can hide the person completely.
    private var hint: String? {
        if !engine.hasBackground { return "Para desaparecer por completo, captura el fondo sin ti antes de empezar" }
        if engine.backgroundHasPerson { return "Saliste en la captura del fondo. Repítela fuera del cuadro" }
        return nil
    }

    private var status: String {
        guard engine.access == .granted else { return "" }
        guard engine.fps > 0 else { return engine.cameraName }
        return "\(engine.cameraName) · \(engine.fps) fps · \(Int(engine.milliseconds.rounded())) ms por fotograma"
    }

    private func notice(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 34, weight: .light))
            Text(text).multilineTextAlignment(.center).frame(maxWidth: 380)
        }
        .foregroundStyle(.white.opacity(0.75))
        .padding(40)
    }
}

/// «Tú», the gesture being held while its meter fills, or the effect that is on.
struct StatePill: View {
    let look: Look
    let hold: Double
    let holding: Gesture

    var body: some View {
        let filling = hold > 0
        let tint: Color = filling ? .accentColor : (look == .person ? .secondary : .green)
        let names: [Look: String] = [.trunk: "Tronco activo", .clones: "Clones activos", .away: "Cartel activo", .question: "Pregunta activa",
                                     .confetti: "Confeti", .breakTime: "Descanso activo", .spotlight: "Foco activo"]
        let text = filling ? holding.title + "…" : (names[look] ?? "Tú")
        HStack(spacing: 7) {
            ZStack {
                Circle().stroke(tint.opacity(0.25), lineWidth: 2)
                Circle().trim(from: 0, to: filling ? hold : 1).stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 11, height: 11)
            Text(text).font(.callout.weight(.medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
        .animation(.easeOut(duration: 0.15), value: look)
    }
}

/// Which hand position starts each effect.
struct CommandsView: View {
    @ObservedObject var engine: Engine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                ForEach(Effect.allCases) { effect in
                    Section {
                        Picker("Posición de manos", selection: binding(effect)) {
                            // The recorded one is offered only once there is a recording for this effect.
                            ForEach(Gesture.allCases.filter { $0 != .custom || engine.poses[effect] != nil }) { gesture in Text(gesture.title).tag(gesture) }
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text((engine.commands[effect] ?? .none).symbol).font(.system(size: 30))
                            Text((engine.commands[effect] ?? .none).hint).font(.callout).foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Button("Practicar") {
                                dismiss()
                                engine.startPractice(for: [effect])
                            }
                            .disabled((engine.commands[effect] ?? Gesture.none) == Gesture.none)
                        }
                        LabeledContent(engine.poses[effect].map { "Tu propia posición: \($0.summary.lowercased())" } ?? "Tu propia posición") {
                            Button(engine.poses[effect] == nil ? "Grabar posición…" : "Volver a grabar…") {
                                dismiss()
                                engine.startRecording(for: effect)
                            }
                        }
                        LabeledContent("Atajo de teclado") {
                            Text(effect.shortcut).font(.body.monospaced()).foregroundStyle(.secondary)
                        }
                        WordingFields(effect: effect)
                        if let other = clash(effect) {
                            Label("«\(other.title)» usa la misma posición: se activará ese y no este.", systemImage: "exclamationmark.triangle")
                                .font(.callout).foregroundStyle(.orange)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(effect.title).font(.headline).foregroundStyle(.primary)
                            Text(effect.detail).font(.callout).foregroundStyle(.secondary)
                        }
                        .textCase(nil)
                        .padding(.bottom, 4)
                    }
                }
                Section {
                    Text("Mantén la posición algo más de medio segundo. La misma posición apaga el efecto; la de otro efecto cambia a ese. Los atajos funcionan aunque la videollamada esté al frente.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Practicar todas las posiciones") {
                        dismiss()
                        engine.startPractice(for: Effect.allCases)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Listo") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 520, height: 720)
    }

    private func binding(_ effect: Effect) -> Binding<Gesture> {
        Binding(get: { engine.commands[effect] ?? .none }, set: { engine.commands[effect] = $0 })
    }

    /// An earlier effect bound to the same gesture wins; say so instead of failing silently.
    private func clash(_ effect: Effect) -> Effect? {
        guard let gesture = engine.commands[effect], gesture != .none else { return nil }
        return Effect.allCases.prefix(while: { $0 != effect }).first { engine.commands[$0] == gesture }
    }
}

/// The words an effect shows, or how long it lasts, for the effects that have either.
struct WordingFields: View {
    let effect: Effect
    @AppStorage(Wording.Key.sign1.rawValue) private var sign1 = ""
    @AppStorage(Wording.Key.sign2.rawValue) private var sign2 = ""
    @AppStorage(Wording.Key.question1.rawValue) private var question1 = ""
    @AppStorage(Wording.Key.question2.rawValue) private var question2 = ""
    @AppStorage(Wording.Key.cheer.rawValue) private var cheer = ""
    @AppStorage(Wording.Key.breakMinutes.rawValue) private var minutes = Wording.defaultBreakMinutes

    var body: some View {
        switch effect {
        case .away:
            field("Primera línea", $sign1, .sign1)
            field("Segunda línea", $sign2, .sign2)
        case .question:
            field("Primera línea", $question1, .question1)
            field("Segunda línea", $question2, .question2)
        case .confetti:
            field("Palabra", $cheer, .cheer)
        case .breakTime:
            Stepper(value: $minutes, in: 1...60) {
                LabeledContent("Duración") { Text(minutes == 1 ? "1 minuto" : "\(minutes) minutos").foregroundStyle(.secondary) }
            }
        default:
            EmptyView()
        }
    }

    /// Empty means the built-in text, shown as the placeholder.
    private func field(_ label: String, _ text: Binding<String>, _ key: Wording.Key) -> some View {
        TextField(label, text: text, prompt: Text(Wording.defaults[key] ?? ""))
            .onChange(of: text.wrappedValue) { _, new in
                if new.count > Wording.longest { text.wrappedValue = String(new.prefix(Wording.longest)) }
            }
    }
}

/// Mirrored, like looking at yourself in any video-call app. Not while the sign is up: its text has to read
/// the right way round here, the way the others see it.
struct Preview: NSViewRepresentable {
    let layer: AVSampleBufferDisplayLayer
    let mirrored: Bool

    final class Host: NSView {
        var video: CALayer?
        var mirrored = true { didSet { if mirrored != oldValue { needsLayout = true } } }
        override func layout() {
            super.layout()
            guard let video else { return }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            video.setAffineTransform(.identity)
            video.frame = bounds
            video.setAffineTransform(CGAffineTransform(scaleX: mirrored ? -1 : 1, y: 1))
            CATransaction.commit()
        }
    }

    func makeNSView(context: Context) -> Host {
        let host = Host()
        host.wantsLayer = true
        host.layer?.addSublayer(layer)
        host.video = layer
        host.mirrored = mirrored
        return host
    }

    func updateNSView(_ nsView: Host, context: Context) { nsView.mirrored = mirrored }
}

/// Where the virtual camera stands, and the one thing to do about it.
struct VirtualCameraControl: View {
    @ObservedObject var camera: VirtualCamera

    var body: some View {
        switch camera.state {
        case .ready:
            Label("Cámara virtual activa", systemImage: "web.camera")
                .font(.callout).foregroundStyle(.secondary)
                .help("En Meet, Zoom o cualquier app de video, elige la cámara «Kawaru».")
        case .notInstalled:
            Button("Instalar cámara virtual") { camera.install() }
                .help("Instala la cámara «Kawaru» para usarla en Meet, Zoom y otras apps. macOS te pedirá aprobarla.")
        case .installing:
            HStack(spacing: 7) { ProgressView().controlSize(.small); Text("Instalando…").font(.callout).foregroundStyle(.secondary) }
        case .needsApproval:
            Button("Aprobar en Configuración…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
            }
            .help("Actívala en Configuración del Sistema, General, Ítems de inicio y extensiones, Extensiones de cámara.")
        case .unavailable(let why):
            Label("Cámara virtual no disponible", systemImage: "web.camera").font(.callout).foregroundStyle(.tertiary).help(why)
        case .failed(let why):
            Button("Reintentar instalación") { camera.install() }.help("No se pudo instalar: \(why)")
        }
    }
}

/// Teaches one hand position: what it looks like, how to do it, what to change when it is not being read,
/// and a count of the times it has been read. Sits over the top of the preview so the hand stays in view.
struct PracticeCard: View {
    @ObservedObject var engine: Engine
    let gesture: Gesture

    private var done: Bool { engine.practiceHits >= Engine.practiceGoal }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(gesture.symbol).font(.system(size: 46)).frame(minWidth: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(done ? "¡Listo! \(gesture.title)" : "Practica: \(gesture.title)").font(.headline)
                Text(gesture.hint).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !done, let tip = engine.practiceTip {
                    Label(tip, systemImage: "lightbulb").font(.callout.weight(.medium)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !done, engine.hold > 0 {
                    Label("Bien, mantenla…", systemImage: "checkmark.circle").font(.callout.weight(.medium)).foregroundStyle(.green)
                }
            }
            Spacer(minLength: 12)
            // One dot per successful read.
            HStack(spacing: 6) {
                ForEach(0..<Engine.practiceGoal, id: \.self) { i in
                    Circle().fill(i < engine.practiceHits ? Color.green : Color.secondary.opacity(0.3)).frame(width: 10, height: 10)
                }
            }
            if done {
                Button(engine.practiceLeft > 0 ? "Siguiente" : "Terminar") { engine.nextPractice() }.keyboardShortcut(.defaultAction)
            } else {
                Button("Saltar") { engine.nextPractice() }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.easeOut(duration: 0.2), value: engine.practiceHits)
    }
}

/// Recording a hand position: a countdown to get the hands ready, then a moment of holding still.
struct RecordingCard: View {
    @ObservedObject var engine: Engine
    let effect: Effect

    var body: some View {
        VStack(spacing: 12) {
            if let left = engine.recordCountdown {
                Text("\(left)").font(.system(size: 96, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("Pon las manos como quieras para «\(effect.title)»").font(.title3.weight(.medium))
                Text("Elige una posición que no hagas sin querer, y mantenla quieta.").font(.callout).opacity(0.85)
            } else {
                Image(systemName: "record.circle").font(.system(size: 64, weight: .light)).symbolEffect(.pulse)
                Text("Grabando… no te muevas").font(.title3.weight(.medium))
            }
            Button("Cancelar") { engine.cancelRecording() }.padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(engine.recordCountdown == nil ? 0.2 : 0.45))
    }
}
