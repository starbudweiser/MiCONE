import AppKit
import CoreGraphics
import Foundation
import ImageIO

/// Lecture des images source (PNG, JPEG, WebP, HEIC, TIFF, GIF, BMP, ICNS, SVG…).
public enum ImageSource {
    /// Extensions proposées à l'ouverture et au glisser-déposer.
    public static let extensions = ["png", "jpg", "jpeg", "webp", "svg", "heic", "tiff", "tif", "gif", "bmp", "icns"]

    public static func estImage(_ chemin: String) -> Bool { extensions.contains((chemin as NSString).pathExtension.lowercased()) }

    /// Image en BGRA prémultiplié (sRGB), orientation EXIF appliquée.
    public static func charger(_ chemin: String) throws -> CGImage {
        let nom = (chemin as NSString).lastPathComponent
        let url = URL(fileURLWithPath: chemin)
        if url.pathExtension.lowercased() == "svg" { return try svg(url, nom: nom) }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 0 else {
            throw ErreurMiCONE(L("err_lecture", nom, "format inconnu"))
        }
        // ICNS et TIFF multi-images : la plus grande
        var meilleur = 0, surface = 0
        for i in 0..<CGImageSourceGetCount(src) {
            if let p = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any],
               let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int, w * h > surface { surface = w * h; meilleur = i }
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 16384, kCGImageSourceShouldCacheImmediately: true]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, meilleur, options as CFDictionary) ?? CGImageSourceCreateImageAtIndex(src, meilleur, nil) else {
            throw ErreurMiCONE(L("err_lecture", nom, "lecture impossible"))
        }
        return normaliser(img)
    }

    static func normaliser(_ img: CGImage) -> CGImage {
        let c = Rendu.contexte(img.width, img.height, retourne: false)
        c.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return c.makeImage() ?? img
    }

    private static func svg(_ url: URL, nom: String) throws -> CGImage {
        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else {
            throw ErreurMiCONE(L("err_lecture", nom, "SVG"))
        }
        let k = min(2048 / image.size.width, 2048 / image.size.height)
        let w = max(1, Int((image.size.width * k).rounded())), h = max(1, Int((image.size.height * k).rounded()))
        let c = Rendu.contexte(w, h, retourne: false)
        let g = NSGraphicsContext(cgContext: c, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = g
        image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        guard let out = c.makeImage() else { throw ErreurMiCONE(L("err_lecture", nom, "SVG")) }
        return out
    }
}
