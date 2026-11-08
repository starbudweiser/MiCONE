import CoreGraphics
import XCTest
@testable import MiCONECore

final class CoreTests: XCTestCase {
    private func pixel(_ img: CGImage, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let c = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4, space: Rendu.srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        let p = c.data!.assumingMemoryBound(to: UInt8.self) + (y * img.width + x) * 4
        return (p[0], p[1], p[2], p[3])
    }

    private func carre(_ cote: Int, fond: Couleur?, motif: Couleur) -> CGImage {
        let c = Rendu.contexte(cote, cote)
        if let fond { c.setFillColor(fond.cg); c.fill(CGRect(x: 0, y: 0, width: cote, height: cote)) }
        c.setFillColor(motif.cg)
        c.fill(CGRect(x: cote / 4, y: cote / 4, width: cote / 2, height: cote / 2))
        return c.makeImage()!
    }

    func testColorHexAndShade() {
        XCTAssertEqual(Couleur(hex: "#ff8000")?.hex, "#ff8000")
        XCTAssertNil(Couleur(hex: "pas une couleur"))
        let base = Couleur(hex: "#2d6cdf")!
        XCTAssertGreaterThan(base.lighter(122).luminosite, base.luminosite)
        XCTAssertLessThan(base.darker(165).luminosite, base.luminosite)
    }

    func testRenderIsSquircleOnTransparentCanvas() {
        let img = Rendu.rendre(carre(200, fond: nil, motif: Couleur(hex: "#ff0000")!), Reglages())
        XCTAssertEqual(img.width, 1024)
        XCTAssertEqual(pixel(img, 5, 5).a, 0, "coin transparent")
        XCTAssertEqual(pixel(img, 512, 512).a, 255, "centre opaque")
        XCTAssertEqual(pixel(img, 130, 512).a, 255, "intérieur de la forme")
        XCTAssertEqual(pixel(img, 50, 512).a, 0, "marge de 100 px transparente")
    }

    func testFolderRender() {
        var r = Reglages(); r.type = "dossier"
        let img = Rendu.rendre(carre(200, fond: nil, motif: Couleur(hex: "#ff0000")!), r)
        XCTAssertEqual(pixel(img, 512, 600).a, 255)
        XCTAssertEqual(pixel(img, 5, 5).a, 0)
    }

    func testCropRemovesTransparentMargins() {
        let r = Rendu.recadrer(carre(200, fond: nil, motif: .blanc(1)))
        XCTAssertEqual(r.width, 100)
        XCTAssertEqual(r.height, 100)
    }

    func testReduce() {
        let img = Rendu.rendre(nil, Reglages())
        XCTAssertEqual(Rendu.reduire(img, 16).width, 16)
        XCTAssertEqual(Rendu.reduire(img, 512).height, 512)
    }

    func testWandRemovesPlainBackground() {
        let out = Detourage.baguette(carre(200, fond: Couleur(hex: "#10a030")!, motif: Couleur(hex: "#ff0000")!))
        XCTAssertEqual(pixel(out, 5, 5).a, 0, "fond retiré")
        XCTAssertEqual(pixel(out, 100, 100).a, 255, "sujet conservé")
    }

    func testExportICNS() throws {
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("micone_test_\(UUID().uuidString).icns")
        defer { try? FileManager.default.removeItem(at: dest); try? FileManager.default.removeItem(atPath: dest.path.replacingOccurrences(of: ".icns", with: "_1024.png")) }
        let sortie = try Rendu.exporterICNS(Rendu.rendre(nil, Reglages()), destination: dest.path, png: true)
        XCTAssertEqual(sortie, dest.path)
        let data = try Data(contentsOf: dest)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "icns")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path.replacingOccurrences(of: ".icns", with: "_1024.png")))
    }

    func testSettingsRoundTripAndTolerance() throws {
        var r = Reglages(); r.taille = 55; r.type = "dossier"; r.fond = "nuit"
        let back = try JSONDecoder().decode(Reglages.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back, r)
        let partiel = try JSONDecoder().decode(Reglages.self, from: Data(#"{"taille": 40, "grave": "n'importe quoi"}"#.utf8))
        XCTAssertEqual(partiel.taille, 40)
        XCTAssertTrue(partiel.grave, "valeur illisible : défaut conservé")
    }

    func testKeyDetectionAndPrompt() {
        XCTAssertEqual(IA.detecter("AIzaXYZ"), "gemini")
        XCTAssertEqual(IA.detecter("sk-ant-abc"), "anthropic")
        XCTAssertEqual(IA.detecter("sk-abc"), "openai")
        XCTAssertNil(IA.detecter("rien"))
        let p = IA.consigne(["a rocket", "bluer"], .d3, false)
        XCTAssertTrue(p.contains("MAIN REQUEST (highest priority): a rocket"))
        XCTAssertTrue(p.contains("bluer"))
        XCTAssertTrue(IA.consigne(["x"], .glyphe, false).contains("pure black background"))
        XCTAssertTrue(IA.consigne(["x"], .d3, true).contains("fully transparent"))
    }

    func testIconiQCollectionsAndInbox() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("micone_iconiq_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let saved = IconiQ.racine
        IconiQ.racine = tmp
        defer { IconiQ.racine = saved }
        XCTAssertEqual(IconiQ.collections(), [])
        let db = tmp.appendingPathComponent("Library.db").path
        let sh = Process()
        sh.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        sh.arguments = [db, "CREATE TABLE groups(id TEXT, parent TEXT, name TEXT); CREATE TABLE collections(id TEXT, grp TEXT, name TEXT, kind TEXT); INSERT INTO groups VALUES('g1','','Apps'); INSERT INTO collections VALUES('c1','g1','Outils','normal'); INSERT INTO collections VALUES('c2','','Portail','portal'); INSERT INTO collections VALUES('c3','','Zèbre','normal');"]
        try sh.run(); sh.waitUntilExit()
        XCTAssertEqual(IconiQ.collections().map(\.chemin), ["Apps › Outils", "Zèbre"])
        let png = tmp.appendingPathComponent("x.png")
        try Rendu.ecrirePNG(Rendu.rendre(nil, Reglages()), png)
        XCTAssertTrue(IconiQ.envoyer(nom: "Test", fichier: png, origine: "app:/x.png", genre: "app", collection: "c1", lancer: false))
        let boite = tmp.appendingPathComponent("Inbox")
        let json = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: boite.path).first { $0.hasSuffix(".json") })
        let d = try JSONSerialization.jsonObject(with: Data(contentsOf: boite.appendingPathComponent(json))) as? [String: String]
        XCTAssertEqual(d?["name"], "Test"); XCTAssertEqual(d?["collection"], "c1"); XCTAssertEqual(d?["source"], "MiCONE"); XCTAssertEqual(d?["kind"], "app")
        XCTAssertTrue(FileManager.default.fileExists(atPath: boite.appendingPathComponent(d?["file"] ?? "?").path))
    }
}
