import AppKit
import CoreGraphics
import Foundation

// MARK: - Enumeraciones de Configuración de la Barra de Tareas

/// Ícono predefinido seleccionable para el botón del Menú Inicio en la barra de tareas.
public enum TaskbarStartButtonIcon: String, CaseIterable, Identifiable, Codable, Sendable {
    case windowsGrid
    case macOSApps
    case appleLogo
    case dotsGrid
    case macFileExplorer
    case macFileExplorerMono
    case macFileExplorerLayers
    case macFileExplorerSquircle
    case emonkBrain
    case emonkBrainMono
    case emonkBrainSquircle
    case commandKey

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .windowsGrid: return loc.text(es: "Cuadrícula Windows", en: "Windows Grid")
        case .macOSApps: return loc.text(es: "Apps de macOS", en: "macOS Apps")
        case .appleLogo: return "Apple"
        case .dotsGrid: return loc.text(es: "Cuadrícula 3×3", en: "3×3 Grid")
        case .macFileExplorer: return "MacFileExplorer"
        case .macFileExplorerMono: return "Explorer Mono"
        case .macFileExplorerLayers: return loc.text(es: "Explorer Capas", en: "Explorer Layers")
        case .macFileExplorerSquircle: return loc.text(es: "Explorer Sello", en: "Explorer Badge")
        case .emonkBrain: return "EmonkBrain"
        case .emonkBrainMono: return "EmonkBrain Mono"
        case .emonkBrainSquircle: return loc.text(es: "EmonkBrain Sello", en: "EmonkBrain Badge")
        case .commandKey: return loc.text(es: "Comando (⌘)", en: "Command (⌘)")
        }
    }

    public var menuSymbolName: String {
        switch self {
        case .windowsGrid: return "square.grid.2x2.fill"
        case .macOSApps: return "square.grid.3x2.fill"
        case .appleLogo: return "apple.logo"
        case .dotsGrid: return "circle.grid.3x3.fill"
        case .macFileExplorer: return "folder.fill"
        case .macFileExplorerMono: return "sidebar.left"
        case .macFileExplorerLayers: return "rectangle.stack.fill"
        case .macFileExplorerSquircle: return "folder.badge.gearshape"
        case .emonkBrain: return "brain.head.profile"
        case .emonkBrainMono: return "brain"
        case .emonkBrainSquircle: return "cpu.fill"
        case .commandKey: return "command.square.fill"
        }
    }
}

/// Estilo de animación cuando una aplicación muestra un globo rojo de notificación en la barra de tareas.
public enum TaskbarNotificationAnimation: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case bounce
    case shake
    case pulse
    case flash
    case ripple
    case swing

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .none: return loc.text(es: "Sin animación", en: "None")
        case .bounce: return loc.text(es: "Salto", en: "Bounce")
        case .shake: return loc.text(es: "Campana", en: "Bell Shake")
        case .pulse: return loc.text(es: "Latido", en: "Heartbeat")
        case .flash: return loc.text(es: "Destello", en: "Glow Flash")
        case .ripple: return loc.text(es: "Onda expansiva", en: "Ripple Wave")
        case .swing: return loc.text(es: "Bamboleo", en: "Swing Float")
        }
    }

    @MainActor
    public func localizedSubtitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .none: return loc.text(es: "Solo globo rojo", en: "Static red badge")
        case .bounce: return loc.text(es: "Salto elástico", en: "Elastic hop")
        case .shake: return loc.text(es: "Sacudida de alerta", en: "Ringing wiggle")
        case .pulse: return loc.text(es: "Pulso suave", en: "Double beat")
        case .flash: return loc.text(es: "Brillo en el botón", en: "Button highlight")
        case .ripple: return loc.text(es: "Aros desde el globo", en: "Sonar rings")
        case .swing: return loc.text(es: "Inclinación flotante", en: "Buoyant tilt")
        }
    }

    public var symbolName: String {
        switch self {
        case .none: return "circle.slash"
        case .bounce: return "arrow.up.circle.fill"
        case .shake: return "bell.badge.fill"
        case .pulse: return "heart.circle.fill"
        case .flash: return "sparkles"
        case .ripple: return "dot.radiowaves.left.and.right"
        case .swing: return "metronome.fill"
        }
    }

    /// Duración de un ciclo completo de animación en segundos.
    public var burstDuration: TimeInterval {
        switch self {
        case .none: return 0
        case .bounce: return 0.95
        case .shake: return 0.85
        case .pulse: return 1.05
        case .flash: return 1.15
        case .ripple: return 1.10
        case .swing: return 1.05
        }
    }
}

/// Frecuencia con la que se reproduce la animación de notificación en la barra de tareas.
public enum TaskbarNotificationAnimationCadence: String, CaseIterable, Identifiable, Codable, Sendable {
    case periodic
    case continuous
    case onceOnArrival

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .periodic: return loc.text(es: "Periódica (cada unos segundos)", en: "Periodic (every few seconds)")
        case .continuous: return loc.text(es: "Continua", en: "Continuous")
        case .onceOnArrival: return loc.text(es: "Solo al llegar una notificación", en: "Once on new notification")
        }
    }

    public var symbolName: String {
        switch self {
        case .periodic: return "clock.arrow.2.circlepath"
        case .continuous: return "repeat"
        case .onceOnArrival: return "bell.and.waves.left.and.right"
        }
    }
}

