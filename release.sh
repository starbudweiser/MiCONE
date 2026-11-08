#!/bin/bash
# Publie une version : tests, compilation, notarisation (Developer ID), puis release GitHub avec MiCONE.zip et son .sha256,
# que la mise à jour automatique de l'appli va chercher. Notes : _tools/changelogs/MiCONE_<version>.txt (4 langues).
# Usage : ./release.sh <version>   (ex. 2.0.1 ; le tag devient v2.0.1 ; VERSION est mis à jour et commité avant)
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${1:?Usage : ./release.sh <version>}"
NOTARIZE=/Volumes/SKYRIM/TOOLS/MAC/_tools/notarize_app.sh
DIST="$(mktemp -d)"

[ -z "$(git status --porcelain -- . ':!VERSION')" ] || { echo "Modifications non commitées : commitez d'abord." >&2; exit 1; }
echo "$VERSION" > VERSION
swift test
VERSION="$VERSION" NO_INSTALL=1 ./build_app.sh
DIST="$DIST" "$NOTARIZE" MiCONE.app
# MiCONE-X.Y.Z.zip : nom attendu par les versions 1.x (Python), pour qu'elles se mettent à jour vers celle-ci
cp "$DIST/MiCONE.zip" "$DIST/MiCONE-$VERSION.zip"
(cd "$DIST" && shasum -a 256 MiCONE.zip > MiCONE.zip.sha256)
python3 /Volumes/SKYRIM/TOOLS/MAC/_tools/release_notes.py MiCONE "$VERSION" --sha "$DIST/MiCONE.zip.sha256" -o "$DIST/notes.md"
git add VERSION && { git diff --cached --quiet || git commit -m "Version $VERSION"; }
git push origin main
gh release create "v$VERSION" "$DIST/MiCONE.zip" "$DIST/MiCONE.zip.sha256" "$DIST/MiCONE-$VERSION.zip" --title "MiCONE $VERSION" --notes-file "$DIST/notes.md"
rm -rf "$DIST"
echo "OK : release v$VERSION publiée"
