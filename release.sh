#!/bin/bash
# Publie la version de src/version.py : compile, signe Developer ID, notarise, agrafe, archive, crée la release GitHub vX.Y.Z.
# L'appli installée se met à jour toute seule depuis cette release (src/maj.py). Usage : ./release.sh   (NOTES="…")
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(sed -n 's/^__version__ = "\(.*\)"/\1/p' src/version.py)"
TAG="v$VERSION"
[ -z "$(git status --porcelain)" ] || { echo "Modifications non commitées : commitez d'abord." >&2; exit 1; }
git rev-parse "$TAG" >/dev/null 2>&1 && { echo "$TAG existe déjà : changez la version dans src/version.py." >&2; exit 1; }

WORK="$(mktemp -d)"
MICONE_APPS_DIR="$WORK/build" ./build_app.sh
DIST="$WORK/notarized" /Volumes/SKYRIM/TOOLS/MAC/_tools/notarize_app.sh "$WORK/build/MiCONE.app"
ZIP="$WORK/MiCONE-$VERSION.zip"
/usr/bin/ditto -c -k --keepParent "$WORK/notarized/MiCONE.app" "$ZIP"
git push origin main
gh release create "$TAG" "$ZIP" --title "MiCONE $VERSION" --notes "${NOTES:-Version $VERSION}"
rm -rf "$WORK"
echo "OK : release $TAG publiée"
