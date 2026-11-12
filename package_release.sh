#!/usr/bin/env zsh
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="MacFileExplorer"
INFO_PLIST_SRC="MacFileExplorer.app/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST_SRC" 2>/dev/null || echo "1.0.0")

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

cp "$INFO_PLIST_SRC" "${RELEASE_APP}/Contents/Info.plist"
cp "${BIN_PATH}/${APP_NAME}" "${RELEASE_APP}/Contents/MacOS/${APP_NAME}"
chmod +x "${RELEASE_APP}/Contents/MacOS/${APP_NAME}"

cp "Sources/MacFileExplorer/Resources/AppIcon.icns" "${RELEASE_APP}/Contents/Resources/AppIcon.icns"
cp "Sources/MacFileExplorer/Resources/AppIcon-Light.png" "${RELEASE_APP}/Contents/Resources/AppIcon-Light.png"
cp "Sources/MacFileExplorer/Resources/AppIcon-Dark.png" "${RELEASE_APP}/Contents/Resources/AppIcon-Dark.png"

if [ -d "${BIN_PATH}/${APP_NAME}_${APP_NAME}.bundle" ]; then
    cp -R "${BIN_PATH}/${APP_NAME}_${APP_NAME}.bundle" "${RELEASE_APP}/Contents/Resources/"
fi

xattr -cr "$RELEASE_APP"
codesign --force --deep --sign - --identifier "com.macfileexplorer.app" -r='designated => identifier "com.macfileexplorer.app"' "$RELEASE_APP"
codesign --verify --deep --strict "$RELEASE_APP"

echo "3) Creando imagen de disco ${DMG_PATH}..."
mkdir -p "$STAGING_DIR"
ditto "$RELEASE_APP" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"

cat <<'EOF' > "${STAGING_DIR}/COMO_ABRIR_LA_PRIMERA_VEZ.txt"
MacFileExplorer - Instalación rápida (macOS 14 o superior)
============================================================

1. Arrastra "MacFileExplorer.app" hacia la carpeta "Applications".
2. Como la app no está firmada con una cuenta paga de Apple Developer,
   la primera vez que la abras macOS puede mostrar un aviso de seguridad:
   - Intenta abrirla desde Aplicaciones y cierra el aviso.
   - Ve a Configuración del Sistema -> Privacidad y seguridad.
   - Baja hasta Seguridad y haz clic en "Abrir de todas formas".
   (Alternativa por Terminal: xattr -dr com.apple.quarantine /Applications/MacFileExplorer.app)
3. Acepta los permisos de acceso a Escritorio, Documentos, Descargas y Volúmenes.
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
