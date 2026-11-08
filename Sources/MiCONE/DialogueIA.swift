import AppKit
import MiCONECore
import SwiftUI

/// Fenêtre « Créer avec une IA » : conversation avec un service de génération d'images.
@MainActor
enum DialogueIA {
    private static var fenetre: NSWindow?
    static let modele = DialogueModele()

    static func afficher() {
        if fenetre == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 720), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = L("ia_titre")
            w.isReleasedWhenClosed = false
            w.contentMinSize = NSSize(width: 600, height: 560)
            w.contentView = NSHostingView(rootView: DialogueIAView(m: modele))
            w.setContentSize(NSSize(width: 720, height: 720))
            fenetre = w
        }
        guard let w = fenetre else { return }
        w.updaterCenter()   // au centre de la fenêtre de l'appli (règle Socle)
        w.present()
    }
}

@MainActor
final class DialogueModele: ObservableObject {
    enum Entree: Identifiable {
        case vous(UUID, String), traduit(UUID, String)
        case carte(UUID, apercu: NSImage, brute: NSImage, image: CGImage, prompt: String)
        var id: UUID {
            switch self { case .vous(let i, _), .traduit(let i, _), .carte(let i, _, _, _, _): i }
        }
    }

    private let d = UserDefaults.standard
    private var conv = Conversation()
    @Published var entrees: [Entree] = []
    @Published var fournisseur: Fournisseur { didSet { d.set(fournisseur.rawValue, forKey: "ia/fournisseur"); changerFournisseur() } }
    @Published var style: StyleIA { didSet { d.set(style.rawValue, forKey: "ia/style") } }
    @Published var flat: Bool { didSet { d.set(flat, forKey: "ia/flat") } }
    @Published var detourer: Bool { didSet { d.set(detourer, forKey: "ia/detourer") } }
    @Published var traduire: Bool { didSet { d.set(traduire, forKey: "ia/traduire") } }
    @Published var retoucher = true
    @Published var peutRetoucher = false
    @Published var modele = "" { didSet { d.set(modele.trimmingCharacters(in: .whitespaces), forKey: "ia/modele/\(fournisseur.rawValue)") } }
    @Published var cle = ""
    @Published var reglages = false
    @Published var demande = ""
    @Published var statut = ""
    @Published var danger = false
    @Published var occupe = false

    init() {
        fournisseur = Fournisseur(rawValue: d.string(forKey: "ia/fournisseur") ?? "") ?? .pollinations
        style = StyleIA(rawValue: d.string(forKey: "ia/style") ?? "") ?? .d3
        flat = d.bool(forKey: "ia/flat")
        detourer = d.object(forKey: "ia/detourer") as? Bool ?? true
        traduire = d.object(forKey: "ia/traduire") as? Bool ?? true
        changerFournisseur()
    }

    private func changerFournisseur() {
        let f = fournisseur
        modele = d.string(forKey: "ia/modele/\(f.rawValue)").flatMap { $0.isEmpty ? nil : $0 } ?? f.modeleParDefaut
        cle = IA.lireCle(f)
        if f.cleRequise && cle.isEmpty { reglages = true }
    }

    func dire(_ t: String, danger: Bool = false) { statut = t; self.danger = danger }

    /// Bascule sur le service auquel appartient la clé collée.
    func cleSaisie(_ texte: String) {
        guard let service = IA.detecter(texte) else { return }
        if service == "anthropic" { dire(L("ia_cle_claude")); return }
        if let f = Fournisseur(rawValue: service), f != fournisseur {
            fournisseur = f
            cle = texte
            dire(L("ia_cle_detectee", L("ia_f_\(f.rawValue)")))
        }
    }

    func enregistrerCle() {
        if IA.detecter(cle) == "anthropic" { dire(L("ia_cle_claude")); return }
        do { try IA.ecrireCle(fournisseur, cle.trimmingCharacters(in: .whitespaces)); dire(L("ia_cle_ok")) }
        catch { dire(L("ia_err_trousseau", error.localizedDescription), danger: true) }
    }

    func nouvelle() {
        guard !occupe else { return }
        conv = Conversation()
        entrees = []; peutRetoucher = false; retoucher = true
        dire("")
    }

