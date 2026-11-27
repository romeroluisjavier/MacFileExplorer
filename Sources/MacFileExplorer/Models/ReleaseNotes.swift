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
    public let semanticVersion: String
    public let versionLabelES: String
    public let versionLabelEN: String
    public let dateLabelES: String
    public let dateLabelEN: String
    public let items: [ReleaseNoteItem]

    public init(
        id: String,
        semanticVersion: String = "0.0.0",
        versionLabelES: String,
        versionLabelEN: String,
        dateLabelES: String,
        dateLabelEN: String,
        items: [ReleaseNoteItem]
    ) {
        self.id = id
        self.semanticVersion = semanticVersion
        self.versionLabelES = versionLabelES
        self.versionLabelEN = versionLabelEN
        self.dateLabelES = dateLabelES
        self.dateLabelEN = dateLabelEN
        self.items = items
    }

    /// Indica si esta sección corresponde a una versión estrictamente más reciente que `previousVersion`.
    public func isNewer(than previousVersion: String) -> Bool {
        AppVersionComparator.isNewer(semanticVersion, than: previousVersion)
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
    /// Devuelve todas las secciones con novedades posteriores a `previousVersion`.
    public static func sectionsNewer(than previousVersion: String) -> [ReleaseNoteSection] {
        sections.filter { $0.isNewer(than: previousVersion) }
    }

    /// Cantidad total de novedades individuales incorporadas después de `previousVersion`.
    public static func newItemsCount(since previousVersion: String) -> Int {
        sectionsNewer(than: previousVersion).reduce(0) { $0 + $1.items.count }
    }

    public static let sections: [ReleaseNoteSection] = [
        ReleaseNoteSection(
            id: "v2.7.0-setup-wizard-tour-notch-customization-bug-reporter",
            semanticVersion: "2.7.0",
            versionLabelES: "Versión 2.7.0 — Asistente de instalación, Tour interactivo, Novedades al actualizar, 10 ajustes nuevos del Notch y Reporte de errores",
            versionLabelEN: "Version 2.7.0 — Setup Wizard, Interactive Tour, Post-Upgrade What's New, 10 New Notch Settings & Built-In Bug Reporter",
            dateLabelES: "27 nov 2026",
            dateLabelEN: "Nov 27, 2026",
            items: [
                ReleaseNoteItem(
                    id: "notch-10-new-customization-settings",
                    icon: "paintpalette.fill",
                    titleES: "10 nuevas opciones de personalización para el reproductor «Notch»",
                    titleEN: "10 New Customization Options for the «Notch» Music Player",
                    summaryES: "En Configuración de Notch → Apariencia y Animaciones (con vista previa en vivo al instante) ahora podés elegir el color de acento (automático de la carátula, color de tu app musical o un color propio), el tipo de animación (Elástico, Fluido, Preciso o Suave), la velocidad de las animaciones (de 0.5× a 2.0×), mostrar u ocultar la tapa del álbum, el nombre del álbum y la insignia de la app, cambiar el estilo del visualizador musical (Barras, Onda, Puntos o Pulso), regular la intensidad del brillo ambiental y la opacidad del fondo (vidrio translúcido o negro puro) y ajustar el tamaño de texto de las letras sincronizadas.",
                    summaryEN: "In Notch Settings → Appearance & Animations (with live instant preview) you can now customize the accent color (auto from album art, music app brand color, or your own custom color), animation style (Bouncy, Fluid, Snappy, or Gentle), animation speed (0.5× to 2.0×), toggle album cover art, album name, and app corner badge, switch between 4 animated visualizer styles (Bars, Wave, Dots, or Pulse), tune ambient glow intensity and background opacity (frosted glass to pure OLED black), and choose the font size for synced karaoke lyrics."
                ),
                ReleaseNoteItem(
                    id: "notch-interactive-youtube-music-progress-seek",
                    icon: "slider.horizontal.below.rectangle",
                    titleES: "Barra de avance clicable en el «Notch» para adelantar o retroceder canciones (incluyendo YouTube Music)",
                    titleEN: "Clickable Progress Bar Seeking in «Notch» (Including YouTube Music)",
                    summaryES: "Ahora podés hacer clic o arrastrar directamente sobre la barra de avance del reproductor Notch para saltar al instante a cualquier momento de la canción que estés escuchando en YouTube Music, Spotify o Apple Music, sin abrir la ventana del reproductor.",
                    summaryEN: "Click or drag directly along the Notch progress bar to jump instantly to any part of the current song in YouTube Music, Spotify, or Apple Music without switching windows."
                ),
                ReleaseNoteItem(
                    id: "onboarding-setup-wizard-guided-tour-and-upgrade-highlights",
                    icon: "sparkles",
                    titleES: "Nuevo asistente de instalación inicial, tour interactivo y novedades destacadas al actualizar",
                    titleEN: "New First-Install Setup Wizard, Interactive Guided Tour & Post-Upgrade What's New Highlights",
                    summaryES: "Al instalar MacFileExplorer por primera vez ahora te guía un asistente claro en 6 pasos para elegir tu idioma, ícono y qué módulos opcionales querés activar (Barra de tareas, AltTab, reproductor Notch, Portapapeles, acceso en la barra superior y Ver Escritorio con ⌘D), con un botón «Instalar por defecto» para empezar al instante en un clic. Luego podés recorrer un tour interactivo con globitos señalando cada zona de la ventana —que podés suspender o cerrar en cualquier momento con un clic o presionando Esc— y volver a abrir ambos cuando quieras desde el menú Ayuda. Además, cada vez que actualices a una nueva versión, la app abrirá automáticamente las Notas de la versión resaltando exactamente qué funciones se agregaron desde la versión que tenías instalada.",
                    summaryEN: "Installing MacFileExplorer for the first time now greets you with a friendly 6-step setup wizard to choose your language, app icon, and which optional modules you want enabled (Taskbar, AltTab, Notch music player, Clipboard History, menu bar tray icon, and View Desktop with ⌘D), plus an «Install by Default» button to start immediately in one click. Afterwards, an interactive guided tour highlights each area of the window with floating callout bubbles that you can suspend or close at any moment (or replay anytime from the Help menu). Plus, whenever you update to a newer version, MacFileExplorer automatically opens Release Notes highlighting every feature added since the version you previously had installed."
                ),
                ReleaseNoteItem(
                    id: "about-bug-report-and-monthly-log-diagnostics",
                    icon: "ladybug.fill",
                    titleES: "Reportar errores e ideas directo desde «Acerca de» + revisión mensual del log interno",
                    titleEN: "Report Bugs & Ideas Right Inside «About» + Monthly Internal Error Check",
                    summaryES: "La ventana «Acerca de MacFileExplorer» ahora incluye una pestaña simple y sin desplazamiento «Reportar error / Idea» (accesible también desde Ayuda → Reportar un error o sugerencia…) con botón «Enviar reporte» siempre visible para contarnos cualquier problema o sugerencia sin tecnicismos. Además, una vez al mes junto a la comprobación de actualizaciones, la app revisa si aparecieron errores nuevos en su registro interno (ocultando siempre tu usuario, nombres de archivos y datos personales) y te avisa para revisarlos y enviarlos en un clic.",
                    summaryEN: "The «About MacFileExplorer» window now features a clean, scroll-free «Report Bug / Idea» tab (also available via Help → Report a Bug or Suggestion…) with an always-visible «Send Report» button so you can share issues or ideas in plain words. Plus, during the monthly update check-in, the app scans its internal error log for new issues (automatically hiding your username, filenames, and personal info) and offers a 1-click option to review and send them."
                )
            ]
        ),
        ReleaseNoteSection(
            id: "v2.6.0-notch-player-taskbar-smart-layout-shortcuts-tools",
            semanticVersion: "2.6.0",
            versionLabelES: "Versión 2.6.0 — Reproductor «Notch», Barra inteligente, Atajos y «Tools» (⌘D)",
            versionLabelEN: "Version 2.6.0 — «Notch» Player, Smart Taskbar, All Shortcuts & «Tools» (⌘D)",
            dateLabelES: "26 nov 2026",
            dateLabelEN: "Nov 26, 2026",
            items: [
                ReleaseNoteItem(
                    id: "notch-music-player-now-playing",
                    icon: "waveform",
                    titleES: "Nuevo reproductor de música «Notch» con animaciones fluidas, YouTube Music, Spotify y letras sincronizadas",
                    titleEN: "New «Notch» Music Player with Fluid Animations, YouTube Music, Spotify & Synced Lyrics",
                    summaryES: "Se incorporó un nuevo menú «Notch» en la barra superior para transformar el Notch de tu MacBook (o la parte superior de cualquier monitor) en un reproductor de música interactivo y elegante sin robarte el foco. Mientras suena música en YouTube Music, Spotify, Apple Music o el navegador, verás la carátula exacta y un ecualizador animado a los costados del Notch, con breves avisos al cambiar de canción. Al pasar el cursor o hacer clic se despliega suavemente con brillo ambiental del color de la portada, controles para pausar o cambiar tema, barra de avance clicable y arrastrable para saltar al instante a cualquier minuto de la canción (también en YouTube Music), cambio rápido de parlantes o auriculares y letras sincronizadas en vivo. Cuando no suena música ofrece accesos directos para volver a abrir tu último reproductor (como YouTube Music), la cruz «✕» cierra y oculta el Notch por completo, y podés personalizar tamaño, estilo de carátula, pantallas y comportamiento desde «Configuración de Notch…».",
                    summaryEN: "Added a new «Notch» menu in the top bar that turns your MacBook's notch (or the top center of any display) into a sleek, interactive music player without stealing focus from your work. While listening on YouTube Music, Spotify, Apple Music, or your browser, exact album artwork and an animated equalizer sit cleanly beside the notch with brief track-change previews. Hover or click to smoothly expand with ambient artwork glow, playback controls, a clickable and draggable progress bar to jump instantly to any part of the song (including YouTube Music), a quick audio output switcher, and live time-synced lyrics. When nothing is playing it offers quick buttons to reopen your last music app (such as YouTube Music), the «✕» button completely closes and hides the Notch, and you can customize size, artwork style, displays, and behavior in «Notch Settings…»."
                ),
                ReleaseNoteItem(
                    id: "taskbar-overflow-shrink-to-fit-vs-scroll",
                    icon: "arrow.right.and.line.vertical.and.arrow.left",
                    titleES: "Barra de tareas con ajuste automático de ancho sin scroll (configurable)",
                    titleEN: "Auto-Shrinking Taskbar Buttons Without Horizontal Scroll (Configurable)",
                    summaryES: "Ahora podés elegir desde el menú Barra de tareas («Ajustar ancho sin scroll horizontal») o desde Configuración de la Barra de tareas cómo comportarse cuando abrís muchas ventanas: el modo automático (por defecto) reduce suavemente el ancho de los botones —y compacta a solo íconos si hay muchísimas— para que todas las apps entren completas a la vista sin cortes ni scroll, o podés volver al scroll horizontal con ancho mínimo fijo cuando prefieras.",
                    summaryEN: "Choose in the Taskbar menu («Auto-Shrink Buttons (No Scroll)») or Taskbar Settings how the bar handles many open windows: the new default mode smoothly shrinks button widths (and automatically collapses to icons-only when very crowded) so every app stays fully visible without clipping or scrolling, or switch back to fixed minimum width with horizontal scroll anytime."
                ),
                ReleaseNoteItem(
                    id: "taskbar-pinned-apps-first-in-pinned-order",
                    icon: "pin.circle.fill",
                    titleES: "Ventanas de apps fijadas primero en la Barra de tareas (con indicador sutil y aviso al arrastrar)",
                    titleEN: "Pinned Apps' Open Windows First in the Taskbar (with Subtle Indicator & Drag Hint)",
                    summaryES: "Ahora podés activar desde el menú Barra de tareas («Apps fijadas primero en la barra (en su mismo orden)») o desde Configuración que las ventanas abiertas de tus apps fijadas aparezcan primero respetando exactamente el orden en que están fijadas (identificadas con un pequeño ícono de pin sutil y un divisor fino antes de las apps no fijadas). Si reordenás un ícono fijado a la izquierda, las ventanas se reacomodan al instante; y si intentás arrastrar una ventana con orden fijo hacia otra app, aparece un breve aviso flotante explicando el motivo con opción de desactivarlo en un clic.",
                    summaryEN: "Toggle «Pinned Apps' Windows First (in Pinned Order)» from the Taskbar menu or Settings to show open windows of your pinned apps first in their exact pinned order, subtly marked with a tiny pin indicator and a slim divider before unpinned apps. Reordering pinned icons on the left updates open windows immediately, and trying to drag a pinned-order window across another app displays a clear floating hint explaining why with a 1-click option to disable the lock."
                ),
                ReleaseNoteItem(
                    id: "taskbar-instant-overlap-resize-on-maximize",
                    icon: "arrow.up.left.and.arrow.down.right",
                    titleES: "Ajuste instantáneo al maximizar ventanas (como Chrome) para no quedar detrás de la Barra de tareas",
                    titleEN: "Instant Window Maximize Adjustment Above the Taskbar (Chrome & All Apps)",
                    summaryES: "Se optimizó por completo el ajuste automático de ventanas superpuestas con la Barra de tareas: al hacer doble clic en la barra de título de Chrome o cualquier otra app para maximizarla (o al soltar un arrastre), la ventana se ajusta casi al instante sobre la barra sin la demora previa de 1 a 2 segundos.",
                    summaryEN: "Significantly accelerated automatic window overlap adjustment above the Taskbar: double-clicking the title bar of Chrome or any other app to maximize (or releasing a window resize/drag) now snaps the window cleanly above the Taskbar almost instantaneously instead of waiting 1–2 seconds."
                ),
                ReleaseNoteItem(
                    id: "taskbar-auto-hide-windowless-document-apps",
                    icon: "eye.slash.fill",
                    titleES: "Barra de tareas sin botones fantasma de Preview y apps de documentos sin ventanas",
                    titleEN: "No More Ghost Buttons in Taskbar for Windowless Preview & Document Apps",
                    summaryES: "Apps de documentos de macOS como Preview (Vista Previa), QuickTime Player, TextEdit, Pages, Numbers y Keynote ahora se ocultan automáticamente de la Barra de tareas apenas cerrás su última ventana, y vuelven a mostrarse normalmente cada vez que abrís un archivo en ellas. Además podés sumar o quitar cualquier otra app con clic derecho («Ocultar cuando no tenga ventanas») o desde Configuración de la Barra de tareas, y hacer clic medio sobre cualquier app sin ventanas para cerrarla directamente (configurable).",
                    summaryEN: "Document-centric macOS apps such as Preview, QuickTime Player, TextEdit, Pages, Numbers, and Keynote now disappear automatically from the Taskbar as soon as their last window closes, while reappearing normally whenever you open a file. You can also add or remove any other app via right-click («Hide When Windowless») or Taskbar Settings, and middle-click any remaining windowless app button to quit it right away (respecting your middle-click setting)."
                ),
                ReleaseNoteItem(
                    id: "file-shortcuts-manager-and-tools-view-desktop",
                    icon: "keyboard",
                    titleES: "Administrador central de atajos y submenú «Herramientas» con «View Desktop Shortcut» (⌘D)",
                    titleEN: "Central Keyboard Shortcuts Manager & «Tools» Submenu with «View Desktop Shortcut» (⌘D)",
                    summaryES: "En el menú Archivo ahora encontrás «Administrar todos los atajos de teclado…» para ver, buscar, activar, personalizar o restablecer todos los atajos de MacFileExplorer (Herramientas, Explorador, Portapapeles Maccy y AltTab) desde una sola ventana con detección automática de conflictos. Además se incorporó el nuevo submenú «Herramientas (Tools)» preparado para futuras utilidades: su primera configuración es «View Desktop Shortcut», que viene activado por defecto con ⌘D para mostrar y poner en foco el Escritorio de tu Mac desde cualquier app (y volver a tus ventanas al pulsarlo de nuevo), con presets rápidos (⌘D, ⌥D, ⌃⌘D, ⇧⌘D, F11) y elección entre modo nativo de macOS o estilo Windows Win+D.",
                    summaryEN: "The File menu now includes «Manage All Keyboard Shortcuts…» so you can search, toggle, customize, and reset every shortcut across MacFileExplorer (Tools, File Explorer, Maccy Clipboard, and AltTab) from one central window with live conflict detection. A new extensible «Tools» submenu was also added under File: its first setting is «View Desktop Shortcut», enabled by default with ⌘D to reveal and focus your Mac Desktop from any app (and press again to return to your windows), complete with quick presets (⌘D, ⌥D, ⌃⌘D, ⇧⌘D, F11) and choice between native macOS Show Desktop or Windows Win+D window hiding."
                ),
                ReleaseNoteItem(
                    id: "unified-feature-settings-naming",
                    icon: "slider.horizontal.3",
                    titleES: "Nombres de configuración unificados por módulo en todos los menús",
                    titleEN: "Unified Settings Naming Across All Feature Menus",
                    summaryES: "Se unificaron los nombres de acceso a las pantallas de configuración en todos los menús y ventanas para mantener coherencia entre funciones: «Clipboard Settings…» / «Configuración del Portapapeles…», «Taskbar Settings…», «AltTab Settings…», «Tools Settings…», «Notch Settings…» y «Send to Drive Settings…».",
                    summaryEN: "Unified settings menu items and window titles across every feature for a consistent experience: «Clipboard Settings…», «Taskbar Settings…», «AltTab Settings…», «Tools Settings…», «Notch Settings…», and «Send to Drive Settings…»."
                ),
                ReleaseNoteItem(
                    id: "help-macos-permissions-and-privacy-guide",
                    icon: "lock.shield.fill",
                    titleES: "Guía transparente de Permisos de macOS y Privacidad en la Ayuda",
                    titleEN: "Transparent macOS Permissions & Privacy Guide in Help",
                    summaryES: "La ventana de Ayuda de MacFileExplorer incorpora una nueva sección «Permisos de macOS» (accesible también desde Ayuda → Permisos de macOS y Privacidad…) donde se explica con claridad para qué función puntual se solicita cada permiso (Archivos y carpetas, Accesibilidad, Grabación de pantalla y Automatización), por qué solo se pide lo mínimo y necesario, qué funciones trabajan sin permisos especiales, qué permisos nunca se piden y el estado actual con accesos directos a Ajustes del Sistema.",
                    summaryEN: "MacFileExplorer Help now includes a dedicated «macOS Permissions» section (also reachable via Help → macOS Permissions & Privacy…) that clearly explains which exact feature needs each permission (Files & Folders, Accessibility, Screen Recording, and Automation), why only the strict minimum is requested, which features require zero special permissions, what permissions are never requested, and live status indicators with direct links to macOS System Settings."
                )
            ]
        ),
        ReleaseNoteSection(
            id: "v2.5.1-kofi-monthly-checkin-start-menu-focus-mono-dark",
            semanticVersion: "2.5.1",
            versionLabelES: "Versión 2.5.1 — Menú Inicio sin robar foco, aviso mensual con actualizaciones + Ko-fi, «Acerca de» renovado e ícono Mono Oscuro",
            versionLabelEN: "Version 2.5.1 — Non-Activating Start Menu, Monthly Update Check-In + Optional Ko-fi Tip, Wider About Window & Dark Mono Default Icon",
            dateLabelES: "26 nov 2026",
            dateLabelEN: "Nov 26, 2026",
            items: [
                ReleaseNoteItem(
                    id: "start-menu-nonactivating-keeps-current-app-focus",
                    icon: "macwindow.badge.plus",
                    titleES: "El botón Inicio ya no trae al frente la ventana de MacFileExplorer",
                    titleEN: "Start Button No Longer Brings MacFileExplorer Window to the Front",
                    summaryES: "Al abrir el Menú Inicio desde la Barra de tareas mientras trabajás en otra aplicación (como Chrome, Slack o tu editor), el Menú Inicio se despliega suavemente encima con el buscador listo para escribir pero manteniendo en primer plano la aplicación donde estabas, sin traer al frente las ventanas de carpetas de MacFileExplorer.",
                    summaryEN: "Clicking the Start button on the Taskbar while working in another app (such as Chrome, Slack, or your editor) now opens the Start Menu smoothly above it with instant search typing while keeping your current app in the foreground, without raising MacFileExplorer folder windows."
                ),
                ReleaseNoteItem(
                    id: "kofi-optional-tip-and-monthly-update-checkin",
                    icon: "heart.circle.fill",
                    titleES: "Propina opcional en Ko-fi y aviso mensual discreto con comprobación de actualizaciones",
                    titleEN: "Optional Ko-fi Tip Support & Non-Invasive Monthly Update Check-In",
                    summaryES: "MacFileExplorer sigue siendo 100% gratuito y sin anuncios. Se sumó una tarjeta con botón de Ko-fi y código QR grande de fácil escaneo (ampliable a 240 px en un clic) tanto en «Acerca de MacFileExplorer» (ahora con ventana más ancha, redimensionable y encabezado horizontal mucho más cómodo de leer) como en «Historial de releases» por si querés dejar una propina voluntaria. Además, el ícono Mono Oscuro pasa a ser el predeterminado de la app y la web, y una vez cada 30 días se muestra un aviso flotante discreto en la esquina inferior derecha que comprueba automáticamente si hay una versión nueva lista para actualizar.",
                    summaryEN: "MacFileExplorer remains 100% free and ad-free. Added an optional Ko-fi tip card with button and a large, easy-to-scan QR code (with 1-click 240 px zoom) in both «About MacFileExplorer» (now wider, resizable, with a spacious horizontal header) and «Release History» in case you want to support development. Dark Mono is now the default app and website icon, and once every 30 days a non-invasive floating corner card automatically checks for new updates right inside the card and can be snoozed or permanently dismissed in one click."
                )
            ]
        ),
        ReleaseNoteSection(
            id: "v2.5.0-office-quicklook-media-actions-taskbar-upgrades",
            semanticVersion: "2.5.0",
            versionLabelES: "Versión 2.5.0 — Editor Office y CSV con selección por arrastre, Vista Rápida libre con Acciones rápidas y Copiar, Barra de tareas avanzada e ícono rojo PDF",
            versionLabelEN: "Version 2.5.0 — Office & CSV Editor with Drag-Select, Free Quick Look with Media Quick Actions & Copy, Advanced Taskbar & Red PDF Icon",
            dateLabelES: "25 nov 2026",
            dateLabelEN: "Nov 25, 2026",
            items: [
                ReleaseNoteItem(
                    id: "quicklook-media-quick-actions-and-copy-bar",
                    icon: "wand.and.stars",
                    titleES: "Acciones rápidas y Copiar directo dentro de la Vista Rápida de imágenes y videos",
                    titleEN: "Quick Actions & Copy Directly Inside Image and Video Previews",
                    summaryES: "Al previsualizar una imagen o un video con Espacio ahora tenés una barra superior con las mismas Acciones rápidas del menú contextual y un botón de Copiar (también con ⌘C). En imágenes podés copiar imagen y archivo en un clic (o elegir solo imagen / solo archivo para pegar directo en chats, documentos o carpetas), eliminar el fondo a PNG transparente, convertir a JPG/PNG, rotar 90° a izquierda/derecha o 180° viendo el resultado al instante, y limpiar metadatos privados. En videos podés copiar el archivo, convertir a MP4, recortar (Trim) con vista previa, eliminar el audio (silenciar) y limpiar metadatos sin salir de la ventana de Vista Rápida.",
                    summaryEN: "When previewing an image or video with Space, you now get a dedicated bar with the exact same Quick Actions from the right-click menu plus a Copy button (and ⌘C shortcut). For images, copy both the image and file in one click (or choose image-only / file-only for chats, documents, or folders), remove the background into a transparent PNG, convert to JPG/PNG, rotate 90° left/right or 180° with instant live refresh, and strip private metadata. For videos, copy the file, convert to MP4, trim with live preview, mute audio, and strip metadata right inside the Quick Look window."
                ),
                ReleaseNoteItem(
                    id: "pdf-distinctive-red-acrobat-style-icon",
                    icon: "doc.richtext.fill",
                    titleES: "Nuevo ícono rojo estilo Acrobat para archivos PDF",
                    titleEN: "New Distinctive Red Acrobat-Style Icon for PDF Files",
                    summaryES: "Los archivos PDF ahora muestran un ícono rojo nítido estilo Acrobat Reader en lugar del ícono azul genérico de Vista Previa de macOS, permitiendo distinguir a simple vista tus documentos PDF de las imágenes PNG/JPG tanto en la lista de archivos como en la barra de Vista Rápida, Propiedades, historial del portapapeles y al arrastrar archivos.",
                    summaryEN: "PDF files now display a crisp, unmistakable red Acrobat-style icon instead of macOS Preview's generic blue icon, making it effortless to tell PDF documents apart from PNG/JPG images at a glance across file lists, the Quick Look header bar, Properties, clipboard history, and file dragging."
                ),
                ReleaseNoteItem(
                    id: "quicklook-free-independent-window-movement",
                    icon: "macwindow.on.rectangle",
                    titleES: "Movimiento libre de la ventana de Vista Rápida fuera de MacFileExplorer y entre monitores",
                    titleEN: "Move Quick Look Preview Freely Outside MacFileExplorer & Across Displays",
                    summaryES: "La ventana de Vista Rápida (Espacio) ahora es completamente independiente de la ventana principal de MacFileExplorer: podés arrastrarla con suavidad desde su barra superior hacia cualquier parte de la pantalla, colocarla al costado del explorador o llevarla a otro monitor sin que se frene ni quede atada a la ventana original, manteniendo todos los atajos (Espacio, Esc y flechas) y recordando su última ubicación.",
                    summaryEN: "The Quick Look preview window (Space) is now fully independent from the main MacFileExplorer window: drag it smoothly by its top bar anywhere on screen, place it side by side next to the explorer, or move it onto another display without getting stuck or tethered to the parent window, while keeping all shortcuts (Space, Esc, and arrow keys) and remembering its last position."
                ),
                ReleaseNoteItem(
                    id: "spreadsheet-mouse-drag-range-selection",
                    icon: "rectangle.dashed",
                    titleES: "Selección de múltiples filas y columnas arrastrando con el mouse en CSV y Excel",
                    titleEN: "Drag-Select Multiple Rows & Columns with the Mouse in CSV & Excel Previews",
                    summaryES: "Dentro de la vista previa y editor de planillas CSV y Excel (.xlsx / .xls) ahora podés hacer clic y arrastrar con el mouse sobre las celdas para seleccionar cualquier bloque rectangular de filas y columnas con desplazamiento automático en los bordes. También podés arrastrar sobre los números de fila (#) para seleccionar varias filas completas o sobre los encabezados de columna (A, B, C…) para seleccionar varias columnas enteras, ver el rango seleccionado (ej. D3:G14) y sus dimensiones junto a Conteo/Suma/Promedio en vivo, copiar directo a Excel o Google Sheets (⌘C) y rellenar el rango pegando un valor (⌘V).",
                    summaryEN: "Inside CSV and Excel (.xlsx / .xls) previews and editors, you can now click and drag with your mouse across cells to select any rectangular block of rows and columns with smooth edge auto-scrolling. You can also drag down row numbers (#) to select multiple entire rows or across column headers (A, B, C…) to select entire columns, see the active range (e.g. D3:G14) and dimensions alongside live Count/Sum/Avg stats, copy cleanly to Excel or Google Sheets (⌘C), and fill the range when pasting a single value (⌘V)."
                ),
                ReleaseNoteItem(
                    id: "taskbar-icons-only-and-compact-minimized-windows",
                    icon: "app.dashed",
                    titleES: "Modo «Solo íconos» y ventanas minimizadas compactas en la Barra de tareas",
                    titleEN: "Icons-Only Mode & Compact Icon-Only Minimized Windows on the Taskbar",
                    summaryES: "Ahora podés configurar fácilmente desde Configuración → Apariencia, el menú superior «Barra de tareas» o con clic derecho directo sobre la barra si querés ver todas las ventanas como «Solo íconos», o bien mantener el título en las ventanas abiertas y compactar únicamente las ventanas minimizadas u ocultas a solo su ícono — ahorrando espacio y dejando más lugar libre para los títulos de las ventanas que estás usando.",
                    summaryEN: "You can now easily choose from Taskbar Settings → Appearance, the top \"Taskbar\" menu, or right-clicking directly on the bar whether to show all windows as \"Icons Only\", or keep titles on open windows while collapsing minimized or hidden windows to icon-only buttons — saving space and giving more room to the windows you are actively using."
                ),
                ReleaseNoteItem(
                    id: "taskbar-drag-hover-spring-load-apps",
                    icon: "hand.point.up.left.and.text",
                    titleES: "Abrir apps desde la Barra de tareas mientras arrastrás un archivo",
                    titleEN: "Open Apps from the Taskbar While Dragging a File",
                    summaryES: "Al arrastrar uno o varios archivos (desde MacFileExplorer, Finder o cualquier otra app), solo tenés que apoyar el puntero sobre una aplicación o ventana de la barra inferior y quedarte quieto 1 segundo: verás una barra de progreso en el botón y automáticamente esa ventana pasará al frente — incluso si estaba minimizada u oculta — sin soltar el archivo, para que puedas subir el cursor y soltarlo directo adentro de esa app.",
                    summaryEN: "While dragging one or more files (from MacFileExplorer, Finder, or any other app), simply hover and hold still for 1 second over any app or window button on the bottom Taskbar: a subtle progress bar fills along the button and that window automatically comes to the front — even if minimized or hidden — without dropping your file, so you can move straight up and drop it right inside that app."
                ),
                ReleaseNoteItem(
                    id: "taskbar-keep-same-app-windows-side-by-side",
                    icon: "rectangle.split.2x1",
                    titleES: "Agrupación lado a lado de ventanas de la misma aplicación en la Barra de tareas",
                    titleEN: "Keep Same-App Windows Side by Side on the Taskbar",
                    summaryES: "Ahora podés activar en un clic (desde clic derecho en la Barra de tareas, el menú superior «Taskbar» o Configuración → General) la opción para mantener siempre juntas y una al lado de la otra todas las ventanas de una misma aplicación — por ejemplo, todas tus ventanas de Chrome. Cada ventana sigue teniendo su propio botón, las ventanas nuevas que abras más tarde se ubican automáticamente al lado de las existentes, las apps web (como Gemini o YouTube Music) se mantienen separadas, y al arrastrar una ventana hacia otra app se mueve todo el grupo junto.",
                    summaryEN: "You can now toggle with one click (from right-clicking the Taskbar, the top \"Taskbar\" menu, or Taskbar Settings → General) keeping all windows of the same application side by side — for example, keeping all your Chrome windows next to each other. Each window keeps its own button, new windows opened later automatically appear right beside existing ones, web apps (like Gemini or YouTube Music) stay distinct, and dragging a window past another app moves its whole group together."
                ),
                ReleaseNoteItem(
                    id: "office-menu-bar-settings-and-send-to-drive",
                    icon: "menubar.dock.rectangle",
                    titleES: "Nuevo menú superior «Office» para configurar edición en Vista Rápida y «Enviar a Drive»",
                    titleEN: "New \"Office\" Menu Bar Menu for Quick Look Editing & \"Send to Drive\" Settings",
                    summaryES: "Se agregó el menú «Office» en la barra superior de MacFileExplorer para centralizar todas las preferencias en un clic: activar o desactivar el modo edición en Vista Rápida, elegir si los documentos abren en Vista original o directo en Editor, habilitar o deshabilitar Word, Excel, PowerPoint y CSV por separado, configurar encabezados fijos y ajuste de texto en planillas, y controlar todo lo relacionado con «Enviar a Drive» (activarlo, elegir cuenta de Google, carpeta destino y si abrir Sheets/Docs/Slides dentro de la app o en Google Chrome externo).",
                    summaryEN: "Added an \"Office\" menu to MacFileExplorer's top menu bar to manage everything in one place: enable or disable editing mode in Quick Look, choose whether documents open in Original View or Quick Editor by default, toggle Word, Excel, PowerPoint, and interactive CSV previews individually, configure frozen CSV headers and text wrapping, and control all \"Send to Drive\" options (enable/disable, default Google account, target folder, and opening Sheets/Docs/Slides inside MacFileExplorer or in external Google Chrome)."
                ),
                ReleaseNoteItem(
                    id: "office-quicklook-libreoffice-editing-toolbar",
                    icon: "doc.richtext.fill",
                    titleES: "Edición rápida tipo Office / LibreOffice al previsualizar Word, Excel (.xlsx y .xls) y PowerPoint",
                    titleEN: "Quick Office / LibreOffice-Style Editing When Previewing Word, Excel (.xlsx & .xls) & PowerPoint",
                    summaryES: "Al tocar Espacio sobre documentos de Word, planillas de Excel (tanto modernas .xlsx como las versiones clásicas .xls, incluyendo exportaciones de bancos y sistemas) o presentaciones de PowerPoint ahora aparece una barra de herramientas práctica para editar sin salir del explorador: cambiar fuente, tamaño, negrita, cursiva, colores, alineación, listas, copiar y pegar texto o celdas, buscar y reemplazar, manejar hojas o diapositivas, editar notas del orador, convertir archivos .xls a .xlsx en un clic y elegir entre Guardar directamente (⌘S) o Guardar copia (⇧⌘S). Además podés alternar en un clic entre el modo Editor y la Vista original.",
                    summaryEN: "Pressing Space on Word documents, Excel spreadsheets (both modern .xlsx and classic .xls files, including bank/ERP table exports), or PowerPoint presentations now opens a handy editing toolbar right inside Quick Look: change font, size, bold, italic, colors, alignment, lists, copy and paste text or cells, find and replace, switch sheets or slides, edit speaker notes, convert .xls files to .xlsx in one click, and choose between Save (⌘S) or Save Copy (⇧⌘S). You can also toggle between Editor mode and Original View in one click."
                ),
                ReleaseNoteItem(
                    id: "interactive-csv-spreadsheet-preview",
                    icon: "tablecells.fill",
                    titleES: "Visor y editor interactivo de archivos CSV y TSV en Vista Rápida",
                    titleEN: "Interactive CSV & TSV Spreadsheet Viewer and Editor in Quick Look",
                    summaryES: "Los archivos CSV y TSV ahora se abren como una planilla interactiva completa sin necesidad de abrir otra aplicación: detecta automáticamente el separador (coma, punto y coma, tabulador o barra), congela los encabezados, permite filtrar filas en vivo, ordenar haciendo clic en cualquier columna, editar celdas con barra de valor, seleccionar rangos para copiar y pegar directo en Excel o Google Sheets, agregar o quitar filas y columnas, ver suma y promedio de lo seleccionado y guardar cambios o guardar una copia.",
                    summaryEN: "CSV and TSV files now open as a full interactive spreadsheet without launching another app: it automatically detects delimiters (comma, semicolon, tab, or pipe), freezes headers, filters rows live, sorts by clicking any column, lets you edit cells with a formula/value bar, copy and paste cell ranges directly to Excel or Google Sheets, insert or delete rows and columns, inspect live sum/average stats on selected numbers, and save changes or save a copy."
                ),
                ReleaseNoteItem(
                    id: "send-to-drive-auto-open-google-editors",
                    icon: "icloud.and.arrow.up.fill",
                    titleES: "«Enviar a Drive» automático con apertura en MacFileExplorer o Google Chrome externo",
                    titleEN: "Automatic \"Send to Drive\" Opening in MacFileExplorer or External Google Chrome",
                    summaryES: "Tanto desde Vista Rápida como haciendo clic derecho sobre cualquier archivo podés elegir «Enviar a Drive»: usa tu cuenta de Gmail conectada para subir automáticamente el archivo a la carpeta de Drive que elijas (incluso al volver a subir archivos varias veces seguidas sin abrir ventanas del Finder) y lo abre directo en Google Sheets, Docs o Slides. Si elegís «Google Chrome externo», el progreso y el aviso de apertura se muestran de forma discreta en la barra de estado inferior del Explorador sin mover la lista de archivos, y el documento se abre directo en una pestaña nueva de Chrome externo con tu misma cuenta.",
                    summaryEN: "From both Quick Look and the right-click menu on any file, choose \"Send to Drive\" to use your connected Gmail account to upload the file straight to your chosen Drive folder (reliably across repeated uploads without ever popping up Finder dialogs) and open it right away in Google Sheets, Docs, or Slides. When \"External Google Chrome\" is selected, upload progress and completion status appear neatly in the bottom status bar of your Explorer without shifting the file list, and the document opens straight in a new external Chrome tab under your same Google account."
                ),
                ReleaseNoteItem(
                    id: "taskbar-top-divider-and-5-visual-settings",
                    icon: "paintbrush.pointed.fill",
                    titleES: "Línea divisoria superior opcional y 5 nuevos ajustes visuales para la Barra de tareas",
                    titleEN: "Optional Top Divider Line & 5 New Visual Appearance Controls for the Taskbar",
                    summaryES: "En Configuración de la barra → Apariencia ahora podés activar o desactivar la línea divisoria que aparece arriba de la barra y personalizar 5 detalles visuales más en tiempo real: elegir entre barra acoplada al borde o Isla flotante redondeada, cambiar el material de fondo (Vidrio esmerilado, Cristal translúcido o Sólido), elegir el estilo de los botones (Tarjeta, Píldora o Sin borde), cambiar la forma del indicador de ventana activa (Píldora, Barra completa, Punto u Oculto) y personalizar su color entre 6 tonos.",
                    summaryEN: "In Taskbar Settings → Appearance you can now show or hide the top divider line above the taskbar and customize 5 additional visual details live: switch between Edge-to-Edge or rounded Floating Island bar style, choose the background material (Frosted Glass, Crystal Translucent, or Solid Matte), pick the window button shape (Card, Pill, or Borderless), customize the active window indicator style (Pill, Full Bar, Dot, or Hidden), and pick from 6 active indicator accent colors."
                )
            ]
        ),
        ReleaseNoteSection(
            id: "v2.0.0-start-menu-animations-instant-navigation-bilingual",
            semanticVersion: "2.0.0",
            versionLabelES: "Versión 2.0.0 — 8 animaciones en el Menú Inicio, carpetas instantáneas y traducción total",
            versionLabelEN: "Version 2.0.0 — 8 Start Menu Animations, Instant Folder Switching & Full Bilingual Polish",
            dateLabelES: "25 nov 2026",
            dateLabelEN: "Nov 25, 2026",
            items: [
                ReleaseNoteItem(
                    id: "start-menu-8-animations-and-instant-delay",
                    icon: "sparkles.rectangle.stack",
                    titleES: "8 animaciones y velocidad ajustable para el Menú Inicio (incluye modo 0 ms instantáneo)",
                    titleEN: "8 Start Menu Opening Animations & Adjustable Speed (Including 0 ms Instant Mode)",
                    summaryES: "Ahora podés elegir entre 8 formas distintas de desplegar el Menú Inicio: 4 estilos clásicos iguales a las vistas previas de la barra (Suave, Desde la barra, Rebote elástico y Giro 3D), 2 estilos profesionales (Cortina ejecutiva y Enfoque Spotlight) y 2 divertidos (Gelatina y Genio giratorio). Además podés regular la duración del despliegue con un control deslizante o elegir 0 ms para que abra al instante sin animación, con vista previa en vivo y botón «Probar ahora» desde Configuración de la barra o haciendo clic derecho sobre el botón Inicio.",
                    summaryEN: "Choose from 8 different ways to open the Start Menu: 4 classic styles matching the taskbar hover previews (Smooth Fade, Rise from Bar, Elastic Pop, and 3D Hinge), 2 professional styles (Executive Curtain and Spotlight Focus), and 2 fun styles (Jelly Bounce and Genie Twirl). You can also fine-tune the opening speed with a slider or pick 0 ms for an instant opening with zero animation — complete with live preview cards and a Test Now button in Taskbar Settings or by right-clicking the Start button."
                ),
                ReleaseNoteItem(
                    id: "instant-cached-folder-switching-no-loading-flash",
                    icon: "bolt.horizontal.circle.fill",
                    titleES: "Cambio instantáneo entre carpetas ya visitadas (sin pantalla de carga)",
                    titleEN: "Instant Switching Between Revisited Folders (Zero Loading Flash)",
                    summaryES: "Al moverte entre carpetas que ya habías abierto, ahora se muestran al instante sin que parpadee el indicador de «Cargando…» ni la pantalla de espera. Además se mejoró el arranque, se aceleró la búsqueda de duplicados y se optimizó el reconocimiento de texto en fotos para responder en milisegundos en cualquier Mac con Apple Silicon (M1, M2, M3 y M4).",
                    summaryEN: "Switching back to folders you already visited now renders instantaneously with zero 'Loading…' spinner flash. Startup, duplicate detection, and image text search were also tuned to respond in milliseconds across all Apple Silicon Macs (M1, M2, M3, and M4)."
                ),
                ReleaseNoteItem(
                    id: "bilingual-menus-context-menus-polish",
                    icon: "globe",
                    titleES: "Traducción completa Español / Inglés en todos los menús, submenús y menús contextuales",
                    titleEN: "Complete Spanish / English Localization Across All Menus, Submenus & Context Menus",
                    summaryES: "Se revisaron y tradujeron todos los menús superiores nuevos (Ícono de la aplicación, Barra de tareas, Animaciones, AltTab y Portapapeles), los menús contextuales (Abrir en Vista Previa, Acciones rápidas y opciones de resolución), los mensajes de error de archivos y los títulos de ventanas abiertas para que cambien en vivo entre Español e Inglés.",
                    summaryEN: "Audited and translated all new top-bar menus and submenus (App Icon, Taskbar, Animations, AltTab, and Clipboard), context menus (Open in Preview, Quick Actions, and resolution options), file operation error messages, and open window titles so everything updates live between Spanish and English."
                ),
                ReleaseNoteItem(
                    id: "fix-taskbar-notification-badge-animations",
                    icon: "bell.badge.fill",
                    titleES: "Corrección en las animaciones de notificaciones de la barra de tareas",
                    titleEN: "Fixed Taskbar Notification Badge Animations",
                    summaryES: "Se corrigió un problema que hacía que los globos rojos de notificaciones (como Slack, Mail o WhatsApp) aparecieran fijos sin reproducir su animación elegida. Ahora los 6 estilos (Salto, Campana, Latido, Destello, Onda expansiva y Bamboleo) vuelven a animarse con fluidez en las tres frecuencias (Periódica, Continua y Solo al llegar) manteniendo 0% de CPU en reposo.",
                    summaryEN: "Fixed an issue where red notification badges (such as Slack, Mail, or WhatsApp) appeared static instead of playing their selected animation. All 6 animation styles (Bounce, Bell Shake, Heartbeat, Glow Flash, Ripple Wave, and Swing Float) now animate smoothly across all three cadences (Periodic, Continuous, and Once on arrival) while keeping idle CPU usage at 0%."
                ),
                ReleaseNoteItem(
                    id: "start-button-brain-icon-names",
                    icon: "brain.head.profile",
                    titleES: "Íconos Brain simplificados para el botón Inicio",
                    titleEN: "Simplified Brain Icons for the Start Button",
                    summaryES: "Las tres opciones de ícono de cerebro para el botón Inicio de la barra de tareas ahora aparecen de forma más clara y directa como Brain, Brain Mono y Brain Sello tanto en Configuración → Apariencia como en el menú superior y el menú contextual.",
                    summaryEN: "The three brain icon options for the taskbar Start button now appear cleanly and directly as Brain, Brain Mono, and Brain Badge across Appearance settings, the top menu, and the right-click context menu."
                ),
                ReleaseNoteItem(
                    id: "legal-disclaimer-about-notice",
                    icon: "shield.lefthalf.filled",
                    titleES: "Aviso legal en «Acerca de MacFileExplorer»",
                    titleEN: "Legal Disclaimer in About MacFileExplorer",
                    summaryES: "Se incorporó un aviso legal breve y claro en la ventana «Acerca de MacFileExplorer» detallando los términos de uso bajo responsabilidad propia y la exención de responsabilidad ante errores del sistema, pérdida de datos o daños.",
                    summaryEN: "Added a concise, clear legal disclaimer inside the About MacFileExplorer window outlining the as-is terms of use and limitation of liability regarding system errors, data loss, or damages."
                )
            ]
        ),
        ReleaseNoteSection(
            id: "v1.8.1-apple-silicon-performance-and-app-icons",
            semanticVersion: "1.8.1",
            versionLabelES: "Versión 1.8.1 — Optimización Apple Silicon y 5 íconos seleccionables",
            versionLabelEN: "Version 1.8.1 — Apple Silicon Optimization & 5 Selectable App Icons",
            dateLabelES: "24 nov 2026",
            dateLabelEN: "Nov 24, 2026",
            items: [
                ReleaseNoteItem(
                    id: "apple-silicon-idle-cpu-optimization",
                    icon: "bolt.circle.fill",
                    titleES: "Consumo de CPU casi nulo en reposo y mayor eficiencia en procesadores Apple Silicon (M1/M2/M3/M4)",
                    titleEN: "Near-Zero Idle CPU Usage & Higher Efficiency on Apple Silicon (M1/M2/M3/M4)",
                    summaryES: "Se optimizó el consumo en segundo plano para que MacFileExplorer permanezca prácticamente en reposo cuando no estás interactuando: las ventanas de configuración ahora detienen sus vistas previas animadas apenas se cierran, el análisis automático de texto en imágenes corre suavemente en núcleos de eficiencia sin provocar recargas repetidas de carpetas, y la barra de tareas evita redibujos y consultas repetitivas al sistema.",
                    summaryEN: "Background activity has been deeply optimized so MacFileExplorer stays nearly idle when you are not interacting with it: settings windows stop all live preview animations the instant they close, automatic image text indexing runs gently on efficiency cores without triggering folder reload loops, and the taskbar eliminates redundant redraws and system queries."
                ),
                ReleaseNoteItem(
                    id: "selectable-macos-app-icons-5-styles",
                    icon: "app.badge.checkmark",
                    titleES: "4 nuevos íconos para MacFileExplorer y selector de ícono en macOS",
                    titleEN: "4 New MacFileExplorer Icons & macOS App Icon Picker",
                    summaryES: "Ahora podés elegir entre 5 íconos distintos para que MacFileExplorer se muestre en el Dock de macOS, ⌘+Tab, la Barra de tareas y AltTab: Clásico, Estilo macOS (azul nativo), Mono Oscuro, Mono Claro y Capas Cristal. Cambialo al instante desde el menú MacFileExplorer → Ícono de la aplicación, desde Acerca de MacFileExplorer o en Configuración de la barra de tareas → Apariencia.",
                    summaryEN: "Choose from 5 distinct icons for MacFileExplorer across the macOS Dock, ⌘+Tab, Taskbar, and AltTab: Classic, macOS Style (native Apple blue), Dark Mono, Light Mono, and Glass Layers. Switch instantly from MacFileExplorer → App Icon, About MacFileExplorer, or Taskbar Settings → Appearance."
                )
            ]
        ),
        ReleaseNoteSection(
            id: "v1.8.0-windows-style-taskbar",
            semanticVersion: "1.8.0",
            versionLabelES: "Versión 1.8.0 — Barra de tareas estilo Windows, Menú Inicio y Selector AltTab",
            versionLabelEN: "Version 1.8.0 — Windows-Style Taskbar, Start Menu & AltTab Window Switcher",
            dateLabelES: "24 nov 2026",
            dateLabelEN: "Nov 24, 2026",
            items: [
                ReleaseNoteItem(
                    id: "taskbar-hover-preview-4-animations",
                    icon: "dock.arrow.up.rectangle",
                    titleES: "4 animaciones seleccionables para la vista previa de ventanas en la barra",
                    titleEN: "4 Selectable Hover Window Preview Animations on the Taskbar",
                    summaryES: "Ahora podés elegir cómo aparece y se oculta la vista previa al pasar el cursor por un botón de la barra de tareas entre 4 estilos: Suave (fundido y elevación), Desde la barra (emerge directamente desde el borde superior de la barra y vuelve a guardarse dentro de ella), Rebote elástico y Giro 3D. Podés probarlos y elegir el tuyo en vivo desde Configuración de la barra de tareas → Apariencia → Vista previa al pasar el cursor o desde el menú Barra de tareas → Tema y tamaño.",
                    summaryEN: "You can now choose how the hover window preview enters and exits on the taskbar from 4 styles: Smooth Fade, Rise from Bar (slides straight out of the top edge of the taskbar and retracts back into it), Elastic Pop, and 3D Tilt. Preview all 4 styles live and switch anytime from Taskbar Settings → Appearance → Hover Window Previews or the Taskbar → Theme & Size menu."
                ),
                ReleaseNoteItem(
                    id: "taskbar-smooth-hover-preview-fixed-size",
                    icon: "rectangle.on.rectangle.angled",
                    titleES: "Vistas previas de la barra más rápidas, con tamaño fijo y transiciones suaves",
                    titleEN: "Faster Taskbar Hover Previews with Fixed Size & Smooth Transitions",
                    summaryES: "Las miniaturas al pasar el cursor por la barra de tareas ahora calculan su tamaño definitivo antes de abrirse para que la tarjeta nunca salte ni cambie de tamaño al cargarse la imagen. Además precargan la captura apenas apoyás el cursor, mantienen miniaturas listas al cambiar de ventana y aplican aparición suave, deslizamiento entre botones y fundido progresivo al actualizar la imagen.",
                    summaryEN: "Taskbar hover thumbnails now lock their exact final size before appearing so the preview card never jumps or resizes when the screenshot finishes loading. Captures also prefetch the instant your pointer enters a button, pre-warm on focus switches, and animate smoothly with fade-in entrance, gliding between buttons, and crossfade updates."
                ),
                ReleaseNoteItem(
                    id: "taskbar-windowless-apps-and-stable-order",
                    icon: "pin.square.fill",
                    titleES: "Apps abiertas sin ventanas (como VS Code) y orden fijo al minimizar/restaurar",
                    titleEN: "Running Windowless Apps (e.g. VS Code) & Fixed Order on Minimize/Restore",
                    summaryES: "La barra de tareas ahora muestra también las apps que siguen abiertas en macOS aunque hayas cerrado su última ventana (como Visual Studio Code, Terminal o Numbers, al igual que el Dock original), con clic directo para abrir ventana y opción para activar o desactivar esto en Configuración → General. Además se reforzó el orden de botones para que minimizar, restaurar o cambiar pestañas mantenga siempre cada app en su posición original sin mandarla al final.",
                    summaryEN: "The taskbar now also shows macOS apps that remain running even after closing their last window (such as Visual Studio Code, Terminal, or Numbers, just like the native Dock) with one-click window reopen and a toggle in Settings → General. Button ordering was also hardened so minimizing, restoring, or switching tabs always keeps each app in its exact original slot instead of moving it to the end."
                ),
                ReleaseNoteItem(
                    id: "taskbar-notification-badge-animations",
                    icon: "bell.badge.fill",
                    titleES: "6 animaciones configurables y detección mejorada de notificaciones en la barra",
                    titleEN: "6 Configurable Notification Animations & Enhanced Badge Detection",
                    summaryES: "Cuando una app recibe una notificación (como el globo rojo de Slack, WhatsApp, Mail o apps web PWA), ahora se detecta combinando el Dock de macOS, LaunchServices y el contador de título en PWAs/mensajería, y podés elegir entre 6 animaciones desde Configuración → Apariencia o el menú superior: Salto, Campana, Latido, Destello, Onda expansiva y Bamboleo (o dejarlo sin animación). Incluye vista previa en vivo y selector de frecuencia, pausándose al entrar a leer la app.",
                    summaryEN: "When an app receives a notification (such as a red badge on Slack, WhatsApp, Mail, or web PWAs), detection now combines the macOS Dock, LaunchServices, and unread title counters for PWAs/messaging apps. Choose from 6 animations in Taskbar Settings → Appearance or the top menu: Bounce, Bell Shake, Heartbeat, Glow Flash, Ripple Wave, and Swing Float (or None), with live previews and configurable cadence that pauses automatically when you focus the app."
                ),
                ReleaseNoteItem(
                    id: "alttab-window-switcher-full-preview",
                    icon: "rectangle.stack.fill",
                    titleES: "Selector de ventanas AltTab en el nuevo menú superior «AltTab»",
                    titleEN: "AltTab Window Switcher in New Top Menu «AltTab»",
                    summaryES: "Ahora podés activar un selector ultrarrápido estilo Alt+Tab de Windows desde su propio menú superior «AltTab» (desactivado de fábrica). Muestra cada ventana abierta por separado incluso si son de la misma app, incluye minimizadas, ocultas y de otros escritorios (Spaces) con etiquetas claras, ofrece vista previa a tamaño completo encima del resto, 3 estilos (Miniaturas, Íconos o Lista de títulos) con tamaño automático, búsqueda rápida y hasta 5 atajos personalizables (⌥⇥ y ⌥` por defecto).",
                    summaryEN: "Enable an ultra-fast Windows-style Alt+Tab switcher from its own top menu «AltTab» (off by default). Lists every individual open window even within the same app, includes minimized, hidden, and other-Space windows with clear badges, displays a full-size preview above other windows, supports 3 auto-sized styles (Thumbnails, App Icons, or Compact Titles List), instant search, and up to 5 customizable shortcuts (⌥⇥ and ⌥` by default)."
                ),
                ReleaseNoteItem(
                    id: "taskbar-window-buttons-and-start-menu",
                    icon: "dock.rectangle",
                    titleES: "Barra de tareas estilo Windows en el nuevo menú superior «Barra de tareas»",
                    titleEN: "Windows-Style Taskbar in New Top Menu «Taskbar»",
                    summaryES: "Ahora podés activar o desactivar desde el menú superior una barra inferior con un botón individual por cada ventana abierta, apertura y cambio de foco al instante (incluyendo WhatsApp y apps web PWA), miniaturas en vivo al pasar el cursor, aplicaciones fijadas y un Menú Inicio con buscador, recientes y lista alfabética. Viene desactivada de fábrica, podés elegir si arranca encendida por defecto y evita que macOS duerma la app mientras la barra esté activa.",
                    summaryEN: "Turn on an optional Windows-style bottom bar from the new top menu with one button per open window, instant app switching (including WhatsApp and web PWAs), live hover thumbnails, pinned apps, and a searchable alphabetical Start Menu. Starts disabled by default with a setting to enable on launch, and prevents macOS App Nap from pausing the bar."
                ),
                ReleaseNoteItem(
                    id: "taskbar-multimonitor-spaces-mouse-controls",
                    icon: "display.2",
                    titleES: "Multimonitor (hasta 5 pantallas), Spaces, reordenamiento y controles rápidos",
                    titleEN: "Multi-Monitor (up to 5 Displays), Spaces, Reordering & Mouse Controls",
                    summaryES: "Muestra una barra independiente en cada monitor conectado (o unifica todas las ventanas en una sola barra), se actualiza automáticamente al cambiar de escritorio virtual (Spaces), permite arrastrar botones para reordenarlos o agruparlos por app, minimiza al volver a hacer clic en la ventana activa, cierra con clic central y redimensiona ventanas que tapen la barra.",
                    summaryEN: "Displays an independent bar on each connected screen (or unifies all windows into one bar), stays in sync with macOS Spaces, supports drag-to-reorder or grouping by app, minimizes on clicking the active window, closes on middle-click, and auto-resizes overlapping windows."
                ),
                ReleaseNoteItem(
                    id: "taskbar-safe-dock-and-emergency-restore",
                    icon: "arrow.uturn.backward.circle.fill",
                    titleES: "Personalización visual, 12 íconos de Inicio (incluidos monocromáticos nativos) y gestión segura del Dock",
                    titleEN: "Visual Customization, 12 Start Icons (Including Native Monochrome Variants) & Safe Dock Management",
                    summaryES: "Elegí el ícono del botón Inicio entre 12 opciones predefinidas (cuadrícula estilo Windows, Apps de macOS, Apple, MacFileExplorer color y 3 estilos modernos en blanco con espacio negativo, Brain color y 2 estilos monocromáticos tipo macOS, cuadrícula 3×3 y Comando ⌘) con animación táctil de zoom al pasar el cursor, desde Apariencia, el menú superior o con clic derecho sobre el botón. Además podés ajustar tamaño, fuente, transparencia, tema claro/oscuro, solo íconos y apps excluidas, manteniendo tu Dock original intacto con botón de restauración de emergencia.",
                    summaryEN: "Pick your Start button icon from 12 built-in presets (Windows-style grid, official macOS Apps, Apple, MacFileExplorer full color plus 3 modern monochrome negative-space styles, Brain full color plus 2 native-style monochrome variants, 3×3 grid, and Command ⌘) with a subtle hover scale animation, from Settings, the top menu, or by right-clicking the Start button. Also customize height, font, transparency, light/dark theme, icon-only mode, and excluded apps, while keeping your original macOS Dock untouched with Emergency Restore."
                )
            ]
        ),
        ReleaseNoteSection(
            id: "v1.7.0-ocr-cache-manager-help",
            semanticVersion: "1.7.0",
            versionLabelES: "Versión 1.7.0 — Índice OCR en Background, Gestor de Caché y Ayuda",
            versionLabelEN: "Version 1.7.0 — Background OCR Index, Cache Manager & Help Guide",
            dateLabelES: "18 nov 2026",
            dateLabelEN: "Nov 18, 2026",
            items: [
                ReleaseNoteItem(
                    id: "interactive-help-guide",
                    icon: "questionmark.circle.fill",
                    titleES: "Guía completa y Ayuda interactiva en el menú Help",
                    titleEN: "Complete Interactive Help & User Guide in Help Menu",
                    summaryES: "El menú superior Ayuda / Help ahora abre una guía navegable y buscable basada en todos los releases: funciones destacadas, catálogo completo, explicación del menú lateral y del buscador avanzado con OCR, tabla de todos los atajos de teclado y todas las configuraciones disponibles.",
                    summaryEN: "The top Help menu now opens a searchable interactive guide built from all releases, covering highlighted & full features, sidebar & OCR search explanations, complete keyboard/mouse shortcuts, and all available settings."
                ),
                ReleaseNoteItem(
                    id: "hidden-cache-manager-file-menu",
                    icon: "internaldrive.fill",
                    titleES: "Gestor de caché oculta (.macfileexplorer) en el menú Archivo",
                    titleEN: "Hidden Cache Manager (.macfileexplorer) in File Menu",
                    summaryES: "Desde Archivo → Caché oculta (.macfileexplorer)… podés ver cuántos archivos ocultos de caché existen (índices de carpetas, miniaturas e OCR), cuánto espacio ocupan en total y borrarlos todos con un clic para regenerarlos limpios.",
                    summaryEN: "From File → Hidden Cache (.macfileexplorer)… you can see how many hidden cache files exist (folder indexes, thumbnails, and OCR), their total disk usage, and delete all of them in one click to regenerate cleanly."
                ),
                ReleaseNoteItem(
                    id: "ocr-background-folder-cache",
                    icon: "text.viewfinder",
                    titleES: "Indexación OCR automática en segundo plano (máx. 5 MB por carpeta)",
                    titleEN: "Background OCR Image Indexing (max 5 MB per folder)",
                    summaryES: "Al abrir una carpeta, las imágenes se analizan silenciosamente en segundo plano y su texto se guarda comprimido en un índice oculto (tope estricto de 5 MB por carpeta). Así la búsqueda dentro de imágenes del buscador avanzado devuelve coincidencias al instante y muestra resultados en vivo mientras escanea imágenes nuevas.",
                    summaryEN: "When opening a folder, images are quietly indexed in the background and saved in a compressed hidden cache capped at 5 MB per folder. Content search in Advanced Search now returns instant matches and streams live results for new images."
                )
            ]
        ),
        ReleaseNoteSection(
            id: "v1.6.0-address-bar-bg-remove-ocr",
            semanticVersion: "1.6.0",
            versionLabelES: "Versión 1.6.0 — Barra Editable, Eliminar Fondo (PNG) y OCR Preciso",
            versionLabelEN: "Version 1.6.0 — Editable Address Bar, Remove Background & Enhanced OCR",
            dateLabelES: "17 nov 2026",
            dateLabelEN: "Nov 17, 2026",
            items: [
                ReleaseNoteItem(
                    id: "editable-breadcrumb-address-bar",
                    icon: "chevron.right.2",
                    titleES: "Barra de direcciones editable estilo Windows Explorer",
                    titleEN: "Windows Explorer-style Editable Address Bar",
                    summaryES: "Ahora podés hacer clic sobre el último segmento de la ruta o en cualquier espacio de la barra de direcciones (además de ⌘L) para escribir o pegar directamente rutas como ~/Documents/Proyectos con auto-selección, autocompletado con Tab y flechas › para saltar entre subcarpetas.",
                    summaryEN: "Click the current path segment or empty bar area (as well as ⌘L) to type or paste paths like ~/Documents/Projects with auto-selection, Tab folder autocompletion, and clickable › chevron menus."
                ),
                ReleaseNoteItem(
                    id: "quick-actions-remove-background",
                    icon: "person.and.background.dotted",
                    titleES: "Eliminar fondo de imágenes en Quick Actions",
                    titleEN: "Remove Image Background in Quick Actions",
                    summaryES: "Al hacer clic derecho sobre una o varias imágenes (JPG, PNG, HEIC, etc.) y elegir Quick Actions → Eliminar fondo (PNG transparente), se separa automáticamente el sujeto u objeto principal y se guarda una imagen nueva en PNG con fondo transparente sin modificar la original.",
                    summaryEN: "Right-clicking one or more images (JPG, PNG, HEIC, etc.) and selecting Quick Actions → Remove Background (Transparent PNG) automatically isolates the main subject and saves a new PNG with a transparent background without overwriting the original."
                ),
                ReleaseNoteItem(
                    id: "improved-ocr-image-search",
                    icon: "text.viewfinder",
                    titleES: "Búsqueda de texto en imágenes más precisa (OCR mejorado)",
                    titleEN: "More accurate text search inside images (Enhanced OCR)",
                    summaryES: "Se mejoró la búsqueda dentro de imágenes del buscador avanzado para reconocer textos pequeños o sobre fondos complejos (como capturas de videollamadas o pantallas), ignorando mayúsculas y tildes, y acelerando búsquedas repetidas.",
                    summaryEN: "Improved image text search in Advanced Search to recognize small or low-contrast captions (such as video call or UI screenshots), ignoring case and accents, with faster scanning and caching."
                )
            ]
        ),
        ReleaseNoteSection(
            id: "v1.5.1-check-upgrades",
            semanticVersion: "1.5.1",
            versionLabelES: "Versión 1.5.1 — Buscar actualizaciones desde GitHub",
            versionLabelEN: "Version 1.5.1 — Check Upgrades from GitHub",
            dateLabelES: "17 nov 2026",
            dateLabelEN: "Nov 17, 2026",
            items: [
                ReleaseNoteItem(
                    id: "check-upgrades-github",
                    icon: "arrow.down.circle.fill",
                    titleES: "Buscar actualizaciones directamente desde GitHub",
                    titleEN: "Check Upgrades directly from GitHub",
                    summaryES: "Agregamos el botón «Buscar actualizaciones» (en Acerca de MacFileExplorer, menú superior e icono de la barra de menús) para consultar directamente el repositorio en GitHub y descargar automáticamente el nuevo instalador en tu carpeta Descargas cuando haya una versión más reciente.",
                    summaryEN: "Added a «Check Upgrades» button (in About MacFileExplorer, the top menu, and the menu bar tray icon) to check GitHub directly and automatically download the new installer to your Downloads folder whenever a newer version is available."
                )
            ]
        ),
        ReleaseNoteSection(
            id: "v1.5.0-search-duplicates-transfer-queue",
            semanticVersion: "1.5.0",
            versionLabelES: "Versión 1.5.0 — Búsqueda Avanzada, Duplicados y Cola de Transferencias",
            versionLabelEN: "Version 1.5.0 — Advanced Search, Duplicates & Transfer Queue",
            dateLabelES: "17 nov 2026",
            dateLabelEN: "Nov 17, 2026",
            items: [
                ReleaseNoteItem(
                    id: "duplicate-finder",
                    icon: "doc.on.doc.fill",
                    titleES: "Buscador de archivos duplicados",
                    titleEN: "Duplicate File Finder",
                    summaryES: "Desde el menú Archivo → Buscar archivos duplicados… podés escanear la carpeta actual (o subcarpetas) para encontrar archivos repetidos, pre-marcar automáticamente las copias conservando el original y elegir si moverlas a la Papelera, eliminarlas o seleccionarlas.",
                    summaryEN: "From File → Find Duplicate Files… you can scan the current folder (or subfolders) for duplicate files, automatically pre-check copies while keeping the original, and choose to move them to Trash, delete permanently, or select them."
                ),
                ReleaseNoteItem(
                    id: "transfer-queue-1gb",
                    icon: "arrow.up.arrow.down.circle.fill",
                    titleES: "Cola de transferencias con pausa y reanudación (> 1 GB)",
                    titleEN: "Transfer Queue with Pause & Resume (> 1 GB)",
                    summaryES: "Al copiar, cortar o mover archivos o carpetas de más de 1 GB, el progreso aparece centrado directamente en la barra inferior. Al hacer clic sobre la barra podés abrir el subpanel para pausar, reanudar o cancelar, y se limpia y cierra automáticamente al finalizar.",
                    summaryEN: "When copying, cutting, or moving files or folders over 1 GB, progress appears centered in the bottom status bar. Clicking it opens the queue popover to pause, resume, or cancel transfers, and it closes and clears automatically when done."
                ),
                ReleaseNoteItem(
                    id: "advanced-search-popover",
                    icon: "line.3.horizontal.decrease.circle",
                    titleES: "Buscador avanzado en la barra de búsqueda",
                    titleEN: "Advanced Search in the search bar",
                    summaryES: "Ahora puedes hacer clic en el icono de filtros a la derecha de la barra de búsqueda para filtrar por tipo de archivo o extensión, tamaño mínimo/máximo, incluir subcarpetas y buscar texto dentro de archivos de texto, PDFs e imágenes.",
                    summaryEN: "Click the filter icon on the right side of the search bar to filter by file type or extension, minimum/maximum file size, include subfolders, and search inside text files, PDFs, and images."
                ),
                ReleaseNoteItem(
                    id: "ui-navigation-delete-modal-polish",
                    icon: "slider.horizontal.3",
                    titleES: "Mejoras en columnas, menú contextual y confirmación al eliminar",
                    titleEN: "Column cursor, context menu & delete confirmation improvements",
                    summaryES: "Al ajustar el ancho de las columnas en vista Detalles el puntero cambia al cursor de redimensionado, puedes mostrar u ocultar «Modificados hoy (24h)» en Acceso rápido, el menú contextual ordena «Añadir a Gemini» anteúltimo y «Propiedades» siempre último, y el aviso de eliminación permanente luce centrado y más claro.",
                    summaryEN: "Adjusting column widths in Details view now shows the horizontal resize cursor, «Modified Today (24h)» can be shown or hidden in Quick Access, the context menu consistently places «Add to Gemini» second-to-last and «Properties» last, and the permanent delete confirmation modal is centered and cleaner."
                )
            ]
        ),
        ReleaseNoteSection(
            id: "v1.4.0-quick-actions-privacy-quicklook",
            semanticVersion: "1.4.0",
            versionLabelES: "Versión 1.4.0 — Quick Actions, Privacy Stripper, Vista Rápida y Fluidez",
            versionLabelEN: "Version 1.4.0 — Quick Actions, Privacy Stripper, Quick Look & Performance",
            dateLabelES: "16 nov 2026",
            dateLabelEN: "Nov 16, 2026",
            items: [
                ReleaseNoteItem(
                    id: "privacy-stripper-quick-action",
                    icon: "shield.lefthalf.filled",
                    titleES: "Limpiador de metadatos (Privacy Stripper) en Quick Actions",
                    titleEN: "Metadata Privacy Stripper in Quick Actions",
                    summaryES: "Al hacer clic derecho sobre fotos, videos o archivos PDF, ahora puedes elegir Quick Actions → Limpiar metadatos para crear una copia segura sin ubicación GPS, autor, ni datos de cámara o dispositivo antes de compartirla.",
                    summaryEN: "Right-clicking photos, videos, or PDF files now offers Quick Actions → Strip Metadata to create a clean copy free of GPS location, author, and camera or device details before sharing."
                ),
                ReleaseNoteItem(
                    id: "status-bar-linear-progress",
                    icon: "chart.bar.fill",
                    titleES: "Barra de progreso en la barra inferior",
                    titleEN: "Progress bar in the bottom status bar",
                    summaryES: "Cuando copiás, movés, eliminás, comprimís o cargás carpetas pesadas, ahora ves una barra de progreso integrada directamente en la barra inferior junto al conteo y tamaño de archivos.",
                    summaryEN: "When copying, moving, deleting, compressing, or loading large folders, a progress bar now appears directly in the bottom status bar next to the item count and size."
                ),
                ReleaseNoteItem(
                    id: "rich-quicklook-markdown-json-code",
                    icon: "doc.richtext",
                    titleES: "Vista rápida mejorada para Markdown, JSON y código",
                    titleEN: "Enhanced Quick Look for Markdown, JSON & source code",
                    summaryES: "Al presionar Espacio sobre archivos .md, .json o código fuente, la vista rápida renderiza Markdown completo (incluyendo tablas, listas y metadatos), muestra JSON en árbol colapsable o Texto plano limpio y legible, y resalta código con números de línea.",
                    summaryEN: "Pressing Space on .md, .json, or source code files now renders full Markdown (including tables, lists, and frontmatter), displays JSON as a collapsible tree or clean Plain Text, and highlights source code with line numbers."
                ),
                ReleaseNoteItem(
                    id: "multi-format-archive-tool",
                    icon: "archivebox.fill",
                    titleES: "Compresor y descompresor multipropósito (.zip, .7z, .tar.gz, .rar)",
                    titleEN: "Multi-format compressor & extractor (.zip, .7z, .tar.gz, .rar)",
                    summaryES: "Ahora puedes comprimir archivos y carpetas en .zip, .tar.gz o .7z y extraer archivos .zip, .7z, .tar.gz y .rar desde el menú contextual con barra de progreso nativa y sin crear carpetas intermedias innecesarias ni archivos basura.",
                    summaryEN: "You can now compress files and folders into .zip, .tar.gz, or .7z and extract .zip, .7z, .tar.gz, and .rar archives from the context menu with a native progress bar and without leaving junk intermediate folders."
                ),
                ReleaseNoteItem(
                    id: "exif-media-metadata-properties",
                    icon: "camera.aperture",
                    titleES: "Visor de metadatos EXIF y multimedia en Propiedades",
                    titleEN: "EXIF & Media Metadata viewer in Properties",
                    summaryES: "Al abrir Propiedades (⌘I) sobre cualquier imagen o video, ahora se muestran sus datos técnicos: resolución, PPP, cámara, lente, apertura, velocidad, ISO, duración del video, cuadros por segundo y pistas de audio.",
                    summaryEN: "Opening Properties (⌘I) on any image or video now displays its technical metadata: resolution, DPI, camera, lens, aperture, shutter speed, ISO, video duration, frame rate, and audio tracks."
                ),
                ReleaseNoteItem(
                    id: "recent-24h-virtual-folder",
                    icon: "clock.arrow.2.circlepath",
                    titleES: "Carpeta virtual «Modificados hoy (24h)» en Acceso rápido",
                    titleEN: "«Modified Today (24h)» virtual folder in Quick Access",
                    summaryES: "Se agregó el acceso rápido «Modificados hoy (24h)» en el panel lateral izquierdo con escaneo paralelo acelerado para listar al instante todos los archivos modificados, creados o agregados en las últimas 24 horas dentro del árbol de carpetas actual (puedes mostrarlo u ocultarlo desde Ver → Carpetas en Acceso rápido).",
                    summaryEN: "Added a «Modified Today (24h)» virtual folder in the left sidebar with accelerated parallel scanning to instantly list all files modified, created, or added in the last 24 hours within the current folder tree (show or hide it anytime from View → Quick Access Folders)."
                ),
                ReleaseNoteItem(
                    id: "quick-actions-media",
                    icon: "wand.and.stars",
                    titleES: "Quick Actions para imágenes y videos desde el clic derecho",
                    titleEN: "Quick Actions for images and videos from right-click",
                    summaryES: "Al hacer clic derecho sobre imágenes o videos aparece el menú «Quick Actions». En imágenes puedes convertir a JPG o PNG eligiendo calidad, PPP, ancho o peso máximo en MB (o mantener tamaño original) y rotarlas 90°/180°. En videos puedes convertir de MOV a MP4 eligiendo calidad y peso máximo en MB, recortar (Trim) o eliminar el audio.",
                    summaryEN: "Right-clicking images or videos now reveals the «Quick Actions» menu. For images, you can convert to JPG or PNG with custom quality, DPI, target width, or max file size in MB (or keep original size) and rotate 90°/180°. For videos, you can convert MOV to MP4 with custom quality and max MB size, trim clips, or remove audio."
                ),
                ReleaseNoteItem(
                    id: "bulk-rename-regex-exif",
                    icon: "pencil.and.list.clipboard",
                    titleES: "Renombrado masivo con Regex, numeración y fechas EXIF",
                    titleEN: "Bulk Rename with Regex, sequential numbering & EXIF dates",
                    summaryES: "Al seleccionar varios archivos o carpetas y presionar Enter (o F2 / Renombrar), se abre el nuevo panel de Renombrado masivo. Puedes cambiar cientos de nombres a la vez usando expresiones regulares, numeración secuencial o la fecha de metadatos EXIF de tus fotos, con vista previa en tiempo real, detección de conflictos y soporte para deshacer con ⌘Z.",
                    summaryEN: "Selecting multiple files or folders and pressing Enter (or F2 / Rename) opens the new Bulk Rename panel. You can rename hundreds of files at once using regular expressions, sequential numbering, or photo EXIF metadata dates, complete with live preview, conflict detection, and ⌘Z undo support."
                )
            ]
        ),
        ReleaseNoteSection(
            id: "v1.3-clipboard-tray-quicklook-sessions",
            semanticVersion: "1.3.0",
            versionLabelES: "Versión 1.3 — Portapapeles Maccy, Tray Icon, Vista Rápida y Sesiones",
            versionLabelEN: "Version 1.3 — Maccy Clipboard, Tray Icon, Quick Look & Sessions",
            dateLabelES: "16 nov 2026",
            dateLabelEN: "Nov 16, 2026",
            items: [
                ReleaseNoteItem(
                    id: "clipboard-history-maccy",
                    icon: "doc.on.clipboard.fill",
                    titleES: "Historial del Portapapeles estilo Maccy, menú superior Portapapeles y desplegable global (⌃⌘V)",
                    titleEN: "Maccy-style Clipboard History, top Clipboard menu & global paste dropdown (⌃⌘V)",
                    summaryES: "Se sumó un menú específico «Portapapeles» en la barra superior de macOS y una nueva sección debajo de Cuentas de Google que guarda automáticamente todo lo que copies (texto, enlaces, archivos e imágenes). Al presionar ⌃⌘V desde cualquier aplicación de la Mac se abre un menú desplegable estilo Maccy con los últimos 10 elementos copiados (incluyendo miniaturas de imágenes y acceso rápido con ⌘1..9) mientras que el pegado normal sigue usando lo último copiado. Además puedes configurar el tiempo de guardado, la cantidad máxima, personalizar todos los atajos de teclado o activar y desactivar la función cuando quieras.",
                    summaryEN: "Added a dedicated «Clipboard» menu in the top macOS menu bar and a new sidebar section below Google Accounts that automatically saves everything you copy (text, links, files, and images). Pressing ⌃⌘V anywhere on your Mac opens a Maccy-style dropdown menu showing the last 10 copied items (with inline image previews and ⌘1..9 quick shortcuts) while normal paste continues using the latest copied item. You can also configure retention time, maximum item count, customize all keyboard shortcuts, or enable and disable the feature anytime."
                ),
                ReleaseNoteItem(
                    id: "menu-bar-tray-icon",
                    icon: "menubar.rectangle",
                    titleES: "Icono de acceso rápido en la barra de menús de macOS (Tray Icon)",
                    titleEN: "Quick access icon in the macOS menu bar (Tray Icon)",
                    summaryES: "Ahora MacFileExplorer cuenta con su propio icono en la barra superior de macOS (junto al reloj, Wi‑Fi y batería). Al hacer clic sobre él puedes abrir o traer al frente el explorador, abrir una nueva pestaña o ventana, ir directamente a tus carpetas favoritas, cambiar entre tus pestañas abiertas o de Google Workspace, cerrar la pestaña o ventana actual, o salir de la aplicación.",
                    summaryEN: "MacFileExplorer now includes its own icon in the top macOS menu bar (next to the clock, Wi‑Fi, and battery). Clicking it lets you open or bring the explorer to the front, open a new tab or window, jump directly to your favorite folders, switch between open tabs or Google Workspace services, close the current tab or window, or quit the app."
                ),
                ReleaseNoteItem(
                    id: "quicklook-movable-resizable-maximize",
                    icon: "arrow.up.left.and.arrow.down.right",
                    titleES: "Ventana de Vista Rápida movible, redimensionable y maximizable",
                    titleEN: "Movable, resizable & double-click maximizable Quick Look window",
                    summaryES: "La ventana de previsualización rápida (Espacio) ahora funciona como una ventana flotante independiente: puedes moverla libremente arrastrando su barra superior, ajustar su tamaño desde cualquier borde o esquina, y maximizarla o restaurar su tamaño haciendo doble clic en la barra de título (o usando el botón de expandir).",
                    summaryEN: "The Quick Look preview window (Space) now works as an independent floating window: you can move it freely by dragging its top bar, resize it from any edge or corner, and maximize or restore its size by double-clicking the title bar (or clicking the expand button)."
                ),
                ReleaseNoteItem(
                    id: "remember-open-tabs-and-web-sessions",
                    icon: "clock.arrow.circlepath",
                    titleES: "Recordar carpetas, pestañas y sesiones de Google al reabrir",
                    titleEN: "Remember open folders, tabs & Google sessions on relaunch",
                    summaryES: "Ahora MacFileExplorer recuerda automáticamente no solo la carpeta activa, sino también todas las pestañas que tenías abiertas (carpetas, Gmail, Google Drive, Google Calendar y marcadores web) respetando su orden y cuál estabas viendo al cerrar la aplicación. Puedes activar o desactivar esta opción en cualquier momento desde el menú Ver de la barra superior o el menú Ver de la barra de herramientas.",
                    summaryEN: "MacFileExplorer now automatically remembers not only your active folder, but also every tab you had open (folders, Gmail, Google Drive, Google Calendar, and web bookmarks) along with their exact order and active tab when you quit. You can turn this option on or off at any time from the top View menu or the toolbar View menu."
                )
            ]
        ),
        ReleaseNoteSection(
            id: "v1.2-slack-mxmaster-responsive",
            semanticVersion: "1.2.0",
            versionLabelES: "Versión 1.2 — Slack, Ratón MX Master y Barra Adaptable",
            versionLabelEN: "Version 1.2 — Slack, MX Master Mouse & Responsive Toolbar",
            dateLabelES: "13 nov 2026",
            dateLabelEN: "Nov 13, 2026",
            items: [
                ReleaseNoteItem(
                    id: "version-1-2-release",
                    icon: "sparkles",
                    titleES: "Lanzamiento oficial de la versión 1.2",
                    titleEN: "Official Version 1.2 Release",
                    summaryES: "MacFileExplorer llega a la versión 1.2 sumando envío directo de archivos a Slack con búsqueda y autocompletado, compatibilidad completa con botones laterales y gestos de ratones Logitech MX Master 3 (Atrás y Adelante), menú «Ir», barra de herramientas adaptable al tamaño de la ventana e íconos completos en el menú Edición.",
                    summaryEN: "MacFileExplorer reaches version 1.2 with direct file sharing to Slack including search and autocomplete, full out-of-the-box support for Logitech MX Master 3 side buttons and swipe gestures (Back and Forward), a new «Go» menu, a window-responsive toolbar, and complete Edit menu icons."
                ),
                ReleaseNoteItem(
                    id: "mx-master-swipe-navigation",
                    icon: "computermouse.fill",
                    titleES: "Botones laterales Logitech MX Master y gestos Atrás / Adelante",
                    titleEN: "Logitech MX Master side buttons and Back / Forward gestures",
                    summaryES: "Los botones laterales Atrás y Adelante de ratones como Logitech MX Master 3 (y gestos de deslizamiento lateral del trackpad) ahora funcionan de forma automática y sin configuración extra tanto al explorar carpetas como en las pestañas web, igual que en Finder y Chrome, junto con compatibilidad mejorada para teclados en español con ⌘[ y ⌘].",
                    summaryEN: "Side Back and Forward buttons on mice like Logitech MX Master 3 (as well as trackpad horizontal swipe gestures) now work automatically out of the box both when browsing folders and in web tabs, just like in Finder and Chrome, alongside improved ⌘[ and ⌘] support on international keyboards."
                ),
                ReleaseNoteItem(
                    id: "slack-disable-option-refinement",
                    icon: "bubble.left.and.bubble.right",
                    titleES: "Desactivar «Compartir con Slack» desde menús o desde el diálogo",
                    titleEN: "Disable «Share with Slack» from menus or the dialog",
                    summaryES: "Ahora puedes activar o desactivar al instante la opción de compartir archivos con Slack desde el menú Ver de la barra superior, el menú Ver de la barra de herramientas o directamente desde la casilla inferior al abrir «Compartir con Slack», con confirmación inmediata y ocultamiento en todos los menús contextuales.",
                    summaryEN: "You can now instantly turn the «Add to Slack» sharing option on or off from the top View menu, the toolbar View menu, or directly from the checkbox at the bottom of the Share with Slack window, with immediate visual confirmation across all context menus."
                ),
                ReleaseNoteItem(
                    id: "mouse-side-buttons-and-go-menu",
                    icon: "computermouse.fill",
                    titleES: "Navegación completa con ratón (Atrás y Adelante) y menú Ir",
                    titleEN: "Complete mouse navigation (Back & Forward) and Go menu",
                    summaryES: "Se renovó la compatibilidad con los botones laterales de cualquier ratón (Logitech, Razer o genéricos) integrando un gestor global a nivel de aplicación, un nuevo menú «Ir» en la barra superior con los atajos estándar (⌘[ y ⌘]), y la opción de invertir los botones laterales según tu preferencia.",
                    summaryEN: "Restored and perfected compatibility with mouse side buttons for any mouse (Logitech, Razer, or generic) with a global app-level manager, a new «Go» menu in the top bar with standard shortcuts (⌘[ and ⌘]), and an option to swap side buttons if desired."
                ),
                ReleaseNoteItem(
                    id: "slack-search-autocomplete-and-toggle",
                    icon: "magnifyingglass.circle.fill",
                    titleES: "Búsqueda y autocompletado para Slack, y opción para activar o desactivar",
                    titleEN: "Search and autocomplete for Slack, with toggle to show or hide",
                    summaryES: "Al compartir archivos con Slack ahora puedes buscar y autocompletar al instante tanto canales (#) como compañeros de equipo (@) con pestañas de filtro, sugerencias y agregar o eliminar contactos fácilmente. Además, puedes activar o desactivar la opción «Añadir a Slack» en cualquier momento desde el propio diálogo, la barra de herramientas o el menú Ver.",
                    summaryEN: "When sharing files with Slack you can now instantly search and autocomplete channels (#) and teammates (@) with filter tabs, quick suggestions, and simple contact management. You can also easily toggle «Add to Slack» on or off at any time from the share dialog, the toolbar, or the View menu."
                ),
                ReleaseNoteItem(
                    id: "edit-menu-action-icons",
                    icon: "scissors",
                    titleES: "Iconos en todas las opciones del menú Edición",
                    titleEN: "Icons across all Edit menu options",
                    summaryES: "Se agregaron iconos representativos a las acciones de Cortar, Copiar, Pegar, Eliminar y Seleccionar todo en el menú superior de macOS (Edición / Edit), completando el diseño visual de toda la barra de menús.",
                    summaryEN: "Representative icons have been added to Cut, Copy, Paste, Delete, and Select All in the top macOS menu bar (Edit), completing the visual design across all application menus."
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
                )
            ]
        ),
        ReleaseNoteSection(
            id: "v1.1-customization-navigation",
            semanticVersion: "1.1.0",
            versionLabelES: "Versión 1.1 — Personalización, Navegación e Iconos",
            versionLabelEN: "Version 1.1 — Customization, Navigation & Icons",
            dateLabelES: "12 nov 2026",
            dateLabelEN: "Nov 12, 2026",
            items: [
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
            semanticVersion: "1.0.1",
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
            semanticVersion: "1.0.0",
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
