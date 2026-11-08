import AppKit
import MiCONECore
import SwiftUI

struct MainView: View {
    @ObservedObject var m = Modele.shared
    @ObservedObject var maj = UpdateEngine.shared
    @AppStorage("autoUpdate") private var autoUpdate = true

    var body: some View {
        VStack(spacing: Socle.M.space3) {
            header
            HStack(alignment: .top, spacing: Socle.M.space3) {
                sidebar
                work
            }
        }
        .padding(Socle.M.space3)
        .background(Socle.C.bg)
        .background(AjusteFenetre())
        .onDrop(of: [.fileURL], isTargeted: $m.depotSurvol) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url, ImageSource.estImage(url.path) else { return }
                DispatchQueue.main.async { m.charger(url.path) }
            }
            return true
        }
    }

    // MARK: En-tête

    private var header: some View {
        Panel(raised: true) {
            HStack(spacing: Socle.M.space2) {
                Text(branded: "MiCONE").socle(Socle.T.title).foregroundStyle(Socle.C.textStrong)
                Text(L("sous_titre")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                Spacer()
                updateLabel
                BarButton(symbol: "info.circle", help: L("apropos_menu")) { About.show() }
                Menu {
                    Button(L("upd.menu")) { UpdateEngine.shared.checkNow() }
                    Toggle(L("upd.auto"), isOn: $autoUpdate)
                } label: { BarGlyph(symbol: "gearshape") }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help(L("reglages")).accessibilityLabel(L("reglages"))
            }
            .padding(.horizontal, Socle.M.space3)
            .frame(height: Socle.M.sizeBar)
        }
    }

    /// Message de mise à jour, à gauche du bouton « À propos ».
    @ViewBuilder private var updateLabel: some View {
        switch maj.state {
        case .available(let plan):
            Button { maj.present(plan) } label: {
                Text(branded: L("upd.available", plan.target.version)).socle(Socle.T.meta).foregroundStyle(Socle.C.accentText)
            }.buttonStyle(.plain)
        case .downloading, .verifying, .installing:
            Text(L("upd.installing")).socle(Socle.T.meta).foregroundStyle(Socle.C.success)
        case .failed:
            Text(L("upd.failed")).socle(Socle.T.meta).foregroundStyle(Socle.C.danger)
        default:
            EmptyView()
        }
    }

    // MARK: Colonne de gauche

    private var dossier: Bool { m.r.type == "dossier" }
    private var contenir: Bool { m.r.ajustement == "contenir" }

    private var fondChoix: [(value: String, label: String)] {
        dossier ? (Rendu.dossiers.map(\.cle) + ["perso"]).map { ($0, L("dossier_\($0)")) }
                : (Rendu.fonds.map(\.cle) + ["perso"]).map { ($0, L("fond_\($0)")) }
    }

    private var sidebar: some View {
        Panel(raised: true) {
            ScrollView {
            VStack(spacing: Socle.M.space1_5) {
                Button(L("ouvrir")) { m.ouvrir() }.buttonStyle(SocleButtonStyle(.secondary))
                Button(L("ia_ouvrir")) { DialogueIA.afficher() }.buttonStyle(SocleButtonStyle(.secondary))
                Text(m.aImage ? m.infoImage : L("aucune_image")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)

                Eyebrow(L("type")).padding(.top, Socle.M.space2)
                SocleMenuPicker(options: [("appli", L("type_appli")), ("dossier", L("type_dossier"))], selection: $m.r.type)

                Eyebrow(L(dossier ? "couleur_dossier" : "fond")).padding(.top, Socle.M.space2)
                SocleMenuPicker(options: fondChoix, selection: dossier ? $m.r.fondDossier : $m.r.fond)
                if (dossier ? m.r.fondDossier : m.r.fond) == "perso" {
                    Button("\(L("choisir_couleur"))  \(m.r.couleur.uppercased())") {
                        PipetteCouleur.shared.ouvrir(initiale: m.r.couleur) { m.r.couleur = $0 }
                    }.buttonStyle(SocleButtonStyle(.secondary))
                }
                Check(title: L("aplat"), isOn: $m.r.aplat)

                Eyebrow(L("motif")).padding(.top, Socle.M.space2)
                SocleMenuPicker(options: [("contenir", L("ajustement_contenir")), ("remplir", L("ajustement_remplir"))], selection: $m.r.ajustement)
                SocleSlider(label: L("taille"), valueText: "\(m.r.taille) %", value: $m.r.taille, range: 20...100).disabled(!contenir)
                SocleSlider(label: L("decalage"), valueText: String(format: "%+d %%", m.r.decalageY), value: $m.r.decalageY, range: -20...20).disabled(!contenir)
                Check(title: L("recadrer"), isOn: $m.r.recadrer)
                Check(title: L("detourer"), isOn: $m.r.detourer)
                if dossier { Check(title: L("grave"), isOn: $m.r.grave) }

                Eyebrow(L("effets")).padding(.top, Socle.M.space2)
                Check(title: L("verre"), isOn: $m.r.verre)
                Check(title: L("ombre_motif"), isOn: $m.r.ombreMotif).disabled(!contenir)
                Check(title: L("ombre_icone"), isOn: $m.r.ombreIcone)

                Spacer(minLength: Socle.M.space2)
                Check(title: L("png_aussi"), isOn: $m.pngAussi)
                Text(L("rassurer")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).frame(maxWidth: .infinity, alignment: .leading)
                Button(L("creer")) { m.exporter() }.buttonStyle(SocleButtonStyle(.action, height: Socle.M.sizeCta)).disabled(!m.aImage)
                if dossier {
                    Button(L("appliquer_dossier")) { m.appliquerDossier() }.buttonStyle(SocleButtonStyle(.secondary)).disabled(!m.aImage)
                }
                Text(L("nom_iconiq")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted).frame(maxWidth: .infinity, alignment: .leading)
                TextField("", text: $m.nom).socleField().disabled(!m.aImage).onSubmit { m.envoyerIconiQ() }
                Text(L("collection_iconiq")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted).frame(maxWidth: .infinity, alignment: .leading)
                SocleMenuPicker(options: [("", IconiQ.parDefaut)] + m.collections.map { ($0.id, $0.chemin) }, selection: $m.collection).disabled(!m.aImage)
                Button(L("envoyer_iconiq")) { m.envoyerIconiQ() }.buttonStyle(SocleButtonStyle(.secondary)).disabled(!m.aImage)
            }
            .padding(Socle.M.space3)
            }
            .scrollIndicators(.automatic)
        }
        .frame(width: 300)
    }

    // MARK: Zone de travail

    private var work: some View {
        Panel {
            VStack(spacing: Socle.M.space2) {
                if m.aImage { preview } else { depot }
                if m.statutVisible {
                    HStack {
                        Text(m.statut).socle(Socle.T.body).foregroundStyle(couleurStatut).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                        if m.dernierExport != nil { Button(L("reveler")) { m.reveler() }.buttonStyle(SocleButtonStyle(.tertiary)).fixedSize() }
                    }
                }
            }
            .padding(Socle.M.space3)
        }
    }

    private var couleurStatut: Color {
        switch m.niveau { case .succes: Socle.C.success; case .danger: Socle.C.danger; case .aucun: Socle.C.textMuted }
    }

    private var depot: some View {
        let actif = m.depotSurvol
        let formats = ImageSource.extensions.filter { $0 != "tif" }.map { ".\($0.uppercased())" }.joined(separator: ", ")
        return VStack(spacing: Socle.M.space3) {
            Text(L("depot")).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong).multilineTextAlignment(.center)
            Text(L("depot_formats", formats)).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).multilineTextAlignment(.center)
            Button(L("ouvrir")) { m.ouvrir() }.buttonStyle(SocleButtonStyle(.secondary)).frame(width: 220)
            Button(L("ia_ouvrir")) { DialogueIA.afficher() }.buttonStyle(SocleButtonStyle(.tertiary)).frame(width: 220)
        }
        .padding(Socle.M.space6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(actif ? Socle.C.surfaceHover : Socle.C.bgSunken, in: RoundedRectangle(cornerRadius: Socle.M.radiusLg))
        .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusLg).strokeBorder(actif ? Socle.C.accent : Socle.C.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    private var preview: some View {
        VStack(spacing: Socle.M.space3) {
            HStack(spacing: Socle.M.space2) {
                Eyebrow(L("apercu"))
                if m.calcul { ProgressView().controlSize(.small) }
            }
            ZStack {
                if let img = m.apercu { Image(nsImage: img).resizable().interpolation(.high).frame(width: Modele.apercu, height: Modele.apercu) }
            }
            .frame(width: Modele.apercu, height: Modele.apercu)
            Eyebrow(L("tailles"))
            HStack(alignment: .bottom, spacing: Socle.M.space6) {
                Spacer(minLength: 0)
                ForEach(Modele.petites, id: \.self) { c in
                    VStack(spacing: Socle.M.space1) {
                        if let img = m.petitesImages[c] { Image(nsImage: img).resizable().interpolation(.high).frame(width: CGFloat(c), height: CGFloat(c)) }
                        else { Color.clear.frame(width: CGFloat(c), height: CGFloat(c)) }
                        Text("\(c) px").socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                    }
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Sélecteur de couleur du système (fond « personnalisé »), appliqué en direct.
@MainActor
final class PipetteCouleur: NSObject {
    static let shared = PipetteCouleur()
    private var rappel: ((String) -> Void)?

    func ouvrir(initiale: String, changement: @escaping (String) -> Void) {
        let p = NSColorPanel.shared
        rappel = nil
        p.showsAlpha = false
        if let c = Couleur(hex: initiale) { p.color = NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1) }
        p.setTarget(self)
        p.setAction(#selector(change(_:)))
        rappel = changement
        p.makeKeyAndOrderFront(nil)
    }

    @objc private func change(_ panneau: NSColorPanel) {
        guard let c = panneau.color.usingColorSpace(.sRGB) else { return }
        rappel?(Couleur(r: c.redComponent, g: c.greenComponent, b: c.blueComponent).hex)
    }
}

/// Taille par défaut de la fenêtre (celle choisie par Stéphan le 08/11/2026, fenêtre en mode Dossier), réduite à l'écran si besoin, centrée à l'ouverture.
enum TailleFenetre {
    static let defaut = NSSize(width: 940, height: 1062)
}

private struct AjusteFenetre: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ v: NSView, context: Context) {}

    final class Probe: NSView {
        private var fait = false
        override func viewDidMoveToWindow() {
            guard !fait, let w = window else { return }
            fait = true
            w.isRestorable = false
            for delai in [0.0, 0.3] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delai) { [weak w] in
                    guard let w else { return }
                    let zone = (w.screen ?? NSScreen.main)?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
                    w.setContentSize(NSSize(width: min(TailleFenetre.defaut.width, zone.width), height: min(TailleFenetre.defaut.height, zone.height - 40)))
                    w.socleCenter()
                }
            }
        }
    }
}
