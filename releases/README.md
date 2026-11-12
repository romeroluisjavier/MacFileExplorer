# MacFileExplorer Releases

## Versión 1.1.0 (Versión Actual)

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
