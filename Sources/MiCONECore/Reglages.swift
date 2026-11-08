import Foundation

/// Réglages de rendu d'une icône (mêmes valeurs par défaut que la version Python).
public struct Reglages: Codable, Equatable, Sendable {
    public var type = "appli"            // « appli » (squircle) ou « dossier »
    public var fondDossier = "bleu"      // clé de Rendu.dossiers ou "perso"
    public var grave = true              // dossier : motif gravé dans la couleur du dossier
    public var detourer = false          // retire le fond (ou la plaque d'une icône) de l'image
    public var fond = "sombre"           // clé de Rendu.fonds ou "perso"
    public var couleur = "#2d6cdf"       // base du fond « perso »
    public var ajustement = "contenir"   // « contenir » ou « remplir »
    public var taille = 72               // % du côté de la forme occupé par le motif (mode contenir)
    public var decalageY = 0             // décalage vertical du motif, en % du côté de la forme
    public var recadrer = true           // retire les marges transparentes de l'image
    public var verre = true              // reflet de bord et lumière haute
    public var ombreMotif = true         // ombre douce sous le motif
    public var ombreIcone = false        // ombre portée autour de la forme (dans la marge)
    public var aplat = false             // fond d'une seule couleur, sans dégradé ni lumière haute

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case type, fondDossier, grave, detourer, fond, couleur, ajustement, taille, decalageY, recadrer, verre, ombreMotif, ombreIcone, aplat
    }

    /// Lecture tolérante : une clé absente ou illisible garde sa valeur par défaut.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ k: CodingKeys, _ v: inout T) { if let x = try? c.decodeIfPresent(T.self, forKey: k) { v = x } }
        get(.type, &type); get(.fondDossier, &fondDossier); get(.grave, &grave); get(.detourer, &detourer)
        get(.fond, &fond); get(.couleur, &couleur); get(.ajustement, &ajustement); get(.taille, &taille)
        get(.decalageY, &decalageY); get(.recadrer, &recadrer); get(.verre, &verre); get(.ombreMotif, &ombreMotif)
        get(.ombreIcone, &ombreIcone); get(.aplat, &aplat)
    }

    private static let key = "reglages"
    public static func charger(_ defaults: UserDefaults = .standard) -> Reglages {
        guard let d = defaults.data(forKey: key), let r = try? JSONDecoder().decode(Reglages.self, from: d) else { return Reglages() }
        return r
    }
    public func enregistrer(_ defaults: UserDefaults = .standard) {
        if let d = try? JSONEncoder().encode(self) { defaults.set(d, forKey: Self.key) }
    }
}
