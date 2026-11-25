import AppKit
import CoreGraphics
import Foundation

// MARK: - Enumeraciones de Estilos y Filtros de AltTab

/// Estilos de visualización del selector AltTab (inspirado en alt-tab.app).
public enum AltTabDisplayStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case thumbnails
    case appIcons
    case titlesList

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .thumbnails: return "rectangle.grid.2x2"
        case .appIcons: return "app.badge"
        case .titlesList: return "list.bullet.rectangle"
        }
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .thumbnails: return loc.text(es: "Miniaturas", en: "Thumbnails")
        case .appIcons: return loc.text(es: "Íconos de aplicación", en: "App Icons")
        case .titlesList: return loc.text(es: "Lista compacta de títulos", en: "Compact Titles List")
        }
    }
}

public enum AltTabWindowScopeApps: String, CaseIterable, Identifiable, Codable, Sendable {
    case allApps
    case activeAppOnly

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .allApps: return loc.text(es: "Todas las aplicaciones", en: "All Applications")
        case .activeAppOnly: return loc.text(es: "Solo aplicación activa", en: "Active Application Only")
        }
    }
}

public enum AltTabWindowScopeSpaces: String, CaseIterable, Identifiable, Codable, Sendable {
    case allSpaces
    case activeSpaceOnly

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .allSpaces: return loc.text(es: "Todos los Spaces", en: "All Spaces")
        case .activeSpaceOnly: return loc.text(es: "Solo Space actual", en: "Active Space Only")
        }
    }
}

public enum AltTabWindowScopeScreens: String, CaseIterable, Identifiable, Codable, Sendable {
    case allScreens
    case activeMouseScreen
    case mainScreenOnly

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .allScreens: return loc.text(es: "Todos los monitores", en: "All Displays")
        case .activeMouseScreen: return loc.text(es: "Monitor donde está el mouse", en: "Display Under Cursor")
        case .mainScreenOnly: return loc.text(es: "Solo monitor principal", en: "Main Display Only")
        }
    }
}

public enum AltTabReleaseBehavior: String, CaseIterable, Identifiable, Codable, Sendable {
    case switchOnModifierRelease
    case keepOpenUntilConfirmed

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .switchOnModifierRelease:
            return loc.text(es: "Cambiar al soltar la tecla modificadora", en: "Switch on Modifier Release")
        case .keepOpenUntilConfirmed:
            return loc.text(es: "Mantener abierto hasta Enter o clic", en: "Keep Open Until Enter / Click")
        }
    }
}

// MARK: - Perfil de Atajo Configurable (Hasta 5 Perfiles Independientes)

