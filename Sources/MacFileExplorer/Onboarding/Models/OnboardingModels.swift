import Foundation

// MARK: - Semantic Version Comparison

/// Comparador determinista de versiones semánticas (ej. `"v2.6.0"`, `"2.5.1"`, `"1.3"`, `"2.6.0-beta.1"`).
public enum AppVersionComparator {

    private struct ParsedVersion: Sendable {
        let components: [Int]
        let isPrerelease: Bool
    }

    private static func parse(_ rawVersion: String) -> ParsedVersion {
        var cleaned = rawVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("v") {
            cleaned.removeFirst()
        }
        if let plusIndex = cleaned.firstIndex(of: "+") {
            cleaned = String(cleaned[..<plusIndex])
        }

        var isPrerelease = false
        if let dashIndex = cleaned.firstIndex(of: "-") {
            isPrerelease = true
            cleaned = String(cleaned[..<dashIndex])
        }

        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        var numbers: [Int] = []
        numbers.reserveCapacity(max(3, parts.count))

        for part in parts {
            let digits = part.prefix(while: { $0.isNumber })
            if let value = Int(digits), value >= 0 {
                numbers.append(value)
            } else {
                numbers.append(0)
            }
        }

        if numbers.isEmpty {
            numbers = [0, 0, 0]
        }

        return ParsedVersion(components: numbers, isPrerelease: isPrerelease)
    }

    /// Devuelve los componentes numéricos normalizados (al menos 3: major, minor, patch).
    public static func normalizedComponents(of rawVersion: String) -> [Int] {
        var comps = parse(rawVersion).components
        while comps.count < 3 {
            comps.append(0)
        }
        return comps
    }

    /// Limpia espacios y el prefijo `"v"` / `"V"` para mostrar la versión de forma uniforme en la UI (ej. `"2.6.0"`).
    public static func displayVersion(_ rawVersion: String) -> String {
        var cleaned = rawVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("v") {
            cleaned.removeFirst()
        }
        return cleaned.isEmpty ? "0.0.0" : cleaned
    }

    /// Devuelve la cadena canónica `major.minor.patch` (ej. `"v1.3"` → `"1.3.0"`).
    public static func normalizedString(of rawVersion: String) -> String {
        normalizedComponents(of: rawVersion).map(String.init).joined(separator: ".")
    }

    /// Compara dos versiones semánticas:
    /// - `.orderedAscending` si `lhs < rhs`
    /// - `.orderedSame` si `lhs == rhs`
    /// - `.orderedDescending` si `lhs > rhs`
    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let leftParsed = parse(lhs)
        let rightParsed = parse(rhs)

        let count = max(leftParsed.components.count, rightParsed.components.count)
        for index in 0..<count {
            let l = index < leftParsed.components.count ? leftParsed.components[index] : 0
            let r = index < rightParsed.components.count ? rightParsed.components[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }

        if leftParsed.isPrerelease != rightParsed.isPrerelease {
            return leftParsed.isPrerelease ? .orderedAscending : .orderedDescending
        }

        return .orderedSame
    }

    /// Devuelve `true` únicamente cuando `candidate` es estrictamente más reciente que `baseline`.
    public static func isNewer(_ candidate: String, than baseline: String) -> Bool {
        compare(candidate, baseline) == .orderedDescending
    }
}

// MARK: - Setup Wizard Steps

