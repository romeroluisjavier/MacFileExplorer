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

mkdir -p MacFileExplorer.app/Contents/Resources/en.lproj
mkdir -p MacFileExplorer.app/Contents/Resources/es.lproj

if [ -d ".build/debug/MacFileExplorer_MacFileExplorer.bundle" ]; then
    rm -rf MacFileExplorer.app/Contents/Resources/MacFileExplorer_MacFileExplorer.bundle
    cp -R .build/debug/MacFileExplorer_MacFileExplorer.bundle MacFileExplorer.app/Contents/Resources/
fi

touch MacFileExplorer.app
codesign --force --deep --sign - --identifier "com.macfileexplorer.app" -r='designated => identifier "com.macfileexplorer.app"' MacFileExplorer.app

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
