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

echo "Abriendo MacFileExplorer.app..."
open MacFileExplorer.app