    func envoyer() {
        let texte = demande.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texte.isEmpty, !occupe else { return }
        entrees.append(.vous(UUID(), texte))
        demande = ""
        occupe = true
        dire(L("ia_encours"))
        let f = fournisseur, st = flat ? StyleIA.flat : style, cl = cle.trimmingCharacters(in: .whitespaces)
        let mod = modele.trimmingCharacters(in: .whitespaces), tr = traduire, ret = retoucher, det = detourer
        let conversation = conv
        Task {
            do {
                let brute = try await conversation.generer(texte, fournisseur: f, style: st, cle: cl, modele: mod, traduire: tr, retoucher: ret) { anglais in
                    DispatchQueue.main.async { self.entrees.append(.traduit(UUID(), anglais)) }
                }
                let image = (det && !f.transparent) ? await Task.detached { Detourage.baguette(brute) }.value : brute
                let echelle = NSScreen.main?.backingScaleFactor ?? 2
                let (apercu, mini) = await Task.detached { () -> (CGImage, CGImage) in
                    (Rendu.reduire(Rendu.rendre(image, Reglages()), Int(220 * echelle)), Rendu.reduire(image, Int(96 * echelle)))
                }.value
                entrees.append(.carte(UUID(), apercu: NSImage(cgImage: apercu, size: NSSize(width: 220, height: 220)),
                                      brute: NSImage(cgImage: mini, size: NSSize(width: 96, height: 96)), image: image, prompt: conversation.dernierPrompt))
                peutRetoucher = true; retoucher = true
                dire("")
            } catch { dire(error.localizedDescription, danger: true) }
            occupe = false
        }
    }

    /// Enregistre l'image dans ~/Pictures/MiCONE et la charge dans la fenêtre principale.
    func utiliser(_ image: CGImage) {
        let dossier = URL(fileURLWithPath: NSHomeDirectory() + "/Pictures/MiCONE")
        let base = (conv.premiereDemande ?? "icone").lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let url = dossier.appendingPathComponent("\(String(base.prefix(40)).isEmpty ? "icone" : String(base.prefix(40)))-\(f.string(from: Date())).png")
        do {
            try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
            try Rendu.ecrirePNG(image, url)
            Modele.shared.utiliser(url.path)
        } catch { dire(L("ia_err_enregistrer", url.path), danger: true) }
    }
}

struct DialogueIAView: View {
    @ObservedObject var m: DialogueModele
    @State private var promptsOuverts = Set<UUID>()

