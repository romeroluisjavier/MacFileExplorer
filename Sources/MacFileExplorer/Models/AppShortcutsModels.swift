import AppKit
import Carbon
import Foundation
import Observation
import SwiftUI

/// Representación universal y serializable de un atajo de teclado configurable en `MacFileExplorer`
/// (soporta tanto combinaciones con modificadores como teclas de función `F1`–`F19`).
public struct AppKeyShortcut: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt16
    public var command: Bool
    public var control: Bool
    public var option: Bool
    public var shift: Bool
    public var keyDisplayLabel: String
    public var isEnabled: Bool

    public init(
        keyCode: UInt16,
        command: Bool = false,
        control: Bool = false,
        option: Bool = false,
        shift: Bool = false,
        keyDisplayLabel: String,
        isEnabled: Bool = true
    ) {
        self.keyCode = keyCode
        self.command = command
        self.control = control
        self.option = option
        self.shift = shift
        self.keyDisplayLabel = keyDisplayLabel
        self.isEnabled = isEnabled
    }

    /// Atajo predeterminado de «Ver Escritorio»: `⌘D` (`Command + D`).
    public static let defaultViewDesktop = AppKeyShortcut(
        keyCode: 2, // D
        command: true,
        keyDisplayLabel: "D",
        isEnabled: true
    )

    /// Representación legible estilo macOS (ej. `⌘D`, `⇧⌘N`, `⌃⌘V`, `F11`).
    public var displayString: String {
        guard isEnabled else { return "—" }
        var result = ""
        if control { result += "⌃" }
        if option { result += "⌥" }
        if shift { result += "⇧" }
        if command { result += "⌘" }
        result += keyDisplayLabel
        return result
    }

    /// Firma normalizada de tecla + modificadores para detectar conflictos entre atajos activos.
    public var conflictSignature: String? {
        guard isEnabled else { return nil }
        return "\(keyCode)|\(command ? 1 : 0)|\(control ? 1 : 0)|\(option ? 1 : 0)|\(shift ? 1 : 0)"
    }

    /// Modificadores `NSEvent.ModifierFlags` correspondientes.
    public var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if command { flags.insert(.command) }
        if control { flags.insert(.control) }
        if option { flags.insert(.option) }
        if shift { flags.insert(.shift) }
        return flags
    }

    /// Modificadores `SwiftUI.EventModifiers` correspondientes.
    public var swiftUIModifiers: SwiftUI.EventModifiers {
        var mods: SwiftUI.EventModifiers = []
        if command { mods.insert(.command) }
        if control { mods.insert(.control) }
        if option { mods.insert(.option) }
        if shift { mods.insert(.shift) }
        return mods
    }

    /// Modificadores de Carbon (`cmdKey`, `controlKey`, `optionKey`, `shiftKey`) para `RegisterEventHotKey`.
    public var carbonModifiers: UInt32 {
        var mods: UInt32 = 0
        if command { mods |= UInt32(cmdKey) }
        if shift { mods |= UInt32(shiftKey) }
        if option { mods |= UInt32(optionKey) }
        if control { mods |= UInt32(controlKey) }
        return mods
    }

    /// Convierte el atajo a `SwiftUI.KeyboardShortcut` para enlazarlo en menús y botones nativos de SwiftUI.
    public var swiftUIKeyboardShortcut: KeyboardShortcut? {
        guard isEnabled, let equivalent = Self.keyEquivalent(forKeyCode: keyCode, label: keyDisplayLabel) else {
            return nil
        }
        return KeyboardShortcut(equivalent, modifiers: swiftUIModifiers)
    }

    /// Verifica si un evento de teclado coincide con este atajo.
    public func matches(
        keyCode eventKeyCode: UInt16,
        charactersIgnoringModifiers: String?,
        flags: NSEvent.ModifierFlags
    ) -> Bool {
        guard isEnabled else { return false }
        let cleanFlags = flags.intersection([.command, .control, .option, .shift])
        guard cleanFlags == modifierFlags else { return false }
        if eventKeyCode == keyCode {
            return true
        }
        if let chars = charactersIgnoringModifiers?.uppercased(),
           !chars.isEmpty,
           chars.count == 1,
           keyDisplayLabel.count == 1,
           chars == keyDisplayLabel.uppercased() {
            return true
        }
        return false
    }

    /// Indica si un `keyCode` corresponde a una tecla de función (`F1`–`F19`).
    public static func isFunctionKeyCode(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80:
            return true
        default:
            return false
        }
    }

    /// Construye un `AppKeyShortcut` a partir de un `NSEvent` capturado en el grabador de atajos.
    public static func from(
        event: NSEvent,
        allowFunctionKeyWithoutModifiers: Bool = true
    ) -> AppKeyShortcut? {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        // Ignorar pulsaciones de solo modificadores
        let modifierOnlyKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        guard !modifierOnlyKeyCodes.contains(event.keyCode) else { return nil }

        let isFnKey = isFunctionKeyCode(event.keyCode)
        if flags.isEmpty && !(allowFunctionKeyWithoutModifiers && isFnKey) {
            return nil
        }

        let label = Self.humanReadableKeyLabel(
            keyCode: event.keyCode,
            characters: event.charactersIgnoringModifiers
        )
        return AppKeyShortcut(
            keyCode: event.keyCode,
            command: flags.contains(.command),
            control: flags.contains(.control),
            option: flags.contains(.option),
            shift: flags.contains(.shift),
            keyDisplayLabel: label,
            isEnabled: true
        )
    }

    public static func keyEquivalent(forKeyCode keyCode: UInt16, label: String) -> KeyEquivalent? {
        switch keyCode {
        case 36, 76: return .return
        case 48: return .tab
        case 49: return .space
        case 51: return .delete
        case 53: return .escape
        case 117: return .deleteForward
        case 123: return .leftArrow
        case 124: return .rightArrow
        case 125: return .downArrow
        case 126: return .upArrow
        case 115: return .home
        case 119: return .end
        case 116: return .pageUp
        case 121: return .pageDown
        case 24: return KeyEquivalent("+")
        case 27: return KeyEquivalent("-")
        case 29: return KeyEquivalent("0")
        case 33: return KeyEquivalent("[")
        case 30: return KeyEquivalent("]")
        case 47: return KeyEquivalent(".")
        case 43: return KeyEquivalent(",")
        case 44: return KeyEquivalent("/")
        case 50: return KeyEquivalent("`")
        default:
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count == 1, let ch = trimmed.lowercased().first {
                return KeyEquivalent(ch)
            }
            return nil
        }
    }

    public static func humanReadableKeyLabel(keyCode: UInt16, characters: String?) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "+"
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36, 76: return "↵"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "⇥"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "⌫"
        case 53: return "Esc"
        case 64: return "F17"
        case 79: return "F18"
        case 80: return "F19"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 106: return "F16"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 115: return "Home"
        case 116: return "PgUp"
        case 117: return "⌦"
        case 118: return "F4"
        case 119: return "End"
        case 120: return "F2"
        case 121: return "PgDn"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            if let chars = characters?.trimmingCharacters(in: .whitespacesAndNewlines), !chars.isEmpty {
                return chars.uppercased()
            }
            return "Key\(keyCode)"
        }
    }
}