/// Tema visual de la barra de tareas.
public enum TaskbarThemeMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .system: return loc.text(es: "Automático del sistema", en: "System Default")
        case .light: return loc.text(es: "Claro", en: "Light")
        case .dark: return loc.text(es: "Oscuro", en: "Dark")
        }
    }

    public var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

/// Alineación horizontal de los botones de ventanas en la barra.
public enum TaskbarAlignment: String, CaseIterable, Identifiable, Codable, Sendable {
    case left
    case center

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .left: return loc.text(es: "Izquierda", en: "Left")
        case .center: return loc.text(es: "Centrada", en: "Centered")
        }
    }

    public var systemImage: String {
        switch self {
        case .left: return "align.horizontal.left"
        case .center: return "align.horizontal.center"
        }
    }
}

/// En qué monitores se muestra la barra de tareas (hasta 5 pantallas).
public enum TaskbarDisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case allDisplays
    case mainDisplayOnly

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .allDisplays: return loc.text(es: "Todos los monitores (hasta 5)", en: "All Displays (up to 5)")
        case .mainDisplayOnly: return loc.text(es: "Solo pantalla principal", en: "Main Display Only")
        }
    }

    public var systemImage: String {
        switch self {
        case .allDisplays: return "display.2"
        case .mainDisplayOnly: return "display"
        }
    }
}

/// Qué ventanas se listan en cada barra cuando hay múltiples monitores.
public enum TaskbarWindowScopeMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case perDisplay
    case allWindowsOnAllBars

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .perDisplay: return loc.text(es: "Solo ventanas de esa pantalla", en: "Only Windows on That Display")
        case .allWindowsOnAllBars: return loc.text(es: "Todas las ventanas en cada barra", en: "All Windows on Every Bar")
        }
    }

    public var systemImage: String {
        switch self {
        case .perDisplay: return "rectangle.on.rectangle"
        case .allWindowsOnAllBars: return "square.grid.2x2"
        }
    }
}

/// Acción al volver a hacer clic izquierdo en el botón de la ventana actualmente enfocada.
public enum TaskbarFocusedClickAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case minimizeWindow
    case hideApp
    case doNothing

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .minimizeWindow: return loc.text(es: "Minimizar ventana", en: "Minimize Window")
        case .hideApp: return loc.text(es: "Ocultar aplicación", en: "Hide Application")
        case .doNothing: return loc.text(es: "No hacer nada", en: "Do Nothing")
        }
    }
}

/// Tamaño de las miniaturas en vivo mostradas al pasar el cursor.
public enum TaskbarThumbnailSize: String, CaseIterable, Identifiable, Codable, Sendable {
    case small
    case medium
    case large

    public var id: String { rawValue }

    public var maxDimension: CGFloat {
        switch self {
        case .small: return 210
        case .medium: return 290
        case .large: return 380
        }
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .small: return loc.text(es: "Pequeña (210 px)", en: "Small (210 px)")
        case .medium: return loc.text(es: "Mediana (290 px)", en: "Medium (290 px)")
        case .large: return loc.text(es: "Grande (380 px)", en: "Large (380 px)")
        }
    }
}

/// Estilo de animación de entrada/salida de la ventana flotante de vista previa al pasar el cursor por la barra.
public enum TaskbarHoverPreviewAnimation: String, CaseIterable, Identifiable, Codable, Sendable {
    case fadeLift
    case riseFromBar
    case springPop
    case flipReveal

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .fadeLift: return loc.text(es: "Suave", en: "Smooth Fade")
        case .riseFromBar: return loc.text(es: "Desde la barra", en: "Rise from Bar")
        case .springPop: return loc.text(es: "Rebote elástico", en: "Elastic Pop")
        case .flipReveal: return loc.text(es: "Giro 3D", en: "3D Tilt")
        }
    }

    @MainActor
    public func localizedSubtitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .fadeLift: return loc.text(es: "Fundido y elevación", en: "Soft fade & lift")
        case .riseFromBar: return loc.text(es: "Emerge de la barra", en: "Slides out of bar")
        case .springPop: return loc.text(es: "Zoom con resorte", en: "Bouncy spring")
        case .flipReveal: return loc.text(es: "Perspectiva táctil", en: "3D hinge reveal")
        }
    }

    public var symbolName: String {
        switch self {
        case .fadeLift: return "sparkles"
        case .riseFromBar: return "dock.arrow.up.rectangle"
        case .springPop: return "arrow.up.left.and.arrow.down.right"
        case .flipReveal: return "cube.transparent"
        }
    }
}

