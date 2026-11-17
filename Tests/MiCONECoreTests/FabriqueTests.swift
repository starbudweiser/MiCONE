import XCTest
@testable import MiCONECore

final class FabriqueTests: XCTestCase {
    func testCouleurDossier() {
        var r = Reglages()
        XCTAssertTrue(Fabrique.couleurDossier("Nuit", dans: &r)); XCTAssertEqual(r.fondDossier, "nuit")
        XCTAssertTrue(Fabrique.couleurDossier("#2F4F84", dans: &r)); XCTAssertEqual(r.fondDossier, "perso"); XCTAssertEqual(r.couleur, "#2f4f84")
        XCTAssertFalse(Fabrique.couleurDossier("rose", dans: &r)); XCTAssertEqual(r.fondDossier, "perso")
    }

    func testIconeDossier() throws {
        let png = FileManager.default.temporaryDirectory.appendingPathComponent("fab_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: png) }
        let c = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: Rendu.srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)); c.fill(CGRect(x: 16, y: 16, width: 32, height: 32))
        try Rendu.ecrirePNG(c.makeImage()!, png)
        var r = Reglages(); r.type = "dossier"; r.grave = false; Fabrique.couleurDossier("nuit", dans: &r)
        let icone = try Fabrique.icone(png.path, r)
        XCTAssertEqual(icone.width, 1024)
    }
}