/// Los 6 pasos guiados del Asistente de instalación inicial de `MacFileExplorer`.
public enum SetupWizardStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome = 0
    case taskbar = 1
    case altTab = 2
    case notch = 3
    case productivity = 4
    case summary = 5

    public var id: Int { rawValue }

    /// Cantidad total de pasos del asistente (`6`).
    public static var totalCount: Int { allCases.count }

    /// Número de paso visible para el usuario (`1...6`).
    public var stepNumber: Int { rawValue + 1 }

    /// Total de pasos (`6`).
    public var totalSteps: Int { Self.allCases.count }

    /// Cantidad de pasos restantes desde este paso (`5` en el primero, `0` en el último).
    public var remainingSteps: Int { max(0, totalSteps - stepNumber) }

    /// Fracción de avance para barras de progreso (`1/6 ... 6/6`).
    public var progressFraction: Double {
        Double(stepNumber) / Double(totalSteps)
    }

    public var isFirst: Bool { self == .welcome }
    public var isLast: Bool { self == .summary }

    public var next: SetupWizardStep? {
        SetupWizardStep(rawValue: rawValue + 1)
    }

    public var previous: SetupWizardStep? {
        SetupWizardStep(rawValue: rawValue - 1)
    }

    /// Ícono SF Symbol representativo de cada paso.
    public var symbolName: String {
        switch self {
        case .welcome:
            return "sparkles"
        case .taskbar:
            return "dock.rectangle"
        case .altTab:
            return "rectangle.stack.fill"
        case .notch:
            return "waveform"
        case .productivity:
            return "wrench.and.screwdriver.fill"
        case .summary:
            return "checkmark.seal.fill"
        }
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .welcome:
            return loc.text(
                es: "Bienvenido a MacFileExplorer",
                en: "Welcome to MacFileExplorer"
            )
        case .taskbar:
            return loc.text(
                es: "Barra de tareas y Menú Inicio",
                en: "Taskbar & Start Menu"
            )
        case .altTab:
            return loc.text(
                es: "Selector de ventanas AltTab",
                en: "AltTab Window Switcher"
            )
        case .notch:
            return loc.text(
                es: "Reproductor musical «Notch»",
                en: "«Notch» Music Player"
            )
        case .productivity:
            return loc.text(
                es: "Productividad y herramientas rápidas",
                en: "Productivity & Quick Tools"
            )
        case .summary:
            return loc.text(
                es: "Todo listo para empezar",
                en: "Ready to Launch"
            )
        }
    }

    /// Nombre breve ideal para breadcrumbs y botones de edición rápida en el resumen.
    @MainActor
    public func localizedShortTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .welcome:
            return loc.text(es: "Bienvenida", en: "Welcome")
        case .taskbar:
            return loc.text(es: "Barra de tareas", en: "Taskbar")
        case .altTab:
            return "AltTab"
        case .notch:
            return "Notch"
        case .productivity:
            return loc.text(es: "Herramientas", en: "Tools")
        case .summary:
            return loc.text(es: "Resumen", en: "Summary")
        }
    }

    @MainActor
    public func localizedSubtitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .welcome:
            return loc.text(
                es: "Elegí tu idioma e ícono preferido, o instalá la configuración recomendada en un clic. Podés activar o desactivar cualquier módulo después.",
                en: "Pick your language and app icon, or install the recommended setup in one click. Every module can be turned ON or OFF anytime later."
            )
        case .taskbar:
            return loc.text(
                es: "Una barra inferior estilo Windows con un botón por cada ventana abierta, vistas previas al pasar el mouse y Menú Inicio. Tu Dock original queda intacto salvo que elijas ocultarlo.",
                en: "A Windows-style bottom bar showing one button per open window, live hover previews, and a Start Menu. Your original macOS Dock stays untouched unless you choose to hide it."
            )
        case .altTab:
            return loc.text(
                es: "Cambiá entre ventanas individuales con ⌥+Tab, incluso de la misma app o en otros escritorios, con vista previa en grande y búsqueda instantánea.",
                en: "Switch directly between individual windows with ⌥+Tab—even across the same app or other Spaces—with full-size previews and quick search."
            )
        case .notch:
            return loc.text(
                es: "Convertí el Notch (o la parte superior de tu pantalla) en un reproductor fluido para YouTube Music, Spotify y Apple Music con carátula, controles y letras sincronizadas.",
                en: "Turn your MacBook's notch (or the top of any screen) into a fluid music player for YouTube Music, Spotify, and Apple Music with artwork, controls, and synced lyrics."
            )
        case .productivity:
            return loc.text(
                es: "Activá tus utilidades diarias: Historial del Portapapeles (⌃⌘V), acceso en la barra superior, atajo Ver Escritorio (⌘D) y edición rápida de Office/CSV.",
                en: "Choose your everyday utilities: Clipboard History (⌃⌘V), menu bar tray icon, View Desktop shortcut (⌘D), and Quick Look Office/CSV editing."
            )
        case .summary:
            return loc.text(
                es: "Revisá tu configuración antes de empezar. MacFileExplorer solo pide permisos de macOS cuando realmente usás una función que los necesita.",
                en: "Review your selections before getting started. MacFileExplorer only requests macOS permissions when you actually use a feature that needs them."
            )
        }
    }

    /// Etiqueta amigable de avance (ej. `"Paso 2 de 6 · Quedan 4 pasos"` / `"Step 2 of 6 · 4 left"`).
    @MainActor
    public func localizedProgressPill(using loc: LocalizationManager = .shared) -> String {
        if remainingSteps == 0 {
            return loc.text(
                es: "Paso \(stepNumber) de \(totalSteps) · ¡Último paso!",
                en: "Step \(stepNumber) of \(totalSteps) · Final step!"
            )
        }
        if remainingSteps == 1 {
            return loc.text(
                es: "Paso \(stepNumber) de \(totalSteps) · Queda 1 paso",
                en: "Step \(stepNumber) of \(totalSteps) · 1 left"
            )
        }
        return loc.text(
            es: "Paso \(stepNumber) de \(totalSteps) · Quedan \(remainingSteps) pasos",
            en: "Step \(stepNumber) of \(totalSteps) · \(remainingSteps) left"
        )
    }
}

