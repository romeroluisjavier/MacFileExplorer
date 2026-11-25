# MacFileExplorer

Un explorador de archivos nativo, ágil y moderno para macOS, inspirado en la practicidad y flujo de trabajo de Windows 11 Explorer combinado con la potencia de macOS.

![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B-blue?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)
![Architecture](https://img.shields.io/badge/Architecture-Universal%20(Apple%20Silicon%20%2B%20Intel)-brightgreen)
![Release](https://img.shields.io/badge/Release-v2.5.0-blueviolet)

🌐 **Sitio web oficial con demos en vivo e instalación paso a paso:** [romeroluisjavier.github.io/MacFileExplorer](https://romeroluisjavier.github.io/MacFileExplorer/)

---

## ✨ Novedades recientes (v2.5.0)

- 🖼️ **Acciones rápidas y Copiar (`⌘C`) dentro de la Vista Rápida de imágenes y videos**: copiá imagen y archivo en un clic (o elegí solo imagen / solo archivo para pegar en chats, documentos o carpetas), eliminá fondos a PNG transparente, convertí a JPG/PNG, rotá 90°/180° viendo el cambio al instante, pasá videos a MP4, recortá (*Trim*), silenciá audio y limpiá metadatos privados sin salir del Preview.
- 🪟 **Vista Rápida libre e íconos rojos estilo Acrobat para PDF**: arrastrá libremente la ventana de Vista Rápida fuera de `MacFileExplorer` y entre monitores sin frenos, y distinguí a simple vista tus PDFs de las imágenes gracias al nuevo ícono rojo vectorial estilo Acrobat.
- 📊 **Editor Office (`.docx`, `.xlsx`, `.xls`, `.pptx`, `.csv`) con selección por arrastre, Menú «Office» y «Enviar a Drive» en barra inferior**: seleccioná múltiples filas y columnas arrastrando con el mouse en CSV y Excel (con Conteo/Suma/Promedio en vivo y copiado directo a Excel/Sheets), editá documentos Office en un clic y subí archivos a Google Drive con progreso discreto en la barra de estado inferior y apertura automática en Sheets, Docs o Slides (en la app o Chrome externo).
- 🧭 **Barra de tareas avanzada**: mantené un archivo 1 segundo sobre cualquier app de la barra para abrirla y soltarlo adentro, agrupá ventanas de la misma app lado a lado, activá los modos «Solo íconos» o «Solo ícono en minimizadas» y personalizá Isla flotante, línea divisoria y 5 estilos visuales.

---

## ✨ Funcionalidades principales

- 🗂️ **Navegación por pestañas y barra híbrida**:
  - `Cmd + T`: abre una nueva pestaña de carpetas en la misma ubicación; `Cmd + Shift + T` cierra la pestaña activa.
  - Barra de direcciones híbrida (**Breadcrumb + Path Bar**) con segmentos clicables, submenús de subcarpetas en los `>` y edición directa de rutas (`Cmd + L` o clic en la barra/segmento actual).
  - Recordar carpetas, pestañas abiertas y sesiones de Google al relanzar la app.
- 🖱️ **Navegación con ratón (Logitech MX Master 3 y botones laterales)**:
  - Soporte out-of-the-box para botones laterales **Atrás** y **Adelante** vía eventos `.swipe` de Logi Options+, clics laterales estándar y trackpad tanto en carpetas como en pestañas web, más menú **Ir** (`⌘[` / `⌘]`).
- 🎨 **Quick Actions y utilidades multimedia (Clic derecho)**:
  - **Eliminar fondo (PNG transparente)** con Vision nativo.
  - **Limpiar metadatos (Privacy Stripper)** para fotos, videos y PDFs (elimina GPS, cámara, autor).
  - **Conversión y edición rápida**: convertir imágenes a JPG/PNG (calidad, DPI, ancho o MB máximo), rotar 90°/180°, convertir MOV a MP4, recortar video (*Trim*) y silenciar audio.
  - **Compresión y extracción multipropósito**: comprimir a `.zip`, `.tar.gz` o `.7z` y extraer `.zip`, `.7z`, `.tar.gz` y `.rar`.
  - **Renombrado masivo**: al renombrar varios elementos juntos, soporta Regex, numeración secuencial y fechas EXIF con vista previa y `Cmd + Z`.
- 🔍 **Productividad y gestión de archivos**:
  - **Buscador avanzado** (tipo, extensión, tamaño, subcarpetas y contenido/PDF/OCR) y carpeta virtual **Modificados hoy (24h)** en Acceso rápido.
  - **Buscador de archivos duplicados** desde *Archivo → Buscar archivos duplicados…* con pre-selección de copias y acciones (Papelera, Eliminar permanentemente o Seleccionar).
  - **Cola de transferencias (> 1 GB)**: progreso integrado en la barra inferior con pausa, reanudación y cancelación para copias/movimientos pesados.
  - **Columnas redimensionables** en vista Detalles con cursor nativo de ajuste horizontal y ordenamiento consistente del menú contextual.
- 📋 **Historial del Portapapeles estilo Maccy e icono en barra de menús (Tray Icon)**:
  - Menú **Portapapeles**, panel lateral y desplegable global `Ctrl + Cmd + V` (texto, enlaces, archivos e imágenes) con atajos personalizables e icono rápido en la barra superior de macOS.
- 💬 **Integración con Gemini y Slack**:
  - **Añadir a Gemini** y **Añadir a Slack** desde el menú contextual, **Abrir Terminal aquí...**, y visor de **Propiedades (`⌘I`)** con metadatos técnicos **EXIF / multimedia**.
- 👁️ **Vista Rápida enriquecida (`Espacio`)**:
  - Ventana flotante movible y redimensionable para archivos, Markdown completo, JSON colapsable/texto plano, código con números de línea y propiedades de carpetas.
- ↩️ **Deshacer / Rehacer (`Cmd + Z` / `Cmd + Shift + Z`)** y monitoreo en vivo de carpetas.

---

## 📥 Cómo descargar y usar (Paso a paso)

### 1. Descargar el instalador
Descarga la versión más reciente en formato `.dmg` directamente desde este repositorio:
- 👉 **[Descargar MacFileExplorer-2.5.0.dmg](https://github.com/romeroluisjavier/MacFileExplorer/raw/main/releases/MacFileExplorer-2.5.0.dmg)** *(ubicado en la carpeta [`releases/`](./releases) — también podés ver el historial en [`releases/README.md`](./releases/README.md))*

---

### 2. Instalación en tu Mac
1. Haz doble clic en el archivo descargado **`MacFileExplorer-2.5.0.dmg`**.
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

¡Listo! A partir de ese momento podrás abrir `MacFileExplorer` normalmente desde el Launchpad, Spotlight o el Dock, y usar **Buscar actualizaciones** (*Check Upgrades*) para descargar futuras versiones automáticamente desde GitHub.

---

## ⌨️ Atajos de teclado esenciales

| Atajo | Acción |
| :--- | :--- |
| <kbd>Cmd</kbd> + <kbd>L</kbd> *(o clic en barra/segmento actual)* | Editar barra de direcciones (escribir o pegar ruta) |
| <kbd>Cmd</kbd> + <kbd>T</kbd> / <kbd>Cmd</kbd> + <kbd>Shift</kbd> + <kbd>T</kbd> | Nueva pestaña / Cerrar pestaña actual |
| <kbd>Cmd</kbd> + <kbd>[</kbd> / <kbd>Cmd</kbd> + <kbd>]</kbd> *(o botones laterales del ratón)* | Ir atrás / adelante en el historial |
| <kbd>Espacio</kbd> | Vista Rápida (Quick Look / Markdown / JSON / Código / Propiedades) |
| <kbd>Cmd</kbd> + <kbd>I</kbd> | Ver Propiedades y metadatos EXIF / multimedia |
| <kbd>F2</kbd> o <kbd>Enter</kbd> | Renombrar (individual o masivo con Regex/EXIF) |
| <kbd>Ctrl</kbd> + <kbd>Cmd</kbd> + <kbd>V</kbd> | Desplegable rápido del Historial del Portapapeles |
| <kbd>Cmd</kbd> + <kbd>Z</kbd> / <kbd>Cmd</kbd> + <kbd>Shift</kbd> + <kbd>Z</kbd> | Deshacer / Rehacer última acción |
| <kbd>Cmd</kbd> + <kbd>C</kbd> / <kbd>Cmd</kbd> + <kbd>V</kbd> / <kbd>Cmd</kbd> + <kbd>X</kbd> | Copiar / Pegar / Cortar |
| <kbd>Cmd</kbd> + <kbd>Borrar</kbd> / <kbd>Shift</kbd> + <kbd>Borrar</kbd> | Mover a Papelera / Eliminar permanentemente |
| <kbd>Cmd</kbd> + <kbd>Shift</kbd> + <kbd>B</kbd> | Mostrar / ocultar barra de marcadores |
| <kbd>Cmd</kbd> + <kbd>Shift</kbd> + <kbd>.</kbd> | Mostrar / ocultar archivos ocultos |

---

## 🛠️ Compilación desde código fuente (Opcional para desarrolladores)

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
