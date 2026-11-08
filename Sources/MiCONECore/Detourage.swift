import CoreGraphics
import CoreImage
import Foundation
import Vision

/// Détourage : baguette magique (fond relié aux bords ou plaque d'icône) et sujet isolé par Vision, sur la machine.
public enum Detourage {
    /// Pixels non prémultipliés RGBA.
    struct Pixels { var w: Int, h: Int, d: [UInt8] }

    static func pixels(_ img: CGImage) -> Pixels {
        let w = img.width, h = img.height
        let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: Rendu.srgb,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let p = c.data!.assumingMemoryBound(to: UInt8.self)
        var d = [UInt8](UnsafeBufferPointer(start: p, count: w * h * 4))
        var i = 0
        while i < d.count {
            let a = Int(d[i + 3])
            if a > 0 && a < 255 { for k in 0..<3 { d[i + k] = UInt8(min(255, (Int(d[i + k]) * 255 + a / 2) / a)) } }
            i += 4
        }
        return Pixels(w: w, h: h, d: d)
    }

    static func image(_ p: Pixels) -> CGImage {
        var d = p.d
        var i = 0
        while i < d.count {   // prémultiplication
            let a = Int(d[i + 3])
            if a < 255 { for k in 0..<3 { d[i + k] = UInt8((Int(d[i + k]) * a + 127) / 255) } }
            i += 4
        }
        let prov = CGDataProvider(data: Data(d) as CFData)!
        return CGImage(width: p.w, height: p.h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: p.w * 4, space: Rendu.srgb,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: prov, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)!
    }

    /// Médiane de chaque canal sur un ensemble de pixels (histogramme).
    private static func mediane(_ p: Pixels, _ indices: [Int]) -> (Float, Float, Float) {
        guard !indices.isEmpty else { return (0, 0, 0) }
        var out: [Float] = []
        for k in 0..<3 {
            var hist = [Int](repeating: 0, count: 256)
            for i in indices { hist[Int(p.d[i * 4 + k])] += 1 }
            var cumul = 0, v = 0
            for b in 0..<256 { cumul += hist[b]; if cumul * 2 >= indices.count { v = b; break } }
            out.append(Float(v))
        }
        return (out[0], out[1], out[2])
    }

