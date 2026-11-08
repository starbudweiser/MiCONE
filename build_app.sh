#!/bin/bash
# Compile MiCONE.app (release), avec son icône, ses langues et la signature stable, et l'installe dans
# ~/Applications/Applications Personnelles. Usage : ./build_app.sh   (NO_INSTALL=1 : ne pas installer ; VERSION=x.y.z)
set -euo pipefail
cd "$(dirname "$0")"

TOOLS=/Volumes/SKYRIM/TOOLS
DEST="${MICONE_APPS_DIR:-${MICONE_INSTALL_DIR:-$HOME/Applications/Applications Personnelles}}"
VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

# Socle et modules communs : copies reprises à chaque build.
[ -f "$TOOLS/DESIGN/Socle/swift/Socle.swift" ] && cp "$TOOLS/DESIGN/Socle/swift/Socle.swift" Sources/MiCONE/Socle.swift
[ -f "$TOOLS/MAC/_tools/shared/Updater.swift" ] && cp "$TOOLS/MAC/_tools/shared/Updater.swift" "$TOOLS/MAC/_tools/shared/UpdaterView.swift" Sources/MiCONE/

swift build -c release
BIN="$(swift build -c release --show-bin-path)/MiCONE"

APP=MiCONE.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MiCONE"
cp assets/icon.icns "$APP/Contents/Resources/MiCONE.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MiCONE</string>
    <key>CFBundleDisplayName</key><string>MiCONE</string>
    <key>CFBundleIdentifier</key><string>fr.stephan.micone</string>
    <key>CFBundleExecutable</key><string>MiCONE</string>
    <key>CFBundleIconFile</key><string>MiCONE</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>fr</string><string>en</string><string>es</string><string>it</string></array>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.graphics-design</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Starbudweiser</string>
    <key>NSRemovableVolumesUsageDescription</key><string>MiCONE lit vos images et enregistre vos icônes sur vos disques externes.</string>
    <key>CFBundleDocumentTypes</key><array><dict>
        <key>CFBundleTypeName</key><string>Image</string>
        <key>CFBundleTypeRole</key><string>Viewer</string>
        <key>LSItemContentTypes</key><array><string>public.image</string><string>public.svg-image</string></array>
        <key>LSHandlerRank</key><string>Alternate</string>
    </dict></array>
</dict>
</plist>
PLIST

if [ -x "$TOOLS/MAC/_tools/sign_app.sh" ]; then
    "$TOOLS/MAC/_tools/sign_app.sh" "$APP"   # signature stable « sKYCRASH Local Signing »
else
    codesign --force --deep --sign - "$APP"   # signature ad hoc hors de ma machine
fi

if [ "${NO_INSTALL:-0}" != 1 ]; then
    mkdir -p "$DEST"
    osascript -e 'tell application id "fr.stephan.micone" to quit' 2>/dev/null || true
    rm -rf "$DEST/$APP"
    cp -R "$APP" "$DEST/"
    echo "Installé : $DEST/$APP"
fi
