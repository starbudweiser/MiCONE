import AppKit
import MiCONECore
import SwiftUI
import UniformTypeIdentifiers

enum Niveau { case aucun, succes, danger }

@MainActor
final class Modele: ObservableObject {
    static let shared = Modele()

    nonisolated static let apercu: CGFloat = 400                 // côté de l'aperçu principal (points)
    nonisolated static let petites = [128, 64, 32, 16]           // tailles réelles affichées sous l'aperçu

    private let defaults = UserDefaults.standard
    @Published var r: Reglages { didSet { if r != oldValue { r.enregistrer(); planifierRendu() } } }
    @Published var pngAussi: Bool { didSet { defaults.set(pngAussi, forKey: "png_aussi") } }

    @Published private(set) var source: CGImage?
    private(set) var cheminSource: String?
    private var detouree: CGImage?
    @Published private(set) var icone: CGImage?
    @Published private(set) var apercu: NSImage?
    @Published private(set) var petitesImages: [Int: NSImage] = [:]
    @Published private(set) var infoImage = ""
    @Published var nom = ""
    @Published private(set) var collections: [IconiQ.Collection] = []
    @Published var collection: String { didSet { defaults.set(collection, forKey: "collection_iconiq") } }
    @Published private(set) var statut = ""
    @Published private(set) var niveau = Niveau.aucun
    @Published private(set) var dernierExport: String?
    @Published private(set) var calcul = false
    @Published var depotSurvol = false

    private var generation = 0
    private var tache: Task<Void, Never>?

    init() {
        r = Reglages.charger()
        pngAussi = defaults.bool(forKey: "png_aussi")
        collection = defaults.string(forKey: "collection_iconiq") ?? ""
        chargerCollections()
    }

    var aImage: Bool { source != nil }
    var statutVisible: Bool { !statut.isEmpty || dernierExport != nil }

    // MARK: Statut

    func dire(_ texte: String, _ n: Niveau = .aucun) { statut = texte; niveau = n }

    // MARK: Image

    func ouvrir() {
        let panneau = NSOpenPanel()
        panneau.title = L("ouvrir")
        panneau.allowedContentTypes = ImageSource.extensions.compactMap { UTType(filenameExtension: $0) }
        panneau.canChooseDirectories = false
        panneau.directoryURL = URL(fileURLWithPath: defaults.string(forKey: "dossier") ?? NSHomeDirectory() + "/Pictures")
        if panneau.runModal() == .OK, let url = panneau.url { charger(url.path) }
    }

    func charger(_ chemin: String) {
        do {
            let img = try ImageSource.charger(chemin)
            source = img; cheminSource = chemin; detouree = nil
            defaults.set((chemin as NSString).deletingLastPathComponent, forKey: "dossier")
            nom = ((chemin as NSString).lastPathComponent as NSString).deletingPathExtension
            chargerCollections()
            infoImage = L("image_info", (chemin as NSString).lastPathComponent, img.width, img.height)
            dernierExport = nil
            dire("")
            planifierRendu(immediat: true)
        } catch { dire(error.localizedDescription, .danger) }
    }

    func chargerCollections() {
        collections = IconiQ.collections().filter { $0.chemin != IconiQ.parDefaut }
        if !collection.isEmpty && !collections.contains(where: { $0.id == collection }) { collection = "" }
    }

    // MARK: Rendu

    func planifierRendu(immediat: Bool = false) {
        guard let source else { return }
        generation += 1
        let g = generation
        let reglages = r
        let cache = detouree
        let echelle = NSScreen.main?.backingScaleFactor ?? 2
        tache?.cancel()
        tache = Task { [weak self] in
            if !immediat { try? await Task.sleep(nanoseconds: 60_000_000) }
            guard !Task.isCancelled else { return }
            var motif = source
            var nouvelle: CGImage?
            if reglages.detourer {
                if let cache { motif = cache } else {
                    self?.calcul = true
                    nouvelle = await Task.detached(priority: .userInitiated) { Detourage.automatique(source) }.value
                    motif = nouvelle ?? source
                }
            }
            let (icone, grand, petites) = await Task.detached(priority: .userInitiated) { () -> (CGImage, CGImage, [Int: CGImage]) in
                let icone = Rendu.rendre(motif, reglages)
                let grand = Rendu.reduire(icone, Int(Self.apercu * echelle))
                var petites: [Int: CGImage] = [:]
                for c in Self.petites { petites[c] = Rendu.reduire(icone, Int(CGFloat(c) * echelle)) }
                return (icone, grand, petites)
            }.value
            guard let self, g == self.generation else { return }
            self.calcul = false
            if let nouvelle, self.detouree == nil { self.detouree = nouvelle }
            self.icone = icone
            self.apercu = NSImage(cgImage: grand, size: NSSize(width: Self.apercu, height: Self.apercu))
            self.petitesImages = petites.mapValues { NSImage(cgImage: $0, size: NSSize(width: CGFloat($0.width) / echelle, height: CGFloat($0.height) / echelle)) }
        }
    }

