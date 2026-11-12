import Foundation

/// Entrada individual de las Notas de la versión mostrada en "Acerca de MacFileExplorer".
public struct ReleaseNoteItem: Identifiable, Sendable {
    public let id: String
    public let icon: String
    public let titleES: String
    public let titleEN: String
    public let summaryES: String
    public let summaryEN: String

    public init(
        id: String,
        icon: String,
        titleES: String,
        titleEN: String,
        summaryES: String,
        summaryEN: String
    ) {
        self.id = id
        self.icon = icon
        self.titleES = titleES
        self.titleEN = titleEN
        self.summaryES = summaryES
        self.summaryEN = summaryEN
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager) -> String {
        loc.text(es: titleES, en: titleEN)
    }

    @MainActor
    public func localizedSummary(using loc: LocalizationManager) -> String {
        loc.text(es: summaryES, en: summaryEN)
    }
}

/// Bloque cronológico de cambios (agrupado por etapa / fecha) dentro de las Notas de la versión.
public struct ReleaseNoteSection: Identifiable, Sendable {
    public let id: String
    public let versionLabelES: String
    public let versionLabelEN: String
    public let dateLabelES: String
    public let dateLabelEN: String
    public let items: [ReleaseNoteItem]

    public init(
        id: String,
        versionLabelES: String,
        versionLabelEN: String,
        dateLabelES: String,
        dateLabelEN: String,
        items: [ReleaseNoteItem]
    ) {
        self.id = id
        self.versionLabelES = versionLabelES
        self.versionLabelEN = versionLabelEN
        self.dateLabelES = dateLabelES
        self.dateLabelEN = dateLabelEN
        self.items = items
    }

    @MainActor
    public func localizedVersionLabel(using loc: LocalizationManager) -> String {
        loc.text(es: versionLabelES, en: versionLabelEN)
    }

    @MainActor
    public func localizedDateLabel(using loc: LocalizationManager) -> String {
        loc.text(es: dateLabelES, en: dateLabelEN)
    }
}