/// Comportamiento al activar el atajo global «Ver Escritorio» (`View Desktop`).
public enum ViewDesktopBehavior: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Usa el comando nativo de macOS (`CoreDockSendNotification` / Mission Control Show Desktop)
    /// para apartar suavemente todas las ventanas y revelar el Escritorio; volver a pulsar restaura todo.
    case nativeShowDesktop = "native_show_desktop"

    /// Estilo Windows `Win+D`: oculta las ventanas abiertas manteniendo visible la barra de tareas y
    /// enfoca el Escritorio; volver a pulsar restaura las aplicaciones y ventanas previas.
    case hideWindowsFocusDesktop = "hide_windows_focus_desktop"

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .nativeShowDesktop:
            return loc.text(
                es: "Mostrar Escritorio (Mission Control de macOS)",
                en: "Show Desktop (macOS Mission Control)"
            )
        case .hideWindowsFocusDesktop:
            return loc.text(
                es: "Ocultar ventanas y enfocar Escritorio (Estilo Win+D)",
                en: "Hide Windows & Focus Desktop (Win+D Style)"
            )
        }
    }

    @MainActor
    public func localizedDescription(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .nativeShowDesktop:
            return loc.text(
                es: "Desliza suavemente todas las ventanas hacia los bordes para mostrar el Escritorio sin ocultar tus apps. Volvé a pulsar el atajo para traerlas de vuelta.",
                en: "Smoothly slides all open windows aside to reveal the Desktop without hiding apps. Press the shortcut again to bring everything right back."
            )
        case .hideWindowsFocusDesktop:
            return loc.text(
                es: "Oculta las ventanas abiertas y pone el foco en el Escritorio de tu Mac (dejando la Barra de tareas visible). Volvé a pulsar el atajo para restaurar tus ventanas.",
                en: "Hides open windows and focuses your Mac Desktop (while keeping the Taskbar visible). Press the shortcut again to restore your windows."
            )
        }
    }

    public var systemImage: String {
        switch self {
        case .nativeShowDesktop:
            return "macwindow.on.rectangle"
        case .hideWindowsFocusDesktop:
            return "rectangle.inset.bottomleft.filled"
        }
    }
}

