#!/usr/bin/env zsh
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="MacFileExplorer"
INFO_PLIST_SRC="Config/Info.plist"
if [ ! -f "$INFO_PLIST_SRC" ]; then
    INFO_PLIST_SRC="MacFileExplorer.app/Contents/Info.plist"
fi
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST_SRC" 2>/dev/null || echo "1.2.0")

DIST_DIR="dist"
RELEASE_APP="${DIST_DIR}/${APP_NAME}.app"
STAGING_DIR="${DIST_DIR}/dmg_staging"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"

echo "1) Compilando ${APP_NAME} en modo Release universal (Apple Silicon + Intel)..."
swift build -c release --arch arm64 --arch x86_64
BIN_PATH=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

echo "2) Armando ${RELEASE_APP}..."
rm -rf "$RELEASE_APP" "$STAGING_DIR"
mkdir -p "${RELEASE_APP}/Contents/MacOS"
mkdir -p "${RELEASE_APP}/Contents/Resources/en.lproj"
mkdir -p "${RELEASE_APP}/Contents/Resources/es.lproj"
if [ -f "Config/en.lproj/InfoPlist.strings" ]; then
    cp "Config/en.lproj/InfoPlist.strings" "${RELEASE_APP}/Contents/Resources/en.lproj/InfoPlist.strings"
fi
if [ -f "Config/es.lproj/InfoPlist.strings" ]; then
    cp "Config/es.lproj/InfoPlist.strings" "${RELEASE_APP}/Contents/Resources/es.lproj/InfoPlist.strings"
fi

cp "$INFO_PLIST_SRC" "${RELEASE_APP}/Contents/Info.plist"
cp "${BIN_PATH}/${APP_NAME}" "${RELEASE_APP}/Contents/MacOS/${APP_NAME}"
chmod +x "${RELEASE_APP}/Contents/MacOS/${APP_NAME}"

cp "Sources/MacFileExplorer/Resources/AppIcon.icns" "${RELEASE_APP}/Contents/Resources/AppIcon.icns"
cp "Sources/MacFileExplorer/Resources/AppIcon-Light.png" "${RELEASE_APP}/Contents/Resources/AppIcon-Light.png"
cp "Sources/MacFileExplorer/Resources/AppIcon-Dark.png" "${RELEASE_APP}/Contents/Resources/AppIcon-Dark.png"
cp "Sources/MacFileExplorer/Resources/AppIcon-MacOS.png" "${RELEASE_APP}/Contents/Resources/AppIcon-MacOS.png"
cp "Sources/MacFileExplorer/Resources/AppIcon-MonoDark.png" "${RELEASE_APP}/Contents/Resources/AppIcon-MonoDark.png"
cp "Sources/MacFileExplorer/Resources/AppIcon-MonoLight.png" "${RELEASE_APP}/Contents/Resources/AppIcon-MonoLight.png"
cp "Sources/MacFileExplorer/Resources/AppIcon-GlassLayers.png" "${RELEASE_APP}/Contents/Resources/AppIcon-GlassLayers.png"
cp "Sources/MacFileExplorer/Resources/StartIcon-Brain.png" "${RELEASE_APP}/Contents/Resources/StartIcon-Brain.png"
cp "Sources/MacFileExplorer/Resources/KoFi-QR.png" "${RELEASE_APP}/Contents/Resources/KoFi-QR.png"

if [ -d "${BIN_PATH}/${APP_NAME}_${APP_NAME}.bundle" ]; then
    cp -R "${BIN_PATH}/${APP_NAME}_${APP_NAME}.bundle" "${RELEASE_APP}/Contents/Resources/"
fi

# Empaquetar helper universal Music Decoy (Apple Silicon + Intel)
DECOY_APP="${RELEASE_APP}/Contents/Helpers/MacFileExplorerMusicDecoy.app"
mkdir -p "${DECOY_APP}/Contents/MacOS" "${DECOY_APP}/Contents/Resources"
cp "${BIN_PATH}/MacFileExplorerMusicDecoy" "${DECOY_APP}/Contents/MacOS/MacFileExplorerMusicDecoy"
chmod +x "${DECOY_APP}/Contents/MacOS/MacFileExplorerMusicDecoy"
cp "Config/MusicDecoy/Info.plist" "${DECOY_APP}/Contents/Info.plist"
cp "Config/MusicDecoy/MusicDecoy.sdef" "${DECOY_APP}/Contents/Resources/MusicDecoy.sdef"

xattr -cr "$RELEASE_APP"
codesign --force --sign - --identifier "com.apple.Music" "$DECOY_APP"
codesign --force --sign - --identifier "com.macfileexplorer.app" -r='designated => identifier "com.macfileexplorer.app"' "$RELEASE_APP"
codesign --verify --deep --strict "$RELEASE_APP"

echo "3) Creando imagen de disco ${DMG_PATH}..."
mkdir -p "$STAGING_DIR"
ditto "$RELEASE_APP" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"

if [ -f "Config/Installer/Instalar MacFileExplorer.command" ]; then
    cp "Config/Installer/Instalar MacFileExplorer.command" "${STAGING_DIR}/Instalar MacFileExplorer.command"
    chmod +x "${STAGING_DIR}/Instalar MacFileExplorer.command"
fi

cat <<'EOF' > "${STAGING_DIR}/COMO_ABRIR_LA_PRIMERA_VEZ.txt"
MacFileExplorer — Instalación rápida / Quick Install (macOS 14+)
================================================================

OPCIÓN RECOMENDADA (Instalador automático):
  1. Hacé clic derecho (o Control + clic) en "Instalar MacFileExplorer.command"
     y elegí "Abrir" -> "Abrir".
     (Si macOS muestra un aviso de "desarrollador no identificado" por Gatekeeper,
      usar clic derecho -> Abrir permite ejecutarlo en un paso; en macOS Sequoia
      también podés autorizarlo en Configuración del Sistema -> Privacidad y seguridad
      -> "Abrir de todas formas".)
  • Instala o actualiza la app automáticamente en /Applications.
  • Quita el bloqueo de Gatekeeper de la app sin comandos manuales.
  • En una instalación desde cero, abre automáticamente el Asistente paso a paso.
  • En una actualización, abre automáticamente el resumen de novedades.

RECOMMENDED OPTION (Automatic installer):
  1. Right-click (or Control-click) "Instalar MacFileExplorer.command" and choose
     "Open" -> "Open".
     (If macOS Gatekeeper warns about an unidentified developer, Right-click -> Open
      lets you run it directly; on macOS Sequoia you can also allow it under
      System Settings -> Privacy & Security -> "Open Anyway".)
  • Automatically installs or updates the app in /Applications.
  • Removes Gatekeeper quarantine from the app without manual Terminal commands.

OPCIÓN MANUAL (arrastrar y soltar):
  1. Arrastrá "MacFileExplorer.app" hacia la carpeta "Applications".
  2. Si macOS muestra un aviso la primera vez:
     Configuración del Sistema -> Privacidad y seguridad -> "Abrir de todas formas"
     (o en Terminal: xattr -dr com.apple.quarantine /Applications/MacFileExplorer.app).
  3. Al abrirla desde cero, se iniciará el Asistente paso a paso automáticamente.
     (También podés volver a abrir el asistente en cualquier momento desde
      el menú MacFileExplorer -> Asistente de instalación inicial…)
EOF

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"
hdiutil verify "$DMG_PATH"

echo ""
echo "Listo:"
echo " - App Release: ${PWD}/${RELEASE_APP}"
echo " - DMG para compartir: ${PWD}/${DMG_PATH}"
ls -lh "$DMG_PATH"