/// Catálogo oficial de Release Notes de MacFileExplorer en lenguaje claro para cualquier usuario.
/// Nota para desarrolladores/agentes: agregar las novedades más recientes al principio del catálogo.
public enum ReleaseNotesCatalog {
    public static let sections: [ReleaseNoteSection] = [
        ReleaseNoteSection(
            id: "v1.1-customization-navigation",
            versionLabelES: "Versión 1.1 — Personalización, Navegación e Iconos",
            versionLabelEN: "Version 1.1 — Customization, Navigation & Icons",
            dateLabelES: "12 nov 2026",
            dateLabelEN: "Nov 12, 2026",
            items: [
                ReleaseNoteItem(
                    id: "mouse-back-forward-buttons",
                    icon: "computermouse.fill",
                    titleES: "Navegación con botones laterales del ratón (Atrás y Adelante)",
                    titleEN: "Navigation with mouse side buttons (Back and Forward)",
                    summaryES: "Ahora puedes usar los dos botones laterales de tu ratón para retroceder y avanzar rápidamente entre las carpetas visitadas (y en las pestañas web), exactamente igual a cómo funciona en navegadores como Google Chrome.",
                    summaryEN: "You can now use your mouse's two side buttons to swiftly navigate back and forward through visited folders (and in web tabs), exactly like in web browsers such as Google Chrome."
                ),
                ReleaseNoteItem(
                    id: "responsive-command-bar-buttons",
                    icon: "menubar.rectangle",
                    titleES: "Botones adaptables en la barra de herramientas",
                    titleEN: "Responsive toolbar action buttons",
                    summaryES: "Al achicar la ventana, los botones de Cortar, Copiar, Pegar, Renombrar y Eliminar ocultan automáticamente su texto y muestran solo sus iconos característicos, evitando textos cortados y manteniendo la barra siempre limpia y ordenada.",
                    summaryEN: "When resizing or narrowing the window, the Cut, Copy, Paste, Rename, and Delete buttons automatically hide their text labels and show only their icons, preventing awkward text wrapping and keeping the toolbar tidy."
                ),
                ReleaseNoteItem(
                    id: "add-to-slack",
                    icon: "bubble.left.and.bubble.right.fill",
                    titleES: "Compartir y enviar a Slack desde el menú contextual",
                    titleEN: "Share and send to Slack from the context menu",
                    summaryES: "Al hacer clic derecho sobre cualquier archivo, ahora puedes elegir «Añadir a Slack» para enviarlo directamente al canal o persona que elijas con un mensaje opcional y sugerencias de conversaciones frecuentes.",
                    summaryEN: "Right-clicking any file now offers «Add to Slack» to directly share it with your chosen channel or teammate, complete with an optional message and quick recipient suggestions."
                ),
                ReleaseNoteItem(
                    id: "version-1-1-release",
                    icon: "sparkles",
                    titleES: "Lanzamiento oficial de la versión 1.1",
                    titleEN: "Official Version 1.1 Release",
                    summaryES: "MacFileExplorer llega a la versión 1.1 reuniendo iconos en toda la barra de menús superior y menús contextuales, acceso directo a la Papelera desde la barra lateral, control deslizante para agrandar o achicar iconos en cuadrícula, y modos de iconos por app y miniatura.",
                    summaryEN: "MacFileExplorer reaches version 1.1 bringing representative icons across the top Menu Bar and context menus, direct Trash access from the sidebar, icon size slider in Grid view, and app-based icons & thumbnails."
                ),
                ReleaseNoteItem(
                    id: "menu-bar-representative-icons",
                    icon: "menubar.dock.rectangle",
                    titleES: "Iconos en todas las opciones de la barra de menús",
                    titleEN: "Icons across all Menu Bar options",
                    summaryES: "Se agregaron iconos representativos a todos los elementos y submenús de la barra superior de macOS (incluyendo la ventana, archivo, edición, visualización, idioma y ayuda), logrando un diseño visualmente uniforme en toda la app.",
                    summaryEN: "Representative icons have been added to all items and submenus across the macOS Menu Bar (including Window, File, Edit, View, Language, and Help), delivering a visually consistent design throughout the entire app."
                ),
                ReleaseNoteItem(
                    id: "trash-in-quick-access",
                    icon: "trash.fill",
                    titleES: "Papelera en Acceso rápido",
                    titleEN: "Trash in Quick Access",
                    summaryES: "Ahora puedes acceder directamente a la Papelera desde la sección Acceso rápido en la barra lateral izquierda (al igual que en Finder) y elegir mostrarla u ocultarla desde Ver > Carpetas en Acceso rápido.",
                    summaryEN: "You can now access Trash directly from the Quick Access section in the left sidebar (just like in Finder), and show or hide it whenever you want under View > Quick Access Folders."
                ),
                ReleaseNoteItem(
                    id: "grid-icon-size-slider",
                    icon: "slider.horizontal.below.rectangle",
                    titleES: "Control deslizante de tamaño de iconos estilo Finder",
                    titleEN: "Finder-style icon size slider in Grid view",
                    summaryES: "En la vista de Iconos grandes ahora dispones de un control deslizante en la barra inferior (idéntico a Finder) que te permite ajustar de forma fluida el tamaño de los iconos y fotos desde 40 px hasta 192 px.",
                    summaryEN: "In Large icons view, you can now use a slider in the bottom status bar (just like in Finder) to smoothly adjust the size of icons and photo previews from 40 px up to 192 px."
                ),
                ReleaseNoteItem(
                    id: "all-menu-icons",
                    icon: "square.grid.2x2",
                    titleES: "Iconos en todas las opciones de los menús",
                    titleEN: "Icons across all menu options",
                    summaryES: "Se agregaron iconos representativos a todas las opciones de los menús contextuales y menús desplegables (ordenar, dirección, vistas, marcadores y acciones de carpetas), asegurando que ninguna opción quede sin icono.",
                    summaryEN: "Representative icons have been added to all dropdown and context menu options (sorting, direction, views, bookmarks, and folder actions), ensuring no item is left without an icon."
                ),
                ReleaseNoteItem(
                    id: "list-icon-modes",
                    icon: "app.badge.checkmark",
                    titleES: "Iconos por aplicación y miniaturas en modo Lista",
                    titleEN: "App icons and thumbnails in List view",
                    summaryES: "En el menú Ver ahora puedes elegir entre tres formas de ver los iconos en la vista Lista: Básico, Icono de app (muestra el icono de la aplicación que abre cada extensión) o Miniatura (muestra vistas previas visuales en fotos, videos y PDF).",
                    summaryEN: "In the View menu, you can now switch List view icons between three modes: Basic, App Icon (shows the default app icon for each file extension), or Thumbnail (shows visual previews for images, videos, and PDFs)."
                ),
                ReleaseNoteItem(
                    id: "add-to-gemini",
                    icon: "sparkles",
                    titleES: "Añadir a Gemini desde el menú contextual",
                    titleEN: "Add to Gemini from the context menu",
                    summaryES: "Si tienes instalada la app de Gemini, al hacer clic derecho sobre archivos, carpetas o el fondo de una carpeta aparece la opción \"Añadir a Gemini\" con su ícono para adjuntar archivos o vincular la carpeta directamente en el chat de Gemini, igual que en Finder.",
                    summaryEN: "When the Gemini app is installed, right-clicking files, folders, or the empty folder background shows \"Add to Gemini\" with the Gemini icon at the bottom of the menu to attach files or add folders directly to your Gemini chat, just like in Finder."
                ),
                ReleaseNoteItem(
                    id: "open-terminal-here",
                    icon: "terminal",
                    titleES: "Abrir Terminal aquí desde carpetas",
                    titleEN: "Open Terminal here from folders",
                    summaryES: "Al hacer clic derecho sobre una carpeta (en la lista, en la barra lateral o sobre el fondo vacío de la carpeta actual), ahora aparece la opción \"Abrir Terminal aquí...\" para iniciar Terminal directamente en esa ubicación.",
                    summaryEN: "Right-clicking any folder (in the file list, the sidebar, or the empty area of the current folder) now offers \"Open Terminal here...\" to launch Terminal directly at that path."
                ),
                ReleaseNoteItem(
                    id: "quicklook-folder-properties",
                    icon: "info.circle.fill",
                    titleES: "Vista rápida con propiedades completas al tocar Espacio en carpetas",
                    titleEN: "Full folder properties shown in Quick Look on Spacebar",
                    summaryES: "Al presionar la barra espaciadora sobre una carpeta, ahora ves sus propiedades detalladas (tamaño total, cantidad de archivos y subcarpetas, ubicación, fechas y permisos) en lugar de solo su ícono.",
                    summaryEN: "When pressing Spacebar on a folder, Quick Look now shows its detailed properties (total size, file and subfolder counts, location, dates, and permissions) instead of just its icon."
                ),
                ReleaseNoteItem(
                    id: "resizable-details-columns",
                    icon: "arrow.left.and.right.square",
                    titleES: "Columnas redimensionables en la vista Detalles",
                    titleEN: "Resizable columns in Details view",
                    summaryES: "Arrastrá las barras divisorias entre Nombre, Fecha de modificación, Tipo y Tamaño para ajustar el ancho de cada columna a tu gusto (doble clic sobre una barra restablece los anchos).",
                    summaryEN: "Drag the divider bars between Name, Date modified, Type, and Size to resize each column to your liking (double-click any divider to reset column widths)."
                ),
                ReleaseNoteItem(
                    id: "cmd-shift-t-close-tab",
                    icon: "xmark.square",
                    titleES: "Cerrar la pestaña actual con ⇧⌘T",
                    titleEN: "Close the current tab with ⇧⌘T",
                    summaryES: "Presioná ⌘⇧T desde cualquier pestaña (o elegí Archivo → Cerrar pestaña actual) para cerrar la pestaña que estás viendo y volver automáticamente a la anterior.",
                    summaryEN: "Press ⇧⌘T from any tab (or choose File → Close Current Tab) to close the active tab and automatically switch back to an adjacent tab."
                ),
                ReleaseNoteItem(
                    id: "cmd-t-new-folder-tab",
                    icon: "plus.square.on.square",
                    titleES: "Nueva pestaña de carpetas con ⌘T",
                    titleEN: "Open a new folder tab with ⌘T",
                    summaryES: "Presioná ⌘T desde cualquier lugar (o elegí Archivo → Nueva pestaña de carpetas) para abrir al instante otra pestaña de carpetas en la barra superior.",
                    summaryEN: "Press ⌘T anywhere (or choose File → New Folder Tab) to instantly open another folder tab in the top tab bar."
                ),
                ReleaseNoteItem(
                    id: "live-directory-refresh",
                    icon: "arrow.triangle.2.circlepath",
                    titleES: "Refresco automático e instantáneo de archivos nuevos o modificados",
                    titleEN: "Instant automatic refresh for new or updated files",
                    summaryES: "Si agregás, descargás o modificás archivos en la carpeta que estás viendo (como Descargas) desde Finder, el navegador u otra app, la lista ahora se actualiza al instante sin tener que salir y volver.",
                    summaryEN: "When you add, download, or update files in the folder you are viewing (such as Downloads) from Finder, your browser, or another app, the file list now updates right away without needing to navigate away and back."
                ),
                ReleaseNoteItem(
                    id: "cmd-z-undo-redo",
                    icon: "arrow.uturn.backward.circle",
                    titleES: "Deshacer y Rehacer acciones con ⌘Z y ⇧⌘Z",
                    titleEN: "Undo & Redo file actions with ⌘Z and ⇧⌘Z",
                    summaryES: "Presioná ⌘Z (o usá Edición → Deshacer) para revertir acciones como enviar archivos a la Papelera, mover, pegar, copiar, renombrar, crear carpetas/archivos o descomprimir .zip, y ⇧⌘Z para rehacerlas.",
                    summaryEN: "Press ⌘Z (or use Edit → Undo) to undo actions like moving files to Trash, moving, pasting, copying, renaming, creating folders/files, or unzipping archives, and ⇧⌘Z to redo them."
                ),
                ReleaseNoteItem(
                    id: "fast-large-folder-loading",
                    icon: "bolt.fill",
                    titleES: "Carga mucho más rápida en carpetas con miles de archivos",
                    titleEN: "Much faster loading for folders with thousands of files",
                    summaryES: "Las carpetas grandes ahora abren casi al instante guardando un índice temporal oculto dentro de cada carpeta y ordenando en segundo plano. Además, si una carpeta demora un poco en leerse, se muestra un aviso de carga en el centro.",
                    summaryEN: "Large folders now open almost instantly by saving a hidden temporary index inside each folder and sorting in the background. When a folder takes a bit longer to read, a clean centered loading indicator appears."
                ),
                ReleaseNoteItem(
                    id: "about-release-notes",
                    icon: "sparkles.rectangle.stack",
                    titleES: "Historial de novedades en «Acerca de MacFileExplorer»",
                    titleEN: "Release Notes inside “About MacFileExplorer”",
                    summaryES: "Ahora podés consultar aquí todas las funciones y mejoras agregadas desde la creación de la app, explicadas de forma simple.",
                    summaryEN: "You can now browse every feature and improvement added since the app launched, written in plain, everyday language."
                ),
                ReleaseNoteItem(
                    id: "sidebar-double-click-expand",
                    icon: "arrow.up.left.and.arrow.down.right",
                    titleES: "Doble clic para desplegar carpetas en el panel izquierdo",
                    titleEN: "Double-click folders in the sidebar to expand",
                    summaryES: "Al hacer doble clic sobre una carpeta de la barra lateral izquierda se expanden o contraen sus subcarpetas, igual que al tocar la flechita.",
                    summaryEN: "Double-clicking any folder in the left sidebar expands or collapses its subfolders, just like clicking its chevron arrow."
                ),
                ReleaseNoteItem(
                    id: "configurable-new-button",
                    icon: "plus.square",
                    titleES: "Botón «Nuevo» opcional desde el menú Ver",
                    titleEN: "Toggleable “New” button from the View menu",
                    summaryES: "Desde la barra de menú superior (Ver / View) podés elegir si querés mostrar u ocultar el botón «Nuevo» para dejar la barra más limpia.",
                    summaryEN: "From the top View menu you can show or hide the toolbar “New” button to keep the command bar as minimal as you prefer."
                ),
                ReleaseNoteItem(
                    id: "bookmarks-bar-polish",
                    icon: "bookmark.circle",
                    titleES: "Barra de marcadores más limpia y alineada a la derecha",
                    titleEN: "Cleaner, right-aligned Bookmarks Bar",
                    summaryES: "Los accesos directos web se alinean a la derecha sin fondo gris recargado y con una línea divisoria sutil al inicio de la barra.",
                    summaryEN: "Web bookmark links now align neatly to the right without a heavy gray background pill, separated by a subtle starting divider."
                ),
                ReleaseNoteItem(
                    id: "shift-arrow-selection",
                    icon: "keyboard",
                    titleES: "Selección en rango con Shift + Flechas",
                    titleEN: "Range selection with Shift + Arrow keys",
                    summaryES: "Con un archivo seleccionado, mantené presionado Shift y usá las flechas del teclado para ir sumando o ajustando archivos a la selección sin usar el mouse.",
                    summaryEN: "Hold Shift and press the Up/Down (or Left/Right in icon view) arrow keys to extend or adjust your file selection without touching the mouse."
                ),
                ReleaseNoteItem(
                    id: "quick-access-drag-pin",
                    icon: "star.circle",
                    titleES: "Arrastrá carpetas a Acceso rápido y administralas desde Ver",
                    titleEN: "Drag folders into Quick Access & toggle built-in folders",
                    summaryES: "Podés activar o desactivar las carpetas predeterminadas del Mac desde Ver → Carpetas en Acceso rápido, y arrastrar cualquier carpeta propia a la sección izquierda para fijarla como favorita (o quitarla con clic derecho → «Sacar de Favoritos»).",
                    summaryEN: "Show or hide default Mac folders from View → Quick Access Folders, and drag any folder from the file list into Quick Access to pin it as a favorite (remove it anytime via right-click → “Remove from Favorites”)."
                )
            ]
        ),
        ReleaseNoteSection(
            id: "v1.0-google-dragdrop-productivity",
            versionLabelES: "Actualización — Google en Pestañas, Arrastre y Productividad",
            versionLabelEN: "Update — Integrated Google Tabs, Drag & Drop & Productivity",
            dateLabelES: "11 nov 2026",
            dateLabelEN: "Nov 11, 2026",
            items: [
                ReleaseNoteItem(
                    id: "google-accounts-tabs",
                    icon: "globe",
                    titleES: "Cuentas de Google (Gmail, Drive y Calendar) en pestañas separadas",
                    titleEN: "Google accounts (Gmail, Drive & Calendar) in isolated tabs",
                    summaryES: "Sumá una o más cuentas de Google con sesiones aisladas (sin mezclarse entre sí), foto de perfil real, zoom web (⌘+ / ⌘- / ⌘0) y apertura automática en Chrome para enlaces externos.",
                    summaryEN: "Sign in to one or more Google accounts with fully isolated sessions, real profile avatars, page zoom (⌘+ / ⌘- / ⌘0), and automatic opening in Chrome when clicking external links."
                ),
                ReleaseNoteItem(
                    id: "chrome-bookmarks-favicons",
                    icon: "link.circle",
                    titleES: "Favoritos web con ícono real y apertura configurable",
                    titleEN: "Web bookmarks with real site favicons",
                    summaryES: "Guardá accesos directos a tus páginas favoritas con el ícono real de cada sitio y elegí desde el menú Ver si se abren en Chrome o dentro de MacFileExplorer.",
                    summaryEN: "Save quick web shortcuts showing each website’s real favicon, and choose from the View menu whether links open in Chrome or inside MacFileExplorer."
                ),
                ReleaseNoteItem(
                    id: "drag-and-drop-files",
                    icon: "hand.draw",
                    titleES: "Arrastrar y soltar archivos dentro y fuera de la app",
                    titleEN: "Drag & drop files inside and outside the app",
                    summaryES: "Arrastrá archivos o carpetas desde MacFileExplorer hacia Finder u otras aplicaciones, o movelos directamente entre carpetas y el panel lateral dentro del explorador.",
                    summaryEN: "Drag files or folders from MacFileExplorer into Finder or other apps, or drop them between folders and the sidebar right inside the explorer."
                ),
                ReleaseNoteItem(
                    id: "date-modified-mix",
                    icon: "clock.arrow.circlepath",
                    titleES: "Ordenamiento «Date Modified mix»",
                    titleEN: "“Date Modified mix” sorting option",
                    summaryES: "Permite ordenar por fecha de modificación mezclando archivos y carpetas juntos en orden cronológico, además del modo tradicional que agrupa las carpetas arriba.",
                    summaryEN: "Sort items by modification date interleaving files and folders together chronologically, alongside the classic folders-first mode."
                ),
                ReleaseNoteItem(
                    id: "shift-delete-and-sidebar-delete",
                    icon: "trash.slash",
                    titleES: "Borrado directo (Shift + Delete) y gestión desde el árbol lateral",
                    titleEN: "Permanent delete (Shift + Delete) & sidebar folder deletion",
                    summaryES: "Usá Shift + Delete para eliminar elementos sin pasar por la Papelera (confirmando rápido con Enter), y borrá carpetas directo desde el panel izquierdo con actualización inmediata del árbol.",
                    summaryEN: "Press Shift + Delete to permanently remove items bypassing Trash (confirming with Enter), and delete folders directly from the left tree with instant sidebar refresh."
                ),
                ReleaseNoteItem(
                    id: "zip-extract-and-rename",
                    icon: "doc.zipper",
                    titleES: "Descomprimir archivos .zip y renombrado inteligente",
                    titleEN: "Unzip .zip archives & smart file renaming",
                    summaryES: "Extraé archivos .zip desde el menú contextual y renombrá archivos sin que se seleccione la extensión por accidente.",
                    summaryEN: "Extract .zip files right from the right-click menu, and rename files with only the base name highlighted so extensions stay safe."
                ),
                ReleaseNoteItem(
                    id: "ui-polish-hierarchy",
                    icon: "sidebar.left",
                    titleES: "Mejoras visuales en títulos, pestañas y menús",
                    titleEN: "Visual polish across sidebar hierarchy, tabs & menus",
                    summaryES: "Títulos más claros en el panel izquierdo con sus elementos indentados, flechitas solo donde hay subcarpetas, íconos alineados en pestañas y tildes ordenadas en menús.",
                    summaryEN: "Clearer sidebar section headers with indented items, disclosure arrows shown only on folders with subfolders, aligned tab icons, and tidy menu checkmarks."
                )
            ]
        ),
        ReleaseNoteSection(
            id: "v1.0-initial-foundation",
            versionLabelES: "Versión 1.0 — Lanzamiento y Funciones Principales",
            versionLabelEN: "Version 1.0 — Initial Launch & Core Features",
            dateLabelES: "10 nov 2026",
            dateLabelEN: "Nov 10, 2026",
            items: [
                ReleaseNoteItem(
                    id: "win11-explorer-base",
                    icon: "macwindow.on.rectangle",
                    titleES: "Explorador estilo Windows 11 con estética nativa de macOS",
                    titleEN: "Windows 11-style Explorer with native macOS look",
                    summaryES: "Navegación con Atrás/Adelante/Subir, barra de ruta clicable y editable (⌘L), buscador rápido, barra de comandos, vistas de Detalles e Iconos Grandes y barra de estado con totales.",
                    summaryEN: "Back/Forward/Up navigation, clickable & editable path bar (⌘L), instant folder search, command bar, Details & Large Icons views, and a status bar with item counts and total size."
                ),
                ReleaseNoteItem(
                    id: "cut-paste-workflow",
                    icon: "scissors",
                    titleES: "Cortar (⌘X), Mover (⌘V) y atajos clásicos",
                    titleEN: "Real Cut (⌘X), Move (⌘V) & classic shortcuts",
                    summaryES: "Portapapeles estilo Windows para mover archivos sin duplicarlos, selección múltiple con mouse y atajos rápidos como F2/Enter para renombrar y Delete para enviar a la Papelera.",
                    summaryEN: "Windows-style Cut & Paste to move files cleanly, mouse multi-selection, and familiar shortcuts like F2/Enter to rename and Delete to move to Trash."
                ),
                ReleaseNoteItem(
                    id: "quicklook-preview",
                    icon: "eye",
                    titleES: "Vista previa rápida con Espacio y «Abrir en Vista Previa»",
                    titleEN: "Spacebar Quick Look & “Open in Preview”",
                    summaryES: "Presioná la barra espaciadora sobre cualquier archivo para previsualizarlo al instante sin salir de la app, con acceso directo a Vista Previa de macOS.",
                    summaryEN: "Press Spacebar on any file to preview it immediately without leaving the explorer, including a button to open it in macOS Preview."
                ),
                ReleaseNoteItem(
                    id: "thumbnails-and-session",
                    icon: "photo.on.rectangle.angled",
                    titleES: "Miniaturas en caché, sesión persistente e ícono claro/oscuro",
                    titleEN: "Cached image thumbnails, saved session & Light/Dark app icon",
                    summaryES: "Las imágenes cargan rápido gracias a miniaturas en caché, la app recuerda tu última carpeta y árbol expandido al volver a abrirla, e incluye ícono transparente adaptable.",
                    summaryEN: "Images display fast cached thumbnails, the app restores your last open folder and expanded sidebar tree on relaunch, and the transparent app icon adapts to Light and Dark mode."
                ),
                ReleaseNoteItem(
                    id: "properties-openwith-language",
                    icon: "info.circle",
                    titleES: "Propiedades, «Abrir con…», cambio de idioma y permisos estables",
                    titleEN: "Properties window, “Open with…”, live ES/EN language & stable permissions",
                    summaryES: "Consultá los detalles completos de archivos y carpetas, elegí con qué programa abrirlos, cambiá entre Español e Inglés desde el menú principal y conservá tus permisos entre actualizaciones.",
                    summaryEN: "Inspect full file or folder properties, pick which app opens a file, switch between English and Spanish from the menu bar, and keep macOS folder permissions across rebuilds."
                )
            ]
        )
    ]
}