public struct AltTabShortcutProfile: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var isEnabled: Bool
    public var triggerKeyCode: UInt16
    public var triggerKeyLabel: String
    public var holdCommand: Bool
    public var holdOption: Bool
    public var holdControl: Bool
    public var holdShift: Bool
    public var appsScope: AltTabWindowScopeApps
    public var spacesScope: AltTabWindowScopeSpaces
    public var screensScope: AltTabWindowScopeScreens
    public var includeMinimized: Bool
    public var includeHidden: Bool
    public var releaseBehavior: AltTabReleaseBehavior

    public init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        triggerKeyCode: UInt16,
        triggerKeyLabel: String,
        holdCommand: Bool = false,
        holdOption: Bool = true,
        holdControl: Bool = false,
        holdShift: Bool = false,
        appsScope: AltTabWindowScopeApps = .allApps,
        spacesScope: AltTabWindowScopeSpaces = .allSpaces,
        screensScope: AltTabWindowScopeScreens = .allScreens,
        includeMinimized: Bool = true,
        includeHidden: Bool = true,
        releaseBehavior: AltTabReleaseBehavior = .switchOnModifierRelease
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.triggerKeyCode = triggerKeyCode
        self.triggerKeyLabel = triggerKeyLabel
        self.holdCommand = holdCommand
        self.holdOption = holdOption
        self.holdControl = holdControl
        self.holdShift = holdShift
        self.appsScope = appsScope
        self.spacesScope = spacesScope
        self.screensScope = screensScope
        self.includeMinimized = includeMinimized
        self.includeHidden = includeHidden
        self.releaseBehavior = releaseBehavior
    }

    public var hasHoldModifier: Bool {
        holdCommand || holdOption || holdControl || holdShift
    }

    /// Representación visual estilo macOS (ej. `⌥ ⇥`, `⌘ ⇥`, `⌥ \``).
    public var displayString: String {
        var parts: [String] = []
        if holdControl { parts.append("⌃") }
        if holdOption { parts.append("⌥") }
        if holdShift { parts.append("⇧") }
        if holdCommand { parts.append("⌘") }
        parts.append(triggerKeyLabel)
        return parts.joined(separator: " ")
    }

    /// Máscara de flags CGEvent requeridos como modificadores retenidos.
    public var requiredCGFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if holdCommand { flags.insert(.maskCommand) }
        if holdOption { flags.insert(.maskAlternate) }
        if holdControl { flags.insert(.maskControl) }
        if holdShift { flags.insert(.maskShift) }
        return flags
    }

    /// Evalúa si un `keyDown` con `(keyCode, flags)` dispara este atajo (en sentido normal o inverso con `⇧`).
    public func matchesKeyDown(keyCode: UInt16, flags: CGEventFlags) -> (matched: Bool, isReverse: Bool) {
        guard isEnabled, hasHoldModifier, keyCode == triggerKeyCode else {
            return (false, false)
        }
        let relevantMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        let pressed = flags.intersection(relevantMask)
        let required = requiredCGFlags

        if pressed == required {
            return (true, false)
        }
        // Si el atajo no requiere Shift, sumar Shift navega en orden inverso (ej. ⇧⌥⇥)
        if !holdShift && pressed == required.union(.maskShift) {
            return (true, true)
        }
        return (false, false)
    }

    /// Devuelve `true` cuando el usuario soltó alguno de los modificadores retenidos del atajo.
    public func areHoldModifiersReleased(currentFlags: CGEventFlags) -> Bool {
        let required = requiredCGFlags
        guard !required.isEmpty else { return true }
        return !currentFlags.contains(required)
    }

    /// Perfiles predeterminados de fábrica (Atajo 1: `⌥ ⇥` todas las ventanas; Atajo 2: `⌥ \`` ventanas de la app actual).
    public static func makeDefaultProfiles() -> [AltTabShortcutProfile] {
        [
            AltTabShortcutProfile(
                name: "Todas las ventanas / All Windows",
                isEnabled: true,
                triggerKeyCode: 48, // Tab
                triggerKeyLabel: "⇥",
                holdCommand: false,
                holdOption: true,
                holdControl: false,
                holdShift: false,
                appsScope: .allApps,
                spacesScope: .allSpaces,
                screensScope: .allScreens,
                includeMinimized: true,
                includeHidden: true,
                releaseBehavior: .switchOnModifierRelease
            ),
            AltTabShortcutProfile(
                name: "App actual / Active App",
                isEnabled: true,
                triggerKeyCode: 50, // Grave / Backtick / º
                triggerKeyLabel: "`",
                holdCommand: false,
                holdOption: true,
                holdControl: false,
                holdShift: false,
                appsScope: .activeAppOnly,
                spacesScope: .allSpaces,
                screensScope: .allScreens,
                includeMinimized: true,
                includeHidden: true,
                releaseBehavior: .switchOnModifierRelease
            )
        ]
    }

    /// Etiqueta legible para una tecla física grabada por `NSEvent`.
    public static func keyLabel(for keyCode: UInt16, charactersIgnoringModifiers: String?) -> String {
        switch keyCode {
        case 48: return "⇥"
        case 50: return "`"
        case 49: return "Space"
        case 36, 76: return "↵"
        case 51: return "⌫"
        case 53: return "Esc"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:
            if let chars = charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines), !chars.isEmpty {
                return chars.uppercased()
            }
            return "Key \(keyCode)"
        }
    }
}

// MARK: - Motor Puro de Filtrado, Selección MRU y Auto-Tamaño (Testeable)

public struct AltTabLayoutMetrics: Equatable, Sendable {
    public let columns: Int
    public let rows: Int
    public let cellWidth: CGFloat
    public let cellHeight: CGFloat
    public let panelWidth: CGFloat
    public let panelHeight: CGFloat

    public init(
        columns: Int,
        rows: Int,
        cellWidth: CGFloat,
        cellHeight: CGFloat,
        panelWidth: CGFloat,
        panelHeight: CGFloat
    ) {
        self.columns = columns
        self.rows = rows
        self.cellWidth = cellWidth
        self.cellHeight = cellHeight
        self.panelWidth = panelWidth
        self.panelHeight = panelHeight
    }
}

public enum AltTabLayoutEngine {

    /// Filtra la lista completa de ventanas según el perfil de atajo activo, apps excluidas y texto de búsqueda.
    public static func filteredWindows(
        from allWindows: [TaskbarWindowItem],
        profile: AltTabShortcutProfile,
        frontmostPID: pid_t?,
        activeMouseScreenID: String?,
        mainScreenID: String?,
        excludedBundleIDs: [String],
        searchQuery: String
    ) -> [TaskbarWindowItem] {
        let excludedSet = Set(excludedBundleIDs.map { $0.lowercased() })
        let trimmedQuery = TaskbarStringSanitizer.sanitizeDisplayName(searchQuery)
        let foldedQuery = trimmedQuery.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let tokens = foldedQuery.split(whereSeparator: \.isWhitespace).map(String.init)

        return allWindows.filter { item in
            if !item.bundleIdentifier.isEmpty && excludedSet.contains(item.bundleIdentifier.lowercased()) {
                return false
            }
            if !profile.includeMinimized && item.isMinimized {
                return false
            }
            if !profile.includeHidden && item.isAppHidden {
                return false
            }
            if profile.appsScope == .activeAppOnly, let frontmostPID, item.pid != frontmostPID {
                return false
            }
            if profile.spacesScope == .activeSpaceOnly && !item.isOnActiveSpace && !item.isMinimized {
                return false
            }
            switch profile.screensScope {
            case .allScreens:
                break
            case .activeMouseScreen:
                if let activeMouseScreenID, item.screenID != activeMouseScreenID {
                    return false
                }
            case .mainScreenOnly:
                if let mainScreenID, item.screenID != mainScreenID {
                    return false
                }
            }

            if !tokens.isEmpty {
                let haystack = "\(item.appName) \(item.displayTitle)"
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                if !tokens.allSatisfy({ haystack.contains($0) }) {
                    return false
                }
            }
            return true
        }
    }