/// Categoría de atajos dentro del administrador central (`Archivo → Administrar todos los atajos`).
public enum AppShortcutCategory: String, CaseIterable, Identifiable, Sendable {
    case tools
    case tabsAndNavigation
    case filesAndViews
    case clipboard
    case altTab
    case standardReference

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .tools:
            return loc.text(es: "Herramientas (Global)", en: "Tools (Global)")
        case .tabsAndNavigation:
            return loc.text(es: "Pestañas y Navegación", en: "Tabs & Navigation")
        case .filesAndViews:
            return loc.text(es: "Archivos y Vistas", en: "Files & Views")
        case .clipboard:
            return loc.text(es: "Portapapeles (Maccy)", en: "Clipboard (Maccy)")
        case .altTab:
            return "AltTab"
        case .standardReference:
            return loc.text(es: "Estándar y Editor", en: "Standard & Editor")
        }
    }

    public var systemImage: String {
        switch self {
        case .tools: return "wrench.and.screwdriver"
        case .tabsAndNavigation: return "arrow.left.arrow.right"
        case .filesAndViews: return "folder"
        case .clipboard: return "doc.on.clipboard"
        case .altTab: return "rectangle.stack"
        case .standardReference: return "command"
        }
    }
}

/// Acciones con atajo de teclado configurable gestionadas por `AppShortcutPreferences`.
public enum AppShortcutAction: String, Codable, CaseIterable, Identifiable, Sendable {
    // Herramientas Globales (sistema macOS)
    case viewDesktop = "tools.viewDesktop"

    // Pestañas y Navegación
    case newFolderTab = "tabs.newFolderTab"
    case closeCurrentTab = "tabs.closeCurrentTab"
    case focusAddressBar = "nav.focusAddressBar"
    case goBack = "nav.goBack"
    case goForward = "nav.goForward"
    case goUp = "nav.goUp"
    case goHome = "nav.goHome"
    case refreshFolder = "nav.refreshFolder"

    // Archivos, Vistas y Herramientas del Explorador
    case newFolder = "files.newFolder"
    case showProperties = "files.showProperties"
    case toggleHiddenFiles = "files.toggleHiddenFiles"
    case viewDetails = "views.details"
    case viewLargeIcons = "views.largeIcons"
    case toggleBookmarksBar = "views.toggleBookmarksBar"
    case zoomInWeb = "web.zoomIn"
    case zoomOutWeb = "web.zoomOut"
    case resetZoomWeb = "web.resetZoom"
    case findDuplicateFiles = "tools.findDuplicates"
    case openHiddenCache = "tools.hiddenCache"

    public var id: String { rawValue }

    public var isGlobalSystemHotkey: Bool {
        self == .viewDesktop
    }

    public var category: AppShortcutCategory {
        switch self {
        case .viewDesktop:
            return .tools
        case .newFolderTab, .closeCurrentTab, .focusAddressBar, .goBack, .goForward, .goUp, .goHome, .refreshFolder:
            return .tabsAndNavigation
        case .newFolder, .showProperties, .toggleHiddenFiles, .viewDetails, .viewLargeIcons,
             .toggleBookmarksBar, .zoomInWeb, .zoomOutWeb, .resetZoomWeb, .findDuplicateFiles, .openHiddenCache:
            return .filesAndViews
        }
    }

