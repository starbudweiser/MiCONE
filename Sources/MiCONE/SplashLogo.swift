import SwiftUI

/// Logo animé du splash : le motif de l'icône (cadre, deux montagnes, soleil) redessiné pour animer ses pièces.
/// Le cadre se trace, les montagnes montent l'une après l'autre, le soleil se lève.
struct SplashLogo: View {
    @State private var start = Date()

    private struct Courbe {
        let x1, y1, x2, y2: Double
        func callAsFunction(_ x: Double) -> Double {
            if x <= 0 { return 0 }
            if x >= 1 { return 1 }
            func coord(_ t: Double, _ a: Double, _ b: Double) -> Double { 3 * a * t * (1 - t) * (1 - t) + 3 * b * t * t * (1 - t) + t * t * t }
            var lo = 0.0, hi = 1.0
            for _ in 0..<30 { let mid = (lo + hi) / 2; if coord(mid, x1, x2) < x { lo = mid } else { hi = mid } }
            return coord((lo + hi) / 2, y1, y2)
        }
    }
    private static let douce = Courbe(x1: 0.16, y1: 1, x2: 0.3, y2: 1)
    private static let filet = Courbe(x1: 0.65, y1: 0, x2: 0.35, y2: 1)

    private static func phase(_ t: Double, _ debut: Double, _ duree: Double) -> Double { min(1, max(0, (t - debut) / duree)) }

    private static let cadre = CGRect(x: 80, y: 160, width: 640, height: 480)   // axe du trait blanc, repère 800 × 800 du motif
    private static let trait: CGFloat = 40, rayonCadre: CGFloat = 50
    private static let grande = [CGPoint(x: 130, y: 600), CGPoint(x: 330, y: 330), CGPoint(x: 530, y: 600)]
    private static let petite = [CGPoint(x: 400, y: 600), CGPoint(x: 540, y: 440), CGPoint(x: 670, y: 600)]
    private static let bleu = Color(red: 0x46 / 255, green: 0x96 / 255, blue: 1)
    private static let soleil = Color(red: 1, green: 0xb8 / 255, blue: 0x30 / 255)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { ctx in
            let t = reduire ? 3000 : ctx.date.timeIntervalSince(start) * 1000
            Canvas { g, size in dessiner(g, size, t) }
        }
        .onAppear { start = Date() }
    }

    private var reduire: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func dessiner(_ g: GraphicsContext, _ size: CGSize, _ t: Double) {
        var g = g
        let enc = Self.cadre.insetBy(dx: -Self.trait / 2, dy: -Self.trait / 2)   // encombrement : 680 × 520
        let s = min(size.width, size.height) / enc.width
        g.translateBy(x: size.width / 2, y: size.height / 2)
        g.scaleBy(x: s, y: s)
        g.translateBy(x: -enc.midX, y: -enc.midY)

        let k = Self.filet(Self.phase(t, 100, 800))
        if k > 0 {
            let chemin = Path(roundedRect: Self.cadre, cornerRadius: Self.rayonCadre, style: .circular)
            g.stroke(chemin.trimmedPath(from: 0, to: k), with: .color(.white), style: StrokeStyle(lineWidth: Self.trait, lineCap: .butt))
        }
        var interieur = g
        interieur.clip(to: Path(roundedRect: Self.cadre.insetBy(dx: Self.trait / 2, dy: Self.trait / 2), cornerRadius: Self.rayonCadre - Self.trait / 2, style: .circular))

        let ks = Self.douce(Self.phase(t, 850, 800))
        if ks > 0 {
            let c = CGPoint(x: 535, y: 295 + 300 * (1 - ks))
            interieur.fill(Path(ellipseIn: CGRect(x: c.x - 65, y: c.y - 65, width: 130, height: 130)), with: .color(Self.soleil))
        }
        for (pts, debut) in [(Self.petite, 620.0), (Self.grande, 480.0)] {
            let km = Self.douce(Self.phase(t, debut, 650))
            if km > 0 {
                var p = Path(); p.addLines(pts); p.closeSubpath()
                interieur.fill(p.offsetBy(dx: 0, dy: 340 * (1 - km)), with: .color(Self.bleu))
            }
        }
    }
}