/// Modo de gestión opcional del Dock nativo de macOS.
/// Por defecto siempre es `.unchanged` (Dock original de macOS activo y sin modificaciones).
public enum TaskbarDockMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case unchanged
    case autoHideLeft
    case autoHideRight
    case fullyHidden

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .unchanged:
            return loc.text(es: "Mantener Dock original de macOS (sin cambios)", en: "Keep Original macOS Dock (Unchanged)")
        case .autoHideLeft:
            return loc.text(es: "Auto-ocultar Dock a la izquierda", en: "Auto-Hide Dock on Left")
        case .autoHideRight:
            return loc.text(es: "Auto-ocultar Dock a la derecha", en: "Auto-Hide Dock on Right")
        case .fullyHidden:
            return loc.text(es: "Ocultar Dock por completo (se restaura al salir)", en: "Fully Hide Dock (Restored on Quit)")
        }
    }

    public var systemImage: String {
        switch self {
        case .unchanged: return "dock.rectangle"
        case .autoHideLeft: return "dock.arrow.up.rectangle"
        case .autoHideRight: return "dock.arrow.down.rectangle"
        case .fullyHidden: return "eye.slash"
        }
    }
}

/// Respaldo serializable de las claves originales de `com.apple.dock` antes de cualquier modificación.
public struct TaskbarDockBackupSnapshot: Codable, Equatable, Sendable {
    public let orientation: String?
    public let autohide: Bool?
    public let autohideDelay: Double?
    public let autohideTimeModifier: Double?
    public let capturedAt: Date

    public init(
        orientation: String?,
        autohide: Bool?,
        autohideDelay: Double?,
        autohideTimeModifier: Double?,
        capturedAt: Date = Date()
    ) {
        self.orientation = orientation
        self.autohide = autohide
        self.autohideDelay = autohideDelay
        self.autohideTimeModifier = autohideTimeModifier
        self.capturedAt = capturedAt
    }
}

// MARK: - Normalización de Nombres de Apps (remueve marcas Unicode invisibles como `\u{200E}` en WhatsApp)

public enum TaskbarStringSanitizer {
    /// Elimina marcas invisibles bidireccionales / de formato Unicode (ej. `\u{200E}` en `‎WhatsApp`)
    /// y espacios sobrantes en los extremos.
    public static func sanitizeDisplayName(_ raw: String) -> String {
        let filteredScalars = raw.unicodeScalars.filter { scalar in
            let v = scalar.value
            // Marcas bidireccionales (LRM, RLM, LRE..RLO, LRI..PDI), BOM y controles invisibles
            if v == 0x200E || v == 0x200F || v == 0xFEFF || v == 0x200B || v == 0x200C || v == 0x200D {
                return false
            }
            if (0x202A...0x202E).contains(v) || (0x2066...0x2069).contains(v) {
                return false
            }
            if CharacterSet.controlCharacters.contains(scalar) {
                return false
            }
            return true
        }
        return String(String.UnicodeScalarView(filteredScalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Detecta si un bundle ID o ruta corresponde a una PWA (Chrome, Edge, Brave, Arc o Safari Web App).
    public static func isWebAppPWA(bundleIdentifier: String, bundleURL: URL?) -> Bool {
        let lowerID = bundleIdentifier.lowercased()
        if lowerID.hasPrefix("com.google.chrome.app.") ||
           lowerID.hasPrefix("com.microsoft.edgemac.app.") ||
           lowerID.hasPrefix("com.brave.browser.app.") ||
           lowerID.hasPrefix("company.thebrowser.browser.app.") ||
           lowerID.hasPrefix("com.apple.safari.webapp.") {
            return true
        }
        if let path = bundleURL?.standardizedFileURL.path(percentEncoded: false).lowercased() {
            if path.contains("/chrome apps") ||
               path.contains("/edge apps") ||
               path.contains("/brave browser apps") ||
               path.contains("/arc apps") {
                return true
            }
        }
        return false
    }
}

// MARK: - Modelos de Ventanas, Apps Fijadas, Apps Instaladas y Monitores

/// Representa una ventana abierta individual (compartida entre Barra de tareas y AltTab).
public struct TaskbarWindowItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let windowID: CGWindowID
    public let pid: pid_t
    public let bundleIdentifier: String
    public let appName: String
    public let appBundleURL: URL?
    public let title: String
    public let frameAX: CGRect
    public let screenID: String
    public let isFocused: Bool
    public let isMinimized: Bool
    public let isAppHidden: Bool
    public let isFullScreen: Bool
    public let badgeLabel: String?
    /// Número de escritorio virtual (`1, 2, 3…`) resuelto vía metadatos de Spaces de macOS (o `nil` si no aplica).
    public let spaceIndex: Int?
    /// Indica si la ventana pertenece al Space activo actual del monitor donde se encuentra.
    public let isOnActiveSpace: Bool
    /// Indica si WindowServer asocia esta ventana a al menos un Space (las pestañas nativas inactivas de `NSWindowTabGroup` tienen `false`).
    public let hasSpaceMembership: Bool
    /// Secuencia monotónica de uso más reciente (MRU) para ordenar el selector AltTab al instante.
    public let lastFocusedOrder: UInt64
    /// Indica que representa una aplicación abierta en macOS que actualmente no tiene ventanas abiertas (como en el Dock).
    public let isWindowlessApp: Bool

    public init(
        id: String? = nil,
        windowID: CGWindowID,
        pid: pid_t,
        bundleIdentifier: String,
        appName: String,
        appBundleURL: URL?,
        title: String,
        frameAX: CGRect,
        screenID: String,
        isFocused: Bool,
        isMinimized: Bool,
        isAppHidden: Bool,
        isFullScreen: Bool,
        badgeLabel: String? = nil,
        spaceIndex: Int? = nil,
        isOnActiveSpace: Bool = true,
        hasSpaceMembership: Bool = true,
        lastFocusedOrder: UInt64 = 0,
        isWindowlessApp: Bool = false
    ) {
        self.id = id ?? "\(pid)-\(windowID)"
        self.windowID = windowID
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.appBundleURL = appBundleURL
        self.title = title
        self.frameAX = frameAX
        self.screenID = screenID
        self.isFocused = isFocused
        self.isMinimized = isMinimized
        self.isAppHidden = isAppHidden
        self.isFullScreen = isFullScreen
        self.badgeLabel = badgeLabel
        self.spaceIndex = spaceIndex
        self.isOnActiveSpace = isOnActiveSpace
        self.hasSpaceMembership = hasSpaceMembership
        self.lastFocusedOrder = lastFocusedOrder
        self.isWindowlessApp = isWindowlessApp
    }

    /// Título legible del botón: usa el título de la ventana si existe o el nombre de la aplicación.
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appName : trimmed
    }

    /// Clave de agrupación por aplicación (prefiere `bundleIdentifier`, con respaldo en `pid`).
    public var appGroupKey: String {
        bundleIdentifier.isEmpty ? "pid:\(pid)" : bundleIdentifier.lowercased()
    }
}

/// Aplicación fijada permanentemente en la barra de tareas y en el Menú Inicio.
public struct TaskbarPinnedApp: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let bundleIdentifier: String
    public let bundlePath: String
    public let displayName: String