    /// Índice inicial al abrir el selector (índice `1` = ventana anterior MRU, o última si `reverse == true`).
    public static func initialSelectionIndex(windowCount: Int, reverse: Bool) -> Int {
        guard windowCount > 0 else { return 0 }
        if windowCount == 1 { return 0 }
        return reverse ? (windowCount - 1) : 1
    }

    /// Calcula el tamaño óptimo del panel HUD y de cada tarjeta/fila respetando los límites del monitor.
    public static func computeMetrics(
        windowCount: Int,
        style: AltTabDisplayStyle,
        autoSize: Bool,
        manualThumbnailWidth: CGFloat,
        screenSize: CGSize,
        maxWidthRatio: CGFloat = 0.84,
        showSearchBar: Bool = false
    ) -> AltTabLayoutMetrics {
        let safeCount = max(1, windowCount)
        let maxW = max(420, floor(screenSize.width * min(max(maxWidthRatio, 0.50), 0.92)))
        let maxH = max(260, floor(screenSize.height * 0.78))
        let chromeVertical: CGFloat = (showSearchBar ? 54 : 0) + 56 // padding + footer
        let paddingH: CGFloat = 28
        let spacing: CGFloat = 12

        switch style {
        case .titlesList:
            let listWidth = min(maxW, autoSize ? (safeCount > 8 ? 640 : 560) : max(460, min(maxW, manualThumbnailWidth * 2.6)))
            let rowHeight: CGFloat = autoSize && safeCount > 12 ? 36 : 42
            let contentH = CGFloat(safeCount) * (rowHeight + 4) + 12
            let panelH = min(maxH, max(160, contentH + chromeVertical))
            return AltTabLayoutMetrics(
                columns: 1,
                rows: safeCount,
                cellWidth: listWidth - paddingH,
                cellHeight: rowHeight,
                panelWidth: listWidth,
                panelHeight: panelH
            )

        case .appIcons:
            let cellW: CGFloat
            let cellH: CGFloat
            if autoSize {
                if safeCount <= 5 {
                    cellW = 124; cellH = 124
                } else if safeCount <= 10 {
                    cellW = 108; cellH = 112
                } else {
                    cellW = 94; cellH = 100
                }
            } else {
                cellW = min(140, max(88, manualThumbnailWidth * 0.52))
                cellH = cellW + 8
            }

            let maxCols = max(1, Int(floor((maxW - paddingH + spacing) / (cellW + spacing))))
            let cols = min(safeCount, maxCols)
            let rows = Int(ceil(Double(safeCount) / Double(cols)))
            let panelW = min(maxW, CGFloat(cols) * cellW + CGFloat(max(0, cols - 1)) * spacing + paddingH)
            let panelH = min(maxH, CGFloat(rows) * cellH + CGFloat(max(0, rows - 1)) * spacing + chromeVertical + 36)
            return AltTabLayoutMetrics(
                columns: cols,
                rows: rows,
                cellWidth: cellW,
                cellHeight: cellH,
                panelWidth: panelW,
                panelHeight: panelH
            )

        case .thumbnails:
            let cellW: CGFloat
            if autoSize {
                if safeCount <= 3 {
                    cellW = min(310, (maxW - paddingH - CGFloat(safeCount - 1) * spacing) / CGFloat(safeCount))
                } else if safeCount <= 6 {
                    cellW = 248
                } else if safeCount <= 12 {
                    cellW = 206
                } else {
                    cellW = 176
                }
            } else {
                cellW = min(320, max(140, manualThumbnailWidth))
            }
            let clampedCellW = min(320, max(150, floor(cellW)))
            let cellH = floor(clampedCellW * 0.66) + 34 // miniatura 16:10 + cabecera ícono/título

            let maxCols = max(1, Int(floor((maxW - paddingH + spacing) / (clampedCellW + spacing))))
            let cols = min(safeCount, maxCols)
            let rows = Int(ceil(Double(safeCount) / Double(cols)))
            let panelW = min(maxW, CGFloat(cols) * clampedCellW + CGFloat(max(0, cols - 1)) * spacing + paddingH)
            let panelH = min(maxH, CGFloat(rows) * cellH + CGFloat(max(0, rows - 1)) * spacing + chromeVertical)
            return AltTabLayoutMetrics(
                columns: cols,
                rows: rows,
                cellWidth: clampedCellW,
                cellHeight: cellH,
                panelWidth: panelW,
                panelHeight: panelH
            )
        }
    }
}
