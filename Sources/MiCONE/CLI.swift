import AppKit
import Foundation
import MiCONECore

/// Ligne de commande : MiCONE --cli image.png [autres…] [--sortie DOSSIER] [--fond sombre] [--couleur #rrggbb]
///                     [--taille 72] [--remplir] [--sans-verre] [--dossier] [--png]
enum CLI {
    static func run(_ argv: [String]) -> Int32 {
        var images: [String] = [], sortie: String?, r = Reglages(), png = false
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
            case "--png": png = true
            case "--cli": break
            default: images.append(argv[i])
            }
            i += 1
        }
        guard !images.isEmpty else { FileHandle.standardError.write("usage: MiCONE --cli image… [--sortie DOSSIER] [--fond sombre|graphite|nuit|clair|perso] [--couleur #rrggbb] [--taille 72] [--remplir] [--sans-verre] [--dossier] [--png]\n".data(using: .utf8)!); return 2 }
        var code: Int32 = 0
        for img in images {
            var dest = (img as NSString).deletingPathExtension + ".icns"
            if let sortie {
                try? FileManager.default.createDirectory(atPath: sortie, withIntermediateDirectories: true)
                dest = (sortie as NSString).appendingPathComponent((dest as NSString).lastPathComponent)
            }
            do { print(try Rendu.exporterICNS(Rendu.rendre(try ImageSource.charger(img), r), destination: dest, png: png)) }
            catch { FileHandle.standardError.write("\(error.localizedDescription)\n".data(using: .utf8)!); code = 1 }
        }
        return code
    }
}
