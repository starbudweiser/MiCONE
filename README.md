# MiCONE

Turns any image into a macOS icon (`.ICNS`) set on the dark background of macOS 27 icons, so the system does not add a white plate behind transparent or non-square PNGs. Also makes Finder-style folder icons and can generate an icon with an AI service.

## About

MiCONE is made by Starbudweiser & Claude Code (Anthropic) and released under the MIT license (© 2026 Starbudweiser). It is provided "as is", without warranty of any kind. The same information is in the app: *MiCONE → About MiCONE*.

## Features

- Image → `.ICNS`: application icon (squircle) or Finder-style folder icon with an engraved motif, with background, size, offset, glass and shadow controls.
- Automatic background removal (numpy for icon plates, Apple Vision otherwise).
- "Apply to a folder…" sets the icon on a folder directly.
- Optional AI generation (Pollinations, Hugging Face, Gemini, OpenAI). API keys are kept in the macOS Keychain, never in a file.
- Command line: `MiCONE --cli image.png [more…] [--sortie DIR] [--fond sombre] [--taille 72] [--png]`.
- English, French, Spanish and Italian (follows the system language, English otherwise).
- Automatic updates from GitHub releases (see below).

## Install

Download `MiCONE-X.Y.Z.zip` from the [latest release](https://github.com/starbudweiser/MiCONE/releases/latest), unzip it and move `MiCONE.app` to your Applications folder. Signed with a Developer ID and notarized by Apple.

## Updates

At launch (at most once a day) MiCONE checks the latest GitHub release. If a newer version exists it downloads the zip, verifies the bundle identifier, the version and the code signature (which must match the running app's signing requirement), then replaces itself and relaunches. If an image is loaded, the new version is installed when you quit instead. Turn it off with *MiCONE → Install updates automatically*; *Check for Updates…* in the same menu checks on demand.

## Build from source

```bash
python3 -m unittest discover tests   # tests
./build_app.sh                        # PyInstaller build, signs and installs MiCONE.app
```

Requires Python 3.12, PyQt6, Pillow, numpy and PyInstaller. `build_app.sh` copies the Socle design-system module and signs with helper scripts specific to the author's machine; adjust the `SOCLE_QT` and `SIGN` lines for your setup. `release.sh` is the author's notarize-and-publish script.

## License

MIT. See [LICENSE](LICENSE).
