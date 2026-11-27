#!/usr/bin/env zsh
set -euo pipefail

cd "$(dirname "$0")"

echo "Compilando MacFileExplorer..."
swift build

echo "Empaquetando MacFileExplorer.app con icono transparente (Light/Dark)..."
mkdir -p MacFileExplorer.app/Contents/MacOS
mkdir -p MacFileExplorer.app/Contents/Resources

cp .build/debug/MacFileExplorer MacFileExplorer.app/Contents/MacOS/MacFileExplorer
chmod +x MacFileExplorer.app/Contents/MacOS/MacFileExplorer

if [ -f Config/Info.plist ]; then
    cp Config/Info.plist MacFileExplorer.app/Contents/Info.plist
fi

cp Sources/MacFileExplorer/Resources/AppIcon.icns MacFileExplorer.app/Contents/Resources/AppIcon.icns
cp Sources/MacFileExplorer/Resources/AppIcon-Light.png MacFileExplorer.app/Contents/Resources/AppIcon-Light.png
cp Sources/MacFileExplorer/Resources/AppIcon-Dark.png MacFileExplorer.app/Contents/Resources/AppIcon-Dark.png
cp Sources/MacFileExplorer/Resources/AppIcon-MacOS.png MacFileExplorer.app/Contents/Resources/AppIcon-MacOS.png
cp Sources/MacFileExplorer/Resources/AppIcon-MonoDark.png MacFileExplorer.app/Contents/Resources/AppIcon-MonoDark.png
cp Sources/MacFileExplorer/Resources/AppIcon-MonoLight.png MacFileExplorer.app/Contents/Resources/AppIcon-MonoLight.png
cp Sources/MacFileExplorer/Resources/AppIcon-GlassLayers.png MacFileExplorer.app/Contents/Resources/AppIcon-GlassLayers.png
find MacFileExplorer.app/Contents/Resources -maxdepth 1 -name 'StartIcon-*.png' -delete
cp Sources/MacFileExplorer/Resources/StartIcon-Brain.png MacFileExplorer.app/Contents/Resources/StartIcon-Brain.png
cp Sources/MacFileExplorer/Resources/KoFi-QR.png MacFileExplorer.app/Contents/Resources/KoFi-QR.png

mkdir -p MacFileExplorer.app/Contents/Resources/en.lproj
mkdir -p MacFileExplorer.app/Contents/Resources/es.lproj
if [ -f Config/en.lproj/InfoPlist.strings ]; then
    cp Config/en.lproj/InfoPlist.strings MacFileExplorer.app/Contents/Resources/en.lproj/InfoPlist.strings
fi
if [ -f Config/es.lproj/InfoPlist.strings ]; then
    cp Config/es.lproj/InfoPlist.strings MacFileExplorer.app/Contents/Resources/es.lproj/InfoPlist.strings
fi

if [ -d ".build/debug/MacFileExplorer_MacFileExplorer.bundle" ]; then
    rm -rf MacFileExplorer.app/Contents/Resources/MacFileExplorer_MacFileExplorer.bundle
    cp -R .build/debug/MacFileExplorer_MacFileExplorer.bundle MacFileExplorer.app/Contents/Resources/
fi

# Empaquetar helper integrado Music Decoy (0% CPU, bloquea apertura automática de Apple Music)
DECOY_APP="MacFileExplorer.app/Contents/Helpers/MacFileExplorerMusicDecoy.app"
rm -rf "$DECOY_APP"
mkdir -p "${DECOY_APP}/Contents/MacOS" "${DECOY_APP}/Contents/Resources"
cp .build/debug/MacFileExplorerMusicDecoy "${DECOY_APP}/Contents/MacOS/MacFileExplorerMusicDecoy"
chmod +x "${DECOY_APP}/Contents/MacOS/MacFileExplorerMusicDecoy"
cp Config/MusicDecoy/Info.plist "${DECOY_APP}/Contents/Info.plist"
cp Config/MusicDecoy/MusicDecoy.sdef "${DECOY_APP}/Contents/Resources/MusicDecoy.sdef"

touch MacFileExplorer.app
codesign --force --sign - --identifier "com.apple.Music" "$DECOY_APP"
codesign --force --sign - --identifier "com.macfileexplorer.app" -r='designated => identifier "com.macfileexplorer.app"' MacFileExplorer.app

if pgrep -x "MacFileExplorerMusicDecoy" >/dev/null 2>&1; then
    pkill -x "MacFileExplorerMusicDecoy" || true
fi

if pgrep -x "MacFileExplorer" >/dev/null 2>&1; then
    echo "Reiniciando instancia previa de MacFileExplorer.app..."
    osascript -e 'tell application id "com.macfileexplorer.app" to quit' >/dev/null 2>&1 || true
    for _ in {1..20}; do
        if ! pgrep -x "MacFileExplorer" >/dev/null 2>&1; then
            break
        fi
        sleep 0.1
    done
    if pgrep -x "MacFileExplorer" >/dev/null 2>&1; then
        pkill -x "MacFileExplorer" || true
        sleep 0.2
    fi
fi

echo "Abriendo MacFileExplorer.app..."
open MacFileExplorer.app
