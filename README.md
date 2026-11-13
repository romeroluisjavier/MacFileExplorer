# MacFileExplorer

Un explorador de archivos nativo, ágil y moderno para macOS, inspirado en la practicidad y flujo de trabajo de Windows 11 Explorer combinado con la potencia de macOS.

![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B-blue?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)
![Architecture](https://img.shields.io/badge/Architecture-Universal%20(Apple%20Silicon%20%2B%20Intel)-brightgreen)
![Release](https://img.shields.io/badge/Release-v1.2.0-blueviolet)

---

## ✨ Funcionalidades principales

- 🗂️ **Navegación por pestañas**:
  - `Cmd + T`: Abre una nueva pestaña de carpetas en la misma ubicación.
  - `Cmd + Shift + T`: Cierra la pestaña activa y regresa a la anterior.
- 🖱️ **Navegación con ratón (Logitech MX Master 3 y botones laterales)**:
  - Usa los botones laterales **Atrás** y **Adelante** directamente en carpetas y pestañas web igual que en Finder y Chrome (compatible con gestos de Logi Options+, clics laterales estándar y trackpad).
  - Menú **Ir** (`Go`) con atajos `⌘[` / `⌘]` (compatible con teclados en español/latinoamericano y US) y opción para invertir botones laterales.
- 💬 **Compartir archivos con Slack («Añadir a Slack»)**:
  - Envía archivos directamente desde el menú contextual eligiendo canales (`#`) o personas (`@`) con búsqueda, autocompletado en vivo y opción para activar o desactivar el acceso cuando quieras.
- 📐 **Columnas ajustables (Vista Detalles) y barra adaptable**:
  - Cambia el ancho de las columnas (Nombre, Fecha, Tipo, Tamaño) arrastrando los divisores (doble clic restablece los predeterminados).
  - La barra superior oculta automáticamente los textos de Cortar, Copiar, Pegar, Renombrar y Eliminar en ventanas estrechas para mostrar solo los iconos sin cortes, e incluye iconografía completa en todos los menús.
- 🖼️ **3 Modos de iconos en la lista** *(configurables desde el menú **Ver → Iconos en vista Lista**)*:
  - **Básico**: icono rápido estándar.
  - **Icono de app (predeterminado)**: muestra el icono de la app predeterminada según la extensión (.png con Vista Previa, .mov con QuickTime Player, etc.).
  - **Miniatura**: previsualizaciones visuales de fotos, videos y documentos con caché de alto rendimiento.
- 👁️ **Vista Rápida enriquecida (Barra espaciadora)**:
  - Sobre un archivo: visor rápido nativo de macOS.
  - Sobre una carpeta: panel completo de **Propiedades** con tamaño calculado, cantidad de archivos y acceso directo para abrirla.
- ⚡ **Menú contextual extendido (Clic derecho)**:
  - **Abrir Terminal aquí...**: abre `Terminal.app` directamente en la carpeta seleccionada o en el área vacía del directorio actual.
  - **Añadir a Gemini** y **Añadir a Slack**: integración directa con `Gemini.app` y envío rápido de archivos a Slack.
- ↩️ **Deshacer / Rehacer (`Cmd + Z` / `Cmd + Shift + Z`)**:
  - Deshaz y rehaz operaciones como renombrar archivos, enviar a la papelera, mover y duplicar/pegar.
- 🔄 **Refresco en tiempo real**:
  - Detección inmediata de nuevos archivos, descargas o modificaciones externas sin necesidad de recargar manualmente.
- 🌐 **Soporte web y marcadores**:
  - Cuentas de Google aisladas en pestañas y barra de marcadores integrada (`Cmd + Shift + B`).

---

## 📥 Cómo descargar y usar (Paso a paso)

### 1. Descargar el instalador
Descarga la versión más reciente en formato `.dmg` directamente desde este repositorio:
- 👉 **[Descargar MacFileExplorer-1.2.0.dmg](https://github.com/romeroluisjavier/MacFileExplorer/raw/main/releases/MacFileExplorer-1.2.0.dmg)** *(ubicado en la carpeta [`releases/`](./releases))*

---

### 2. Instalación en tu Mac
1. Haz doble clic en el archivo descargado **`MacFileExplorer-1.2.0.dmg`**.
2. Arrastra el icono de **MacFileExplorer** a la carpeta **Applications** (Aplicaciones).

---

### 3. Primer inicio (Software independiente)
Al no estar firmado mediante una suscripción de pago de Apple Developer Program, macOS mostrará la advertencia estándar de Gatekeeper la primera vez que lo abras.

**Para abrirlo en 2 clics:**
1. Ve a tu carpeta **Aplicaciones**.
2. Haz **clic derecho** (o `Control + Clic`) sobre **MacFileExplorer** y selecciona **Abrir** (*Open*).
3. En la ventana emergente que pregunta si estás seguro, haz clic en **Abrir** (*Open*).

> **Alternativa rápida por Terminal (si lo prefieres):**
> ```bash
> xattr -cr /Applications/MacFileExplorer.app
> ```

¡Listo! A partir de ese momento podrás abrir `MacFileExplorer` normalmente desde el Launchpad, Spotlight o el Dock.

---

## ⌨️ Atajos de teclado esenciales

| Atajo | Acción |
| :--- | :--- |
| <kbd>Cmd</kbd> + <kbd>T</kbd> | Nueva pestaña en la carpeta actual |
| <kbd>Cmd</kbd> + <kbd>Shift</kbd> + <kbd>T</kbd> | Cerrar la pestaña actual |
| <kbd>Cmd</kbd> + <kbd>[</kbd> / <kbd>Cmd</kbd> + <kbd>]</kbd> *(o botones laterales del ratón)* | Ir atrás / adelante en el historial |
| <kbd>Espacio</kbd> | Vista Rápida (Quick Look / Propiedades de carpeta) |
| <kbd>F2</kbd> o <kbd>Enter</kbd> | Renombrar archivo o carpeta seleccionado |
| <kbd>Cmd</kbd> + <kbd>Z</kbd> | Deshacer última acción (renombrar, borrar, mover, pegar) |
| <kbd>Cmd</kbd> + <kbd>Shift</kbd> + <kbd>Z</kbd> | Rehacer acción deshecha |
| <kbd>Cmd</kbd> + <kbd>C</kbd> / <kbd>Cmd</kbd> + <kbd>V</kbd> | Copiar / Pegar |
| <kbd>Cmd</kbd> + <kbd>X</kbd> | Cortar (con atenuación visual estilo Windows) |
| <kbd>Cmd</kbd> + <kbd>Borrar</kbd> | Mover a la Papelera |
| <kbd>Shift</kbd> + <kbd>Borrar</kbd> | Eliminar permanentemente (con confirmación) |
| <kbd>Cmd</kbd> + <kbd>Shift</kbd> + <kbd>B</kbd> | Mostrar / ocultar barra de marcadores |

---

## 🛠️ Compilación desde código fuente (Opcional para desarrolladores)

Si deseas compilar la aplicación por tu cuenta:

```bash
# Clonar el repositorio
git clone https://github.com/romeroluisjavier/MacFileExplorer.git
cd MacFileExplorer

# Compilar y ejecutar la versión de depuración
./run.sh

# O generar el paquete Release universal (.app + .dmg)
./package_release.sh
```

---

## 📄 Licencia

Desarrollado por [Luis Javier Romero](https://github.com/romeroluisjavier).
Uso libre bajo los términos del proyecto.