    /// Image source sans son fond si l'option est cochée (calcul gardé en cache).
    private func motif() async -> CGImage? {
        guard let source else { return nil }
        guard r.detourer else { return source }
        if let detouree { return detouree }
        let d = await Task.detached(priority: .userInitiated) { Detourage.automatique(source) }.value
        detouree = d
        return d
    }

    // MARK: Actions

    func exporter() {
        guard source != nil, let chemin = cheminSource else { return }
        let panneau = NSSavePanel()
        panneau.title = L("enregistrer_sous")
        panneau.allowedContentTypes = [UTType(filenameExtension: "icns")!]
        panneau.directoryURL = URL(fileURLWithPath: (chemin as NSString).deletingLastPathComponent)
        panneau.nameFieldStringValue = ((chemin as NSString).lastPathComponent as NSString).deletingPathExtension + ".icns"
        guard panneau.runModal() == .OK, let url = panneau.url else { return }
        let reglages = r, png = pngAussi
        Task {
            guard let motif = await motif() else { return }
            do {
                let sortie = try await Task.detached { try Rendu.exporterICNS(Rendu.rendre(motif, reglages), destination: url.path, png: png) }.value
                dernierExport = sortie
                dire(L("ok_export", sortie), .succes)
            } catch { dire(L("erreur_export", error.localizedDescription), .danger) }
        }
    }

    func envoyerIconiQ() {
        guard source != nil else { return }
        guard IconiQ.installee() else { dire(L("iconiq_absent"), .danger); return }
        let stem = ((cheminSource ?? "MiCONE") as NSString).lastPathComponent as NSString
        let base = stem.deletingPathExtension
        let nomFinal = nom.trimmingCharacters(in: .whitespaces).isEmpty ? base : nom.trimmingCharacters(in: .whitespaces)
        let genre = r.type == "dossier" ? "folder" : "app"
        let origine = "\(genre):\(cheminSource ?? base)"
        let reglages = r, choisie = collection.isEmpty ? nil : collection
        let fichier = FileManager.default.temporaryDirectory.appendingPathComponent("micone_\(base).png")
        Task {
            guard let motif = await motif() else { return }
            let ok = await Task.detached { () -> Bool in
                do { try Rendu.ecrirePNG(Rendu.rendre(motif, reglages), fichier) } catch { return false }
                return IconiQ.envoyer(nom: nomFinal, fichier: fichier, origine: origine, genre: genre, collection: choisie)
            }.value
            if ok { dire(L("ok_iconiq"), .succes) } else { dire(L("erreur_iconiq"), .danger) }
        }
    }

    func appliquerDossier() {
        guard source != nil else { return }
        let panneau = NSOpenPanel()
        panneau.title = L("appliquer_dossier")
        panneau.canChooseFiles = false
        panneau.canChooseDirectories = true
        panneau.directoryURL = URL(fileURLWithPath: defaults.string(forKey: "dossier_cible") ?? NSHomeDirectory())
        guard panneau.runModal() == .OK, let url = panneau.url else { return }
        defaults.set(url.deletingLastPathComponent().path, forKey: "dossier_cible")
        let reglages = r
        Task {
            guard let motif = await motif() else { return }
            let icone = await Task.detached { Rendu.rendre(motif, reglages) }.value
            do {
                try Rendu.appliquerDossier(icone, url.path)
                dernierExport = url.path
                dire(L("ok_applique", url.path), .succes)
            } catch { dire(L("erreur_export", error.localizedDescription), .danger) }
        }
    }

    func reveler() {
        if let d = dernierExport { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: d)]) }
    }

    /// Image choisie dans le dialogue IA : chargée comme une image ouverte.
    func utiliser(_ chemin: String) { charger(chemin) }

}
