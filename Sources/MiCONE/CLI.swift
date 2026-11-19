import AppKit
import Foundation
import MiCONECore

/// Ligne de commande : MiCONE --cli image.png [autres…] [--sortie DOSSIER] [--fond sombre] [--couleur #rrggbb]
///                     [--taille 72] [--remplir] [--sans-verre] [--dossier] [--fond-dossier nuit|#rrggbb]
///                     [--grave | --sans-grave] [--detourer] [--appliquer DOSSIER] [--png]
enum CLI {
    static func run(_ argv: [String]) -> Int32 {
        var images: [String] = [], sortie: String?, r = Reglages(), png = false, appliquer: String?
        var i = 0
        func valeur() -> String? { i += 1; return i < argv.count ? argv[i] : nil }
        while i < argv.count {
            switch argv[i] {
            case "--sortie": sortie = valeur()
            case "--fond": r.fond = valeur() ?? r.fond
            case "--couleur": r.couleur = valeur() ?? r.couleur
            case "--taille": r.taille = Int(valeur() ?? "") ?? r.taille
            case "--remplir": r.ajustement = "remplir"
            case "--sans-verre": r.verre = false
            case "--dossier": r.type = "dossier"
            case "--fond-dossier":
                r.type = "dossier"
                if !Fabrique.couleurDossier(valeur() ?? "", dans: &r) { erreur("--fond-dossier : \(Fabrique.couleursDossier.joined(separator: "|"))|#rrggbb"); return 2 }
            case "--grave": r.grave = true
            case "--sans-grave": r.grave = false
            case "--detourer": r.detourer = true
            case "--appliquer": appliquer = valeur()
            case "--png": png = true
            case "--cli": break
            default: images.append(argv[i])
            }
            i += 1
        }
        guard !images.isEmpty else { erreur(L("cli_usage")); return 2 }
        if appliquer != nil && images.count != 1 { erreur(L("cli_une_image")); return 2 }
        var code: Int32 = 0
        for img in images {
            var dest = (img as NSString).deletingPathExtension + ".icns"
            if let sortie {
                try? FileManager.default.createDirectory(atPath: sortie, withIntermediateDirectories: true)
                dest = (sortie as NSString).appendingPathComponent((dest as NSString).lastPathComponent)
            }
            do {
                let icone = try Fabrique.icone(img, r)
                print(try Rendu.exporterICNS(icone, destination: dest, png: png))
                if let appliquer { try MainActor.assumeIsolated { try Rendu.appliquerDossier(icone, appliquer) } }
            } catch { erreur(error.localizedDescription); code = 1 }
        }
        return code
    }

    private static func erreur(_ texte: String) { FileHandle.standardError.write("\(texte)\n".data(using: .utf8)!) }
}
