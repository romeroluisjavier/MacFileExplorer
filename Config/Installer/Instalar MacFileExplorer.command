#!/usr/bin/env zsh
set -euo pipefail

# ==============================================================================
#  MacFileExplorer — Instalador automático en 1 doble clic (macOS 14+)
#  - Copia MacFileExplorer.app a /Applications
#  - Quita la cuarentena de Gatekeeper para abrir sin trabas
#  - En instalaciones desde 0, abre automáticamente el Asistente de configuración
#  - En actualizaciones, abre automáticamente las Novedades de la nueva versión
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_APP="${SCRIPT_DIR}/MacFileExplorer.app"
DEST_APP="/Applications/MacFileExplorer.app"
STAGING_APP="/Applications/.MacFileExplorer.app.staging"
BACKUP_APP="/Applications/.MacFileExplorer.app.backup"

fail_and_pause() {
    local message="$1"
    echo ""
    echo "❌ ${message}"
    echo "   Tu instalación anterior (si existía) permanece intacta."
    echo ""
    read -k 1 "?Presioná cualquier tecla para cerrar..." || true
    exit 1
}

trap 'fail_and_pause "Ocurrió un error inesperado durante la instalación."' ERR

clear || true
echo "=============================================================="
echo "   MacFileExplorer — Instalador rápido / Quick Installer"
echo "=============================================================="
echo ""

if [ ! -d "$SRC_APP" ]; then
    echo "❌ No se encontró MacFileExplorer.app junto a este instalador."
    echo "   Abrí el archivo .dmg y ejecutá este instalador desde adentro."
    echo ""
    read -k 1 "?Presioná cualquier tecla para cerrar..." || true
    exit 1
fi

IS_FRESH_INSTALL=true
if [ -d "$DEST_APP" ]; then
    IS_FRESH_INSTALL=false
    echo "🔄 Actualización detectada (ya tenías MacFileExplorer instalado)."
else
    echo "✨ Instalación nueva detectada: al finalizar se abrirá el Asistente paso a paso."
fi
echo ""

# 1. Cerrar instancia previa de MacFileExplorer / Music Decoy si estuviera abierta
if pgrep -x "MacFileExplorer" >/dev/null 2>&1; then
    echo "⏹  Cerrando instancia abierta de MacFileExplorer..."
    osascript -e 'tell application id "com.macfileexplorer.app" to quit' >/dev/null 2>&1 || true
    for _ in {1..20}; do
        if ! pgrep -x "MacFileExplorer" >/dev/null 2>&1; then
            break
        fi
        sleep 0.1
    done
    if pgrep -x "MacFileExplorer" >/dev/null 2>&1; then
        pkill -x "MacFileExplorer" >/dev/null 2>&1 || true
    fi
fi
if pgrep -x "MacFileExplorerMusicDecoy" >/dev/null 2>&1; then
    pkill -x "MacFileExplorerMusicDecoy" >/dev/null 2>&1 || true
fi

# 2. Copiar MacFileExplorer.app a /Applications usando staging atómico + intercambio seguro
install_without_admin() {
    rm -rf "$STAGING_APP" "$BACKUP_APP" || return 1
    if ! ditto "$SRC_APP" "$STAGING_APP"; then
        rm -rf "$STAGING_APP" >/dev/null 2>&1 || true
        return 1
    fi
    xattr -dr com.apple.quarantine "$STAGING_APP" >/dev/null 2>&1 || true

    if [ -e "$DEST_APP" ]; then
        if ! mv "$DEST_APP" "$BACKUP_APP"; then
            rm -rf "$STAGING_APP" >/dev/null 2>&1 || true
            return 1
        fi
    fi

    if mv "$STAGING_APP" "$DEST_APP"; then
        rm -rf "$BACKUP_APP" >/dev/null 2>&1 || true
        return 0
    else
        if [ -e "$BACKUP_APP" ]; then
            mv "$BACKUP_APP" "$DEST_APP" >/dev/null 2>&1 || true
        fi
        rm -rf "$STAGING_APP" >/dev/null 2>&1 || true
        return 1
    fi
}

install_with_admin() {
    echo "🔐 Solicitando permiso de administrador de macOS..."
    osascript - "$SRC_APP" "$DEST_APP" "$STAGING_APP" "$BACKUP_APP" <<'APPLESCRIPT'
on run argv
    set srcApp to item 1 of argv
    set destApp to item 2 of argv
    set stagingApp to item 3 of argv
    set backupApp to item 4 of argv
    set qSrc to quoted form of srcApp
    set qDest to quoted form of destApp
    set qStage to quoted form of stagingApp
    set qBack to quoted form of backupApp
    set cmd to "rm -rf " & qStage & " " & qBack
    set cmd to cmd & " && ditto " & qSrc & " " & qStage
    set cmd to cmd & " && (xattr -dr com.apple.quarantine " & qStage & " >/dev/null 2>&1 || true)"
    set cmd to cmd & " && if [ -e " & qDest & " ]; then mv " & qDest & " " & qBack & "; fi"
    set cmd to cmd & " && if mv " & qStage & " " & qDest & "; then rm -rf " & qBack & "; else if [ -e " & qBack & " ]; then mv " & qBack & " " & qDest & "; fi; rm -rf " & qStage & "; exit 1; fi"
    do shell script cmd with administrator privileges
end run
APPLESCRIPT
}

echo "📦 Instalando MacFileExplorer en /Applications..."
INSTALLED_OK=false
if [ -w "/Applications" ] && ( [ ! -e "$DEST_APP" ] || [ -O "$DEST_APP" ] ); then
    if install_without_admin; then
        INSTALLED_OK=true
    fi
fi

if [ "$INSTALLED_OK" = false ]; then
    if ! install_with_admin; then
        trap - ERR
        fail_and_pause "La instalación fue cancelada o no se otorgaron permisos de administrador."
    fi
fi

trap - ERR

echo "✅ ¡MacFileExplorer instalado correctamente en /Applications!"
echo ""

# 3. Abrir MacFileExplorer: en instalación desde 0 lanzar directamente con --wizard
if [ "$IS_FRESH_INSTALL" = true ]; then
    echo "🪄 Abriendo MacFileExplorer con el Asistente de configuración inicial..."
    open -n "$DEST_APP" --args --wizard
else
    echo "🚀 Abriendo MacFileExplorer..."
    open "$DEST_APP"
fi

echo ""
echo "Listo — podés cerrar esta ventana. / Done — you can close this window."
