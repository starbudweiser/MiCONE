import AppKit
import Foundation
import SQLite3

/// Lien dynamique avec iCONIQ (bibliothèque d'icônes) : chaque icône envoyée est déposée dans la boîte de réception d'iCONIQ.
///
/// iCONIQ surveille ce dossier : il range l'icône dans sa collection « MiCONE », ou met à jour sur place celle déjà suivie
/// pour la même origine. Si iCONIQ n'est pas lancé, il est démarré en arrière-plan, sans prendre le focus.
public enum IconiQ {
    public static let bundleID = "fr.stephan.iconiq"
    public static let parDefaut = "MiCONE"   // collection où iCONIQ range les icônes quand aucune n'est choisie
    public static var racine = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/iCONIQ")
    static var boite: URL { racine.appendingPathComponent("Inbox") }
    static let applis = [NSHomeDirectory() + "/Applications/Applications Personnelles/iCONIQ.app", "/Applications/iCONIQ.app"]

    public struct Collection: Hashable, Sendable { public let id: String; public let chemin: String }

    /// Collections d'iCONIQ (hors portails) : « Groupe › Sous-groupe › Collection », triées par chemin.
    public static func collections() -> [Collection] {
        let base = racine.appendingPathComponent("Library.db").path
        guard FileManager.default.fileExists(atPath: base) else { return [] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(base, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else { sqlite3_close(db); return [] }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 1000)
        func lignes(_ sql: String) -> [[String]] {
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            var out: [[String]] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append((0..<sqlite3_column_count(st)).map { sqlite3_column_text(st, $0).map { String(cString: $0) } ?? "" })
            }
            return out
        }
        var groupes: [String: (parent: String, nom: String)] = [:]
        for l in lignes("SELECT id, parent, name FROM groups") where l.count == 3 { groupes[l[0]] = (l[1], l[2]) }
        let cols = lignes("SELECT id, grp, name FROM collections WHERE kind <> 'portal'")
        func chemin(_ grp: String, _ nom: String) -> String {
            var morceaux = [nom], g = grp, vus = Set<String>()
            while !g.isEmpty, let x = groupes[g], !vus.contains(g) { vus.insert(g); morceaux.insert(x.nom, at: 0); g = x.parent }
            return morceaux.joined(separator: " › ")
        }
        return cols.filter { $0.count == 3 }.map { Collection(id: $0[0], chemin: chemin($0[1], $0[2])) }
            .sorted { $0.chemin.localizedCaseInsensitiveCompare($1.chemin) == .orderedAscending }
    }

    public static func installee() -> Bool {
        FileManager.default.fileExists(atPath: racine.path) || applis.contains { FileManager.default.fileExists(atPath: $0) }
    }

    struct Demande: Encodable {
        var name: String, file: String, origin: String, kind: String, source: String
        var collection: String?
    }

    /// Dépose `fichier` (.icns ou .png) dans la boîte d'iCONIQ. `origine` identifie le lien (chemin de l'image source).
    @discardableResult
    public static func envoyer(nom: String, fichier: URL, origine: String, genre: String = "app", collection: String? = nil, lancer: Bool = true) -> Bool {
        let fm = FileManager.default
        guard installee(), fm.fileExists(atPath: fichier.path) else { return false }
        do {
            try fm.createDirectory(at: boite, withIntermediateDirectories: true)
            let ident = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            let copie = "\(ident).\(fichier.pathExtension.lowercased())"
            try fm.copyItem(at: fichier, to: boite.appendingPathComponent(copie))
            // le descripteur est écrit en dernier et d'un coup : iCONIQ ne lit jamais un fichier incomplet
            let json = try JSONEncoder().encode(Demande(name: nom, file: copie, origin: origine, kind: genre, source: "MiCONE", collection: collection))
            let tmp = boite.appendingPathComponent(".\(ident).tmp")
            try json.write(to: tmp)
            _ = try fm.replaceItemAt(boite.appendingPathComponent("\(ident).json"), withItemAt: tmp)
        } catch { return false }
        if lancer, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: cfg)
        }
        return true
    }
}