// MARK: - Setup Wizard Draft

/// Borrador editable con todas las preferencias elegibles durante el Asistente de instalación inicial.
///
/// Valores seguros por defecto (`recommendedDefaults()`):
/// - Activos: Explorador, Historial del Portapapeles (`⌃⌘V`), Ver Escritorio (`⌘D`), Editor Office/CSV y Tour interactivo.
/// - Apagados hasta que el usuario los elija: Barra de tareas, AltTab, Notch, Tray Icon y Ocultar Dock de macOS.
public struct SetupWizardDraft: Equatable, Sendable {
    // Paso 1: Bienvenida
    public var languagePreference: AppLanguagePreference
    public var selectedAppIcon: MacFileExplorerAppIcon

    // Paso 2: Barra de tareas y Menú Inicio
    public var enableTaskbar: Bool
    public var taskbarStartOnLaunch: Bool
    public var taskbarBarStyle: TaskbarBarStyle
    public var hideMacOSDock: Bool

    // Paso 3: AltTab
    public var enableAltTab: Bool
    public var altTabStartOnLaunch: Bool
    public var altTabDisplayStyle: AltTabDisplayStyle

    // Paso 4: Notch
    public var enableNotch: Bool
    public var notchStartOnLaunch: Bool
    public var notchPillSize: NotchPillSize

    // Paso 5: Productividad y Tour
    public var enableClipboardHistory: Bool
    public var enableTrayIcon: Bool
    public var enableViewDesktopShortcut: Bool
    public var enableOfficeQuickLookEditor: Bool
    public var startTourAfterSetup: Bool

    public init(
        languagePreference: AppLanguagePreference = .system,
        selectedAppIcon: MacFileExplorerAppIcon = .monoDark,
        enableTaskbar: Bool = false,
        taskbarStartOnLaunch: Bool = false,
        taskbarBarStyle: TaskbarBarStyle = .docked,
        hideMacOSDock: Bool = false,
        enableAltTab: Bool = false,
        altTabStartOnLaunch: Bool = false,
        altTabDisplayStyle: AltTabDisplayStyle = .thumbnails,
        enableNotch: Bool = false,
        notchStartOnLaunch: Bool = false,
        notchPillSize: NotchPillSize = .normal,
        enableClipboardHistory: Bool = true,
        enableTrayIcon: Bool = false,
        enableViewDesktopShortcut: Bool = true,
        enableOfficeQuickLookEditor: Bool = true,
        startTourAfterSetup: Bool = true
    ) {
        self.languagePreference = languagePreference
        self.selectedAppIcon = selectedAppIcon
        self.enableTaskbar = enableTaskbar
        self.taskbarStartOnLaunch = taskbarStartOnLaunch
        self.taskbarBarStyle = taskbarBarStyle
        self.hideMacOSDock = hideMacOSDock
        self.enableAltTab = enableAltTab
        self.altTabStartOnLaunch = altTabStartOnLaunch
        self.altTabDisplayStyle = altTabDisplayStyle
        self.enableNotch = enableNotch
        self.notchStartOnLaunch = notchStartOnLaunch
        self.notchPillSize = notchPillSize
        self.enableClipboardHistory = enableClipboardHistory
        self.enableTrayIcon = enableTrayIcon
        self.enableViewDesktopShortcut = enableViewDesktopShortcut
        self.enableOfficeQuickLookEditor = enableOfficeQuickLookEditor
        self.startTourAfterSetup = startTourAfterSetup
    }

