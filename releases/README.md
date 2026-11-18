# MacFileExplorer Releases

## Versión 1.6.0 (Versión Actual)

- **Instalador:** [`MacFileExplorer-1.6.0.dmg`](./MacFileExplorer-1.6.0.dmg)
- **Tamaño:** ~13 MB
- **Arquitectura:** Binario Universal (`arm64` Apple Silicon + `x86_64` Intel)
- **Requisitos del sistema:** macOS 14.0 (Sonoma) o posterior

### Novedades principales en la v1.6.0:
1. **Barra de direcciones editable estilo Windows Explorer (Breadcrumb + Path Bar)**: hacé clic en el segmento actual de la ruta, en el icono izquierdo o en cualquier zona libre de la barra (además de `⌘L`) para editar o pegar directamente rutas como `~/Documents/Proyectos` con selección automática completa, autocompletado de carpetas (`Tab`, `↑`/`↓`), soporte de comillas/`file://`/escapes de Terminal y menú de subcarpetas en cada `>`.
2. **Eliminar fondo de imágenes en Quick Actions (`PNG transparente`)**: al hacer clic derecho sobre una o varias imágenes (JPG, PNG, HEIC, etc.) → *Quick Actions → Eliminar fondo (PNG transparente)*, separa automáticamente el sujeto principal con Vision nativo y guarda un nuevo `.png` con fondo transparente (`<nombre>_no_bg.png`) sin modificar el original.
3. **Búsqueda de texto en imágenes más precisa (OCR mejorado)**: el buscador avanzado utiliza reconocimiento `.accurate` con corrección idiomática (`es-ES` / `en-US`), búsqueda insensible a mayúsculas y tildes, caché en memoria y escaneo paralelo con indicador de progreso en la barra inferior.

---

## Versión 1.5.1

- **Instalador:** [`MacFileExplorer-1.5.1.dmg`](./MacFileExplorer-1.5.1.dmg)
- **Tamaño:** ~13 MB
- **Arquitectura:** Binario Universal (`arm64` Apple Silicon + `x86_64` Intel)
- **Requisitos del sistema:** macOS 14.0 (Sonoma) o posterior

### Novedades principales en la v1.5.1:
1. **Buscar actualizaciones desde GitHub (*Check Upgrades*)**: botón y accesos dedicados en *Acerca de MacFileExplorer*, menú principal de la aplicación, barra de herramientas (*Ver*) e icono de la barra de menús para consultar directamente el repositorio en GitHub y descargar automáticamente el instalador `.dmg` en `~/Downloads` cuando hay una versión nueva.

---

## Versión 1.5.0

- **Instalador:** [`MacFileExplorer-1.5.0.dmg`](./MacFileExplorer-1.5.0.dmg)
- **Tamaño:** ~13 MB
- **Arquitectura:** Binario Universal (`arm64` Apple Silicon + `x86_64` Intel)
- **Requisitos del sistema:** macOS 14.0 (Sonoma) o posterior

### Novedades principales en la v1.5.0:
1. **Buscador avanzado en la barra de búsqueda**: filtro por tipo de archivo o extensión, tamaño mínimo/máximo, inclusión de subcarpetas y búsqueda dentro de texto plano, PDFs e imágenes.
2. **Buscador de archivos duplicados**: disponible en *Archivo → Buscar archivos duplicados…* con pre-marcado automático de copias conservando el original y selector de acción (Papelera, Eliminar permanentemente o Seleccionar).
3. **Cola de transferencias (> 1 GB)**: al copiar, cortar o mover más de 1 GB, el progreso aparece centrado en la barra inferior con subpanel clicable para pausar, reanudar o cancelar, y limpieza automática al terminar.
4. **Mejoras visuales y de uso**: cursor horizontal nativo al ajustar columnas en vista Detalles, opción en *Ver → Carpetas en Acceso rápido* para mostrar/ocultar *Modificados hoy (24h)*, menú contextual ordenado (*Añadir a Gemini* anteúltimo y *Propiedades* último) y ventana centrada renovada de eliminación permanente.

---

## Versión 1.4.0

- **Instalador:** [`MacFileExplorer-1.4.0.dmg`](./MacFileExplorer-1.4.0.dmg)
- **Tamaño:** ~12 MB
- **Arquitectura:** Binario Universal (`arm64` Apple Silicon + `x86_64` Intel)
- **Requisitos del sistema:** macOS 14.0 (Sonoma) o posterior

### Novedades principales en la v1.4.0:
1. **Quick Actions multimedia y Privacy Stripper**: conversión a JPG/PNG (calidad, DPI, ancho o tamaño máximo en MB), rotación 90°/180°, MOV a MP4, recorte (*Trim*), silenciado de video y limpieza de metadatos (GPS, cámara, autor) en fotos, videos y PDFs.
2. **Vista Rápida enriquecida y EXIF**: renderizado de Markdown, JSON en árbol colapsable o texto plano, código con números de línea y visor técnico EXIF/multimedia en Propiedades (`⌘I`).
3. **Compresor/descompresor multipropósito, Renombrado masivo y Modificados hoy (24h)**: soporte `.zip`, `.7z`, `.tar.gz` y `.rar`; renombrado por lotes con Regex, numeración y fechas EXIF; carpeta virtual de últimos cambios en 24h y barra de progreso integrada.

---

## Versiones 1.3.0 y 1.3.1

*(Lanzamientos publicados vía tags `v1.3.0` y `v1.3.1`)*