    /// Rend transparent le fond relié aux bords, à la manière d'une baguette magique.
    ///
    /// Le remplissage avance d'un pixel à son voisin tant que la couleur change peu : il suit les fonds en dégradé et
    /// s'arrête net au contour du sujet. Bords adoucis, teinte du fond retirée des bords.
    public static func baguette(_ img: CGImage, tolerance: Float = 40) -> CGImage {
        let p = pixels(img)
        let w = p.w, h = p.h, n = w * h
        func rgb(_ i: Int) -> (Float, Float, Float) { (Float(p.d[i * 4]), Float(p.d[i * 4 + 1]), Float(p.d[i * 4 + 2])) }
        func dist(_ a: (Float, Float, Float), _ b: (Float, Float, Float)) -> Float {
            let x = a.0 - b.0, y = a.1 - b.1, z = a.2 - b.2
            return (x * x + y * y + z * z).squareRoot()
        }
        var vide = [Bool](repeating: false, count: n)
        var nbVide = 0
        for i in 0..<n where p.d[i * 4 + 3] < 200 { vide[i] = true; nbVide += 1 }

        var zone = [Bool](repeating: false, count: n)
        var fond: (Float, Float, Float)
        var plaque = false
        if nbVide > 0 && nbVide < n {
            // Icône déjà posée sur une plaque (coins transparents) : la plaque est le fond, et la graine est la bande
            // opaque qui longe la transparence (reflets de bord compris).
            plaque = true
            var bande = vide
            for _ in 0..<max(3, min(w, h) / 40) {
                var d = bande
                for y in 0..<h {
                    for x in 0..<w where bande[y * w + x] {
                        if y > 0 { d[(y - 1) * w + x] = true }
                        if y < h - 1 { d[(y + 1) * w + x] = true }
                        if x > 0 { d[y * w + x - 1] = true }
                        if x < w - 1 { d[y * w + x + 1] = true }
                    }
                }
                bande = d
            }
            var graine: [Int] = []
            for i in 0..<n where bande[i] && !vide[i] { graine.append(i) }
            fond = mediane(p, graine)
            for i in 0..<n where bande[i] || vide[i] { zone[i] = true }
        } else {
            var bord: [Int] = []
            for x in 0..<w { bord.append(x); bord.append((h - 1) * w + x) }
            for y in 0..<h { bord.append(y * w); bord.append(y * w + w - 1) }
            fond = mediane(p, bord)
        }
        let pas = tolerance / 5
        let seuilFond = tolerance * 5
        func loin(_ i: Int) -> Bool { zone[i] && plaque || dist(rgb(i), fond) < seuilFond }

        var file: [Int] = []
        if plaque { for i in 0..<n where zone[i] { file.append(i) } }
        else {
            func graineBord(_ i: Int) { if !zone[i] && loin(i) { zone[i] = true; file.append(i) } }
            for x in 0..<w { graineBord(x); graineBord((h - 1) * w + x) }
            for y in 0..<h { graineBord(y * w); graineBord(y * w + w - 1) }
        }
        var tete = 0
        while tete < file.count {
            let i = file[tete]; tete += 1
            let x = i % w, y = i / w
            let c = rgb(i)
            func essayer(_ j: Int) {
                if zone[j] { return }
                let v = rgb(j)
                if dist(c, v) < pas && loin(j) { zone[j] = true; file.append(j) }
            }
            if y > 0 { essayer(i - w) }
            if y < h - 1 { essayer(i + w) }
            if x > 0 { essayer(i - 1) }
            if x < w - 1 { essayer(i + 1) }
        }

        // Bords adoucis : flou 3 × 3 répété sur le masque.
        var alpha = [Float](repeating: 0, count: n)
        for i in 0..<n where !zone[i] { alpha[i] = 1 }
        for _ in 0..<2 {
            var sortie = alpha
            for y in 0..<h {
                for x in 0..<w {
                    var s: Float = 0
                    for dy in -1...1 { for dx in -1...1 { s += alpha[min(h - 1, max(0, y + dy)) * w + min(w - 1, max(0, x + dx))] } }
                    sortie[y * w + x] = s / 9
                }
            }
            alpha = sortie
        }
        var out = p
        for i in 0..<n {
            let al = max(alpha[i], 1e-3)
            let c = rgb(i)
            let comps = [c.0, c.1, c.2], f = [fond.0, fond.1, fond.2]
            for k in 0..<3 {
                let v = al < 1 ? min(255, max(0, (comps[k] - f[k] * (1 - al)) / al)) : comps[k]
                out.d[i * 4 + k] = UInt8(v.rounded())
            }
            out.d[i * 4 + 3] = UInt8(min(255, max(0, alpha[i] * Float(p.d[i * 4 + 3]))).rounded())
        }
        return image(out)
    }

    private static func coinsTransparents(_ img: CGImage) -> Bool {
        let p = pixels(img)
        let w = p.w, h = p.h
        return [0, w - 1, (h - 1) * w, h * w - 1].allSatisfy { p.d[$0 * 4 + 3] < 200 }
    }

    /// Détourage automatique : plaque d'icône retirée par la baguette ; sinon le sujet est isolé par Vision (sur la machine) ;
    /// à défaut de sujet reconnu, retour à la baguette.
    public static func automatique(_ img: CGImage) -> CGImage {
        if coinsTransparents(img) { return baguette(img) }
        if let sujet = vision(img) { return sujet }
        return baguette(img)
    }

    static func vision(_ img: CGImage) -> CGImage? {
        let requete = VNGenerateForegroundInstanceMaskRequest()
        let gestion = VNImageRequestHandler(cgImage: img)
        do {
            try gestion.perform([requete])
            guard let res = requete.results?.first, !res.allInstances.isEmpty else { return nil }
            let tampon = try res.generateMaskedImage(ofInstances: res.allInstances, from: gestion, croppedToInstancesExtent: false)
            let ci = CIImage(cvPixelBuffer: tampon)
            guard let out = Rendu.ci.createCGImage(ci, from: ci.extent, format: .RGBA8, colorSpace: Rendu.srgb) else { return nil }
            return ImageSource.normaliser(out)
        } catch { return nil }
    }
}