    var body: some View {
        VStack(spacing: Socle.M.space3) {
            haut
            if m.reglages { panneauReglages }
            conversation
            TextEditor(text: $m.demande).socleField(multiline: true).frame(height: 72)
                .overlay(alignment: .topLeading) {
                    if m.demande.isEmpty { Text(L("ia_placeholder")).socle(Socle.T.body).foregroundStyle(Socle.C.textDisabled).padding(Socle.M.space3).padding(.leading, 5).allowsHitTesting(false) }
                }
            HStack(spacing: Socle.M.space4) {
                if !m.fournisseur.transparent { Check(title: L("ia_detourer"), isOn: $m.detourer).fixedSize() }
                Check(title: L("ia_traduire"), isOn: $m.traduire).fixedSize()
                Check(title: L("ia_retoucher"), isOn: $m.retoucher).fixedSize().disabled(!m.peutRetoucher)
                Spacer()
            }
            HStack {
                Spacer()
                Button(L("ia_nouvelle")) { m.nouvelle() }.buttonStyle(SocleButtonStyle(.tertiary)).fixedSize().disabled(m.occupe)
                Button(L("ia_envoyer")) { m.envoyer() }.buttonStyle(SocleButtonStyle(.primary)).frame(width: 120)
                    .keyboardShortcut(.return, modifiers: .command).disabled(m.occupe)
            }
            HStack(spacing: Socle.M.space3) {
                Text(m.statut).socle(Socle.T.body).foregroundStyle(m.danger ? Socle.C.danger : Socle.C.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                if m.occupe { ProgressView().progressViewStyle(.linear).frame(width: 120) }
            }
            .frame(minHeight: 16)
        }
        .padding(Socle.M.space4)
        .background(Socle.C.bg)
    }

    private var haut: some View {
        HStack(spacing: Socle.M.space2) {
            Text(L("ia_service")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted)
            SocleMenuPicker(options: Fournisseur.allCases.map { ($0, L("ia_f_\($0.rawValue)")) }, selection: $m.fournisseur)
            Text(L("ia_style")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted).padding(.leading, Socle.M.space2)
            SocleMenuPicker(options: [StyleIA.d3, .plat, .glyphe].map { ($0, L("ia_s_\($0.rawValue)")) }, selection: $m.style).disabled(m.flat)
            Check(title: L("ia_flat"), isOn: $m.flat).fixedSize().padding(.leading, Socle.M.space2)
            Button(L("ia_reglages")) { m.reglages.toggle() }.buttonStyle(SocleButtonStyle(m.reglages ? .secondary : .tertiary)).fixedSize()
        }
    }

    private var panneauReglages: some View {
        Panel(raised: true) {
            VStack(alignment: .leading, spacing: Socle.M.space2) {
                HStack {
                    Text(L("ia_modele")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted)
                    TextField("", text: $m.modele).socleField()
                    Menu { ForEach(m.fournisseur.modeles, id: \.self) { n in Button(n) { m.modele = n } } } label: { Image(systemName: "chevron.down").foregroundStyle(Socle.C.textMuted) }
                        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                }
                HStack {
                    Text(L("ia_cle")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted)
                    SecureField("", text: $m.cle).socleField().onChange(of: m.cle) { _, v in m.cleSaisie(v) }
                    Button(L("ia_cle_enregistrer")) { m.enregistrerCle() }.buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
                    Button(L("ia_cle_obtenir")) { if let u = URL(string: m.fournisseur.lien) { NSWorkspace.shared.open(u) } }.buttonStyle(SocleButtonStyle(.tertiary)).fixedSize()
                }
                Hint(m.fournisseur.cleRequise ? L("ia_cle_aide") : L("ia_cle_facultative") + " " + L("ia_cle_aide"))
            }
            .padding(Socle.M.space3)
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Socle.M.space3) {
                    if m.entrees.isEmpty {
                        Text(L("ia_vide")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted).multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity).padding(.top, Socle.M.space6)
                    }
                    ForEach(m.entrees) { e in ligne(e).id(e.id) }
                }
                .padding(Socle.M.space3)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Socle.C.bgSunken)
            .overlay(Rectangle().stroke(Socle.C.border, lineWidth: 1))
            .onChange(of: m.entrees.count) { _, _ in
                if let last = m.entrees.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    @ViewBuilder private func ligne(_ e: DialogueModele.Entree) -> some View {
        switch e {
        case .vous(_, let t):
            (Text("\(L("ia_vous")) : ").bold() + Text(t)).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted).textSelection(.enabled)
        case .traduit(_, let t):
            Text("→ \(L("ia_traduit")) : \(t)").socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).textSelection(.enabled)
        case .carte(let id, let apercu, let brute, let image, let prompt):
            VStack(alignment: .leading, spacing: Socle.M.space2) {
                Panel {
                    HStack(alignment: .top, spacing: Socle.M.space3) {
                        Image(nsImage: apercu).resizable().frame(width: 220, height: 220)
                        VStack(alignment: .leading) {
                            Image(nsImage: brute).resizable().frame(width: 96, height: 96)
                                .background(Socle.C.bgInset).overlay(Rectangle().stroke(Socle.C.border, lineWidth: 1))
                            Spacer(minLength: Socle.M.space2)
                            Button(L("ia_utiliser")) { m.utiliser(image) }.buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(Socle.M.space3)
                }
                Button(L("ia_voir_prompt")) {
                    if promptsOuverts.contains(id) { promptsOuverts.remove(id) } else { promptsOuverts.insert(id) }
                }.buttonStyle(SocleButtonStyle(promptsOuverts.contains(id) ? .secondary : .tertiary)).fixedSize()
                if promptsOuverts.contains(id) {
                    Text(prompt).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).textSelection(.enabled)
                }
            }
        }
    }
}
