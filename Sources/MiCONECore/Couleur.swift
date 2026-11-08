import CoreGraphics
import Foundation

/// Couleur sRGB (0…1) avec `lighter` / `darker` identiques à ceux de Qt (travail sur la valeur HSV), pour garder le rendu de la version Python.
public struct Couleur: Equatable, Sendable {
    public var r: Double, g: Double, b: Double, a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }

    /// « #rrggbb » ; nil si illisible.
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(r: Double((v >> 16) & 255) / 255, g: Double((v >> 8) & 255) / 255, b: Double(v & 255) / 255)
    }

    public static func valide(_ hex: String) -> Bool { Couleur(hex: hex) != nil }
    public static func noir(_ a: Double) -> Couleur { Couleur(r: 0, g: 0, b: 0, a: a) }
    public static func blanc(_ a: Double) -> Couleur { Couleur(r: 1, g: 1, b: 1, a: a) }

    public func alpha(_ a: Double) -> Couleur { Couleur(r: r, g: g, b: b, a: a) }
    public var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    public var hex: String { String(format: "#%02x%02x%02x", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded())) }

    /// Luminosité HSL (QColor::lightnessF).
    public var luminosite: Double { (max(r, g, b) + min(r, g, b)) / 2 }

    private var hsv: (h: Double, s: Double, v: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    private init(h: Double, s: Double, v: Double, a: Double) {
        let i = Int(h * 6) % 6, f = h * 6 - Double(Int(h * 6)), p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        let (r, g, b): (Double, Double, Double)
        switch i {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }
        self.init(r: r, g: g, b: b, a: a)
    }

    public func lighter(_ factor: Int) -> Couleur {
        if factor <= 0 { return self }
        if factor < 100 { return darker(10000 / factor) }
        var (h, s, v) = hsv
        v = v * Double(factor) / 100
        if v > 1 { s = max(0, s - (v - 1)); v = 1 }
        return Couleur(h: h, s: s, v: v, a: a)
    }

    public func darker(_ factor: Int) -> Couleur {
        if factor <= 0 { return self }
        if factor < 100 { return lighter(10000 / factor) }
        let (h, s, v) = hsv
        return Couleur(h: h, s: s, v: v * 100 / Double(factor), a: a)
    }
}
