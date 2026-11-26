import ServiceManagement
import SwiftUI

/// What drops down from the menu bar icon: every effect one click away, without bringing the window forward.
struct MenuPanel: View {
    @ObservedObject var engine: Engine
    @ObservedObject var camera: VirtualCamera
    @Environment(\.openWindow) private var openWindow
    @State private var atLogin = SMAppService.mainApp.status == .enabled
    @State private var loginProblem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: AppIcon.image).resizable().frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Kawaru").font(.headline)
                    Text(status).font(.callout).foregroundStyle(statusTint)
                }
                Spacer()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
                ForEach(Effect.allCases) { effect in
                    Button { engine.toggle(effect) } label: { tile(effect) }
                        .buttonStyle(.plain)
                        .help("\(effect.title) · \(effect.shortcut)")
                }
            }

            if !engine.rotulos.isEmpty {
                Divider()
                Text(tr("Rótulos")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                VStack(spacing: 2) {
                    ForEach(Array(engine.rotulos.prefix(9).enumerated()), id: \.element.id) { index, rotulo in
                        let up = engine.captionsUp.contains(rotulo.id)
                        Button { engine.toggle(rotulo) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: up ? "checkmark.circle.fill" : rotulo.kind.symbol).foregroundStyle(up ? Color.green : Color.secondary).frame(width: 20)
                                Text(rotulo.title.isEmpty ? rotulo.kind.title : rotulo.title).lineLimit(1)
                                Spacer()
                                Text("⌃⌥⇧\(index + 1)").font(.caption.monospaced()).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()
            Toggle(tr("Gestos de manos"), isOn: $engine.gesturesOn)
                .help(tr("Apágalos cuando vayas a mover mucho las manos; los atajos y estos botones siguen funcionando."))
            Toggle(tr("Abrir al iniciar sesión"), isOn: Binding(get: { atLogin }, set: setLogin))
            if let loginProblem { Text(loginProblem).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            Divider()
            HStack {
                Button(tr("Abrir Kawaru")) {
                    openWindow(id: "main")
                    AppDelegate.showWindow()
                }
                Spacer()
                Button(tr("Salir")) { NSApp.terminate(nil) }
            }
        }
        .toggleStyle(.switch)
        .padding(16)
        .frame(width: 340)
    }

    private func tile(_ effect: Effect) -> some View {
        let on = engine.look == effect.look
        return VStack(spacing: 4) {
            PreviewImage(image: EffectPreview.illustration(effect) ?? EffectPreview.after(effect))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(on ? Color.green : Color.primary.opacity(0.12), lineWidth: on ? 2.5 : 1))
            Text(short(effect)).font(.caption).lineLimit(1).foregroundStyle(on ? Color.green : Color.primary)
        }
        .contentShape(Rectangle())
        .accessibilityLabel(on ? tr("%@, activo", effect.title) : effect.title)
    }

    /// One word for under the picture.
    private func short(_ effect: Effect) -> String {
        switch effect {
        case .substitution: tr("Sustitución")
        case .clones: tr("Clones")
        case .away: tr("Cartel")
        case .question: tr("Pregunta")
        case .confetti: tr("Confeti")
        case .breakTime: tr("Descanso")
        case .spotlight: tr("Foco")
        }
    }

    private var status: String {
        if engine.access != .granted { return tr("Sin cámara") }
        if let n = engine.watchers, n > 0 { return n == 1 ? tr("En uso en una llamada") : tr("En uso en %lld apps", n) }
        return engine.cameraOn ? tr("Cámara encendida") : tr("En espera, cámara apagada")
    }

    private var statusTint: Color {
        if let n = engine.watchers, n > 0 { return .green }
        return .secondary
    }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginProblem = nil
        } catch {
            loginProblem = tr("No se pudo cambiar: %@", error.localizedDescription)
        }
        atLogin = SMAppService.mainApp.status == .enabled
    }
}
