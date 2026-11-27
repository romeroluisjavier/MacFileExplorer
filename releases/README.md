# MacFileExplorer Releases

> ☕ **MacFileExplorer es 100% gratis y sin anuncios.** Si te resulta útil y querés colaborar con una **propina opcional** para apoyar el desarrollo, podés invitar un café en [**ko-fi.com/luisjavierromero**](https://ko-fi.com/luisjavierromero) *(o escanear el código QR desde *Acerca de MacFileExplorer* o *Ayuda → Historial de releases* dentro de la app)*.

## Versión 2.8.0 (Versión Actual)

- **Instalador (GitHub Releases):** [`MacFileExplorer-2.8.0.dmg`](https://github.com/romeroluisjavier/MacFileExplorer/releases/download/v2.8.0/MacFileExplorer-2.8.0.dmg) *(copia local: [`./MacFileExplorer-2.8.0.dmg`](./MacFileExplorer-2.8.0.dmg))*
- **Tamaño:** ~33 MB
- **Arquitectura:** Binario Universal (`arm64` Apple Silicon + `x86_64` Intel)
- **Requisitos del sistema:** macOS 14.0 (Sonoma) o posterior

### Novedades principales en la v2.8.0:
1. **Google Calendar y alertas de Meet integradas en el «Notch» (con 15+ configuraciones)**:
   - Mostrá tu agenda diaria o semanal en formato Google Calendar (Agenda con barra de color, Línea de tiempo o Compacto), con colores reales de tus eventos y apertura directa en Google Chrome.
   - Tarjeta exclusiva de aviso cuando está por empezar una Meet (sin recortar el reproductor de música), con sonido configurable, animación superior y botón **«Unirse a Meet»** en 1 clic.
   - 5 nuevos ajustes para el ícono de Calendario en la barra del Notch: estilo (incluyendo cápsula igual a *YouTube Music*), posición, tamaño, contador de eventos y número de día actual.
2. **Volumen, Ecualizador de 5 bandas y reproductor por defecto al presionar `▶ Play` (bloqueo de Apple Music)**:
   - Control de Volumen del sistema y Ecualizador de sonido de 5 bandas con 8 perfiles prearmados directo en la barra superior del Notch.
   - Elegí qué app abrir al apretar `▶ Play` (YouTube Music, Spotify, etc.) y bloqueá la apertura automática de Apple Music (0% CPU).
3. **Visor PDF interactivo en Vista Rápida (`Espacio`)**:
   - Seleccioná y copiá texto (`⌘C`), recortá cualquier zona o gráfico como imagen en alta resolución, pegá texto o imágenes (`⌘V`) sobre el PDF con Deshacer y Guardar (`⌘S`), buscá (`⌘F`), hacé zoom y rotá páginas.
4. **Portapapeles con columna Fecha y Ordenar + Foco multi-monitor + Boost de velocidad e instalador mejorado**:
   - Nueva columna **Fecha** y menú **Ordenar** (Fecha, Contenido, Tipo, Tamaño, Aplicación o Más usados) en el Historial del Portapapeles.
   - Enfoque de una sola ventana al hacer clic en apps con varias ventanas entre monitores (como Chrome) sin moverlas de pantalla.
   - Navegación más fluida en carpetas grandes, mejoras de estabilidad en transferencias/PDF/ecualizador, instalador atómico `Instalar MacFileExplorer.command` dentro del `.dmg` y 20 nuevos tests de validación.

---

## Versión 2.7.0

- **Instalador (GitHub Releases):** [`MacFileExplorer-2.7.0.dmg`](https://github.com/romeroluisjavier/MacFileExplorer/releases/download/v2.7.0/MacFileExplorer-2.7.0.dmg) *(copia local: [`./MacFileExplorer-2.7.0.dmg`](./MacFileExplorer-2.7.0.dmg))*
- **Tamaño:** ~30 MB
- **Arquitectura:** Binario Universal (`arm64` Apple Silicon + `x86_64` Intel)
- **Requisitos del sistema:** macOS 14.0 (Sonoma) o posterior

### Novedades principales en la v2.7.0:
1. **Asistente de instalación inicial (6 pasos), Tour interactivo y Novedades destacadas al actualizar**:
   - **Asistente paso a paso al instalar por primera vez**: elegí tu idioma, ícono y qué módulos opcionales querés activar (Barra de tareas, AltTab, reproductor Notch, Portapapeles, ícono en la barra superior y Ver Escritorio con `⌘D`), con barra de progreso en vivo y botón **«Instalar por defecto (omitir asistente)»** para empezar al instante.
   - **Tour interactivo con globitos desplegables**: señala las 7 zonas clave de la app y se puede suspender o cerrar en cualquier momento con un clic o `Esc` (y reabrirse cuando quieras desde el menú *Ayuda*).
   - **Novedades automáticas tras cada upgrade**: al actualizar desde una versión previa, abre automáticamente *Acerca de → Notas de la versión* con banner de actualización y etiquetas **`NUEVO`** resaltando únicamente lo que se agregó desde tu versión anterior.
2. **10 nuevas configuraciones para el reproductor «Notch» + barra de avance interactiva en YouTube Music**:
   - Personalizá en vivo desde *Configuración de Notch → Apariencia y Animaciones*: **color de acento** (carátula, app musical o color personalizado), **tipo de animación** (*Elástico*, *Fluido*, *Preciso*, *Suave*), **velocidad** (`0.5×`–`2.0×`), **mostrar/ocultar tapa del álbum**, **mostrar/ocultar nombre del álbum**, **4 estilos de visualizador** (*Barras*, *Onda*, *Puntos*, *Pulso*), **intensidad del brillo ambiental**, **opacidad del fondo** (vidrio translúcido a negro OLED), **insignia de la app sobre la carátula** y **tamaño de texto en letras sincronizadas**.
   - **Adelantar o retroceder canciones desde el Notch**: hacé clic o arrastrá directamente sobre la barra de avance (también compatible con YouTube Music, Spotify y Apple Music).
3. **Reportar errores e ideas directo desde «Acerca de» + revisión mensual del log interno**:
   - Pestaña simple, amigable y sin scroll **«Reportar error / Idea»** en *Acerca de* (y *Ayuda → Reportar un error o sugerencia…*) con botón **«Enviar reporte»** siempre visible, prellenado automático de versión/macOS y vista previa del diagnóstico técnico sin datos personales.
   - Revisión mensual automática junto al chequeo de actualizaciones para detectar errores internos nuevos y ofrecer enviarlos en 1 clic.

---

## Versión 2.6.0

- **Instalador (GitHub Releases):** [`MacFileExplorer-2.6.0.dmg`](https://github.com/romeroluisjavier/MacFileExplorer/releases/download/v2.6.0/MacFileExplorer-2.6.0.dmg) *(copia local: [`./MacFileExplorer-2.6.0.dmg`](./MacFileExplorer-2.6.0.dmg))*
- **Tamaño:** ~28 MB
- **Arquitectura:** Binario Universal (`arm64` Apple Silicon + `x86_64` Intel)
- **Requisitos del sistema:** macOS 14.0 (Sonoma) o posterior

### Novedades principales en la v2.6.0:
1. **Nuevo reproductor musical «Notch» (YouTube Music, Spotify y Apple Music)**: se integra de forma orgánica con el notch físico de tu MacBook (o como píldora flotante en cualquier monitor externo) sin robar foco, con carátula exacta, ecualizador animado, brillo ambiental del color de la portada, letras sincronizadas tipo karaoke en vivo, selector rápido de salida de audio, botones para reabrir tu última app musical cuando no suena nada y botón `✕` para cerrarlo por completo. Activable desde el nuevo menú superior **Notch** y personalizable desde **Configuración de Notch…**.
2. **Barra de tareas inteligente sin scroll ni botones fantasma**:
   - **Ajuste automático sin scroll horizontal (configurable)**: reduce suavemente el ancho de los botones cuando hay muchas ventanas abiertas para verlas todas sin cortes.
   - **Apps fijadas primero en su mismo orden**: muestra primero las ventanas de tus apps fijadas con un pin sutil, divisor y aviso explicativo al arrastrar.
   - **Sin botones fantasma de Preview**: oculta automáticamente Preview, QuickTime, TextEdit, Pages, Numbers y Keynote al cerrar su última ventana (personalizable con clic derecho y cierre con clic medio).
   - **Ajuste instantáneo al maximizar**: Chrome y demás ventanas se ajustan arriba de la Barra de tareas casi al instante sin la demora previa de 1–2 segundos.
3. **Administrador central de atajos y submenú «Herramientas (Tools)» con «View Desktop Shortcut» (`⌘D`)**: gestioná todos los atajos en una sola ventana desde *Archivo → Administrar todos los atajos de teclado…*, y usá `⌘D` para mostrar y enfocar el Escritorio desde cualquier app.
4. **Nombres de configuración unificados y guía transparente de Permisos de macOS**: nombres coherentes en todos los menús (`Notch Settings…`, `Taskbar Settings…`, `AltTab Settings…`, `Clipboard Settings…`, `Tools Settings…`) y nueva sección *Permisos de macOS* en la Ayuda explicando por qué solo se solicita lo mínimo indispensable.

---

## Versión 2.5.1

- **Instalador:** [`MacFileExplorer-2.5.1.dmg`](./MacFileExplorer-2.5.1.dmg)
- **Tamaño:** ~24 MB
- **Arquitectura:** Binario Universal (`arm64` Apple Silicon + `x86_64` Intel)
- **Requisitos del sistema:** macOS 14.0 (Sonoma) o posterior

### Novedades principales en la v2.5.1:
1. **El botón Inicio ya no trae al frente la ventana de MacFileExplorer**: abrir el Menú Inicio desde la Barra de tareas mientras usás otra aplicación (Chrome, Slack, etc.) ahora despliega el menú encima con el buscador listo para escribir manteniendo en primer plano tu app activa.
2. **Propina opcional en Ko-fi y aviso mensual discreto con comprobación automática de actualizaciones**: MacFileExplorer sigue siendo 100% gratis y sin anuncios; se agregó botón + QR de Ko-fi en *Acerca de* y en *Historial de releases*, además de una tarjeta flotante no invasiva 1 vez cada 30 días en la esquina inferior derecha que también comprueba automáticamente si hay actualizaciones disponibles.
3. **Ventana «Acerca de» más ancha y horizontal + ícono «Mono Oscuro» por defecto**: rediseño horizontal de *Acerca de MacFileExplorer* (redimensionable y con el doble de espacio para novedades) e ícono *Mono Oscuro* como diseño predeterminado en la app, el `.dmg` y la web.

---

## Versión 2.5.0

- **Instalador:** [`MacFileExplorer-2.5.0.dmg`](./MacFileExplorer-2.5.0.dmg)
- **Tamaño:** ~23 MB
- **Arquitectura:** Binario Universal (`arm64` Apple Silicon + `x86_64` Intel)
- **Requisitos del sistema:** macOS 14.0 (Sonoma) o posterior

### Novedades principales en la v2.5.0:
1. **Acciones rápidas y Copiar (`⌘C`) dentro de la Vista Rápida de imágenes y videos**: copiá imagen y archivo en un clic (o elegí solo imagen / solo archivo), eliminá fondos a PNG transparente, convertí a JPG/PNG, rotá 90°/180° en vivo, convertí videos a MP4, recortá (*Trim*), silenciá audio y limpiá metadatos privados sin salir del Preview.
2. **Vista Rápida libre entre monitores e ícono rojo estilo Acrobat para PDFs**: arrastrá la ventana de Vista Rápida con total suavidad fuera de MacFileExplorer o hacia otro monitor, y distinguí al instante archivos `.pdf` de imágenes `.png`/`.jpg` gracias al nuevo ícono rojo vectorial estilo Acrobat.
3. **Editor Office y CSV con selección por arrastre, menú «Office» y «Enviar a Drive» en barra inferior**: arrastrá con el mouse sobre celdas, filas (`#`) o columnas (`A, B, C…`) en CSV y Excel para seleccionar múltiples filas y columnas con Conteo/Suma/Promedio en vivo y copiado directo a Excel/Sheets; editá Word, Excel (`.xlsx`/`.xls`) y PowerPoint en un clic; y subí archivos a Google Drive con progreso discreto en la barra de estado inferior y apertura automática en Sheets, Docs o Slides (en la app o Google Chrome externo).
4. **Barra de tareas avanzada**: abrir apps manteniendo un archivo arrastrado 1 segundo sobre su botón, agrupación lado a lado de ventanas de la misma app, modos «Solo íconos» y «Solo ícono en ventanas minimizadas», línea divisoria superior opcional y 5 ajustes visuales en vivo (incluyendo Isla flotante).

---

## Versión 2.0.0

- **Instalador:** [`MacFileExplorer-2.0.0.dmg`](./MacFileExplorer-2.0.0.dmg)
- **Tamaño:** ~22 MB
- **Arquitectura:** Binario Universal (`arm64` Apple Silicon + `x86_64` Intel)
- **Requisitos del sistema:** macOS 14.0 (Sonoma) o posterior

### Novedades principales en la v2.0.0:
1. **8 animaciones y velocidad ajustable para el Menú Inicio (incluye modo `0 ms` instantáneo)**: elegí entre 4 estilos clásicos (*Suave*, *Desde la barra*, *Rebote elástico*, *Giro 3D*), 2 estilos Pro (*Cortina ejecutiva*, *Enfoque Spotlight*) y 2 divertidos (*Gelatina*, *Genio giratorio*). Incluye deslizador de duración (`0 ms` a `600 ms`), accesos rápidos (`0 ms`, `150 ms`, `220 ms`, `420 ms`), previsualización en vivo y botón **Probar ahora** en Configuración, menú superior y clic derecho sobre el botón Inicio.
2. **Cambio instantáneo entre carpetas ya visitadas (sin parpadeo de carga)**: volver a carpetas recientes ahora es inmediato, junto con mejoras de arranque, búsqueda de duplicados más rápida y búsqueda de texto en fotos optimizada para Apple Silicon (M1–M4).
3. **Traducción completa Español / Inglés en toda la app**: revisión integral de menús superiores, submenús, menús contextuales, mensajes de error y títulos de ventanas con cambio en vivo.
4. **Corrección de animaciones de notificaciones en la Barra de tareas**: los 6 estilos de globo rojo (Slack, Mail, WhatsApp, PWAs) vuelven a animarse con fluidez manteniendo `0%` CPU en reposo.
5. **Íconos *Brain* simplificados y aviso legal en *Acerca de MacFileExplorer***: nombres más claros (*Brain*, *Brain Mono*, *Brain Sello*) y aviso legal visible en la ventana *Acerca de*.

---

## Versión 1.8.1

- **Instalador:** [`MacFileExplorer-1.8.1.dmg`](./MacFileExplorer-1.8.1.dmg)
- **Tamaño:** ~22 MB
- **Arquitectura:** Binario Universal (`arm64` Apple Silicon + `x86_64` Intel)
- **Requisitos del sistema:** macOS 14.0 (Sonoma) o posterior

### Novedades principales en la v1.8.1:
1. **Optimización integral de rendimiento y consumo en reposo para Apple Silicon (M1/M2/M3/M4)**: consumo en reposo reducido a `~0,0% – 0,2%` CPU y `0–1` Idle Wake Ups mediante planificación de OCR en núcleos de eficiencia (`background`), supresión de recargas repetidas al guardar cachés internas, liberación de `TimelineView` al cerrar ventanas de Configuración/Asistente, cero suscripciones `CVDisplayLink` en reposo en la Barra de tareas, caché `O(1)` de aplicaciones en ejecución y timers coalescidos.
2. **4 nuevos íconos para MacFileExplorer y selector en macOS**: elegí entre **Clásico**, **Estilo macOS** (azul nativo), **Mono Oscuro**, **Mono Claro** y **Capas Cristal** desde `MacFileExplorer → Ícono de la aplicación`, *Acerca de MacFileExplorer* o *Configuración de la Barra de tareas → Apariencia* con actualización inmediata en el Dock, `⌘+Tab`, Barra de tareas y AltTab.

---

## Versión 1.8.0

- **Instalador:** [`MacFileExplorer-1.8.0.dmg`](./MacFileExplorer-1.8.0.dmg)
- **Tamaño:** ~18 MB
- **Arquitectura:** Binario Universal (`arm64` Apple Silicon + `x86_64` Intel)
- **Requisitos del sistema:** macOS 14.0 (Sonoma) o posterior

### Novedades principales en la v1.8.0:
1. **Barra de tareas estilo Windows y Menú Inicio (`Barra de tareas`)**: barra inferior opcional con soporte multimonitor (hasta 5 pantallas), sincronización con Spaces, un botón por ventana (incluyendo apps abiertas sin ventana como VS Code y apps web/PWA), orden fijo al minimizar o restaurar, reordenamiento arrastrando, **12 íconos personalizables para el botón Inicio** con animación hover, Menú Inicio con buscador instantáneo y gestión segura del Dock de macOS con restauración de emergencia.
2. **Vistas previas al pasar el cursor con tamaño fijo y 4 animaciones seleccionables**: miniaturas ultrarrápidas con precarga al pasar el cursor y 4 estilos con previsualización en vivo en Configuración (**Suave**, **Desde la barra**, **Rebote elástico** y **Giro 3D**).
3. **6 animaciones configurables para notificaciones en la barra**: avisos animados (**Salto**, **Campana**, **Latido**, **Destello**, **Onda expansiva** y **Bamboleo**) cuando una app tiene notificaciones pendientes (Slack, Mail, WhatsApp y PWAs), con selector de frecuencia y pausa automática al entrar a leer.
4. **Selector rápido de ventanas AltTab (`⌥ + Tab` / menú `AltTab`)**: selector estilo Windows para ver cada ventana abierta por separado (incluyendo minimizadas, ocultas y otros Spaces), con vista previa a tamaño completo, 3 estilos visuales (Miniaturas, Íconos o Lista), buscador integrado y hasta 5 atajos personalizables.

---

## Versión 1.7.0

- **Instalador:** [`MacFileExplorer-1.7.0.dmg`](./MacFileExplorer-1.7.0.dmg)
- **Tamaño:** ~13 MB
- **Arquitectura:** Binario Universal (`arm64` Apple Silicon + `x86_64` Intel)
- **Requisitos del sistema:** macOS 14.0 (Sonoma) o posterior

### Novedades principales en la v1.7.0:
1. **Indexación OCR automática en segundo plano (`.macfileexplorer_ocr.cache`, máx. 5 MB por carpeta)**: al abrir una carpeta, las imágenes nuevas se analizan silenciosamente y su texto se guarda comprimido con LZFSE (con tope estricto de 5 MB mediante LRU). El buscador avanzado muestra coincidencias al instante y resultados parciales en vivo mientras escanea.
2. **Gestor de caché oculta (`.macfileexplorer`) en menú Archivo**: nueva opción *Archivo → Caché oculta (.macfileexplorer)…* que lista cuántos archivos ocultos existen, cuánto ocupan en total desglosado por tipo y permite borrarlos todos para regenerarlos limpios.
3. **Ayuda interactiva completa en menú Help (`⌘?`)**: guía navegable y buscable con funciones destacadas, explicación del menú lateral y del buscador avanzado con OCR, tabla completa de atajos, todas las configuraciones posibles e historial de releases.

---

## Versión 1.6.0

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
