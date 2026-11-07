# MiCONE

Image → macOS icon (.ICNS) set on the dark background of macOS 27 icons (824 px squircle in a 1024 px canvas).
Two kinds: application (squircle) or Finder-style folder (engraved motif, "Apply to a folder…" through NSWorkspace/JXA).
Automatic background removal (`ia.detourer_auto`): icon plate → numpy magic wand; otherwise `outils/detourage.swift` (Vision, compiled and embedded by build_app.sh); no subject → magic wand.

- UI: follow the Socle design system — https://claude.ai/artifact/TkNj2Y6SQGZwT6EyME92Ah
- `src/MiCONE.py` (PyQt6 UI + `--cli`), `src/rendu.py` (engine), `src/textes.py` (languages), `src/ia.py` (AI generation: Pollinations, Hugging Face, Gemini, OpenAI; keys in the Keychain, service "MiCONE"; numpy background removal), `src/dialogue_ia.py` (chat window), `src/a_propos.py` (About window, Socle model), `src/bouton_icone.py` (header buttons: ⓘ About, ⚙ settings menu with updates), `src/splash.py` (animated splash, Socle rule), `src/maj.py` (automatic updates), `src/version.py` (single source of the version).
- Build: `./build_app.sh` → installs `~/Applications/Applications Personnelles/MiCONE.app` (Socle copied from /Volumes/SKYRIM/TOOLS/DESIGN/Socle, signed through /Volumes/SKYRIM/TOOLS/MAC/_tools/sign_app.sh). The version in Info.plist comes from `src/version.py`. The app icon (`assets/icon.*`) is produced by the app itself from `assets/motif.png`.
- Languages: fr, en, es, it (`src/textes.py`, same keys everywhere; no visible text hard-coded). Detected from the macOS preferred language; anything else → English. `MICONE_LANG=xx` forces a language for tests.
- Tests: `python3 -m unittest discover tests` (texts in 4 languages, versions, release parsing, install script).
- Brand: the lowercase "i" of the name takes the logo blue (#4090f0) wherever the name is written (`socle_qt.brand`).

## About and updates
- About: menu "About MiCONE" (macOS app menu, `AboutRole`) → `a_propos.APropos` (300 px column, 28 px margins, one instance). README has an English About section.
- Updates: `maj.MiseAJour` reads the GitHub releases of starbudweiser/MiCONE (unauthenticated; `gh auth token` only as a fallback if the repo is not readable without it), at launch at most once a day. Downloads `MiCONE-X.Y.Z.zip`, checks bundle id, version, `codesign --verify` and that the signing requirement equals the running app's, then a detached shell script replaces the bundle and relaunches (`open -g`). If an image is loaded the install is deferred to quit (no relaunch). Setting "Install updates automatically" (menu, on by default).
- Release: bump `src/version.py`, commit, `./release.sh` (build, Developer ID signing, notarization, stapling, zip, push, GitHub release). Every published build is Developer ID signed: a locally signed build will not auto-update to it.

## Link with iCONIQ
- `src/iconiq.py`: the "Send to iCONIQ" button drops the displayed icon (PNG, kind app/folder, origin = source image) into `~/Library/Application Support/iCONIQ/Inbox/` (file + `.json` descriptor; optional `collection` id chosen in the "Collection in iCONIQ" picker, read from iCONIQ's Library.db). iCONIQ files it in its "MiCONE" collection (a landing point: moving the icon elsewhere removes it from that folder), or updates in place the icon already linked to the same origin; it is started in the background (`open -g`) if not running. Nothing is sent automatically.
