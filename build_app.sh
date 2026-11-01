#!/bin/bash
# Construit MiCONE.app, la signe et l'installe dans ~/Applications/Home Applications (remplace la version précédente).
# Socle est recopié depuis sa source à chaque build : socle_qt.py est toujours à jour.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/src/MiCONE.py"
APP_NAME="MiCONE"
VERSION="$(sed -n 's/^__version__ = "\(.*\)"/\1/p' "$ROOT/src/version.py")"
BUILD="$(sed -n 's/^__build__ = "\(.*\)"/\1/p' "$ROOT/src/version.py")"
SOCLE_QT="/Volumes/SKYRIM/TOOLS/DESIGN/Socle/qt/socle_qt.py"
SIGN="/Volumes/SKYRIM/TOOLS/MAC/_tools/sign_app.sh"
OUT="${MICONE_APPS_DIR:-$HOME/Applications/Home Applications}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/micone_build.XXXXXX")"
export PATH="/Library/Frameworks/Python.framework/Versions/3.12/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

cleanup() {
  rm -rf "$TMP" "$ROOT/build" "$ROOT/$APP_NAME.spec" "$ROOT/src/__pycache__"
}
trap cleanup EXIT

[ -f "$SRC" ] || { echo "Erreur : $SRC introuvable." >&2; exit 1; }
command -v pyinstaller >/dev/null 2>&1 || { echo "Erreur : pyinstaller absent (pip install pyinstaller)." >&2; exit 1; }
if [ -f "$SOCLE_QT" ]; then cp "$SOCLE_QT" "$ROOT/src/socle_qt.py"
else echo "ATTENTION : Socle introuvable ($SOCLE_QT), copie locale de socle_qt.py utilisée." >&2; fi

# Outil de détourage automatique (Vision d'Apple), embarqué dans l'appli.
swiftc -O "$ROOT/outils/detourage.swift" -o "$ROOT/outils/detourage"

pyinstaller --noconfirm --clean --windowed --name "$APP_NAME" \
  --icon "$ROOT/assets/icon.icns" --hidden-import PyQt6.QtSvg \
  --add-binary "$ROOT/outils/detourage:." \
  --add-data "$ROOT/assets/icon.png:." \
  --distpath "$TMP/dist" --workpath "$TMP/work" --specpath "$TMP/spec" \
  "$SRC"

[ -d "$TMP/dist/$APP_NAME.app" ] || { echo "Erreur : app non générée." >&2; exit 1; }
# Version (src/version.py) lue par la fenêtre « À propos » et par la mise à jour automatique.
PLIST="$TMP/dist/$APP_NAME.app/Contents/Info.plist"
for kv in "CFBundleShortVersionString:$VERSION" "CFBundleVersion:$BUILD"; do
  /usr/libexec/PlistBuddy -c "Set :${kv%%:*} ${kv#*:}" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :${kv%%:*} string ${kv#*:}" "$PLIST"
done
/usr/libexec/PlistBuddy -c "Add :NSHumanReadableCopyright string © 2026 Starbudweiser" "$PLIST" 2>/dev/null || true
# Langues déclarées à macOS (fr, en, es, it ; anglais par défaut), avant la signature.
/usr/libexec/PlistBuddy -c "Delete :CFBundleLocalizations" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleLocalizations array" "$PLIST"
for L in fr en es it; do /usr/libexec/PlistBuddy -c "Add :CFBundleLocalizations: string $L" "$PLIST"; done
/usr/libexec/PlistBuddy -c "Set :CFBundleDevelopmentRegion en" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string en" "$PLIST"

if [ -x "$SIGN" ]; then "$SIGN" "$TMP/dist/$APP_NAME.app"  # signature stable « sKYCRASH Local Signing »
else echo "ATTENTION : $SIGN introuvable, appli non signée." >&2; fi

mkdir -p "$OUT"
rm -rf "$OUT/$APP_NAME.app"
mv "$TMP/dist/$APP_NAME.app" "$OUT/$APP_NAME.app"
echo "OK : $OUT/$APP_NAME.app"