    public init(bundleIdentifier: String, bundlePath: String, displayName: String) {
        let normalizedID = bundleIdentifier.isEmpty ? bundlePath : bundleIdentifier
        self.id = normalizedID.lowercased()
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
        self.displayName = displayName
    }

    public var bundleURL: URL {
        URL(fileURLWithPath: bundlePath)
    }
}

/// Aplicación instalada descubierta para el Menú Inicio alfabético.
public struct TaskbarInstalledApp: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let bundleIdentifier: String
    public let name: String
    public let bundleURL: URL
    public let isSystemUtility: Bool

    public init(
        bundleIdentifier: String,
        name: String,
        bundleURL: URL,
        isSystemUtility: Bool = false
    ) {
        let normalizedID = bundleIdentifier.isEmpty ? bundleURL.path(percentEncoded: false) : bundleIdentifier
        self.id = normalizedID.lowercased()
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.bundleURL = bundleURL
        self.isSystemUtility = isSystemUtility
    }

    /// Letra inicial normalizada (`A`–`Z` o `#`) para agrupar el índice alfabético del Menú Inicio.
    public var sectionLetter: String {
        let sanitized = TaskbarStringSanitizer.sanitizeDisplayName(name)
        let folded = sanitized.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard let first = folded.first else { return "#" }
        if first >= "a" && first <= "z" {
            return String(first).uppercased()
        }
        return "#"
    }
}

/// Descriptor geométrico y de identidad de un monitor conectado.
public struct TaskbarScreenDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayID: CGDirectDisplayID
    public let localizedName: String
    /// Rectángulo del monitor en coordenadas Cocoa (origen abajo-izquierda).
    public let frameCocoa: CGRect
    /// Rectángulo del monitor en coordenadas AX/CG (origen arriba-izquierda de la pantalla principal).
    public let frameAX: CGRect
    public let isMain: Bool

    public init(
        id: String,
        displayID: CGDirectDisplayID,
        localizedName: String,
        frameCocoa: CGRect,
        frameAX: CGRect,
        isMain: Bool
    ) {
        self.id = id
        self.displayID = displayID
        self.localizedName = localizedName
        self.frameCocoa = frameCocoa
        self.frameAX = frameAX
        self.isMain = isMain
    }
}

// MARK: - Utilidades Puras de Geometría Multimonitor y Auto-Redimensionamiento

