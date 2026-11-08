import AppKit
import MiCONECore
import SwiftUI

struct MiCONEApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Window("MiCONE", id: "main") {
            MainView()
                .frame(minWidth: 940, minHeight: 560)
                .splashGated()
        }
        .defaultSize(width: TailleFenetre.defaut.width, height: TailleFenetre.defaut.height)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L("apropos_menu")) { About.show() }
                Button(L("upd.menu")) { UpdateEngine.shared.checkNow() }
            }
            CommandGroup(replacing: .newItem) {
                Button(L("ouvrir")) { Modele.shared.ouvrir() }.keyboardShortcut("o", modifiers: [.command])
                Button(L("ia_ouvrir")) { DialogueIA.afficher() }.keyboardShortcut("n", modifiers: [.command])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var enAttente: String?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Le splash part avant que SwiftUI ouvre la fenêtre principale, pour pouvoir la retenir jusqu'à t = 2 s.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        Splash.shared.start(Splash.Config(title: "MiCONE", accentLowercase: true, subtitle: L("splash_sous_titre"),
                                          footer: version.isEmpty ? "" : "v" + version, iconView: AnyView(SplashLogo()), accent: Brand.color))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Socle.apply()
        Socle.brand("MiCONE", color: Brand.color)
        let updates = UpdateEngine.shared
        updates.configure(repo: "MiCONE", lang: { Lang.code })
        updates.autoCheck = { UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true }
        updates.canInstall = { !Modele.shared.aImage }   // un travail en cours n'est pas interrompu
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { updates.start() }
        let ouvrir = enAttente ?? CommandLine.arguments.dropFirst().first { FileManager.default.fileExists(atPath: $0) && ImageSource.estImage($0) }
        if let ouvrir { Modele.shared.charger(ouvrir) }
        enAttente = nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Fichiers déposés sur l'icône du Dock ou ouverts avec MiCONE.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let u = urls.first(where: { ImageSource.estImage($0.path) }) else { return }
        if NSApp.isRunning { Modele.shared.charger(u.path) } else { enAttente = u.path }
    }
}
