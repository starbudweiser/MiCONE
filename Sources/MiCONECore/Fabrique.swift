import CoreGraphics
import Foundation

/// Fabrication d'une icône sans interface (ligne de commande, serveur MCP d'iCONIQ) : chargement, détourage éventuel, rendu.
public enum Fabrique {
    /// Couleurs de dossier nommées (clés de `Rendu.dossiers`).
    public static var couleursDossier: [String] { Rendu.dossiers.map(\.cle) }

    /// Règle la couleur du dossier : une clé (`bleu`, `nuit`…) ou une couleur `#rrggbb`. Renvoie faux si la valeur est inconnue.
    @discardableResult
    public static func couleurDossier(_ valeur: String, dans r: inout Reglages) -> Bool {
        let v = valeur.trimmingCharacters(in: .whitespaces).lowercased()
        if couleursDossier.contains(v) { r.fondDossier = v; return true }
        if v.hasPrefix("#"), Couleur(hex: v) != nil { r.fondDossier = "perso"; r.couleur = v; return true }
        return false
    }

    /// Image source → icône 1024 px (appli ou dossier selon `r.type`), détourée si `r.detourer`.
    public static func icone(_ chemin: String, _ r: Reglages) throws -> CGImage {
        var source = try ImageSource.charger(chemin)
        if r.detourer { source = Detourage.automatique(source) }
        return Rendu.rendre(source, r)
    }
}
