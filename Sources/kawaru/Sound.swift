import AVFoundation

/// The "poof" of the swap: a burst of air that closes down, with a knock of wood under it.
/// Synthesized here, so there is no audio file to license or ship.
final class Poof {
    private var player: AVAudioPlayer?

    /// `air` false leaves only the knock of wood: the sign landing.
    init(air: Bool = true) {
        let rate = 44_100.0, length = 0.5
        let count = Int(rate * length)
        var samples = [Int16](repeating: 0, count: count)
        let withAir = air
        var seed: UInt64 = 0x706f6f66
        var low = 0.0
        for i in 0..<count {
            let t = Double(i) / rate
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let noise = Double((seed >> 33) % 20_001) / 10_000 - 1
            // Air: noise through a low-pass whose cutoff falls, so it starts bright and ends dull.
            let cutoff = 400 + 5200 * exp(-t * 9)
            let a = 1 - exp(-2 * Double.pi * cutoff / rate)
            low += (noise - low) * a
            let air = low * min(1, t / 0.008) * exp(-t * 7.5)
            // Wood: two short, damped tones.
            let k = max(0, t - 0.03)
            let wood = t < 0.03 ? 0 : (sin(2 * .pi * 190 * k) * 0.6 + sin(2 * .pi * 430 * k) * 0.3) * exp(-k * 38)
            samples[i] = Int16(max(-1, min(1, (withAir ? air * 1.5 : 0) + wood * (withAir ? 0.7 : 1.3))) * 26_000)
        }
        var wav = Data()
        func put<T>(_ v: T) { withUnsafeBytes(of: v) { wav.append(contentsOf: $0) } }
        let bytes = UInt32(count * 2)
        wav.append(contentsOf: Array("RIFF".utf8)); put(36 + bytes); wav.append(contentsOf: Array("WAVEfmt ".utf8))
        put(UInt32(16)); put(UInt16(1)); put(UInt16(1)); put(UInt32(rate)); put(UInt32(rate) * 2); put(UInt16(2)); put(UInt16(16))
        wav.append(contentsOf: Array("data".utf8)); put(bytes)
        samples.withUnsafeBytes { wav.append(contentsOf: $0) }
        player = try? AVAudioPlayer(data: wav)
        player?.prepareToPlay()
    }

    func play() {
        player?.currentTime = 0
        player?.play()
    }
}