1. **Historial del Portapapeles estilo Maccy (`⌃⌘V`)**: menú superior dedicado, sección lateral y desplegable global no activante con pegado automático.
2. **Tray Icon en la barra de menús de macOS**: acceso rápido a ventanas, pestañas, carpetas favoritas y Google Workspace.
3. **Vista Rápida flotante y persistencia de sesiones**: ventana movible/redimensionable y recordatorio de carpetas, pestañas y sesiones web abiertas al reabrir.

---

## Versión 1.2.0

- **Instalador:** [`MacFileExplorer-1.2.0.dmg`](./MacFileExplorer-1.2.0.dmg)
- **Tamaño:** ~9.9 MB
- **Arquitectura:** Binario Universal (`arm64` Apple Silicon + `x86_64` Intel)
- **Requisitos del sistema:** macOS 14.0 (Sonoma) o posterior

### Novedades principales en la v1.2.0:
1. **Compartir en Slack («Añadir a Slack»)**: envía archivos desde el menú contextual eligiendo canales (`#`) o personas (`@`) con búsqueda en vivo, autocompletado, destinos recientes, mensaje opcional y opción para activar/desactivar la función desde menú Ver, barra de herramientas o diálogo.
2. **Navegación completa con ratón lateral (Logitech MX Master 3) y menú Ir**: soporte out-of-the-box para botones Atrás y Adelante vía eventos `.swipe` de Logi Options+, clics laterales estándar y trackpad tanto en carpetas como en pestañas web, menú superior **Ir** con atajos `⌘[` / `⌘]` (incluyendo teclados en español/latinoamericano y US) y preferencia para invertir botones.
3. **Barra de herramientas adaptable**: al reducir el ancho de la ventana, Cortar, Copiar, Pegar, Renombrar y Eliminar ocultan sus etiquetas para mostrar solo íconos y evitar cortes visuales.
4. **Iconos en el menú Edición**: iconografía SF Symbol completa también en Cortar, Copiar, Pegar, Eliminar y Seleccionar todo.
5. **Versión actualizada a 1.2.0 (Build 3)**: reflejada en `Info.plist`, «Acerca de MacFileExplorer» y el instalador universal.

---

## Versión 1.1.0

- **Instalador:** [`MacFileExplorer-1.1.0.dmg`](./MacFileExplorer-1.1.0.dmg)
- **Tamaño:** ~9.5 MB
- **Arquitectura:** Binario Universal (`arm64` Apple Silicon + `x86_64` Intel)
- **Requisitos del sistema:** macOS 14.0 (Sonoma) o posterior

### Novedades principales en la v1.1.0:
1. **Iconos representativos en la barra de menús (`Menu Bar`) y menús contextuales**: todos los elementos de la barra superior (Ventana, Archivo, Edición, Ver, Idioma y Ayuda) y menús contextuales cuentan con su icono SF Symbol.
2. **Acceso directo a la Papelera (Trash)**: disponible directamente desde la sección Acceso rápido en la barra lateral (configurable desde *Ver → Carpetas en Acceso rápido*).
3. **Control deslizante de tamaño en vista de Iconos Grandes**: barra inferior estilo Finder para redimensionar de forma fluida los iconos de 40 px a 192 px.
4. **Soporte de miniaturas y modos de icono optimizados**: vistas previas rápidas con caché en memoria y disco.
5. **Detección dinámica de versión**: la ventana "Acerca de MacFileExplorer" refleja automáticamente la versión 1.1.0 (Build 2).

---

## Versión 1.0.0 (Release Inicial)

- **Instalador:** [`MacFileExplorer-1.0.0.dmg`](./MacFileExplorer-1.0.0.dmg)
- **Tamaño:** ~9.4 MB
- **Arquitectura:** Binario Universal (`arm64` Apple Silicon + `x86_64` Intel)
- **Requisitos del sistema:** macOS 14.0 (Sonoma) o posterior

### Novedades principales en la v1.0.0:
1. **Navegación por pestañas**: `Cmd+T` abre una nueva pestaña en la misma carpeta y `Cmd+Shift+T` cierra la pestaña actual.
2. **Columnas redimensionables en vista Detalles**: arrastre interactivo de divisores entre Nombre, Fecha de modificación, Tipo y Tamaño con persistencia automática y restablecimiento por doble clic.
3. **Tres modos de iconos en vista Lista**: configurable desde el menú **Ver / View → Iconos en vista Lista**:
   - *Básico*: icono rápido del sistema.
   - *Icono de app*: icono representativo según la aplicación predeterminada de cada extensión (.png con Vista Previa, .mov con QuickTime Player, etc.).
   - *Miniatura*: vistas previas visuales para fotos, videos y documentos con caché de alto rendimiento.
4. **Vista Rápida enriquecida (Espacio)**: al presionar la barra espaciadora sobre una carpeta, muestra su panel completo de Propiedades (conteo de archivos, tamaño acumulado y botón para abrirla).
5. **Menú contextual extendido**:
   - *Abrir Terminal aquí...*: inicia `Terminal.app` directamente en la carpeta seleccionada o en el fondo de la carpeta actual.
   - *Añadir a Gemini*: detecta la app oficial `Gemini.app` y permite adjuntar archivos o vincular carpetas en el chat con un clic.
6. **Deshacer / Rehacer (`Cmd+Z` / `Cmd+Shift+Z`)**: soporte completo para deshacer acciones como renombrar, eliminar a la papelera, mover y duplicar/pegar.
7. **Monitoreo en vivo**: actualización automática instantánea del contenido del directorio ante descargas o cambios externos sin necesidad de refrescar manualmente.