public enum TaskbarGeometry {
    /// Convierte un rectángulo en coordenadas Cocoa (origen abajo-izquierda de la pantalla principal)
    /// a coordenadas AX/CG (origen arriba-izquierda de la pantalla principal).
    public static func cocoaRectToAX(_ cocoaRect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: cocoaRect.origin.x,
            y: primaryScreenHeight - cocoaRect.maxY,
            width: cocoaRect.width,
            height: cocoaRect.height
        )
    }

    /// Convierte un rectángulo en coordenadas AX/CG (arriba-izquierda) a coordenadas Cocoa (abajo-izquierda).
    public static func axRectToCocoa(_ axRect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: axRect.origin.x,
            y: primaryScreenHeight - axRect.maxY,
            width: axRect.width,
            height: axRect.height
        )
    }

    /// Resuelve en qué monitor reside una ventana (coordenadas AX) seleccionando la pantalla con mayor área de intersección,
    /// o la más cercana al centro de la ventana si estuviera parcialmente fuera de pantalla.
    public static func assignScreenID(
        forWindowFrameAX frameAX: CGRect,
        screens: [TaskbarScreenDescriptor]
    ) -> String {
        guard !screens.isEmpty else { return "primary" }

        var bestScreen = screens[0]
        var bestArea: CGFloat = -1

        for screen in screens {
            let intersection = frameAX.intersection(screen.frameAX)
            let area = intersection.isNull ? 0 : (intersection.width * intersection.height)
            if area > bestArea {
                bestArea = area
                bestScreen = screen
            }
        }

        if bestArea > 0 {
            return bestScreen.id
        }

        let center = CGPoint(x: frameAX.midX, y: frameAX.midY)
        return screens.min(by: { lhs, rhs in
            let dl = hypot(center.x - lhs.frameAX.midX, center.y - lhs.frameAX.midY)
            let dr = hypot(center.x - rhs.frameAX.midX, center.y - rhs.frameAX.midY)
            return dl < dr
        })?.id ?? bestScreen.id
    }

    /// Calcula el nuevo frame AX si una ventana se superpone con la franja inferior de la barra de tareas.
    /// Devuelve `nil` si no hay superposición o si la ventana está en pantalla completa/minimizada.
    public static func adjustedFrameAvoidingTaskbar(
        windowFrameAX: CGRect,
        screenFrameAX: CGRect,
        barHeight: CGFloat,
        isFullScreen: Bool,
        isMinimized: Bool,
        minimumWindowHeight: CGFloat = 180
    ) -> CGRect? {
        guard !isFullScreen, !isMinimized, barHeight > 0 else { return nil }
        guard windowFrameAX.width >= 100, windowFrameAX.height >= 60 else { return nil }

        // Verificar que la ventana efectivamente intersecta horizontalmente con esta pantalla
        let horizontalOverlap = min(windowFrameAX.maxX, screenFrameAX.maxX) - max(windowFrameAX.minX, screenFrameAX.minX)
        guard horizontalOverlap > 20 else { return nil }

        let safeBottomAX = screenFrameAX.maxY - barHeight
        let overlap = windowFrameAX.maxY - safeBottomAX
        guard overlap > 1.5 else { return nil }

        // Descartar ventanas que cubren toda la pantalla (pantalla completa personalizada / overlay)
        if abs(windowFrameAX.minY - screenFrameAX.minY) < 2 &&
           abs(windowFrameAX.maxY - screenFrameAX.maxY) < 2 &&
           abs(windowFrameAX.width - screenFrameAX.width) < 4 {
            return nil
        }

        var targetY = windowFrameAX.origin.y
        var targetHeight = windowFrameAX.height - overlap

        let effectiveMinHeight = min(minimumWindowHeight, windowFrameAX.height)
        if targetHeight < effectiveMinHeight {
            let deficit = effectiveMinHeight - targetHeight
            targetHeight = effectiveMinHeight
            targetY = max(screenFrameAX.minY + 24, targetY - deficit)
            // Si aún toca la barra, recortar lo justo para respetar el borde
            let remainingOverlap = (targetY + targetHeight) - safeBottomAX
            if remainingOverlap > 0 {
                targetHeight = max(80, targetHeight - remainingOverlap)
            }
        }

        let adjusted = CGRect(
            x: windowFrameAX.origin.x,
            y: round(targetY),
            width: windowFrameAX.width,
            height: round(targetHeight)
        )

        if abs(adjusted.origin.y - windowFrameAX.origin.y) < 1 &&
           abs(adjusted.height - windowFrameAX.height) < 1 {
            return nil
        }
        return adjusted
    }
}

// MARK: - Motor Determinista de Ordenamiento y Agrupación de Botones

/// Mantiene el orden estable de los botones en la barra de tareas soportando:
/// - Reordenamiento manual por arrastrar y soltar
/// - Preservación exacta de posición al minimizar, restaurar, cambiar de Space o cambiar pestañas nativas
/// - Periodo de gracia ante ausencias transitorias (animaciones de macOS / timeouts breves de AX)
/// - Herencia de ranura en el lugar exacto cuando cambia el ID de pestaña o entre app sin ventanas y ventana abierta
/// - Agrupación opcional de ventanas de una misma aplicación juntas
public struct TaskbarWindowOrderEngine: Sendable {
    public struct SlotMetadata: Sendable, Equatable {
        public let pid: pid_t
        public let appGroupKey: String
        public let frameAX: CGRect
        public let isWindowlessApp: Bool
    }

    /// Lista histórica ordenada de IDs de ventanas conocidos.
    public private(set) var orderedWindowIDs: [String] = []
    private var metadataByID: [String: SlotMetadata] = [:]
    private var missingSinceByID: [String: TimeInterval] = [:]

    /// Tiempo de gracia antes de purgar una ranura ausente de `orderedWindowIDs` (si su app sigue viva).
    public let missingGraceInterval: TimeInterval

    public init(orderedWindowIDs: [String] = [], missingGraceInterval: TimeInterval = 15.0) {
        self.orderedWindowIDs = orderedWindowIDs
        self.missingGraceInterval = missingGraceInterval
    }

