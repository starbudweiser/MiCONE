import CoreGraphics
import Foundation
import ImageIO

/// Génération d'icônes par IA : fournisseurs, conversation, trousseau macOS.
///
/// - pollinations : gratuit sans clé (logo incrusté, 1 image / 45 s) ; clé facultative pour lever ces limites.
/// - huggingface : clé gratuite (crédits mensuels), FLUX. Comme Pollinations, la conversation est rejouée en un seul prompt avec la même graine.
/// - gemini : clé Google AI Studio. Chaque tour envoie la dernière image + la consigne (retouche).
/// - openai : clé OpenAI (payant). Fond transparent natif ; les tours suivants passent par /images/edits.
public enum Fournisseur: String, CaseIterable, Sendable {
    case pollinations, huggingface, gemini, openai

    public var cleRequise: Bool { self != .pollinations }
    public var modeleParDefaut: String {
        switch self {
        case .pollinations: "flux"
        case .huggingface: "black-forest-labs/FLUX.1-schnell"
        case .gemini: "gemini-2.5-flash-image"
        case .openai: "gpt-image-1"
        }
    }
    public var transparent: Bool { self == .openai }
    public var lien: String {
        switch self {
        case .pollinations: "https://enter.pollinations.ai"
        case .huggingface: "https://huggingface.co/settings/tokens"
        case .gemini: "https://aistudio.google.com/apikey"
        case .openai: "https://platform.openai.com/api-keys"
        }
    }
    /// Modèles proposés dans la liste (le champ reste modifiable pour un modèle plus récent).
    public var modeles: [String] {
        switch self {
        case .pollinations: ["flux", "turbo"]
        case .huggingface: ["black-forest-labs/FLUX.1-schnell", "black-forest-labs/FLUX.1-dev", "stabilityai/stable-diffusion-xl-base-1.0"]
        case .gemini: ["gemini-2.5-flash-image", "gemini-3-pro-image-preview"]
        case .openai: ["gpt-image-1", "gpt-image-1-mini"]
        }
    }
}

public enum StyleIA: String, CaseIterable, Sendable {
    case d3 = "3d", plat, glyphe, flat

    var description: String {
        switch self {
        case .d3: "a polished glossy 3D object in the style of modern macOS app icons, soft studio lighting, subtle reflections"
        case .plat: "a flat minimalist vector illustration, bold simple shapes, limited vivid palette"
        case .glyphe: "a single solid white glyph symbol, minimal line-free silhouette"
        // Style des icônes des outils Skyrim (case « Style flat vectoriel »).
        case .flat: "a clean flat vector pictogram in the spirit of modern macOS Big Sur icon symbols: one bold, simple, instantly readable pictogram built from geometric shapes, two or three vivid saturated colors (such as orange, sky blue, green, yellow or red) combined with white, crisp sharp edges, a very subtle soft gradient on each shape and a soft drop shadow beneath, no outlines, no texture, no photorealism, no fine details, legible even at 16 pixels"
        }
    }
    var fond: String {
        switch self {
        case .d3, .plat: "white"
        case .glyphe: "black"
        case .flat: "medium grey (#808080)"
        }
    }
}

public struct ErreurIA: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum IA {
    static let timeout: TimeInterval = 180

    /// Service probable d'une clé d'après son préfixe ; « anthropic » pour une clé Claude.
    public static func detecter(_ cle: String) -> String? {
        let c = cle.trimmingCharacters(in: .whitespacesAndNewlines)
        for (prefixe, service) in [("sk-ant-", "anthropic"), ("AIza", "gemini"), ("hf_", "huggingface"), ("sk_", "pollinations"), ("pk_", "pollinations"), ("sk-", "openai")]
        where c.hasPrefix(prefixe) { return service }
        return nil
    }

    // MARK: Trousseau