    public var systemImage: String {
        switch self {
        case .viewDesktop: return "macwindow.on.rectangle"
        case .newFolderTab: return "folder.badge.plus"
        case .closeCurrentTab: return "xmark.circle"
        case .focusAddressBar: return "character.cursor.ibeam"
        case .goBack: return "chevron.backward"
        case .goForward: return "chevron.forward"
        case .goUp: return "arrow.up"
        case .goHome: return "house"
        case .refreshFolder: return "arrow.clockwise"
        case .newFolder: return "folder.badge.plus"
        case .showProperties: return "info.circle"
        case .toggleHiddenFiles: return "eye"
        case .viewDetails: return "list.bullet"
        case .viewLargeIcons: return "square.grid.2x2"
        case .toggleBookmarksBar: return "bookmark"
        case .zoomInWeb: return "plus.magnifyingglass"
        case .zoomOutWeb: return "minus.magnifyingglass"
        case .resetZoomWeb: return "arrow.counterclockwise"
        case .findDuplicateFiles: return "doc.on.doc"
        case .openHiddenCache: return "internaldrive"
        }
    }

    public var defaultShortcut: AppKeyShortcut {
        switch self {
        case .viewDesktop:
            return .defaultViewDesktop
        case .newFolderTab:
            return AppKeyShortcut(keyCode: 17, command: true, keyDisplayLabel: "T")
        case .closeCurrentTab:
            return AppKeyShortcut(keyCode: 17, command: true, shift: true, keyDisplayLabel: "T")
        case .focusAddressBar:
            return AppKeyShortcut(keyCode: 37, command: true, keyDisplayLabel: "L")
        case .goBack:
            return AppKeyShortcut(keyCode: 33, command: true, keyDisplayLabel: "[")
        case .goForward:
            return AppKeyShortcut(keyCode: 30, command: true, keyDisplayLabel: "]")
        case .goUp:
            return AppKeyShortcut(keyCode: 126, command: true, keyDisplayLabel: "↑")
        case .goHome:
            return AppKeyShortcut(keyCode: 4, command: true, shift: true, keyDisplayLabel: "H")
        case .refreshFolder:
            return AppKeyShortcut(keyCode: 15, command: true, keyDisplayLabel: "R")
        case .newFolder:
            return AppKeyShortcut(keyCode: 45, command: true, shift: true, keyDisplayLabel: "N")
        case .showProperties:
            return AppKeyShortcut(keyCode: 34, command: true, keyDisplayLabel: "I")
        case .toggleHiddenFiles:
            return AppKeyShortcut(keyCode: 47, command: true, shift: true, keyDisplayLabel: ".")
        case .viewDetails:
            return AppKeyShortcut(keyCode: 18, command: true, keyDisplayLabel: "1")
        case .viewLargeIcons:
            return AppKeyShortcut(keyCode: 19, command: true, keyDisplayLabel: "2")
        case .toggleBookmarksBar:
            return AppKeyShortcut(keyCode: 11, command: true, shift: true, keyDisplayLabel: "B")
        case .zoomInWeb:
            return AppKeyShortcut(keyCode: 24, command: true, keyDisplayLabel: "+")
        case .zoomOutWeb:
            return AppKeyShortcut(keyCode: 27, command: true, keyDisplayLabel: "-")
        case .resetZoomWeb:
            return AppKeyShortcut(keyCode: 29, command: true, keyDisplayLabel: "0")
        case .findDuplicateFiles:
            return AppKeyShortcut(keyCode: 2, command: true, option: true, keyDisplayLabel: "D", isEnabled: false)
        case .openHiddenCache:
            return AppKeyShortcut(keyCode: 8, command: true, option: true, shift: true, keyDisplayLabel: "C", isEnabled: false)
        }
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .viewDesktop:
            return loc.text(es: "Ver Escritorio (View Desktop)", en: "View Desktop")
        case .newFolderTab:
            return loc.text(es: "Nueva pestaña de carpetas", en: "New Folder Tab")
        case .closeCurrentTab:
            return loc.text(es: "Cerrar pestaña actual", en: "Close Current Tab")
        case .focusAddressBar:
            return loc.text(es: "Editar barra de direcciones", en: "Edit Address Bar")
        case .goBack:
            return loc.text(es: "Ir atrás en el historial", en: "Go Back in History")
        case .goForward:
            return loc.text(es: "Ir adelante en el historial", en: "Go Forward in History")
        case .goUp:
            return loc.text(es: "Subir a la carpeta superior", en: "Go to Enclosing Folder")
        case .goHome:
            return loc.text(es: "Ir a la carpeta Inicio (~)", en: "Go to Home Folder (~)")
        case .refreshFolder:
            return loc.text(es: "Actualizar carpeta actual", en: "Refresh Current Folder")
        case .newFolder:
            return loc.text(es: "Crear nueva carpeta", en: "Create New Folder")
        case .showProperties:
            return loc.text(es: "Mostrar Propiedades / Info", en: "Show Properties / Info")
        case .toggleHiddenFiles:
            return loc.text(es: "Mostrar u ocultar archivos ocultos", en: "Show / Hide Hidden Files")
        case .viewDetails:
            return loc.text(es: "Cambiar a vista Detalles", en: "Switch to Details View")
        case .viewLargeIcons:
            return loc.text(es: "Cambiar a vista Iconos Grandes", en: "Switch to Large Icons View")
        case .toggleBookmarksBar:
            return loc.text(es: "Mostrar u ocultar barra de marcadores", en: "Show / Hide Bookmarks Bar")
        case .zoomInWeb:
            return loc.text(es: "Acercar página web", en: "Zoom In Web Page")
        case .zoomOutWeb:
            return loc.text(es: "Alejar página web", en: "Zoom Out Web Page")
        case .resetZoomWeb:
            return loc.text(es: "Restablecer zoom web (100%)", en: "Reset Web Zoom (100%)")
        case .findDuplicateFiles:
            return loc.text(es: "Buscar archivos duplicados…", en: "Find Duplicate Files…")
        case .openHiddenCache:
            return loc.text(es: "Caché oculta (.macfileexplorer)…", en: "Hidden Cache (.macfileexplorer)…")
        }
    }

    @MainActor
    public func localizedSubtitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .viewDesktop:
            return loc.text(
                es: "Global en todo macOS: muestra y enfoca el Escritorio de tu Mac al instante (por defecto ⌘D).",
                en: "Global across macOS: reveals and focuses your Mac Desktop right away (default ⌘D)."
            )
        case .newFolderTab:
            return loc.text(es: "Abre una pestaña nueva en la ruta actual.", en: "Opens a new folder tab at the current location.")
        case .closeCurrentTab:
            return loc.text(es: "Cierra la pestaña activa del explorador.", en: "Closes the active Explorer tab.")
        case .focusAddressBar:
            return loc.text(es: "Activa el campo de ruta para escribir o pegar.", en: "Focuses the address bar to type or paste a path.")
        case .goBack:
            return loc.text(es: "Retrocede a la carpeta anterior (también ⌥← / ⌘←).", en: "Navigates to the previous folder (also ⌥← / ⌘←).")
        case .goForward:
            return loc.text(es: "Avanza a la carpeta siguiente (también ⌥→ / ⌘→).", en: "Navigates to the next folder (also ⌥→ / ⌘→).")
        case .goUp:
            return loc.text(es: "Sube al directorio padre (también ⌥↑).", en: "Moves up to the parent directory (also ⌥↑).")
        case .goHome:
            return loc.text(es: "Navega directo a tu carpeta personal.", en: "Jumps directly to your personal Home folder.")
        case .refreshFolder:
            return loc.text(es: "Recarga el listado y metadatos de la carpeta.", en: "Reloads the current folder items and metadata.")
        case .newFolder:
            return loc.text(es: "Crea una carpeta nueva dentro de la ubicación actual.", en: "Creates a new folder inside the current location.")
        case .showProperties:
            return loc.text(es: "Abre la ventana de propiedades y metadatos EXIF.", en: "Opens Properties & EXIF metadata for the selection.")
        case .toggleHiddenFiles:
            return loc.text(es: "Muestra u oculta archivos que empiezan con punto.", en: "Toggles visibility of dotfiles and hidden folders.")
        case .viewDetails:
            return loc.text(es: "Muestra los archivos en tabla de columnas.", en: "Switches file list to columnar Details table.")
        case .viewLargeIcons:
            return loc.text(es: "Muestra los archivos en cuadrícula con miniaturas.", en: "Switches file list to Large Icons grid.")
        case .toggleBookmarksBar:
            return loc.text(es: "Oculta o despliega la barra superior de marcadores web.", en: "Toggles the top web bookmarks bar.")
        case .zoomInWeb:
            return loc.text(es: "Aumenta el zoom en pestañas web de Google.", en: "Zooms in on active Google web tabs.")
        case .zoomOutWeb:
            return loc.text(es: "Reduce el zoom en pestañas web de Google.", en: "Zooms out on active Google web tabs.")
        case .resetZoomWeb:
            return loc.text(es: "Devuelve el zoom web al 100%.", en: "Resets web tab zoom back to 100%.")
        case .findDuplicateFiles:
            return loc.text(es: "Abre el buscador de archivos repetidos por contenido.", en: "Opens the content-based Duplicate File Finder.")
        case .openHiddenCache:
            return loc.text(es: "Abre el administrador de caché oculta de la app.", en: "Opens the Hidden Cache Manager modal.")
        }
    }
}

