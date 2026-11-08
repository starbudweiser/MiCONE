import AppKit
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ErreurMiCONE: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Moteur de MiCONE : pose une image sur le fond d'icône macOS (squircle 824 px dans 1024 px) et produit un .ICNS complet.
///
/// Grille Apple : toile 1024 × 1024, forme de 824 × 824 centrée (marge de 100 px), coins continus de rayon 185,4 px.
/// Le contexte de dessin est retourné (origine en haut à gauche, y vers le bas) : mêmes coordonnées que la version Qt.
public enum Rendu {
    public static let toile = 1024
    public static let corps = CGRect(x: 100, y: 100, width: 824, height: 824)
    public static let rayon: CGFloat = 185.4

    /// Modèles de fond : (clé, haut, bas) du dégradé vertical.
    public static let fonds: [(cle: String, haut: String, bas: String)] = [
        ("sombre", "#3a3a3f", "#141417"), ("graphite", "#5d5d64", "#2c2c31"), ("nuit", "#23324a", "#0b111c"), ("clair", "#ffffff", "#e2e2e8"),
    ]
    /// Couleurs de dossier (base de la face avant).
    public static let dossiers: [(cle: String, hex: String)] = [
        ("bleu", "#56acf0"), ("graphite", "#8c8c94"), ("nuit", "#2f4f84"), ("clair", "#e6e6ec"),
    ]
    static let dos = CGRect(x: 64, y: 168, width: 896, height: 704)      // panneau arrière (sans l'onglet)
    static let face = CGRect(x: 64, y: 250, width: 896, height: 622)     // face avant

