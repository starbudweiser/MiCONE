# MiCONE

Turns any image into a macOS icon (`.ICNS`) set on the dark background of macOS 27 icons, so the system does not add a white plate behind transparent or non-square PNGs. Also makes Finder-style folder icons and can generate an icon with an AI service.

## About

MiCONE is made by Starbudweiser & Claude Code (Anthropic) and released under the MIT license (© 2026 Starbudweiser). It is provided "as is", without warranty of any kind. The same information is in the app: *MiCONE → About MiCONE*.

## Features

- Image → `.ICNS`: application icon (squircle) or Finder-style folder icon with an engraved motif, with background, size, offset, glass and shadow controls.
- Automatic background removal (flood fill for icon plates, Apple Vision otherwise, all on your Mac).
- "Apply to a folder…" sets the icon on a folder directly.
- Optional AI generation (Pollinations, Hugging Face, Gemini, OpenAI). API keys are kept in the macOS Keychain, never in a file.
- Command line: `MiCONE --cli image.png [more…] [--sortie DIR] [--fond sombre] [--taille 72] [--png]`.
- English, French, Spanish and Italian (follows the system language, English otherwise).
- Automatic updates from GitHub releases (see below).

## Install

Download `MiCONE.zip` from the [latest release](https://github.com/starbudweiser/MiCONE/releases/latest), unzip it and move `MiCONE.app` to your Applications folder. Signed with a Developer ID and notarized by Apple.

## Updates

At launch (at most once a day) MiCONE checks the GitHub releases. If a newer version exists it shows its release notes, then downloads the zip, verifies the SHA-256, the bundle identifier, the version and the Developer ID signature, replaces itself and relaunches. Nothing is installed while an image is loaded. Turn it off with the gear button → *Install updates automatically*; *Check for Updates…* in the same menu (or the app menu) checks on demand.

## Build from source

Swift / SwiftUI, macOS 14+, no dependency.

```bash
swift test          # tests
./build_app.sh      # builds, signs and installs MiCONE.app (NO_INSTALL=1 to only build)
```

`build_app.sh` copies the Socle design-system and updater sources and signs with helper scripts specific to the author's machine; without them it falls back to an ad-hoc signature. `release.sh <version>` is the author's notarize-and-publish script.

## License

MIT. See [LICENSE](LICENSE).
