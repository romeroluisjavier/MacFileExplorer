import AppKit
import CoreGraphics
import Foundation
import SwiftUI

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
    case brain
    case brainMono
    case brainSquircle
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
        case .brain: return "Brain"
        case .brainMono: return "Brain Mono"
        case .brainSquircle: return loc.text(es: "Brain Sello", en: "Brain Badge")
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
        case .brain: return "brain.head.profile"
        case .brainMono: return "brain"
        case .brainSquircle: return "cpu.fill"
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

/// Modo de visualización de las ventanas minimizadas u ocultas cuando la barra muestra títulos.
public enum TaskbarMinimizedWindowDisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case sameAsNormal
    case iconOnly

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .sameAsNormal: return loc.text(es: "Como ahora (con título)", en: "Same as open (with title)")
        case .iconOnly: return loc.text(es: "Solo ícono", en: "Icon only")
        }
    }

    public var systemImage: String {
        switch self {
        case .sameAsNormal: return "rectangle.leadinghalf.inset.filled"
        case .iconOnly: return "app.dashed"
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

/// Categoría visual de cada animación de apertura del Menú Inicio.
public enum TaskbarStartMenuAnimationCategory: String, Sendable {
    case classic
    case professional
    case fun

    @MainActor
    public func localizedBadge(using loc: LocalizationManager = .shared) -> String? {
        switch self {
        case .classic: return nil
        case .professional: return loc.text(es: "Pro", en: "Pro")
        case .fun: return loc.text(es: "Divertida", en: "Fun")
        }
    }
}

/// Fotograma paramétrico unificado de despliegue del Menú Inicio (compartido entre el panel real y las vistas previas).
public struct TaskbarStartMenuMotionFrame: Equatable, Sendable {
    public let opacity: Double
    public let scaleX: CGFloat
    public let scaleY: CGFloat
    public let offsetX: CGFloat
    public let offsetY: CGFloat
    public let rotationX: Double
    public let rotationZ: Double
    /// Fracción oculta desde arriba (`0` = totalmente visible, `1` = totalmente recortado hacia abajo).
    public let clipTopFraction: CGFloat
    public let blurRadius: CGFloat

    public static let identity = TaskbarStartMenuMotionFrame(
        opacity: 1.0,
        scaleX: 1.0,
        scaleY: 1.0,
        offsetX: 0.0,
        offsetY: 0.0,
        rotationX: 0.0,
        rotationZ: 0.0,
        clipTopFraction: 0.0,
        blurRadius: 0.0
    )

    public init(
        opacity: Double,
        scaleX: CGFloat = 1.0,
        scaleY: CGFloat = 1.0,
        offsetX: CGFloat = 0.0,
        offsetY: CGFloat = 0.0,
        rotationX: Double = 0.0,
        rotationZ: Double = 0.0,
        clipTopFraction: CGFloat = 0.0,
        blurRadius: CGFloat = 0.0
    ) {
        self.opacity = opacity
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.rotationX = rotationX
        self.rotationZ = rotationZ
        self.clipTopFraction = clipTopFraction
        self.blurRadius = blurRadius
    }
}

/// 8 animaciones de despliegue del Menú Inicio:
/// 4 clásicas (misma familia que la vista previa de la barra), 2 profesionales y 2 divertidas.
public enum TaskbarStartMenuAnimation: String, CaseIterable, Identifiable, Codable, Sendable {
    // 4 Clásicas (similares a la barra de tareas)
    case fadeLift
    case riseFromBar
    case springPop
    case flipReveal
    // 2 Profesionales
    case executiveCurtain
    case spotlightFocus
    // 2 Divertidas
    case jellyBounce
    case twirlGenie

    public var id: String { rawValue }

    public var category: TaskbarStartMenuAnimationCategory {
        switch self {
        case .fadeLift, .riseFromBar, .springPop, .flipReveal:
            return .classic
        case .executiveCurtain, .spotlightFocus:
            return .professional
        case .jellyBounce, .twirlGenie:
            return .fun
        }
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .fadeLift: return loc.text(es: "Suave", en: "Smooth Fade")
        case .riseFromBar: return loc.text(es: "Desde la barra", en: "Rise from Bar")
        case .springPop: return loc.text(es: "Rebote elástico", en: "Elastic Pop")
        case .flipReveal: return loc.text(es: "Giro 3D", en: "3D Hinge")
        case .executiveCurtain: return loc.text(es: "Cortina ejecutiva", en: "Executive Curtain")
        case .spotlightFocus: return loc.text(es: "Enfoque Spotlight", en: "Spotlight Focus")
        case .jellyBounce: return loc.text(es: "Gelatina", en: "Jelly Bounce")
        case .twirlGenie: return loc.text(es: "Genio giratorio", en: "Genie Twirl")
        }
    }

    @MainActor
    public func localizedSubtitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .fadeLift: return loc.text(es: "Fundido y elevación", en: "Soft fade & lift")
        case .riseFromBar: return loc.text(es: "Emerge de la barra", en: "Slides out of bar")
        case .springPop: return loc.text(es: "Zoom con resorte", en: "Bouncy spring")
        case .flipReveal: return loc.text(es: "Bisagra en 3D", en: "3D hinge reveal")
        case .executiveCurtain: return loc.text(es: "Despliegue sobrio Pro", en: "Crisp curtain unfold")
        case .spotlightFocus: return loc.text(es: "Micro-enfoque Pro", en: "Precision focus zoom")
        case .jellyBounce: return loc.text(es: "Estiramiento gomoso", en: "Squash & stretch")
        case .twirlGenie: return loc.text(es: "Giro desde Inicio", en: "Playful swoop twirl")
        }
    }

    public var symbolName: String {
        switch self {
        case .fadeLift: return "sparkles"
        case .riseFromBar: return "dock.arrow.up.rectangle"
        case .springPop: return "arrow.up.left.and.arrow.down.right"
        case .flipReveal: return "cube.transparent"
        case .executiveCurtain: return "rectangle.topthird.inset.filled"
        case .spotlightFocus: return "viewfinder"
        case .jellyBounce: return "water.waves"
        case .twirlGenie: return "wand.and.stars"
        }
    }

    /// Evalúa de forma pura y determinista el estado visual para `progress ∈ [0, 1]`.
    /// En `progress >= 0.999` devuelve exactamente `.identity` (sin residuos de escala/rotación/blur).
    /// `motionScale` permite reutilizar la misma curva tanto en el panel real (`1.0`) como en mini-tarjetas (`0.42`).
    public func evaluate(progress rawProgress: Double, motionScale: CGFloat = 1.0) -> TaskbarStartMenuMotionFrame {
        let p = max(0.0, min(1.0, rawProgress))
        if p >= 0.999 {
            return .identity
        }

        switch self {
        case .fadeLift:
            let e = 1.0 - pow(1.0 - p, 3.0)
            return TaskbarStartMenuMotionFrame(
                opacity: e,
                scaleX: CGFloat(0.95 + 0.05 * e),
                scaleY: CGFloat(0.95 + 0.05 * e),
                offsetY: CGFloat(14.0 * (1.0 - e)) * motionScale
            )

        case .riseFromBar:
            let e = 1.0 - pow(1.0 - p, 3.2)
            return TaskbarStartMenuMotionFrame(
                opacity: min(1.0, p / 0.25),
                scaleX: CGFloat(0.985 + 0.015 * e),
                scaleY: CGFloat(0.985 + 0.015 * e),
                offsetY: CGFloat(58.0 * (1.0 - e)) * motionScale
            )

        case .springPop:
            let s = 1.0 - exp(-6.8 * p) * cos(11.5 * p)
            let scale = CGFloat(0.78 + 0.22 * s)
            return TaskbarStartMenuMotionFrame(
                opacity: min(1.0, p / 0.22),
                scaleX: scale,
                scaleY: scale,
                offsetY: CGFloat(22.0 * (1.0 - min(1.12, s))) * motionScale
            )

        case .flipReveal:
            let e = 1.0 - pow(1.0 - p, 3.0)
            let scale = CGFloat(0.93 + 0.07 * e)
            return TaskbarStartMenuMotionFrame(
                opacity: min(1.0, p / 0.28),
                scaleX: scale,
                scaleY: scale,
                offsetY: CGFloat(18.0 * (1.0 - e)) * motionScale,
                rotationX: 40.0 * (1.0 - e)
            )

        case .executiveCurtain:
            let e = 1.0 - pow(1.0 - p, 4.0)
            let scale = CGFloat(0.992 + 0.008 * e)
            return TaskbarStartMenuMotionFrame(
                opacity: 0.35 + 0.65 * min(1.0, p / 0.35),
                scaleX: scale,
                scaleY: scale,
                offsetY: CGFloat(14.0 * (1.0 - e)) * motionScale,
                clipTopFraction: CGFloat(max(0.0, 1.0 - e))
            )

        case .spotlightFocus:
            let e = 1.0 - pow(1.0 - p, 3.5)
            let fade = 1.0 - pow(1.0 - min(1.0, p / 0.72), 2.6)
            let scale = CGFloat(1.055 - 0.055 * e)
            return TaskbarStartMenuMotionFrame(
                opacity: fade,
                scaleX: scale,
                scaleY: scale,
                offsetY: CGFloat(-6.0 * (1.0 - e)) * motionScale,
                blurRadius: CGFloat(5.5 * (1.0 - e)) * max(0.45, motionScale)
            )

        case .jellyBounce:
            let rise = 1.0 - exp(-6.0 * p) * cos(9.0 * p)
            let wobble = exp(-5.0 * p) * sin(16.5 * p)
            let base = min(1.05, rise)
            let sx = CGFloat((0.72 + 0.28 * base) - 0.14 * wobble)
            let sy = CGFloat((0.68 + 0.32 * base) + 0.18 * wobble)
            return TaskbarStartMenuMotionFrame(
                opacity: min(1.0, p / 0.18),
                scaleX: max(0.55, sx),
                scaleY: max(0.55, sy),
                offsetY: CGFloat(38.0 * (1.0 - min(1.08, rise))) * motionScale
            )

        case .twirlGenie:
            let e = 1.0 - pow(1.0 - p, 3.0)
            let spring = 1.0 - exp(-6.2 * p) * cos(10.0 * p)
            let scale = CGFloat(max(0.42, 0.46 + 0.54 * spring))
            let rotZ = -13.0 * (1.0 - e) + 4.5 * exp(-5.5 * p) * sin(12.0 * p)
            return TaskbarStartMenuMotionFrame(
                opacity: min(1.0, p / 0.20),
                scaleX: scale,
                scaleY: scale,
                offsetX: CGFloat(-52.0 * (1.0 - e)) * motionScale,
                offsetY: CGFloat(44.0 * (1.0 - e)) * motionScale,
                rotationZ: rotZ
            )
        }
    }
}