    /// Sincroniza la lista de ventanas visibles actuales manteniendo el orden previo,
    /// insertando nuevas ventanas en su ranura heredada, junto a su app (`groupByApp`) o al final.
    public mutating func orderedWindows(
        from currentWindows: [TaskbarWindowItem],
        groupByApp: Bool,
        liveWindowIDsAcrossAllSpaces: Set<String>? = nil,
        runningPIDs: Set<pid_t>? = nil,
        now: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) -> [TaskbarWindowItem] {
        let byID = Dictionary(uniqueKeysWithValues: currentWindows.map { ($0.id, $0) })
        let liveSet = liveWindowIDsAcrossAllSpaces ?? Set(currentWindows.map(\.id))

        // Actualizar metadatos de las ventanas visibles actualmente
        for item in currentWindows {
            metadataByID[item.id] = SlotMetadata(
                pid: item.pid,
                appGroupKey: item.appGroupKey,
                frameAX: item.frameAX,
                isWindowlessApp: item.isWindowlessApp
            )
            missingSinceByID.removeValue(forKey: item.id)
        }

        // Marcar inicio de ausencia para ranuras que ya no figuran en `liveSet`
        for id in orderedWindowIDs {
            if liveSet.contains(id) {
                missingSinceByID.removeValue(forKey: id)
            } else if missingSinceByID[id] == nil {
                missingSinceByID[id] = now
            }
        }

        var knownSet = Set(orderedWindowIDs)

        // Incorporar ventanas nuevas intentando heredar una ranura ausente de la misma app
        let newWindows = currentWindows.filter { !knownSet.contains($0.id) }
        for newWin in newWindows {
            if let inheritedIndex = findInheritableSlotIndex(
                for: newWin,
                liveSet: liveSet,
                currentByID: byID,
                now: now
            ) {
                let replacedID = orderedWindowIDs[inheritedIndex]
                orderedWindowIDs[inheritedIndex] = newWin.id
                knownSet.remove(replacedID)
                knownSet.insert(newWin.id)
                metadataByID.removeValue(forKey: replacedID)
                missingSinceByID.removeValue(forKey: replacedID)
            } else if groupByApp,
                      let lastSiblingIndex = orderedWindowIDs.lastIndex(where: { existingID in
                          (byID[existingID]?.appGroupKey ?? metadataByID[existingID]?.appGroupKey) == newWin.appGroupKey
                      }) {
                orderedWindowIDs.insert(newWin.id, at: lastSiblingIndex + 1)
                knownSet.insert(newWin.id)
            } else {
                orderedWindowIDs.append(newWin.id)
                knownSet.insert(newWin.id)
            }
        }

        // Purgar solo ranuras cuyo proceso ya terminó o que llevan ausentes más que `missingGraceInterval`
        orderedWindowIDs.removeAll { id in
            guard !liveSet.contains(id) else { return false }
            if let runningPIDs, let meta = metadataByID[id], !runningPIDs.contains(meta.pid) {
                metadataByID.removeValue(forKey: id)
                missingSinceByID.removeValue(forKey: id)
                return true
            }
            if let missingSince = missingSinceByID[id], (now - missingSince) >= missingGraceInterval {
                metadataByID.removeValue(forKey: id)
                missingSinceByID.removeValue(forKey: id)
                return true
            }
            return false
        }

        // Construir salida en el orden registrado para las ventanas visibles en este Space/pantalla
        var result = orderedWindowIDs.compactMap { byID[$0] }

        // Si el usuario activó agrupación por app, compactar las ventanas de cada app juntas
        // manteniendo el orden relativo de la primera aparición de cada app.
        if groupByApp && result.count > 1 {
            var seenApps: [String] = []
            var buckets: [String: [TaskbarWindowItem]] = [:]
            for win in result {
                let key = win.appGroupKey
                if buckets[key] == nil {
                    seenApps.append(key)
                    buckets[key] = []
                }
                buckets[key]?.append(win)
            }
            result = seenApps.flatMap { buckets[$0] ?? [] }
            // Reflejar el agrupamiento estable sobre las ventanas visibles
            let visibleIDs = Set(result.map(\.id))
            var rebuilt: [String] = []
            var insertedVisible = false
            for id in orderedWindowIDs {
                if visibleIDs.contains(id) {
                    if !insertedVisible {
                        rebuilt.append(contentsOf: result.map(\.id))
                        insertedVisible = true
                    }
                } else {
                    rebuilt.append(id)
                }
            }
            if !insertedVisible {
                rebuilt.append(contentsOf: result.map(\.id))
            }
            orderedWindowIDs = rebuilt
        }

        return result
    }