    /// Tailles d'un .iconset : (nom, côté en px).
    public static let iconset: [(String, Int)] = [
        ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
        ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024),
    ]

    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    // MARK: Forme

    /// Rectangle à coins continus (courbure progressive, comme les icônes Apple).
    public static func forme(_ rect: CGRect = corps, rayon r0: CGFloat = rayon) -> CGPath {
        let x = rect.minX, y = rect.minY, w = rect.width, h = rect.height
        let r = min(r0, min(w, h) / 2 / 1.52866483)
        func coin(_ cx: CGFloat, _ cy: CGFloat, _ sx: CGFloat, _ sy: CGFloat, _ inverse: Bool) -> [CGPoint] {
            let base: [(CGFloat, CGFloat)] = [(-1.52866471, 0), (-1.08849323, 0), (-0.86840689, 0), (-0.63149399, 0.07491100),
                                              (-0.37282392, 0.16905899), (-0.16905899, 0.37282392), (-0.07491100, 0.63149399),
                                              (0, 0.86840689), (0, 1.08849323), (0, 1.52866471)]
            let pts = base.map { CGPoint(x: cx + sx * $0.0 * r, y: cy + sy * $0.1 * r) }
            return inverse ? pts.reversed() : pts
        }
        let coins = [coin(x + w, y, 1, 1, false), coin(x + w, y + h, 1, -1, true), coin(x, y + h, -1, -1, false), coin(x, y, -1, 1, true)]
        let p = CGMutablePath()
        p.move(to: coins[0][0])
        for (i, c) in coins.enumerated() {
            if i > 0 { p.addLine(to: c[0]) }
            for k in stride(from: 1, to: 10, by: 3) { p.addCurve(to: c[k + 2], control1: c[k], control2: c[k + 1]) }
        }
        p.closeSubpath()
        return p
    }

    /// Panneau arrière avec onglet, et face avant, façon dossier du Finder.
    static func formeDossier() -> (dos: CGPath, face: CGPath) {
        let d = CGPath(roundedRect: dos, cornerWidth: 56, cornerHeight: 56, transform: nil)
        let onglet = CGPath(roundedRect: CGRect(x: dos.minX, y: dos.minY - 44, width: 380, height: 140), cornerWidth: 40, cornerHeight: 40, transform: nil)
        let pente = CGMutablePath()
        pente.move(to: CGPoint(x: dos.minX + 330, y: dos.minY - 44))
        pente.addCurve(to: CGPoint(x: dos.minX + 450, y: dos.minY), control1: CGPoint(x: dos.minX + 380, y: dos.minY - 44), control2: CGPoint(x: dos.minX + 390, y: dos.minY))
        pente.addLine(to: CGPoint(x: dos.minX + 330, y: dos.minY + 60))
        pente.closeSubpath()
        let f = CGPath(roundedRect: face, cornerWidth: 52, cornerHeight: 52, transform: nil)
        return (d.union(onglet).union(pente), f)
    }

    // MARK: Outils de dessin

    /// Contexte BGRA prémultiplié, origine en haut à gauche si `retourne`.
    static func contexte(_ w: Int, _ h: Int, retourne: Bool = true) -> CGContext {
        let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        if retourne { c.translateBy(x: 0, y: CGFloat(h)); c.scaleBy(x: 1, y: -1) }
        c.setAllowsAntialiasing(true)
        c.interpolationQuality = .high
        return c
    }

    static func toileVide() -> CGContext { contexte(toile, toile) }

    /// Dessine `img` dans `rect` (coordonnées retournées).
    static func dessiner(_ c: CGContext, _ img: CGImage, _ rect: CGRect) {
        c.saveGState()
        c.translateBy(x: rect.minX, y: rect.maxY)
        c.scaleBy(x: 1, y: -1)
        c.draw(img, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        c.restoreGState()
    }

    static func degrade(_ stops: [(Double, Couleur)]) -> CGGradient {
        CGGradient(colorsSpace: srgb, colors: stops.map { $0.1.cg } as CFArray, locations: stops.map { CGFloat($0.0) })!
    }

    static func remplir(_ c: CGContext, _ path: CGPath, _ couleur: Couleur) {
        c.addPath(path); c.setFillColor(couleur.cg); c.fillPath()
    }

    static func remplirDegrade(_ c: CGContext, _ path: CGPath, _ g: CGGradient, de: CGPoint, a: CGPoint) {
        c.saveGState(); c.addPath(path); c.clip()
        c.drawLinearGradient(g, start: de, end: a, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        c.restoreGState()
    }

    static func contour(_ c: CGContext, _ path: CGPath, _ couleur: Couleur, _ epaisseur: CGFloat) {
        c.addPath(path); c.setStrokeColor(couleur.cg); c.setLineWidth(epaisseur); c.strokePath()
    }

    static let ci = CIContext(options: [.workingColorSpace: srgb, .outputColorSpace: srgb])

    /// Flou gaussien doux (ombres).
    static func flou(_ img: CGImage, _ rayon: Double) -> CGImage {
        let entree = CIImage(cgImage: img)
        let sortie = entree.clampedToExtent().applyingGaussianBlur(sigma: rayon * 0.65).cropped(to: entree.extent)
        return ci.createCGImage(sortie, from: entree.extent, format: .BGRA8, colorSpace: srgb) ?? img
    }

    /// Image remplacée par sa seule silhouette, teintée.
    static func teinte(_ img: CGImage, _ couleur: Couleur) -> CGImage {
        let c = contexte(img.width, img.height, retourne: false)
        let r = CGRect(x: 0, y: 0, width: img.width, height: img.height)
        c.draw(img, in: r)
        c.setBlendMode(.sourceIn)
        c.setFillColor(couleur.cg)
        c.fill(r)
        return c.makeImage()!
    }

    /// Image posée sur une toile transparente 1024 × 1024.
    static func calque(_ img: CGImage, _ rect: CGRect) -> CGImage {
        let c = toileVide()
        dessiner(c, img, rect)
        return c.makeImage()!
    }

    static func ombre(_ forme: CGPath, decalage: CGFloat, alpha: Double, flou rayon: Double) -> CGImage {
        let c = toileVide()
        var t = CGAffineTransform(translationX: 0, y: decalage)
        if let p = forme.copy(using: &t) { remplir(c, p, .noir(alpha)) }
        return flou(c.makeImage()!, rayon)
    }

    /// Retire les marges entièrement transparentes.
    public static func recadrer(_ img: CGImage, seuil: UInt8 = 8) -> CGImage {
        switch img.alphaInfo { case .none, .noneSkipFirst, .noneSkipLast: return img; default: break }
        let w = img.width, h = img.height
        let c = contexte(w, h, retourne: false)
        c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let base = c.data?.assumingMemoryBound(to: UInt8.self) else { return img }
        let pas = c.bytesPerRow
        var haut = -1, bas = -1, gauche = w, droite = -1
        for y in 0..<h {
            let ligne = base + y * pas
            var g = -1, d = -1
            for x in 0..<w where ligne[x * 4 + 3] > seuil { if g < 0 { g = x }; d = x }
            if g < 0 { continue }
            if haut < 0 { haut = y }
            bas = y; gauche = min(gauche, g); droite = max(droite, d)
        }
        if haut < 0 { return img }
        return img.cropping(to: CGRect(x: gauche, y: haut, width: droite - gauche + 1, height: bas - haut + 1)) ?? img
    }

    // MARK: Rendu

    static func couleursFond(_ r: Reglages) -> (Couleur, Couleur) {
        if r.fond == "perso" {
            let base = Couleur(hex: r.couleur) ?? Couleur(hex: "#2d6cdf")!
            return (base.lighter(122), base.darker(165))
        }
        let f = fonds.first { $0.cle == r.fond } ?? fonds[0]
        return (Couleur(hex: f.haut)!, Couleur(hex: f.bas)!)
    }

    static func fondClair(_ r: Reglages) -> Bool {
        let (h, b) = couleursFond(r)
        return (h.luminosite + b.luminosite) / 2 > 0.6
    }

    static func place(_ img: CGImage, _ zone: CGRect, _ r: Reglages) -> CGRect {
        let iw = CGFloat(img.width), ih = CGFloat(img.height)
        let k: CGFloat
        if r.ajustement == "remplir" { k = max(zone.width / iw, zone.height / ih) }
        else {
            let cote = min(zone.width, zone.height) * CGFloat(max(10, min(100, r.taille))) / 100
            k = min(cote / iw, cote / ih)
        }
        let w = iw * k, h = ih * k
        let cx = zone.midX, cy = zone.midY + zone.height * CGFloat(r.decalageY) / 100
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    /// Icône 1024 × 1024 (fond + motif), prête pour l'.iconset.
    public static func rendre(_ source: CGImage?, _ r: Reglages) -> CGImage {
        r.type == "dossier" ? rendreDossier(source, r) : rendreAppli(source, r)
    }

    static func rendreAppli(_ source: CGImage?, _ r: Reglages) -> CGImage {
        let c = toileVide()
        let chemin = forme()
        if r.ombreIcone { dessiner(c, ombre(chemin, decalage: 12, alpha: 110.0 / 255, flou: 14), CGRect(x: 0, y: 0, width: toile, height: toile)) }

        // Fond : aplat ou dégradé vertical.
        let (haut, bas) = couleursFond(r)
        if r.aplat {
            let uni = r.fond == "perso" && Couleur.valide(r.couleur) ? Couleur(hex: r.couleur)!
                : Couleur(r: (haut.r + bas.r) / 2, g: (haut.g + bas.g) / 2, b: (haut.b + bas.b) / 2)
            remplir(c, chemin, uni)
        } else {
            remplirDegrade(c, chemin, degrade([(0, haut), (1, bas)]), de: CGPoint(x: corps.minX, y: corps.minY), a: CGPoint(x: corps.minX, y: corps.maxY))
        }

        c.saveGState()
        c.addPath(chemin); c.clip()
        let clair = fondClair(r)

        // Lumière haute (verre), absente en aplat.
        if r.verre && !r.aplat {
            c.saveGState()
            c.clip(to: corps)
            let lum = degrade([(0, .blanc(clair ? 60.0 / 255 : 34.0 / 255)), (1, .blanc(0))])
            c.drawRadialGradient(lum, startCenter: CGPoint(x: CGFloat(toile) / 2, y: corps.minY - 120), startRadius: 0,
                                 endCenter: CGPoint(x: CGFloat(toile) / 2, y: corps.minY - 120), endRadius: 760, options: [])
            c.restoreGState()
        }

        // Motif.
        if let source {
            let img = r.recadrer ? recadrer(source) : source
            let cal = calque(img, place(img, corps, r))
            if r.ombreMotif && r.ajustement != "remplir" {
                let o = flou(teinte(cal, .noir(clair ? 90.0 / 255 : 150.0 / 255)), 16)
                dessiner(c, o, CGRect(x: 0, y: 14, width: toile, height: toile))
            }
            dessiner(c, cal, CGRect(x: 0, y: 0, width: toile, height: toile))
        }

        // Reflet de bord (verre) : filet clair plus marqué en haut et en bas.
        if r.verre {
            let a = clair ? 0.55 : 1.0
            let g = degrade([(0, .blanc(120.0 / 255 * a)), (0.25, .blanc(28.0 / 255 * a)), (0.75, .blanc(14.0 / 255 * a)), (1, .blanc(60.0 / 255 * a))])
            c.saveGState()
            c.addPath(chemin); c.setLineWidth(5); c.replacePathWithStrokedPath(); c.clip()
            c.drawLinearGradient(g, start: CGPoint(x: corps.minX, y: corps.minY), end: CGPoint(x: corps.minX, y: corps.maxY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            c.restoreGState()
        }
        c.restoreGState()

        // Filet extérieur très discret pour détacher la forme d'un fond de même valeur.
        contour(c, chemin, .noir(clair ? 40.0 / 255 : 70.0 / 255), 1.5)
        return c.makeImage()!
    }

    static func rendreDossier(_ source: CGImage?, _ r: Reglages) -> CGImage {
        let c = toileVide()
        let (dosChemin, faceChemin) = formeDossier()
        let base: Couleur
        if r.fondDossier == "perso", let perso = Couleur(hex: r.couleur) { base = perso }
        else { base = Couleur(hex: (dossiers.first { $0.cle == r.fondDossier } ?? dossiers[0]).hex)! }
        let clair = base.luminosite > 0.75

        if r.ombreIcone { dessiner(c, ombre(dosChemin.union(faceChemin), decalage: 12, alpha: 110.0 / 255, flou: 14), CGRect(x: 0, y: 0, width: toile, height: toile)) }

        remplir(c, dosChemin, base.darker(122))
        if r.aplat { remplir(c, faceChemin, base) }
        else {
            remplirDegrade(c, faceChemin, degrade([(0, base.lighter(110)), (1, base.darker(108))]),
                           de: CGPoint(x: face.minX, y: face.minY), a: CGPoint(x: face.minX, y: face.maxY))
        }

        c.saveGState()
        c.addPath(faceChemin); c.clip()
        if let source {
            let img = r.recadrer ? recadrer(source) : source
            let cal = calque(img, place(img, face, r))
            let plein = CGRect(x: 0, y: 0, width: toile, height: toile)
            if r.grave {
                // Gravure : liseré clair dessous, motif plus sombre que la face.
                dessiner(c, teinte(cal, .blanc(clair ? 150.0 / 255 : 70.0 / 255)), plein.offsetBy(dx: 0, dy: 4))
                dessiner(c, teinte(cal, base.darker(clair ? 135 : 150)), plein)
            } else {
                if r.ombreMotif && r.ajustement != "remplir" { dessiner(c, flou(teinte(cal, .noir(110.0 / 255)), 16), plein.offsetBy(dx: 0, dy: 12)) }
                dessiner(c, cal, plein)
            }
        }
        if r.verre { contour(c, faceChemin, .blanc(clair ? 200.0 / 255 : 110.0 / 255), 5) }
        c.restoreGState()
        contour(c, faceChemin, .noir(45.0 / 255), 1.5)
        return c.makeImage()!
    }

    // MARK: Réduction et export

    static func mettreALEchelle(_ img: CGImage, _ w: Int, _ h: Int) -> CGImage {
        let c = contexte(w, h, retourne: false)
        c.interpolationQuality = .high
        c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return c.makeImage()!
    }

    /// Réduction par moitiés successives : plus net qu'un seul redimensionnement.
    public static func reduire(_ image: CGImage, _ cote: Int) -> CGImage {
        var img = image
        while img.width / 2 >= cote { img = mettreALEchelle(img, img.width / 2, img.height / 2) }
        if img.width != cote { img = mettreALEchelle(img, cote, cote) }
        return img
    }

    public static func pngData(_ img: CGImage) -> Data? {
        let d = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(d, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, nil)
        return CGImageDestinationFinalize(dest) ? d as Data : nil
    }

    public static func ecrirePNG(_ img: CGImage, _ url: URL) throws {
        guard let d = pngData(img) else { throw ErreurMiCONE(L("err_png", url.lastPathComponent)) }
        do { try d.write(to: url, options: .atomic) } catch { throw ErreurMiCONE(L("err_png", url.lastPathComponent)) }
    }

    /// Écrit le .ICNS (et, si demandé, le .PNG 1024 px à côté). Renvoie le chemin du .ICNS.
    @discardableResult
    public static func exporterICNS(_ icone: CGImage, destination: String, png: Bool = false) throws -> String {
        var dest = destination
        if !dest.lowercased().hasSuffix(".icns") { dest += ".icns" }
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("micone_\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }
        let dossier = tmp.appendingPathComponent("icone.iconset")
        try fm.createDirectory(at: dossier, withIntermediateDirectories: true)
        for (nom, cote) in iconset { try ecrirePNG(reduire(icone, cote), dossier.appendingPathComponent("icon_\(nom).png")) }
        let sortie = tmp.appendingPathComponent("icone.icns")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        p.arguments = ["-c", "icns", dossier.path, "-o", sortie.path]
        let err = Pipe()
        p.standardError = err; p.standardOutput = err
        try p.run(); p.waitUntilExit()
        if p.terminationStatus != 0 {
            let detail = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ErreurMiCONE(L("err_iconutil", detail))
        }
        try? fm.removeItem(atPath: dest)
        try fm.copyItem(at: sortie, to: URL(fileURLWithPath: dest))
        if png { try ecrirePNG(icone, URL(fileURLWithPath: (dest as NSString).deletingPathExtension + "_1024.png")) }
        return dest
    }

    /// Pose l'icône sur un dossier (ou un fichier) du Finder.
    @MainActor
    public static func appliquerDossier(_ icone: CGImage, _ dossier: String) throws {
        let image = NSImage(cgImage: icone, size: NSSize(width: 1024, height: 1024))
        if !NSWorkspace.shared.setIcon(image, forFile: dossier, options: []) { throw ErreurMiCONE(L("err_appliquer", dossier)) }
    }
}