    public static func lireCle(_ f: Fournisseur) -> String {
        let r = executer("/usr/bin/security", ["find-generic-password", "-s", "MiCONE", "-a", f.rawValue, "-w"])
        return r.status == 0 ? r.sortie.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    public static func ecrireCle(_ f: Fournisseur, _ cle: String) throws {
        if cle.isEmpty { _ = executer("/usr/bin/security", ["delete-generic-password", "-s", "MiCONE", "-a", f.rawValue]); return }
        let r = executer("/usr/bin/security", ["add-generic-password", "-U", "-s", "MiCONE", "-a", f.rawValue, "-l", "MiCONE — \(f.rawValue)", "-w", cle])
        if r.status != 0 { throw ErreurIA(r.sortie.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    static func executer(_ chemin: String, _ args: [String]) -> (status: Int32, sortie: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: chemin)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    // MARK: Prompt

    static func fondTexte(_ style: StyleIA, _ transparent: Bool) -> String {
        transparent ? "on a fully transparent background" : "isolated on a plain, uniform, pure \(style.fond) background (flat solid color, no gradient)"
    }

    /// Prompt complet (en anglais) : la demande de l'utilisateur d'abord et prioritaire, le style ensuite.
    public static func consigne(_ demandes: [String], _ style: StyleIA, _ transparent: Bool) -> String {
        var texte = "Create an icon symbol. MAIN REQUEST (highest priority): \(demandes[0])."
        if demandes.count > 1 {
            texte += " Then apply these changes, in this order; each one overrides anything before it: " + demandes.dropFirst().joined(separator: "; ") + "."
        }
        texte += " Style guidelines, to follow only where the request above does not say otherwise: \(style.description)."
            + " Composition: one single centered subject \(fondTexte(style, transparent)), generous empty margin around it, no text, no letters, no frame, no border, no background shape, no tile, no badge, no rounded square, no circle behind it."
        return texte
    }

    /// Retouche de l'image jointe : la nouvelle demande doit se voir nettement.
    public static func consigneRetouche(_ demande: String, _ historique: [String], _ style: StyleIA, _ transparent: Bool) -> String {
        let contexte = historique.isEmpty ? "" : " Earlier requests in this conversation, for context: \(historique.joined(separator: "; "))."
        return "Modify the attached icon according to this NEW REQUEST: \(demande). This new request has priority over the current image and over any earlier style: the change must be clearly visible; redraw the subject entirely if that is what it takes. Do not return an image that looks the same as before.\(contexte) Keep one single centered subject \(fondTexte(style, transparent)), no text, no frame, no tile, no rounded square."
    }

    // MARK: Réseau

    static func image(_ data: Data) throws -> CGImage {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw ErreurIA(L("ia_err_image"))
        }
        return ImageSource.normaliser(img)
    }

    static func requete(_ url: String, corps: Data? = nil, entetes: [String: String] = [:]) async throws -> Data {
        guard let u = URL(string: url) else { throw ErreurIA(L("ia_err_reseau", url)) }
        var req = URLRequest(url: u, timeoutInterval: timeout)
        req.setValue("MiCONE/1.0", forHTTPHeaderField: "User-Agent")
        for (k, v) in entetes { req.setValue(v, forHTTPHeaderField: k) }
        if let corps { req.httpMethod = "POST"; req.httpBody = corps }
        do {
            let (data, rep) = try await URLSession.shared.data(for: req)
            guard let http = rep as? HTTPURLResponse, http.statusCode >= 400 else { return data }
            var msg = String(data: data.prefix(200), encoding: .utf8) ?? ""
            if let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                if let e = j["error"] as? [String: Any] { msg = e["message"] as? String ?? "" } else if let e = j["error"] { msg = "\(e)" }
            }
            switch http.statusCode {
            case 401, 403: throw ErreurIA(L("ia_err_cle", http.statusCode, msg))
            case 402 where url.contains("pollinations"): throw ErreurIA(L("ia_err_gratuit"))
            case 429: throw ErreurIA(L("ia_err_429", msg))
            default: throw ErreurIA(L("ia_err_http", http.statusCode, msg))
            }
        } catch let e as ErreurIA { throw e }
        catch { throw ErreurIA(L("ia_err_reseau", error.localizedDescription)) }
    }

    static func encoder(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? s
    }

    static func pollinations(_ prompt: String, graine: Int, modele: String, cle: String) async throws -> CGImage {
        var params = "width=1024&height=1024&nologo=true&seed=\(graine)"
        if !modele.isEmpty { params += "&model=\(encoder(modele))" }
        let base = cle.isEmpty ? "https://image.pollinations.ai/prompt/" : "https://gen.pollinations.ai/image/"
        return try image(try await requete(base + encoder(prompt) + "?" + params, entetes: cle.isEmpty ? [:] : ["Authorization": "Bearer \(cle)"]))
    }

    static func huggingface(_ prompt: String, graine: Int, modele: String, cle: String) async throws -> CGImage {
        let corps: [String: Any] = ["inputs": prompt, "parameters": ["width": 1024, "height": 1024, "seed": graine]]
        return try image(try await requete("https://router.huggingface.co/hf-inference/models/\(modele)", corps: JSONSerialization.data(withJSONObject: corps),
                                           entetes: ["Authorization": "Bearer \(cle)", "Content-Type": "application/json", "Accept": "image/png"]))
    }

    static func gemini(_ prompt: String, precedente: CGImage?, cle: String, modele: String) async throws -> CGImage {
        var parts: [[String: Any]] = [["text": prompt]]
        if let precedente, let png = Rendu.pngData(precedente) { parts.append(["inline_data": ["mime_type": "image/png", "data": png.base64EncodedString()]]) }
        let corps: [String: Any] = ["contents": [["role": "user", "parts": parts]],
                                    "generationConfig": ["responseModalities": ["TEXT", "IMAGE"], "imageConfig": ["aspectRatio": "1:1"]]]
        let data = try await requete("https://generativelanguage.googleapis.com/v1beta/models/\(modele):generateContent", corps: JSONSerialization.data(withJSONObject: corps),
                                     entetes: ["Content-Type": "application/json", "x-goog-api-key": cle])
        let rep = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        var texte = ""
        for cand in (rep["candidates"] as? [[String: Any]]) ?? [] {
            for p in ((cand["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? [] {
                if let d = (p["inlineData"] ?? p["inline_data"]) as? [String: Any], let b64 = d["data"] as? String, let bin = Data(base64Encoded: b64) { return try image(bin) }
                texte += p["text"] as? String ?? ""
            }
        }
        let raison = ((rep["promptFeedback"] as? [String: Any])?["blockReason"] as? String) ?? String(texte.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        throw ErreurIA(L("ia_err_aucune", "Gemini", raison))
    }

    static func multipart(_ champs: [String: String], fichier: (champ: String, nom: String, donnees: Data, type: String)) -> (Data, String) {
        let limite = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        var out = Data()
        func add(_ s: String) { out.append(s.data(using: .utf8)!) }
        for (k, v) in champs { add("--\(limite)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n") }
        add("--\(limite)\r\nContent-Disposition: form-data; name=\"\(fichier.champ)\"; filename=\"\(fichier.nom)\"\r\nContent-Type: \(fichier.type)\r\n\r\n")
        out.append(fichier.donnees)
        add("\r\n--\(limite)--\r\n")
        return (out, "multipart/form-data; boundary=\(limite)")
    }

    static func openai(_ prompt: String, precedente: CGImage?, cle: String, modele: String) async throws -> CGImage {
        let auth = ["Authorization": "Bearer \(cle)"]
        let data: Data
        if let precedente, let png = Rendu.pngData(precedente) {
            var champs = ["model": modele, "prompt": prompt, "size": "1024x1024", "n": "1"]
            if modele.hasPrefix("gpt-image") { champs["background"] = "transparent" }
            let (corps, type) = multipart(champs, fichier: ("image", "icone.png", png, "image/png"))
            data = try await requete("https://api.openai.com/v1/images/edits", corps: corps, entetes: auth.merging(["Content-Type": type]) { $1 })
        } else {
            var corps: [String: Any] = ["model": modele, "prompt": prompt, "size": "1024x1024", "n": 1]
            if modele.hasPrefix("gpt-image") { corps["background"] = "transparent" }
            data = try await requete("https://api.openai.com/v1/images/generations", corps: JSONSerialization.data(withJSONObject: corps),
                                     entetes: auth.merging(["Content-Type": "application/json"]) { $1 })
        }
        let first = (((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["data"] as? [[String: Any]])?.first ?? [:]
        if let b64 = first["b64_json"] as? String, let bin = Data(base64Encoded: b64) { return try image(bin) }
        if let url = first["url"] as? String { return try image(try await requete(url)) }
        throw ErreurIA(L("ia_err_aucune", "OpenAI", ""))
    }

    // MARK: Traduction

    static func traduireGoogle(_ texte: String) async throws -> (String, String) {
        let url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=en&dt=t&q=" + encoder(texte)
        let rep = try JSONSerialization.jsonObject(with: try await requete(url)) as? [Any] ?? []
        let segments = (rep.first as? [Any]) ?? []
        let anglais = segments.compactMap { ($0 as? [Any])?.first as? String }.joined()
        return (anglais, (rep.count > 2 ? rep[2] as? String : nil) ?? "?")
    }

    static func traduireLLM(_ texte: String, _ f: Fournisseur, _ cle: String) async throws -> String {
        let consigne = "Translate the following image request into natural English. Keep proper nouns. Reply with the translation only.\n\n" + texte
        if f == .gemini {
            let corps: [String: Any] = ["contents": [["role": "user", "parts": [["text": consigne]]]]]
            let d = try await requete("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent", corps: JSONSerialization.data(withJSONObject: corps),
                                      entetes: ["Content-Type": "application/json", "x-goog-api-key": cle])
            let j = try JSONSerialization.jsonObject(with: d) as? [String: Any]
            let t = ((((j?["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let corps: [String: Any] = ["model": "gpt-4.1-mini", "messages": [["role": "user", "content": consigne]]]
        let d = try await requete("https://api.openai.com/v1/chat/completions", corps: JSONSerialization.data(withJSONObject: corps),
                                  entetes: ["Authorization": "Bearer \(cle)", "Content-Type": "application/json"])
        let j = try JSONSerialization.jsonObject(with: d) as? [String: Any]
        let t = (((j?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String) ?? ""
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Traduit la demande en anglais (les modèles d'image le comprennent mieux). Google Traduction (gratuit, langue détectée)
    /// d'abord ; à défaut, Gemini ou OpenAI si une clé est disponible ; en dernier recours, le texte d'origine.
    public static func traduire(_ texte: String, fournisseur: Fournisseur, cle: String) async -> String {
        if let (anglais, langue) = try? await traduireGoogle(texte) { return langue == "en" ? texte : (anglais.isEmpty ? texte : anglais) }
        if !cle.isEmpty, fournisseur == .gemini || fournisseur == .openai, let t = try? await traduireLLM(texte, fournisseur, cle), !t.isEmpty { return t }
        return texte
    }
}

/// Fil d'une conversation avec le service d'image : demandes, images, graine commune.
public final class Conversation: @unchecked Sendable {
    public private(set) var demandes: [String] = []
    public private(set) var images: [CGImage] = []
    public private(set) var dernierPrompt = ""
    private var graine = Int.random(in: 1...1_000_000)

    public init() {}

    public var premiereDemande: String? { demandes.first }

    /// Génère une image. `signaler` reçoit la demande traduite quand elle diffère de l'originale.
    public func generer(_ demande0: String, fournisseur: Fournisseur, style: StyleIA, cle: String, modele modele0: String,
                        traduire: Bool = true, retoucher: Bool = true, signaler: (@Sendable (String) -> Void)? = nil) async throws -> CGImage {
        if fournisseur.cleRequise && cle.isEmpty { throw ErreurIA(L("ia_err_cle_requise")) }
        var demande = demande0
        if traduire {
            let anglais = await IA.traduire(demande, fournisseur: fournisseur, cle: cle)
            if anglais.trimmingCharacters(in: .whitespacesAndNewlines) != demande.trimmingCharacters(in: .whitespacesAndNewlines) { signaler?(anglais) }
            demande = anglais
        }
        let modele = modele0.isEmpty ? fournisseur.modeleParDefaut : modele0
        if !retoucher {   // nouvelle image : on oublie le fil précédent
            demandes = []; images = []; graine = Int.random(in: 1...1_000_000)
        }
        let precedente = images.last
        let toutes = demandes + [demande]
        let prompt: String, img: CGImage
        switch fournisseur {
        case .pollinations, .huggingface:
            // Pas de retouche d'image : la conversation est rejouée en un seul prompt.
            prompt = IA.consigne(toutes, style, false)
            img = fournisseur == .pollinations ? try await IA.pollinations(prompt, graine: graine, modele: modele, cle: cle)
                                              : try await IA.huggingface(prompt, graine: graine, modele: modele, cle: cle)
        case .gemini, .openai:
            prompt = precedente == nil ? IA.consigne(toutes, style, fournisseur.transparent) : IA.consigneRetouche(demande, demandes, style, fournisseur.transparent)
            img = fournisseur == .gemini ? try await IA.gemini(prompt, precedente: precedente, cle: cle, modele: modele)
                                         : try await IA.openai(prompt, precedente: precedente, cle: cle, modele: modele)
        }
        dernierPrompt = prompt
        demandes.append(demande)
        images.append(img)
        return img
    }
}
