import Foundation

/// What the filters say and how long the break lasts: the user's own words, kept in the preferences.
/// Read from the capture queue on every frame, which `UserDefaults` allows.
enum Wording {
    enum Key: String {
        case sign1 = "text.sign1", sign2 = "text.sign2", question1 = "text.question1", question2 = "text.question2"
        case cheer = "text.cheer", breakMinutes = "break.minutes"
    }

    static let defaults: [Key: String] = [.sign1: "Regreso en", .sign2: "5 minutos", .question1: "Tengo una", .question2: "pregunta",
                                          .cheer: "¡Bravo!"]
    static let defaultBreakMinutes = 5
    /// Longest text a line takes; past this the lettering would shrink too far to read on a call.
    static let longest = 18

    private static func string(_ key: Key) -> String {
        let saved = UserDefaults.standard.string(forKey: key.rawValue)?.trimmingCharacters(in: .whitespaces) ?? ""
        return String((saved.isEmpty ? defaults[key]! : saved).prefix(longest))
    }

    static var sign: [String] { [string(.sign1), string(.sign2)] }
    static var question: [String] { [string(.question1), string(.question2)] }
    static var cheer: String { string(.cheer) }
    static var breakMinutes: Int {
        let saved = UserDefaults.standard.integer(forKey: Key.breakMinutes.rawValue)
        return saved == 0 ? defaultBreakMinutes : min(60, max(1, saved))
    }
    static var breakTime: Double { Double(breakMinutes) * 60 }
}
