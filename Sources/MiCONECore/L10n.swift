import Foundation

/// Texte traduit (Resources/<langue>.lproj/Localizable.strings : fr, en, es, it) ; langue du système, anglais sinon.
/// MICONE_LANG=fr|en|es|it force une langue (essais).
public func L(_ key: String, _ args: CVarArg...) -> String {
    let text = Lang.bundle.localizedString(forKey: key, value: nil, table: nil)
    return args.isEmpty ? text : String(format: text, locale: Locale.current, arguments: args)
}

public enum Lang {
    /// Bundle de la langue forcée par MICONE_LANG (essais), sinon le bundle de l'appli.
    static let bundle: Bundle = {
        if let forced = ProcessInfo.processInfo.environment["MICONE_LANG"]?.prefix(2).lowercased(),
           ["fr", "en", "es", "it"].contains(forced),
           let path = Bundle.main.path(forResource: forced, ofType: "lproj"), let b = Bundle(path: path) { return b }
        return Bundle.main
    }()

    /// Code de la langue affichée (fr, en, es, it), pour le moteur de mise à jour.
    public static var code: String {
        if let forced = ProcessInfo.processInfo.environment["MICONE_LANG"]?.prefix(2).lowercased(),
           ["fr", "en", "es", "it"].contains(forced) { return String(forced) }
        return Bundle.main.preferredLocalizations.first ?? "en"
    }
}
