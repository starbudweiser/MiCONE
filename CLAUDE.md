# MiCONE

Image → macOS icon (.ICNS) set on the dark background of macOS 27 icons (824 px squircle in a 1024 px canvas).
Two kinds: application (squircle) or Finder-style folder (engraved motif, "Apply to a folder…" through NSWorkspace/JXA).
Automatic background removal (`ia.detourer_auto`): icon plate → numpy magic wand; otherwise `outils/detourage.swift` (Vision, compiled and embedded by build_app.sh); no subject → magic wand.

- UI: follow the Socle design system — https://claude.ai/artifact/TkNj2Y6SQGZwT6EyME92Ah
- Swift / SwiftUI, macOS 14+, no dependency (the app was Python / PyQt6 up to 1.x; the Python code is in git history before 2.0.0). `Sources/MiCONECore` (testable): `Rendu` (CoreGraphics engine, squircle, folder, `.icns` through iconutil, apply to a folder through NSWorkspace), `Couleur` (Qt-style lighter/darker), `ImageSource` (loading, SVG), `Detourage` (flood fill + Vision `VNGenerateForegroundInstanceMaskRequest`), `IA` (Pollinations, Hugging Face, Gemini, OpenAI; keys in the Keychain through `/usr/bin/security`, service "MiCONE"), `IconiQ` (link), `Reglages`, `L10n`. `Sources/MiCONE` (UI): `App`, `MainView`, `Modele`, `DialogueIA`, `About`, `SplashScreen` + `SplashLogo` (animated logo), `Components`, `CLI`. `Socle.swift`, `Updater.swift`, `UpdaterView.swift`, `WindowPresent.swift` are copied by `build_app.sh` / `_tools/sync_shared.sh`: do not edit them here (SplashScreen.swift is a local copy with `accentLowercase`).
- Build: `./build_app.sh` → installs `~/Applications/Applications Personnelles/MiCONE.app` (bundle id `fr.stephan.micone`, signed through `_tools/sign_app.sh`). Version in `VERSION`. Release: `./release.sh <version>` (notes in `_tools/changelogs/MiCONE_<version>.txt`; also uploads `MiCONE-<version>.zip` so 1.x installs can update).
- Languages: fr, en, es, it (`Resources/<lang>.lproj/Localizable.strings`, same keys and `%@`/`%d` parameters, checked by tests; no visible text hard-coded). `MICONE_LANG=xx` forces a language for tests.
- Tests: `swift test`. Command line: `MiCONE --cli image.png [more…] [--sortie DIR] [--fond sombre] [--taille 72] [--png]`. Quiet launch for tests: `SPLASH_QUIET=1 SKYRIM_TOOLS_NO_UPDATE_CHECK=1 open -g -n MiCONE.app --args image.png`.
- Brand: the lowercase "i" of the name takes the logo blue (#4090f0) wherever the name is written (`Socle.brand`, `Brand.color`).
- Dependent windows (About, AI dialog, update window, alerts) open centred on the app window (`updaterCenter()`); native open/save/colour panels are placed by macOS.

## About and updates
- About: menu "About MiCONE" (app menu) or ⓘ button → `About` (300 px column, 28 px margins, Socle model). README has an English About section.
- Updates: shared `UpdateEngine` (repo starbudweiser/MiCONE, assets `MiCONE.zip` + `.sha256`, Developer ID team check). Header shows the update state left of ⓘ; gear menu: check now, install automatically (default on). Install waits while an image is loaded.

## Link with iCONIQ
- `IconiQ.envoyer`: the "Send to iCONIQ" button drops the displayed icon (PNG, kind app/folder, origin = source image) into `~/Library/Application Support/iCONIQ/Inbox/` (file + `.json` descriptor; optional `collection` id chosen in the "Collection in iCONIQ" picker, read from iCONIQ's Library.db). iCONIQ files it in its "MiCONE" collection (a landing point), or updates in place the icon already linked to the same origin; it is started in the background if not running. Nothing is sent automatically.