    /// Configuración recomendada y segura para «Instalar por defecto (omitir asistente)».
    public static func recommendedDefaults() -> SetupWizardDraft {
        SetupWizardDraft()
    }
}

// MARK: - Interactive Tour Steps

/// Identificadores estables de anclaje (`.tourTarget(...)`) utilizados por el Tour interactivo.
public enum InteractiveTourTargetID {
    public static let commandBar = "commandBar"
    public static let addressBar = "addressBar"
    public static let sidebar = "sidebar"
    public static let fileArea = "fileArea"
    public static let statusBar = "statusBar"
    public static let topMenus = "topMenus"
    public static let helpAndAbout = "helpAndAbout"
}

/// Las 7 paradas prácticas del Tour interactivo con globitos desplegables sobre la ventana principal.
public enum InteractiveTourStep: Int, CaseIterable, Identifiable, Sendable {
    case commandBar = 0
    case addressBar = 1
    case sidebar = 2
    case fileArea = 3
    case statusBar = 4
    case topMenus = 5
    case helpAndAbout = 6

    public var id: Int { rawValue }

    /// Identificador de ancla usado por `.tourTarget(_:)` en `MainExplorerView`.
    public var targetID: String {
        switch self {
        case .commandBar: return InteractiveTourTargetID.commandBar
        case .addressBar: return InteractiveTourTargetID.addressBar
        case .sidebar: return InteractiveTourTargetID.sidebar
        case .fileArea: return InteractiveTourTargetID.fileArea
        case .statusBar: return InteractiveTourTargetID.statusBar
        case .topMenus: return InteractiveTourTargetID.topMenus
        case .helpAndAbout: return InteractiveTourTargetID.helpAndAbout
        }
    }

    /// Indica si esta parada señala hacia la barra superior de menús de macOS (fuera del contenido de la ventana).
    public var pointsToTopMenuBar: Bool {
        self == .topMenus || self == .helpAndAbout
    }

    public static var totalCount: Int { allCases.count }
    public var stepNumber: Int { rawValue + 1 }
    public var totalSteps: Int { Self.allCases.count }
    public var remainingSteps: Int { max(0, totalSteps - stepNumber) }

    public var isFirst: Bool { self == .commandBar }
    public var isLast: Bool { self == .helpAndAbout }

    public var next: InteractiveTourStep? {
        InteractiveTourStep(rawValue: rawValue + 1)
    }

    public var previous: InteractiveTourStep? {
        InteractiveTourStep(rawValue: rawValue - 1)
    }

    public var symbolName: String {
        switch self {
        case .commandBar:
            return "menubar.rectangle"
        case .addressBar:
            return "magnifyingglass.circle.fill"
        case .sidebar:
            return "sidebar.left"
        case .fileArea:
            return "folder.fill"
        case .statusBar:
            return "arrow.up.arrow.down.circle.fill"
        case .topMenus:
            return "menubar.dock.rectangle"
        case .helpAndAbout:
            return "questionmark.circle.fill"
        }
    }

