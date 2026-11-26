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

            Divider()
            Toggle("Gestos de manos", isOn: $engine.gesturesOn)
                .help("Apágalos cuando vayas a mover mucho las manos; los atajos y estos botones siguen funcionando.")
            Toggle("Abrir al iniciar sesión", isOn: Binding(get: { atLogin }, set: setLogin))
            if let loginProblem { Text(loginProblem).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            Divider()
            HStack {
                Button("Abrir Kawaru") {
                    openWindow(id: "main")
                    AppDelegate.showWindow()
                }
                Spacer()
                Button("Salir") { NSApp.terminate(nil) }
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
        .accessibilityLabel("\(effect.title)\(on ? ", activo" : "")")
    }

    /// One word for under the picture.
    private func short(_ effect: Effect) -> String {
        switch effect {
        case .substitution: "Sustitución"
        case .clones: "Clones"
        case .away: "Cartel"
        case .question: "Pregunta"
        case .confetti: "Confeti"
        case .breakTime: "Descanso"
        case .spotlight: "Foco"
        }
    }

    private var status: String {
        if engine.access != .granted { return "Sin cámara" }
        if let n = engine.watchers, n > 0 { return n == 1 ? "En uso en una llamada" : "En uso en \(n) apps" }
        return engine.cameraOn ? "Cámara encendida" : "En espera, cámara apagada"
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
            loginProblem = "No se pudo cambiar: \(error.localizedDescription)"
        }
        atLogin = SMAppService.mainApp.status == .enabled
    }
}