    /// Busca una ranura ausente del mismo `pid` que `newWin` deba reemplazar en el mismo lugar
    /// (cambio de pestaña en `NSWindowTabGroup`, transición app sin ventanas ↔ ventana real, o cambio de ID al restaurar).
    private func findInheritableSlotIndex(
        for newWin: TaskbarWindowItem,
        liveSet: Set<String>,
        currentByID: [String: TaskbarWindowItem],
        now: TimeInterval
    ) -> Int? {
        var bestRecentSamePIDIndex: Int?
        var bestRecentMissingAge: TimeInterval = .greatestFiniteMagnitude

        for (index, oldID) in orderedWindowIDs.enumerated() {
            // Nunca robar la ranura de una ventana todavía viva (ej. en otro Space) o visible ahora
            guard !liveSet.contains(oldID), currentByID[oldID] == nil else { continue }
            guard let oldMeta = metadataByID[oldID], oldMeta.pid == newWin.pid else { continue }

            // 1. Transición directa app sin ventanas ↔ ventana real de la misma app (ej. VS Code)
            if oldMeta.isWindowlessApp != newWin.isWindowlessApp {
                return index
            }

            // 2. Cambio de pestaña en el mismo NSWindowTabGroup o restauración en el mismo frameAX
            if !oldMeta.isWindowlessApp && !newWin.isWindowlessApp &&
               oldMeta.frameAX.width >= 100 && oldMeta.frameAX.height >= 60 &&
               newWin.frameAX.width >= 100 && newWin.frameAX.height >= 60 {
                let sameFrame =
                    abs(oldMeta.frameAX.origin.x - newWin.frameAX.origin.x) <= 12 &&
                    abs(oldMeta.frameAX.origin.y - newWin.frameAX.origin.y) <= 12 &&
                    abs(oldMeta.frameAX.width - newWin.frameAX.width) <= 12 &&
                    abs(oldMeta.frameAX.height - newWin.frameAX.height) <= 12
                if sameFrame {
                    return index
                }
            }

            // 3. Respaldo: ventana del mismo PID desaparecida hace <= 6s (ej. ID reconstruido al restaurar)
            let age = now - (missingSinceByID[oldID] ?? now)
            if age <= 6.0 && age < bestRecentMissingAge {
                bestRecentMissingAge = age
                bestRecentSamePIDIndex = index
            }
        }

        return bestRecentSamePIDIndex
    }

    /// Reordena manualmente un botón moviendo `sourceID` a la posición ocupada por `targetID`.
    public mutating func moveWindow(
        sourceID: String,
        toTargetID targetID: String,
        visibleWindows: [TaskbarWindowItem],
        groupByApp: Bool
    ) {
        guard sourceID != targetID else { return }
        let byID = Dictionary(uniqueKeysWithValues: visibleWindows.map { ($0.id, $0) })

        if groupByApp,
           let sourceWin = byID[sourceID],
           let targetWin = byID[targetID],
           sourceWin.appGroupKey != targetWin.appGroupKey {
            // Al mover hacia otra app en modo agrupado, mover todo el bloque de la app origen
            let sourceGroupIDs = orderedWindowIDs.filter { byID[$0]?.appGroupKey == sourceWin.appGroupKey }
            guard !sourceGroupIDs.isEmpty else { return }
            let sourceSet = Set(sourceGroupIDs)
            guard let sourceFirstIndex = orderedWindowIDs.firstIndex(where: { sourceSet.contains($0) }),
                  let targetIndexBefore = orderedWindowIDs.firstIndex(of: targetID) else {
                return
            }
            let movingRight = sourceFirstIndex < targetIndexBefore
            orderedWindowIDs.removeAll { sourceSet.contains($0) }
            guard let targetIndex = orderedWindowIDs.firstIndex(of: targetID) else {
                orderedWindowIDs.append(contentsOf: sourceGroupIDs)
                return
            }
            let insertionIndex: Int
            if movingRight {
                // Insertar después del bloque de la app destino
                let lastTargetGroupIndex = orderedWindowIDs.lastIndex(where: { byID[$0]?.appGroupKey == targetWin.appGroupKey }) ?? targetIndex
                insertionIndex = lastTargetGroupIndex + 1
            } else {
                let firstTargetGroupIndex = orderedWindowIDs.firstIndex(where: { byID[$0]?.appGroupKey == targetWin.appGroupKey }) ?? targetIndex
                insertionIndex = firstTargetGroupIndex
            }
            orderedWindowIDs.insert(contentsOf: sourceGroupIDs, at: min(insertionIndex, orderedWindowIDs.count))
            return
        }

        guard let fromIndex = orderedWindowIDs.firstIndex(of: sourceID),
              let toIndex = orderedWindowIDs.firstIndex(of: targetID) else {
            return
        }
        let item = orderedWindowIDs.remove(at: fromIndex)
        orderedWindowIDs.insert(item, at: toIndex)
    }
}

// MARK: - Deduplicador de Pestañas Nativas de macOS (`NSWindowTabGroup`)

/// Evita que las pestañas inactivas dentro de un mismo grupo nativo de pestañas de macOS
/// (ej. Fork, Finder, Terminal, Safari, Xcode, Numbers, Preview) aparezcan como múltiples botones
/// al minimizarse u ocultarse la ventana, sin colapsar jamás dos ventanas independientes reales.
public enum TaskbarTabGroupDeduplicator {
    private struct TabClusterKey: Hashable {
        let pid: pid_t
        let isMinimized: Bool
        let isAppHidden: Bool
        let qx: Int
        let qy: Int
        let qw: Int
        let qh: Int
    }