    @MainActor
    public func localizedBadgeText(using loc: LocalizationManager = .shared) -> String {
        loc.text(
            es: "Tour · \(stepNumber) / \(totalSteps)",
            en: "Tour · \(stepNumber) / \(totalSteps)"
        )
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .commandBar:
            return loc.text(
                es: "Barra de comandos rápida",
                en: "Quick Command Bar"
            )
        case .addressBar:
            return loc.text(
                es: "Barra de direcciones y búsqueda con OCR",
                en: "Editable Address Bar & OCR Search"
            )
        case .sidebar:
            return loc.text(
                es: "Acceso rápido, Google y Portapapeles",
                en: "Quick Access, Google & Clipboard"
            )
        case .fileArea:
            return loc.text(
                es: "Tus archivos, Vista Rápida y Acciones",
                en: "Files, Quick Look & Quick Actions"
            )
        case .statusBar:
            return loc.text(
                es: "Barra de estado, Drive y transferencias",
                en: "Status Bar, Drive & Transfer Queue"
            )
        case .topMenus:
            return loc.text(
                es: "Menús superiores: activá lo que quieras",
                en: "Top Menus: Toggle Any Module Anytime"
            )
        case .helpAndAbout:
            return loc.text(
                es: "Ayuda, Permisos y Acerca de la app",
                en: "Help, Permissions & About"
            )
        }
    }

    @MainActor
    public func localizedBody(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .commandBar:
            return loc.text(
                es: "Creá carpetas o archivos nuevos, cortá, copiá, pegá, renombrá, eliminá, ordená y cambiá entre vista Detalles e Iconos Grandes en un clic.",
                en: "Create new folders or files, cut, copy, paste, rename, delete, sort items, and switch between Details and Large Icons views in a single click."
            )
        case .addressBar:
            return loc.text(
                es: "Hacé clic sobre la ruta (o presioná ⌘L) para escribir o pegar cualquier carpeta. Usá Atrás/Adelante o el buscador con filtros por tipo, tamaño y texto dentro de imágenes (OCR).",
                en: "Click the path bar (or press ⌘L) to type or paste any folder path. Use Back/Forward or the search bar to filter by file type, size, and text inside images (OCR)."
            )
        case .sidebar:
            return loc.text(
                es: "Accedé directo a tus carpetas favoritas, a «Modificados hoy (24h)» y a tus discos. También podés conectar varias cuentas de Google separadas y abrir tu Historial del Portapapeles.",
                en: "Jump straight to favorite folders, «Modified Today (24h)», and external drives. You can also sign in to multiple isolated Google accounts and open your Clipboard History."
            )
        case .fileArea:
            return loc.text(
                es: "Presioná Espacio sobre cualquier archivo para verlo al instante: editá Word, Excel, PowerPoint y CSV, o quitá fondos, rotá y limpiá metadatos en fotos y videos. Con clic derecho tenés más herramientas.",
                en: "Press Space on any file to preview it right away: edit Word, Excel, PowerPoint, and CSV files, or remove backgrounds, rotate, and strip metadata on photos and videos. Right-click unlocks even more tools."
            )
        case .statusBar:
            return loc.text(
                es: "Muestra cuántos archivos seleccionaste y su peso total. Cuando subís a Drive o copiás más de 1 GB, el progreso aparece aquí con controles para pausar, junto al selector de vista y zoom.",
                en: "Shows your selected item count and total size. When sending files to Drive or transferring over 1 GB, live progress with pause controls appears right here beside the quick view & zoom switcher."
            )
        case .topMenus:
            return loc.text(
                es: "En la barra superior de macOS tenés menús dedicados para Barra de tareas, AltTab, Notch, Portapapeles, Office y Archivo → Herramientas y Atajos. Podés prender o apagar cualquier módulo cuando quieras.",
                en: "Your Mac's top menu bar has dedicated menus for Taskbar, AltTab, Notch, Clipboard, Office, and File → Tools & All Shortcuts. Turn any feature ON or OFF whenever you like."
            )
        case .helpAndAbout:
            return loc.text(
                es: "Desde Ayuda (⌘?) podés abrir la guía completa, consultar el uso transparente de permisos de macOS o repetir este tour. En «Acerca de» ves todas las novedades y podés reportar errores o ideas.",
                en: "Open Help (⌘?) anytime for the full guide, our transparent macOS permissions overview, or to replay this tour. Under «About», view release notes and report bugs or ideas in one click."
            )
        }
    }

    @MainActor
    public func localizedShortcutHint(using loc: LocalizationManager = .shared) -> String? {
        switch self {
        case .commandBar:
            return loc.text(es: "⌘X · ⌘C · ⌘V · Enter renombrar", en: "⌘X · ⌘C · ⌘V · Enter rename")
        case .addressBar:
            return loc.text(es: "⌘L editar ruta · ⌘[ / ⌘] historial", en: "⌘L edit path · ⌘[ / ⌘] history")
        case .sidebar:
            return loc.text(es: "⌃⌘V desplegable rápido del Portapapeles", en: "⌃⌘V quick Clipboard dropdown")
        case .fileArea:
            return loc.text(es: "Espacio Vista Rápida · ⌘I Propiedades", en: "Space Quick Look · ⌘I Properties")
        case .statusBar:
            return loc.text(es: "⌘1 Detalles · ⌘2 Iconos grandes", en: "⌘1 Details · ⌘2 Large Icons")
        case .topMenus:
            return loc.text(es: "⌘D Ver Escritorio · ⌥⇥ AltTab", en: "⌘D View Desktop · ⌥⇥ AltTab")
        case .helpAndAbout:
            return loc.text(es: "⌘? abrir Guía de Ayuda", en: "⌘? open Help Guide")
        }
    }
}