/// Preferencias reactivas y persistentes para TODOS los atajos de `MacFileExplorer` y ajustes de `Herramientas` (`Tools`).
@MainActor
@Observable
public final class AppShortcutPreferences {

    public static let shared = AppShortcutPreferences()

    private let defaults = UserDefaults.standard
    private var isBootstrapping = true

    private enum Keys {
        static let customShortcuts = "com.macfileexplorer.shortcuts.customMap.v1"
        static let viewDesktopBehavior = "com.macfileexplorer.tools.viewDesktopBehavior.v1"
    }

    /// Callback disparado cada vez que cambia el atajo global de «Ver Escritorio».
    public var onViewDesktopShortcutChanged: (() -> Void)?

    /// Mapa de atajos personalizados por acción (solo persiste los modificados o personalizados).
    public private(set) var overrides: [String: AppKeyShortcut] = [:]

    /// Modo de acción al presionar el atajo de «Ver Escritorio» (`View Desktop`).
    public var viewDesktopBehavior: ViewDesktopBehavior {
        didSet {
            guard !isBootstrapping, viewDesktopBehavior != oldValue else { return }
            defaults.set(viewDesktopBehavior.rawValue, forKey: Keys.viewDesktopBehavior)
        }
    }

    private init() {
        if let rawMode = defaults.string(forKey: Keys.viewDesktopBehavior),
           let parsedMode = ViewDesktopBehavior(rawValue: rawMode) {
            self.viewDesktopBehavior = parsedMode
        } else {
            self.viewDesktopBehavior = .nativeShowDesktop
        }

        if let data = defaults.data(forKey: Keys.customShortcuts),
           let decoded = try? JSONDecoder().decode([String: AppKeyShortcut].self, from: data) {
            self.overrides = decoded
        }

        self.isBootstrapping = false
    }

