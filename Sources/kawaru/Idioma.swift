import CoreText
import Foundation

/// Where the translations are read from: the app itself, or, for scripts/previews.sh, the folder named in
/// KAWARU_IDIOMA (one of assets/idiomas/*.lproj), so the gallery's films can be made in every language.
private let translations: Bundle = ProcessInfo.processInfo.environment["KAWARU_IDIOMA"].flatMap { Bundle(path: $0) } ?? .main

/// The text in the user's language. The Spanish text is the key; the translations live in
/// assets/idiomas/<language>.lproj/Localizable.strings, and scripts/idiomas.sh checks none is missing.
/// With arguments the text is a format: %@ for words, %lld for whole numbers.
func tr(_ key: String, _ arguments: CVarArg...) -> String {
    let text = translations.localizedString(forKey: key, value: key, table: nil)
    return arguments.isEmpty ? text : String(format: text, arguments: arguments)
}

/// The language the app is showing, as its folder in assets/idiomas is named ("es", "en", "pt-BR"…).
let shownLanguage: String = {
    if let forced = ProcessInfo.processInfo.environment["KAWARU_IDIOMA"] { return URL(fileURLWithPath: forced).deletingPathExtension().lastPathComponent }
    return Bundle.main.preferredLocalizations.first ?? "es"
}()

/// The typeface for words drawn on the video. The Latin faces have no Japanese, Chinese or Korean letters, and
/// what the system puts in their place is a thin serif that cannot be read on a call: those get a sturdy sans instead.
func lettering(_ name: String, _ size: CGFloat, for text: String) -> CTFont {
    var kana = false, hangul = false, han = false
    for scalar in text.unicodeScalars {
        switch scalar.value {
        case 0x3040...0x30FF: kana = true
        case 0x1100...0x11FF, 0xAC00...0xD7AF: hangul = true
        case 0x4E00...0x9FFF, 0x3400...0x4DBF: han = true
        default: break
        }
    }
    guard kana || hangul || han else { return CTFontCreateWithName(name as CFString, size, nil) }
    let heavy = ["Bold", "Wide", "Black", "Demi"].contains { name.contains($0) }
    let face: String
    if hangul { face = heavy ? "AppleSDGothicNeo-Bold" : "AppleSDGothicNeo-Medium" }
    else if kana || shownLanguage == "ja" { face = heavy ? "HiraginoSans-W7" : "HiraginoSans-W4" }
    else { face = heavy ? "PingFangSC-Semibold" : "PingFangSC-Regular" }
    return CTFontCreateWithName(face as CFString, size, nil)
}