    public static func deduplicate(
        _ items: [TaskbarWindowItem],
        preferredOrderIDs: [String] = []
    ) -> [TaskbarWindowItem] {
        guard items.count > 1 else { return items }

        let preferredRankByID: [String: Int] = Dictionary(
            preferredOrderIDs.enumerated().map { ($0.element, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )

        var buckets: [TabClusterKey: [TaskbarWindowItem]] = [:]
        var orderedKeys: [TabClusterKey] = []

        for item in items {
            // Las apps abiertas sin ventanas nunca se fusionan en clusters de pestañas
            if item.isWindowlessApp { continue }
            let key = TabClusterKey(
                pid: item.pid,
                isMinimized: item.isMinimized,
                isAppHidden: item.isAppHidden,
                qx: Int((item.frameAX.origin.x / 2.0).rounded()),
                qy: Int((item.frameAX.origin.y / 2.0).rounded()),
                qw: Int((item.frameAX.width / 2.0).rounded()),
                qh: Int((item.frameAX.height / 2.0).rounded())
            )
            if buckets[key] == nil {
                orderedKeys.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(item)
        }

        var keptIDs = Set<String>(items.filter(\.isWindowlessApp).map(\.id))
        for key in orderedKeys {
            guard let cluster = buckets[key] else { continue }
            if cluster.count == 1 {
                keptIDs.insert(cluster[0].id)
                continue
            }

            let withSpace = cluster.filter(\.hasSpaceMembership)
            let withoutSpace = cluster.filter { !$0.hasSpaceMembership }

            if !withSpace.isEmpty && !withoutSpace.isEmpty {
                // Caso estándar macOS NSWindowTabGroup: solo la pestaña activa tiene Space asignado (`spaces=[1]`)
                // y las pestañas inactivas tienen `spaces=[]`. Conservamos todas las que tienen Space real
                // (preservando también ventanas independientes reales con el mismo tamaño).
                for realWin in withSpace {
                    keptIDs.insert(realWin.id)
                }
            } else if key.isMinimized || key.isAppHidden {
                // Respaldo para apps/versiones donde todas las pestañas minimizadas/ocultas de un mismo grupo
                // reportan igual estado de Space y exacto mismo frameAX: conservar únicamente 1 representante
                // (priorizando el ID que ya tenía posición en la barra y el foco previo MRU).
                if let best = selectBestRepresentative(from: cluster, preferredRankByID: preferredRankByID) {
                    keptIDs.insert(best.id)
                }
            } else {
                // Ventanas abiertas independientes que casualmente comparten posición y tamaño exactos: mantener todas
                for win in cluster {
                    keptIDs.insert(win.id)
                }
            }
        }

        return items.filter { keptIDs.contains($0.id) }
    }

    private static func selectBestRepresentative(
        from cluster: [TaskbarWindowItem],
        preferredRankByID: [String: Int]
    ) -> TaskbarWindowItem? {
        cluster.max { lhs, rhs in
            if lhs.isFocused != rhs.isFocused { return !lhs.isFocused }
            if lhs.hasSpaceMembership != rhs.hasSpaceMembership { return !lhs.hasSpaceMembership }
            if lhs.isOnActiveSpace != rhs.isOnActiveSpace { return !lhs.isOnActiveSpace }
            let lhsHasSlot = preferredRankByID[lhs.id] != nil
            let rhsHasSlot = preferredRankByID[rhs.id] != nil
            if lhsHasSlot != rhsHasSlot { return !lhsHasSlot }
            if lhs.lastFocusedOrder != rhs.lastFocusedOrder { return lhs.lastFocusedOrder < rhs.lastFocusedOrder }
            // Menor windowID como desempate determinista (suele ser la ventana principal del tab group)
            return lhs.windowID > rhs.windowID
        }
    }
}

// MARK: - Filtrado de Aplicaciones del Menú Inicio

public enum TaskbarStartMenuFilter {
    /// Filtra aplicaciones instaladas con coincidencia insensible a mayúsculas/acentos,
    /// priorizando coincidencias al inicio del nombre.
    public static func filter(apps: [TaskbarInstalledApp], query: String) -> [TaskbarInstalledApp] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return apps }

        let foldedQuery = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let tokens = foldedQuery.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return apps }

        let scored: [(app: TaskbarInstalledApp, score: Int)] = apps.compactMap { app in
            let foldedName = TaskbarStringSanitizer.sanitizeDisplayName(app.name)
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            let foldedBundle = app.bundleIdentifier.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            guard tokens.allSatisfy({ foldedName.contains($0) || foldedBundle.contains($0) }) else {
                return nil
            }
            if foldedName == foldedQuery {
                return (app, 0)
            } else if foldedName.hasPrefix(foldedQuery) {
                return (app, 1)
            } else if tokens.allSatisfy({ foldedName.contains($0) }) {
                return (app, 2)
            } else {
                return (app, 3)
            }
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score < rhs.score }
                return lhs.app.name.localizedStandardCompare(rhs.app.name) == .orderedAscending
            }
            .map(\.app)
    }
}