/// Geometría visual de la barra de tareas: acoplada al borde inferior o isla flotante redondeada.
public enum TaskbarBarStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case docked
    case floatingIsland

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .docked: return loc.text(es: "Acoplada al borde", en: "Edge-to-Edge")
        case .floatingIsland: return loc.text(es: "Isla flotante", en: "Floating Island")
        }
    }
}

/// Material / desenfoque de fondo de la barra de tareas.
public enum TaskbarBackgroundMaterial: String, CaseIterable, Identifiable, Codable, Sendable {
    case frostedGlass
    case crystalBlur
    case solid

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .frostedGlass: return loc.text(es: "Vidrio esmerilado", en: "Frosted Glass")
        case .crystalBlur: return loc.text(es: "Cristal translúcido", en: "Crystal Translucent")
        case .solid: return loc.text(es: "Sólido", en: "Solid Matte")
        }
    }
}

/// Estilo visual de los botones de ventanas en la barra de tareas.
public enum TaskbarButtonStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case roundedCard
    case pill
    case minimalBorderless

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .roundedCard: return loc.text(es: "Tarjeta", en: "Card")
        case .pill: return loc.text(es: "Píldora", en: "Pill")
        case .minimalBorderless: return loc.text(es: "Sin borde", en: "Borderless")
        }
    }
}

