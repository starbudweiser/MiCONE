import XCTest

/// Les quatre langues ont les mêmes clés et les mêmes paramètres ; toute clé utilisée dans le code existe.
final class StringsTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func table(_ lang: String) throws -> [String: String] {
        let url = root.appendingPathComponent("Resources/\(lang).lproj/Localizable.strings")
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String], "illisible : \(lang)")
    }

    func testSameKeysEverywhere() throws {
        let fr = Set(try table("fr").keys)
        for l in ["en", "es", "it"] { XCTAssertEqual(Set(try table(l).keys), fr, "clés différentes en \(l)") }
    }

    func testNoEmptyText() throws {
        for l in ["fr", "en", "es", "it"] { for (k, v) in try table(l) { XCTAssertFalse(v.trimmingCharacters(in: .whitespaces).isEmpty, "\(k) vide en \(l)") } }
    }

    func testUsedKeysExist() throws {
        let fr = try table("fr")
        let regex = try NSRegularExpression(pattern: #"\bL\("([a-zA-Z0-9_.]+)""#)
        let ternaire = try NSRegularExpression(pattern: #"\? "([a-z_]+)" : "([a-z_]+)""#)
        for sub in ["Sources/MiCONE", "Sources/MiCONECore"] {
            let dir = root.appendingPathComponent(sub)
            for f in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) where f.pathExtension == "swift" && !["Updater.swift", "UpdaterView.swift"].contains(f.lastPathComponent) {
                let text = try String(contentsOf: f, encoding: .utf8)
                for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    let key = String(text[Range(m.range(at: 1), in: text)!])
                    XCTAssertNotNil(fr[key], "clé absente : \(key) (\(f.lastPathComponent))")
                }
                // L(dossier ? "a" : "b")
                let lignes = text.components(separatedBy: "\n").filter { $0.contains("L(") }
                for l in lignes { for m in ternaire.matches(in: l, range: NSRange(l.startIndex..., in: l)) { for g in 1...2 {
                    let key = String(l[Range(m.range(at: g), in: l)!])
                    XCTAssertNotNil(fr[key], "clé absente : \(key) (\(f.lastPathComponent))")
                } } }
                // les clés construites (L("ia_f_\(x)")) : préfixe vérifié
                let dyn = try NSRegularExpression(pattern: #"\bL\("([a-zA-Z0-9_.]+)\\\("#)
                for m in dyn.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    let prefix = String(text[Range(m.range(at: 1), in: text)!])
                    XCTAssertTrue(fr.keys.contains { $0.hasPrefix(prefix) }, "préfixe absent : \(prefix)")
                }
            }
        }
    }

    func testPlaceholdersMatch() throws {
        func spec(_ s: String) -> [String] {
            let r = try! NSRegularExpression(pattern: #"%(\d+\$)?[@d]"#)
            return r.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { String(s[Range($0.range, in: s)!]) }.sorted()
        }
        let fr = try table("fr")
        for l in ["en", "es", "it"] { for (k, v) in try table(l) { XCTAssertEqual(spec(v), spec(fr[k] ?? ""), "paramètres différents : \(k) en \(l)") } }
    }
}