    /// Devuelve el atajo activo para una acción (personalizado si existe, o predeterminado).
    public func shortcut(for action: AppShortcutAction) -> AppKeyShortcut {
        overrides[action.rawValue] ?? action.defaultShortcut
    }

    /// Devuelve el `SwiftUI.KeyboardShortcut` efectivo (o `nil` si el atajo está desactivado).
    public func swiftUIShortcut(for action: AppShortcutAction) -> KeyboardShortcut? {
        shortcut(for: action).swiftUIKeyboardShortcut
    }

    /// Atajo configurado para «Ver Escritorio» (`⌘D` por defecto).
    public var viewDesktopShortcut: AppKeyShortcut {
        get { shortcut(for: .viewDesktop) }
        set { setShortcut(newValue, for: .viewDesktop) }
    }

    /// Indica si el atajo global «Ver Escritorio» está habilitado.
    public var isViewDesktopShortcutEnabled: Bool {
        get { viewDesktopShortcut.isEnabled }
        set { setEnabled(newValue, for: .viewDesktop) }
    }

    /// Guarda un nuevo atajo para la acción indicada.
    public func setShortcut(_ newShortcut: AppKeyShortcut, for action: AppShortcutAction) {
        if newShortcut == action.defaultShortcut {
            overrides.removeValue(forKey: action.rawValue)
        } else {
            overrides[action.rawValue] = newShortcut
        }
        persistOverrides()
        if action == .viewDesktop {
            onViewDesktopShortcutChanged?()
        }
    }

    /// Activa o desactiva el atajo de una acción conservando su tecla configurada.
    public func setEnabled(_ enabled: Bool, for action: AppShortcutAction) {
        var current = shortcut(for: action)
        guard current.isEnabled != enabled else { return }
        current.isEnabled = enabled
        setShortcut(current, for: action)
    }

    /// Restablece el atajo de una sola acción a su valor de fábrica.
    public func resetShortcut(for action: AppShortcutAction) {
        guard overrides[action.rawValue] != nil else { return }
        overrides.removeValue(forKey: action.rawValue)
        persistOverrides()
        if action == .viewDesktop {
            onViewDesktopShortcutChanged?()
        }
    }

