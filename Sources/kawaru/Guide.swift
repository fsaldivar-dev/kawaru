import SwiftUI

/// The guided walk round the window: one balloon at a time, pointing at the real control it explains.
final class Guide: ObservableObject {
    /// A part of the window a balloon can point at.
    enum Spot: Hashable { case gallery, film, tryLive, gesture, record, practise, shortcut, cameraPane, livePane }

    struct Stop { let spot: Spot; let title: String; let text: String }

    static let stops: [Stop] = [
        Stop(spot: .gallery, title: tr("Aquí están tus efectos"), text: tr("Cada tarjeta es un efecto, con el gesto que lo activa debajo. Haz clic en una para verla y configurarla a la derecha.")),
        Stop(spot: .film, title: tr("Así lo verán los demás"), text: tr("El video muestra el efecto real encendiéndose y apagándose, tal como saldrá en tu llamada.")),
        Stop(spot: .tryLive, title: tr("Pruébalo en tu cámara"), text: tr("Lo enciende sobre tu imagen en la sección En vivo. Se quita con el mismo botón, con el gesto o con el atajo.")),
        Stop(spot: .gesture, title: tr("El gesto que lo activa"), text: tr("Elige una de las posiciones de mano que Kawaru ya conoce, o «Ninguno» si solo quieres usar el atajo.")),
        Stop(spot: .record, title: tr("O graba tu propio gesto"), text: tr("Tienes tres segundos para poner las manos. Después lo repites tres veces para que Kawaru aprenda cómo te sale. Se guarda una foto para que lo recuerdes.")),
        Stop(spot: .practise, title: tr("Practica hasta que salga"), text: tr("Te muestra el gesto y los puntos de tu mano, y cuenta cada vez que lo reconoce. Mientras practicas no se dispara ningún efecto.")),
        Stop(spot: .shortcut, title: tr("También con el teclado"), text: tr("Cada efecto tiene su atajo. Funciona aunque la videollamada esté al frente.")),
        Stop(spot: .cameraPane, title: tr("Tu cámara y tu fondo"), text: tr("Aquí eliges la cámara, capturas el fondo sin ti (lo necesitan los efectos que te quitan de la imagen) y ves si la cámara virtual está lista.")),
        Stop(spot: .livePane, title: tr("Lo que sale en la llamada"), text: tr("En vivo muestra tu cámara con el efecto puesto. Es exactamente lo que ven los demás cuando eliges la cámara «Kawaru».")),
    ]

    /// The stop being shown; nil when the walk is not running.
    @Published var index: Int?
    /// Where each spot is in the window right now.
    @Published var frames: [Spot: CGRect] = [:]

    var stop: Stop? { index.map { Self.stops[$0] } }

    func start(at index: Int = 0) { self.index = min(Self.stops.count - 1, max(0, index)) }

    func next() {
        guard let index else { return }
        if index + 1 < Self.stops.count { self.index = index + 1 } else { end() }
    }

    func back() { if let index, index > 0 { self.index = index - 1 } }

    func end() {
        index = nil
        UserDefaults.standard.set(true, forKey: "guided")
    }
}

extension View {
    /// Tells the guide where this view is, so a balloon can point at it.
    func guideSpot(_ spot: Guide.Spot?, in guide: Guide) -> some View {
        background(GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            Color.clear
                .onAppear { if let spot { guide.frames[spot] = frame } }
                .onChange(of: frame) { _, new in if let spot { guide.frames[spot] = new } }
        })
    }
}

/// The balloon and the dimming around the control it points at. Laid over the whole window.
struct GuideOverlay: View {
    @ObservedObject var guide: Guide
    private let card = CGSize(width: 320, height: 190)

    var body: some View {
        GeometryReader { proxy in
            if let index = guide.index, let stop = guide.stop {
                let origin = proxy.frame(in: .global).origin
                let bounds = CGRect(origin: .zero, size: proxy.size)
                let target = guide.frames[stop.spot].map { $0.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -6, dy: -6).intersection(bounds) }
                    .flatMap { $0.isNull || $0.isEmpty ? nil : $0 }
                ZStack(alignment: .topLeading) {
                    // Everything but the control goes dim, and takes the clicks so nothing changes under the tour.
                    Path { path in
                        path.addRect(bounds)
                        if let target { path.addRoundedRect(in: target, cornerSize: CGSize(width: 10, height: 10)) }
                    }
                    .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    if let target {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 2.5)
                            .frame(width: target.width, height: target.height).offset(x: target.minX, y: target.minY)
                            .allowsHitTesting(false)
                    }
                    balloon(stop, index).frame(width: card.width)
                        .offset(place(beside: target, in: bounds))
                }
                .animation(.easeInOut(duration: 0.2), value: index)
            }
        }
    }

    private func balloon(_ stop: Guide.Stop, _ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("%lld de %lld", index + 1, Guide.stops.count)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(stop.title).font(.headline)
            Text(stop.text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(tr("Saltar")) { guide.end() }.buttonStyle(.link).keyboardShortcut(.cancelAction)
                Spacer()
                if index > 0 { Button(tr("Atrás")) { guide.back() } }
                Button(index + 1 < Guide.stops.count ? tr("Siguiente") : tr("Terminar")) { guide.next() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
    }

    /// Beside the control where there is room: to its left or right first, then under or over it; over the
    /// control itself, at the bottom, when it fills the window.
    private func place(beside target: CGRect?, in bounds: CGRect) -> CGSize {
        guard let target else { return CGSize(width: (bounds.width - card.width) / 2, height: (bounds.height - card.height) / 2) }
        let gap: CGFloat = 14
        func clampY(_ y: CGFloat) -> CGFloat { min(max(12, y), bounds.height - card.height - 12) }
        func clampX(_ x: CGFloat) -> CGFloat { min(max(12, x), bounds.width - card.width - 12) }
        if target.minX - gap - card.width >= 12 { return CGSize(width: target.minX - gap - card.width, height: clampY(target.minY)) }
        if target.maxX + gap + card.width <= bounds.width - 12 { return CGSize(width: target.maxX + gap, height: clampY(target.minY)) }
        if target.maxY + gap + card.height <= bounds.height - 12 { return CGSize(width: clampX(target.minX), height: target.maxY + gap) }
        if target.minY - gap - card.height >= 12 { return CGSize(width: clampX(target.minX), height: target.minY - gap - card.height) }
        return CGSize(width: clampX(target.midX - card.width / 2), height: bounds.height - card.height - 24)
    }
}