/// Forma del indicador visual inferior que señala la ventana enfocada actualmente.
public enum TaskbarActiveIndicatorStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case pill
    case fullUnderline
    case dot
    case none

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .pill: return loc.text(es: "Píldora", en: "Pill")
        case .fullUnderline: return loc.text(es: "Barra completa", en: "Full Bar")
        case .dot: return loc.text(es: "Punto", en: "Dot")
        case .none: return loc.text(es: "Oculto", en: "Hidden")
        }
    }
}

/// Color de acento para el indicador de ventana activa en la barra de tareas.
public enum TaskbarActiveIndicatorColor: String, CaseIterable, Identifiable, Codable, Sendable {
    case systemAccent
    case neutral
    case emerald
    case amber
    case coral
    case purple

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .systemAccent: return loc.text(es: "Sistema", en: "System")
        case .neutral: return loc.text(es: "Neutro", en: "Neutral")
        case .emerald: return loc.text(es: "Esmeralda", en: "Emerald")
        case .amber: return loc.text(es: "Ámbar", en: "Amber")
        case .coral: return loc.text(es: "Coral", en: "Coral")
        case .purple: return loc.text(es: "Violeta", en: "Purple")
        }
    }

    public func resolvedColor(effectiveDark: Bool) -> Color {
        switch self {
        case .systemAccent:
            return Color.accentColor
        case .neutral:
            return effectiveDark ? Color.white.opacity(0.92) : Color(white: 0.16)
        case .emerald:
            return Color(red: 0.16, green: 0.80, blue: 0.50)
        case .amber:
            return Color(red: 0.98, green: 0.70, blue: 0.14)
        case .coral:
            return Color(red: 1.0, green: 0.36, blue: 0.34)
        case .purple:
            return Color(red: 0.64, green: 0.42, blue: 1.0)
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

    /// Clave de agrupación por aplicación (prefiere `bundleIdentifier`, luego ruta del bundle y finalmente `pid`).
    public var appGroupKey: String {
        if !bundleIdentifier.isEmpty {
            return bundleIdentifier.lowercased()
        }
        if let bundlePath = appBundleURL?.standardizedFileURL.path(percentEncoded: false), !bundlePath.isEmpty {
            return "path:\(bundlePath.lowercased())"
        }
        return "pid:\(pid)"
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
        public let bundleIdentifier: String
        public let bundlePathLowercased: String
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
    /// insertando nuevas ventanas en su ranura heredada, junto a su app (`groupByApp`) o al final,
    /// y opcionalmente priorizando las ventanas de apps fijadas en su mismo orden (`pinnedAppsForOrdering`).
    public mutating func orderedWindows(
        from currentWindows: [TaskbarWindowItem],
        groupByApp: Bool,
        pinnedAppsForOrdering: [TaskbarPinnedApp]? = nil,
        liveWindowIDsAcrossAllSpaces: Set<String>? = nil,
        runningPIDs: Set<pid_t>? = nil,
        now: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) -> [TaskbarWindowItem] {
        let byID = Dictionary(uniqueKeysWithValues: currentWindows.map { ($0.id, $0) })
        let liveSet = liveWindowIDsAcrossAllSpaces ?? Set(currentWindows.map(\.id))

        // Actualizar metadatos de las ventanas visibles actualmente
        for item in currentWindows {
            let normalizedPath = item.appBundleURL?.standardizedFileURL.path(percentEncoded: false).lowercased() ?? ""
            metadataByID[item.id] = SlotMetadata(
                pid: item.pid,
                appGroupKey: item.appGroupKey,
                bundleIdentifier: item.bundleIdentifier,
                bundlePathLowercased: normalizedPath,
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

        // Si el usuario activó agrupación por app, compactar TODA la lista `orderedWindowIDs`
        // por `appGroupKey` preservando el orden de primera aparición de cada aplicación.
        // Así las ventanas de la misma app quedan siempre contiguas (lado a lado) incluso al abrir
        // una nueva ventana mucho tiempo después o al volver de otros Spaces, sin desplazar otras apps.
        if groupByApp && orderedWindowIDs.count > 1 {
            var seenApps: [String] = []
            var buckets: [String: [String]] = [:]
            for id in orderedWindowIDs {
                let key = byID[id]?.appGroupKey ?? metadataByID[id]?.appGroupKey ?? "id:\(id)"
                if buckets[key] == nil {
                    seenApps.append(key)
                    buckets[key] = []
                }
                buckets[key]?.append(id)
            }
            orderedWindowIDs = seenApps.flatMap { buckets[$0] ?? [] }
        }

        // Si el usuario activó priorizar apps fijadas, colocar primero las ventanas de cada app fijada
        // exactamente en el mismo orden en que están fijadas, y al final las apps no fijadas (preservando el orden relativo).
        if let pinnedApps = pinnedAppsForOrdering, !pinnedApps.isEmpty, orderedWindowIDs.count > 1 {
            let normalizedPinned: [(bundleIDLower: String, pathLower: String, idLower: String)] = pinnedApps.map { pinned in
                let stdPath = pinned.bundlePath.isEmpty
                    ? ""
                    : URL(fileURLWithPath: pinned.bundlePath).standardizedFileURL.path(percentEncoded: false).lowercased()
                return (pinned.bundleIdentifier.lowercased(), stdPath, pinned.id.lowercased())
            }

            var pinnedBuckets: [[String]] = Array(repeating: [], count: normalizedPinned.count)
            var unpinnedIDs: [String] = []
            unpinnedIDs.reserveCapacity(orderedWindowIDs.count)

            for id in orderedWindowIDs {
                let item = byID[id]
                let meta = metadataByID[id]
                let bundleIDLower = (item?.bundleIdentifier ?? meta?.bundleIdentifier ?? "").lowercased()
                let pathLower: String = {
                    if let url = item?.appBundleURL {
                        return url.standardizedFileURL.path(percentEncoded: false).lowercased()
                    }
                    return meta?.bundlePathLowercased ?? ""
                }()
                let groupKeyLower = (item?.appGroupKey ?? meta?.appGroupKey ?? "").lowercased()

                let matchedIndex = normalizedPinned.firstIndex { pinned in
                    if !pinned.bundleIDLower.isEmpty && !bundleIDLower.isEmpty && pinned.bundleIDLower == bundleIDLower {
                        return true
                    }
                    if !pinned.pathLower.isEmpty && !pathLower.isEmpty && pinned.pathLower == pathLower {
                        return true
                    }
                    if !pinned.idLower.isEmpty && !groupKeyLower.isEmpty && pinned.idLower == groupKeyLower {
                        return true
                    }
                    return false
                }

                if let matchedIndex {
                    pinnedBuckets[matchedIndex].append(id)
                } else {
                    unpinnedIDs.append(id)
                }
            }

            var combined: [String] = []
            combined.reserveCapacity(orderedWindowIDs.count)
            for bucket in pinnedBuckets {
                combined.append(contentsOf: bucket)
            }
            combined.append(contentsOf: unpinnedIDs)
            orderedWindowIDs = combined
        }

        // Construir salida en el orden registrado para las ventanas visibles en este Space/pantalla
        return orderedWindowIDs.compactMap { byID[$0] }
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
            // Al mover hacia otra app en modo agrupado, mover todo el bloque de la app origen (incluyendo otros Spaces)
            let metadataSnapshot = metadataByID
            let groupKeyForID: (String) -> String? = { id in
                byID[id]?.appGroupKey ?? metadataSnapshot[id]?.appGroupKey
            }
            let sourceGroupIDs = orderedWindowIDs.filter { groupKeyForID($0) == sourceWin.appGroupKey }
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
                // Insertar después del bloque completo de la app destino
                let lastTargetGroupIndex = orderedWindowIDs.lastIndex(where: { groupKeyForID($0) == targetWin.appGroupKey }) ?? targetIndex
                insertionIndex = lastTargetGroupIndex + 1
            } else {
                let firstTargetGroupIndex = orderedWindowIDs.firstIndex(where: { groupKeyForID($0) == targetWin.appGroupKey }) ?? targetIndex
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

// MARK: - Activación por Permanencia al Arrastrar Archivos sobre la Barra (Spring-Loading 1 s)

/// Estado visual de carga mientras el usuario mantiene un archivo arrastrado sobre un botón de la barra.
public struct TaskbarDragHoverState: Equatable, Sendable {
    public var isHovering: Bool
    /// Progreso normalizado `0...1` durante la espera quieta antes de enfocar la aplicación/ventana.
    public var progress: CGFloat
    /// `true` una vez cumplida la espera y elevada la ventana/aplicación objetivo.
    public var didActivate: Bool

    public static let idle = TaskbarDragHoverState(isHovering: false, progress: 0, didActivate: false)

    public init(isHovering: Bool, progress: CGFloat, didActivate: Bool) {
        self.isHovering = isHovering
        self.progress = progress
        self.didActivate = didActivate
    }
}

/// Máquina de estados determinista que mide permanencia quieta durante un arrastre (`NSDraggingSession`)
/// con tolerancia a micro-movimientos de la mano antes de disparar la apertura/enfoque de la app objetivo.
public struct TaskbarDragDwellTracker: Sendable {
    public static let defaultDwellDuration: TimeInterval = 1.0
    public static let defaultJitterTolerance: CGFloat = 18.0

    public let dwellDuration: TimeInterval
    public let jitterTolerance: CGFloat

    public private(set) var isActive: Bool = false
    public private(set) var didTrigger: Bool = false
    public private(set) var anchorLocation: CGPoint = .zero
    public private(set) var stillSince: TimeInterval = 0

    public init(
        dwellDuration: TimeInterval = Self.defaultDwellDuration,
        jitterTolerance: CGFloat = Self.defaultJitterTolerance
    ) {
        self.dwellDuration = max(0.05, dwellDuration)
        self.jitterTolerance = max(0, jitterTolerance)
    }

    @discardableResult
    public mutating func begin(at location: CGPoint, now: TimeInterval) -> TaskbarDragHoverState {
        isActive = true
        didTrigger = false
        anchorLocation = location
        stillSince = now
        return TaskbarDragHoverState(isHovering: true, progress: 0, didActivate: false)
    }

    @discardableResult
    public mutating func update(location: CGPoint, now: TimeInterval) -> (state: TaskbarDragHoverState, shouldTriggerNow: Bool) {
        guard isActive else {
            return (begin(at: location, now: now), false)
        }
        if didTrigger {
            return (TaskbarDragHoverState(isHovering: true, progress: 1.0, didActivate: true), false)
        }
        let distance = hypot(location.x - anchorLocation.x, location.y - anchorLocation.y)
        if distance > jitterTolerance {
            anchorLocation = location
            stillSince = now
            return (TaskbarDragHoverState(isHovering: true, progress: 0, didActivate: false), false)
        }
        return evaluate(now: now)
    }

    public mutating func evaluate(now: TimeInterval) -> (state: TaskbarDragHoverState, shouldTriggerNow: Bool) {
        guard isActive else {
            return (.idle, false)
        }
        if didTrigger {
            return (TaskbarDragHoverState(isHovering: true, progress: 1.0, didActivate: true), false)
        }
        let elapsed = max(0, now - stillSince)
        if elapsed >= dwellDuration {
            didTrigger = true
            return (TaskbarDragHoverState(isHovering: true, progress: 1.0, didActivate: true), true)
        }
        let progress = CGFloat(min(1.0, elapsed / dwellDuration))
        return (TaskbarDragHoverState(isHovering: true, progress: progress, didActivate: false), false)
    }

    @discardableResult
    public mutating func reset() -> TaskbarDragHoverState {
        isActive = false
        didTrigger = false
        anchorLocation = .zero
        stillSince = 0
        return .idle
    }
}

// MARK: - Cálculo de Anchos Mixtos de Botones (Títulos, Solo Íconos y Minimizadas Compactas)

/// Plan de diseño calculado para la fila de botones de ventanas en la barra de tareas.
public struct TaskbarButtonLayoutPlan: Equatable, Sendable {
    public let buttonWidths: [CGFloat]
    public let showTitles: [Bool]
    public let leadingSpacings: [CGFloat]
    public let needsHorizontalScroll: Bool

    public init(
        buttonWidths: [CGFloat],
        showTitles: [Bool],
        leadingSpacings: [CGFloat],
        needsHorizontalScroll: Bool
    ) {
        self.buttonWidths = buttonWidths
        self.showTitles = showTitles
        self.leadingSpacings = leadingSpacings
        self.needsHorizontalScroll = needsHorizontalScroll
    }
}

/// Calcula dinámicamente qué ventanas muestran título o solo ícono y distribuye el espacio horizontal
/// disponible para que las ventanas abiertas aprovechen todo el espacio liberado por las minimizadas compactas.
/// Comportamiento cuando hay muchas ventanas abiertas y superan el ancho normal de la barra de tareas.
public enum TaskbarOverflowMode: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Ajusta dinámicamente el ancho de los botones (y pasa a solo íconos si hace falta) para que entren todos sin scroll.
    case shrinkToFit = "shrink_to_fit"
    /// Mantiene un ancho mínimo fijo por botón y habilita desplazamiento horizontal (scroll).
    case horizontalScroll = "horizontal_scroll"

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .shrinkToFit:
            return loc.text(es: "Ajustar ancho automáticamente (sin scroll)", en: "Auto-Shrink Buttons to Fit (No Scroll)")
        case .horizontalScroll:
            return loc.text(es: "Ancho mínimo fijo con scroll horizontal", en: "Fixed Minimum Width with Horizontal Scroll")
        }
    }

    public var systemImage: String {
        switch self {
        case .shrinkToFit:
            return "arrow.right.and.line.vertical.and.arrow.left"
        case .horizontalScroll:
            return "arrow.left.and.right"
        }
    }
}

public enum TaskbarButtonLayoutCalculator {
    public static let maxExpandedButtonWidth: CGFloat = 215
    public static let minExpandedButtonWidth: CGFloat = 96
    /// Ancho mínimo al que puede reducirse un botón con título en modo `shrinkToFit` antes de pasar a solo íconos.
    public static let minShrunkTitledButtonWidth: CGFloat = 56
    /// Ancho mínimo absoluto por botón en modo solo íconos cuando hay muchísimas ventanas abiertas.
    public static let minShrunkIconButtonWidth: CGFloat = 24

    public static func shouldShowTitle(
        for item: TaskbarWindowItem,
        showWindowTitles: Bool,
        minimizedDisplayMode: TaskbarMinimizedWindowDisplayMode
    ) -> Bool {
        guard showWindowTitles else { return false }
        if minimizedDisplayMode == .iconOnly && (item.isMinimized || item.isAppHidden) {
            return false
        }
        return true
    }

    public static func computeLayout(
        windows: [TaskbarWindowItem],
        availableWidth: CGFloat,
        barHeight: CGFloat,
        showWindowTitles: Bool,
        minimizedDisplayMode: TaskbarMinimizedWindowDisplayMode,
        groupWindowsByApp: Bool,
        overflowMode: TaskbarOverflowMode = .shrinkToFit
    ) -> TaskbarButtonLayoutPlan {
        guard !windows.isEmpty else {
            return TaskbarButtonLayoutPlan(
                buttonWidths: [],
                showTitles: [],
                leadingSpacings: [],
                needsHorizontalScroll: false
            )
        }

        var leadingSpacings: [CGFloat] = windows.indices.map { idx in
            guard idx > 0 else { return 0 }
            if groupWindowsByApp {
                return windows[idx].appGroupKey == windows[idx - 1].appGroupKey ? 2 : 7
            }
            return 5
        }
        var totalSpacing = leadingSpacings.reduce(0, +)
        let iconOnlyWidth = max(34, barHeight - 2)

        var showTitles = windows.map {
            shouldShowTitle(
                for: $0,
                showWindowTitles: showWindowTitles,
                minimizedDisplayMode: minimizedDisplayMode
            )
        }
        let expandedCount = showTitles.filter { $0 }.count
        let compactCount = windows.count - expandedCount
        let compactTotalWidth = CGFloat(compactCount) * iconOnlyWidth

        switch overflowMode {
        case .horizontalScroll:
            let expandedWidth: CGFloat
            if expandedCount > 0 {
                let remainingForExpanded = availableWidth - totalSpacing - compactTotalWidth
                let idealExpanded = floor(remainingForExpanded / CGFloat(expandedCount))
                expandedWidth = min(maxExpandedButtonWidth, max(minExpandedButtonWidth, idealExpanded))
            } else {
                expandedWidth = iconOnlyWidth
            }

            let buttonWidths = showTitles.map { $0 ? expandedWidth : iconOnlyWidth }
            let totalContentWidth = compactTotalWidth + CGFloat(expandedCount) * expandedWidth + totalSpacing
            let needsHorizontalScroll = totalContentWidth > availableWidth

            return TaskbarButtonLayoutPlan(
                buttonWidths: buttonWidths,
                showTitles: showTitles,
                leadingSpacings: leadingSpacings,
                needsHorizontalScroll: needsHorizontalScroll
            )

        case .shrinkToFit:
            // Paso 1: intentar que entren todos los botones con título reduciendo suavemente su ancho hasta `minShrunkTitledButtonWidth`
            if expandedCount > 0 {
                let remainingForExpanded = availableWidth - totalSpacing - compactTotalWidth
                let idealExpanded = floor(remainingForExpanded / CGFloat(expandedCount))

                if idealExpanded >= minShrunkTitledButtonWidth {
                    let fittedExpanded = min(maxExpandedButtonWidth, idealExpanded)
                    let buttonWidths = showTitles.map { $0 ? fittedExpanded : iconOnlyWidth }
                    return TaskbarButtonLayoutPlan(
                        buttonWidths: buttonWidths,
                        showTitles: showTitles,
                        leadingSpacings: leadingSpacings,
                        needsHorizontalScroll: false
                    )
                }

                // Probar compactando levemente el espaciado entre botones antes de ocultar títulos
                let tighterSpacings: [CGFloat] = windows.indices.map { idx in
                    guard idx > 0 else { return 0 }
                    if groupWindowsByApp {
                        return windows[idx].appGroupKey == windows[idx - 1].appGroupKey ? 1.5 : 4
                    }
                    return 3
                }
                let tighterTotalSpacing = tighterSpacings.reduce(0, +)
                let remainingTighter = availableWidth - tighterTotalSpacing - compactTotalWidth
                let idealTighter = floor(remainingTighter / CGFloat(expandedCount))
                if idealTighter >= minShrunkTitledButtonWidth {
                    let fittedExpanded = min(maxExpandedButtonWidth, idealTighter)
                    let buttonWidths = showTitles.map { $0 ? fittedExpanded : iconOnlyWidth }
                    return TaskbarButtonLayoutPlan(
                        buttonWidths: buttonWidths,
                        showTitles: showTitles,
                        leadingSpacings: tighterSpacings,
                        needsHorizontalScroll: false
                    )
                }
            }

            // Paso 2: si hay demasiadas ventanas para mostrar texto legible, compactar automáticamente a solo íconos ajustando su ancho para que entren todas
            showTitles = Array(repeating: false, count: windows.count)
            leadingSpacings = windows.indices.map { idx in
                guard idx > 0 else { return 0 }
                if groupWindowsByApp {
                    return windows[idx].appGroupKey == windows[idx - 1].appGroupKey ? 1.5 : 4
                }
                return 2.5
            }
            totalSpacing = leadingSpacings.reduce(0, +)

            let idealIconWidth = floor((availableWidth - totalSpacing) / CGFloat(windows.count))
            let fittedIconWidth = min(iconOnlyWidth, max(minShrunkIconButtonWidth, idealIconWidth))
            let totalIconContentWidth = CGFloat(windows.count) * fittedIconWidth + totalSpacing
            let buttonWidths = Array(repeating: fittedIconWidth, count: windows.count)

            return TaskbarButtonLayoutPlan(
                buttonWidths: buttonWidths,
                showTitles: showTitles,
                leadingSpacings: leadingSpacings,
                needsHorizontalScroll: totalIconContentWidth > availableWidth + 1
            )
        }
    }
}