    /// Restablece todos los atajos del explorador y de herramientas a sus valores predeterminados.
    public func resetAllToDefaults() {
        let hadViewDesktopOverride = overrides[AppShortcutAction.viewDesktop.rawValue] != nil
        overrides.removeAll()
        persistOverrides()
        if hadViewDesktopOverride {
            onViewDesktopShortcutChanged?()
        }
    }

    /// Indica si la acción tiene su atajo predeterminado sin modificar.
    public func isDefault(for action: AppShortcutAction) -> Bool {
        shortcut(for: action) == action.defaultShortcut
    }

    /// Indica si existe al menos un atajo modificado en `AppShortcutPreferences`.
    public var hasAnyCustomShortcut: Bool {
        !overrides.isEmpty
    }

    /// Busca nombres de otras acciones que actualmente comparten la misma combinación de teclas activa.
    public func conflictingActionTitles(
        for signature: String?,
        excludingIdentifier excludedID: String,
        using loc: LocalizationManager = .shared
    ) -> [String] {
        guard let signature, !signature.isEmpty else { return [] }
        var matches: [String] = []

        for action in AppShortcutAction.allCases where action.id != excludedID {
            if shortcut(for: action).conflictSignature == signature {
                matches.append(action.localizedTitle(using: loc))
            }
        }

        let clipPrefs = ClipboardHistoryPreferences.shared
        if clipPrefs.isEnabled {
            let clipEntries: [(id: String, title: String, sc: ClipboardKeyShortcut)] = [
                ("clipboard.quickPaste", loc.text(es: "Portapapeles: Menú rápido", en: "Clipboard: Quick Dropdown"), clipPrefs.quickPasteDropdownShortcut),
                ("clipboard.fullSearch", loc.text(es: "Portapapeles: Buscador completo", en: "Clipboard: Full History Search"), clipPrefs.fullHistorySearchShortcut),
                ("clipboard.pin", loc.text(es: "Portapapeles: Fijar elemento", en: "Clipboard: Pin Item"), clipPrefs.pinShortcut),
                ("clipboard.delete", loc.text(es: "Portapapeles: Eliminar elemento", en: "Clipboard: Delete Item"), clipPrefs.deleteShortcut),
                ("clipboard.plainText", loc.text(es: "Portapapeles: Texto plano", en: "Clipboard: Plain Text"), clipPrefs.plainTextShortcut),
                ("clipboard.clear", loc.text(es: "Portapapeles: Limpiar historial", en: "Clipboard: Clear History"), clipPrefs.clearHistoryShortcut)
            ]
            for entry in clipEntries where entry.id != excludedID && entry.sc.isEnabled {
                let sig = "\(entry.sc.keyCode)|\(entry.sc.command ? 1 : 0)|\(entry.sc.control ? 1 : 0)|\(entry.sc.option ? 1 : 0)|\(entry.sc.shift ? 1 : 0)"
                if sig == signature {
                    matches.append(entry.title)
                }
            }
        }

        let altPrefs = AltTabPreferences.shared
        if altPrefs.isEnabled {
            for profile in altPrefs.shortcutProfiles where profile.isEnabled {
                let pid = "alttab.\(profile.id.uuidString)"
                guard pid != excludedID else { continue }
                let sig = "\(profile.triggerKeyCode)|\(profile.holdCommand ? 1 : 0)|\(profile.holdControl ? 1 : 0)|\(profile.holdOption ? 1 : 0)|0"
                if sig == signature {
                    matches.append("AltTab: \(profile.name)")
                }
            }
        }

        return matches
    }

    private func persistOverrides() {
        if overrides.isEmpty {
            defaults.removeObject(forKey: Keys.customShortcuts)
        } else if let data = try? JSONEncoder().encode(overrides) {
            defaults.set(data, forKey: Keys.customShortcuts)
        }
    }
}

public extension View {
    /// Aplica un `.keyboardShortcut(_:)` solo cuando el atajo está habilitado y es representable en SwiftUI.
    @ViewBuilder
    func optionalKeyboardShortcut(_ shortcut: KeyboardShortcut?) -> some View {
        if let shortcut {
            self.keyboardShortcut(shortcut)
        } else {
            self
        }
    }
}
