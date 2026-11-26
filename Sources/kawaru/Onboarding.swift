import AVFoundation
import SwiftUI

/// The welcome tour: what Kawaru is, the two things macOS has to be asked for, a first gesture tried on the
/// spot, and how to use it in a call. One idea per step, a picture of the real thing beside it.
struct Onboarding: View {
    @ObservedObject var engine: Engine
    @ObservedObject var camera: VirtualCamera
    var finish: () -> Void

    /// `-tourStep 3` on the command line opens on that step.
    @State private var step = min(4, max(0, UserDefaults.standard.integer(forKey: "tourStep") - 1))
    private let count = 5
    /// The effect tried in the tour: the easiest gesture, with the most obvious result.
    private let first = Effect.confetti

    var body: some View {
        HStack(spacing: 0) {
            picture
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.96, green: 0.93, blue: 0.88))
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(0..<count, id: \.self) { i in
                        Capsule().fill(i <= step ? Color.accentColor : Color.primary.opacity(0.15)).frame(width: i == step ? 22 : 8, height: 8)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: step)   // only the dots glide; words and picture cut
                .accessibilityLabel(tr("Paso %lld de %lld", step + 1, count))
                Spacer()
                words
                Spacer()
                HStack {
                    if step > 0 { Button(tr("Atrás")) { go(step - 1) } }
                    Spacer()
                    buttons
                }
                .controlSize(.large)
            }
            .padding(40)
            .frame(width: 420)
            .frame(maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .onChange(of: step) { old, new in
            if old == 3 { engine.stopPractice() }
            if new == 2 { camera.start() }
            if new == 3 { engine.start(); engine.startPractice(for: [first]) }
        }
        .onAppear {
            if step == 2 { camera.start() }
            if step == 3 { engine.start(); engine.startPractice(for: [first]) }
        }
    }

    private func go(_ to: Int) { step = min(count - 1, max(0, to)) }

    // MARK: The picture

    @ViewBuilder private var picture: some View {
        switch step {
        case 0: film(.substitution)
        case 1: film(.question)
        case 2: film(.away)
        case 3:
            ZStack {
                Color.black
                if engine.access == .granted {
                    Preview(layer: engine.display, mirrored: true)
                    if !engine.joints.isEmpty { HandMarksView(hands: engine.joints, mirrored: true) }
                } else {
                    Label(tr("Sin cámara todavía"), systemImage: "video.slash").foregroundStyle(.white.opacity(0.7))
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(28)
        default: film(.clones)
        }
    }

    @ViewBuilder private func film(_ effect: Effect) -> some View {
        Group {
            if let url = EffectPreview.film(effect) {
                LoopingFilm(url: url).id(effect)
            } else {
                PreviewImage(image: EffectPreview.illustration(effect) ?? EffectPreview.after(effect))
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .padding(28)
        .accessibilityLabel(tr("Ejemplo del efecto %@", effect.title))
    }

    // MARK: The words

    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 30, weight: .bold, design: .rounded)).fixedSize(horizontal: false, vertical: true)
    }

    private func text(_ text: String) -> some View {
        Text(text).font(.title3).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
    }

    private func done(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Color.accentColor).frame(width: 26)
            Text(text).font(.body).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var words: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch step {
            case 0:
                Image(nsImage: AppIcon.image).resizable().frame(width: 72, height: 72)
                title(tr("Tus videollamadas, con un gesto"))
                text(tr("Haz una seña con la mano y Kawaru pone un efecto sobre tu cámara: confeti para celebrar, un cartel cuando te ausentas, un globo para pedir la palabra."))
                text(tr("Funciona en Meet, Zoom, Teams y cualquier app de video."))
            case 1:
                title(tr("Primero, tu cámara"))
                text(tr("Kawaru mira tu cámara para leer tus manos. Todo pasa en tu Mac: nada se sube a internet."))
                switch engine.access {
                case .granted: done(tr("Cámara lista"))
                case .denied:
                    Label(tr("Kawaru no tiene permiso de cámara. Actívalo en Configuración del Sistema, Privacidad y seguridad, Cámara, y vuelve a abrir Kawaru."), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                case .noCamera: Label(tr("No se encontró ninguna cámara."), systemImage: "video.slash").foregroundStyle(.orange)
                case .asking: EmptyView()
                }
            case 2:
                title(tr("Una cámara nueva para tus llamadas"))
                text(tr("Instala la cámara virtual «Kawaru». Es la que elegirás en Meet o Zoom para que los demás vean tus efectos."))
                switch camera.state {
                case .ready: done(tr("Cámara virtual lista"))
                case .needsApproval:
                    text(tr("macOS pide que la apruebes tú: en Configuración del Sistema, General, Ítems de inicio y extensiones, Extensiones de cámara, activa Kawaru."))
                    VirtualCameraControl(camera: camera)
                default: VirtualCameraControl(camera: camera)
                }
            case 3:
                let gesture = engine.commands[first] ?? first.defaultGesture
                title(engine.practiceHits >= Engine.practiceGoal ? tr("¡Eso es!") : tr("Tu primer gesto"))
                HStack(alignment: .center, spacing: 14) {
                    Text(gesture.symbol).font(.system(size: 44))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(gesture.title).font(.title3.weight(.semibold))
                        Text(gesture.hint).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                text(tr("Mantenlo medio segundo frente a la cámara, bájalo y repite. En una llamada, este gesto lanza «%@».", first.title))
                HStack(spacing: 8) {
                    ForEach(0..<Engine.practiceGoal, id: \.self) { i in
                        Circle().fill(i < engine.practiceHits ? Color.green : Color.primary.opacity(0.15)).frame(width: 14, height: 14)
                    }
                    if engine.practiceHits < Engine.practiceGoal, let tip = engine.practiceTip {
                        Label(tip, systemImage: "lightbulb").font(.callout).foregroundStyle(.orange).padding(.leading, 6)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: engine.practiceHits)
            default:
                title(tr("Listo para tu próxima llamada"))
                VStack(alignment: .leading, spacing: 14) {
                    point("web.camera", tr("En Meet, Zoom o Teams, elige la cámara «Kawaru»."))
                    point("hand.raised", tr("Cada efecto tiene su gesto y su atajo de teclado. Cámbialos, o graba tu propio gesto, en Efectos."))
                    point("photo", tr("Para los efectos que te quitan de la imagen, captura antes el fondo sin ti, en Cámara."))
                }
            }
        }
    }

    // MARK: The buttons

    @ViewBuilder private var buttons: some View {
        switch step {
        case 0:
            Button(tr("Empezar")) { go(1) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        case 1:
            if engine.access == .asking {
                Button(tr("Permitir cámara")) { engine.start() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            } else {
                Button(tr("Continuar")) { go(2) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        case 2:
            if case .ready = camera.state {
                Button(tr("Continuar")) { go(3) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            } else {
                Button(tr("Más tarde")) { go(3) }
            }
        case 3:
            if engine.practiceHits >= Engine.practiceGoal {
                Button(tr("Continuar")) { go(4) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            } else {
                Button(tr("Saltar")) { go(4) }
            }
        default:
            Button(tr("Abrir Kawaru"), action: finish).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }
    }
}
