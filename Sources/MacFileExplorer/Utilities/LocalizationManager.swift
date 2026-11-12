import AppKit
import Foundation
import Observation

/// Idiomas soportados por la aplicación (con detección automática del idioma del sistema por defecto).
public enum AppLanguagePreference: String, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case spanish = "es"
    case english = "en"

    public var id: String { rawValue }
}

/// Idioma efectivo resuelto (`es` o `en`).
public enum EffectiveLanguage: String, Sendable {
    case spanish = "es"
    case english = "en"
}

/// Gestor reactivo (`@Observable`) de internacionalización (Inglés y Español).
/// Por defecto toma la configuración de idioma del sistema macOS (`Locale.preferredLanguages`),
/// persiste la preferencia y traduce en tiempo real tanto la UI como la barra de menús y submenús de macOS (`NSMenu`).
@MainActor
@Observable
public final class LocalizationManager {

    public static let shared = LocalizationManager()

    private let preferenceKey = "com.macfileexplorer.languagePreference"
    private var menuTrackingObserverInstalled = false

    /// Idioma original del sistema capturado antes de sobreescribir `AppleLanguages`.
    private nonisolated static let initialSystemLanguage: EffectiveLanguage = {
        if let globalLangs = CFPreferencesCopyAppValue("AppleLanguages" as CFString, kCFPreferencesAnyApplication) as? [String] {
            for identifier in globalLangs {
                let lower = identifier.lowercased()
                if lower.hasPrefix("es") { return .spanish }
                if lower.hasPrefix("en") { return .english }
            }
        }
        for identifier in Locale.preferredLanguages {
            let lower = identifier.lowercased()
            if lower.hasPrefix("es") { return .spanish }
            if lower.hasPrefix("en") { return .english }
        }
        return .english
    }()

    /// Preferencia seleccionada (`.system` por defecto).
    public var preference: AppLanguagePreference {
        didSet {
            UserDefaults.standard.set(preference.rawValue, forKey: preferenceKey)
            syncAppleLanguagesDefault()
            applyLanguageToMainMenu()
        }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: preferenceKey),
           let saved = AppLanguagePreference(rawValue: raw) {
            self.preference = saved
        } else {
            self.preference = .system
        }
        syncAppleLanguagesDefault()
        installMenuTrackingObserverIfNeeded()
    }

    /// Idioma efectivo actual (`spanish` o `english`).
    public var effectiveLanguage: EffectiveLanguage {
        switch preference {
        case .spanish:
            return .spanish
        case .english:
            return .english
        case .system:
            return Self.detectSystemLanguage()
        }
    }

    public var isSpanish: Bool {
        effectiveLanguage == .spanish
    }

    /// Detecta si el idioma preferido global de macOS es español o inglés.
    public nonisolated static func detectSystemLanguage() -> EffectiveLanguage {
        initialSystemLanguage
    }

    /// Devuelve la cadena localizada según el idioma efectivo activo.
    public func text(es: String, en: String) -> String {
        isSpanish ? es : en
    }

    /// Nombre visible para cada opción de preferencia de idioma.
    public func displayName(for option: AppLanguagePreference) -> String {
        switch option {
        case .system:
            let sysCode = Self.detectSystemLanguage() == .spanish ? "ES" : "EN"
            return text(es: "Automático del sistema (\(sysCode))", en: "System Default (\(sysCode))")
        case .spanish:
            return "Español"
        case .english:
            return "English"
        }
    }

    // MARK: - Sincronización de Barra de Menú Principal y Submenús de macOS (`NSMenu`)

    private func syncAppleLanguagesDefault() {
        switch preference {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .spanish:
            UserDefaults.standard.set(["es"], forKey: "AppleLanguages")
        case .english:
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        }
    }

    public func installMenuTrackingObserverIfNeeded() {
        guard !menuTrackingObserverInstalled else { return }
        menuTrackingObserverInstalled = true

        NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                LocalizationManager.shared.applyLanguageToMainMenu()
            }
        }
    }

    /// Traduce en vivo todos los menús principales de la barra superior de macOS y todos sus submenús.
    public func applyLanguageToMainMenu() {
        guard let mainMenu = NSApplication.shared.mainMenu else { return }
        let targetSpanish = isSpanish

        for topItem in mainMenu.items {
            if let submenu = topItem.submenu {
                let translatedTopTitle = Self.translateMenuTitle(submenu.title, toSpanish: targetSpanish)
                    ?? Self.translateMenuTitle(topItem.title, toSpanish: targetSpanish)
                if let translatedTopTitle {
                    topItem.title = translatedTopTitle
                    submenu.title = translatedTopTitle
                }
                translateSubmenuRecursively(submenu, toSpanish: targetSpanish)
            }
        }
        mainMenu.update()
    }

    private func translateSubmenuRecursively(_ menu: NSMenu, toSpanish: Bool) {
        if let translatedMenuTitle = Self.translateMenuTitle(menu.title, toSpanish: toSpanish) {
            menu.title = translatedMenuTitle
        }

        for item in menu.items {
            if item.isSeparatorItem { continue }

            // 1. Traducir por selector de acción estándar de AppKit si aplica
            if let action = item.action,
               let bySelector = Self.translateBySelector(action, currentTitle: item.title, toSpanish: toSpanish) {
                item.title = bySelector
            } else if let byTitle = Self.translateMenuItemTitle(item.title, toSpanish: toSpanish) {
                item.title = byTitle
            }

            // 2. Si el ítem tiene un submenú anidado, traducirlo recursivamente
            if let childMenu = item.submenu {
                if let translatedSubTitle = Self.translateMenuTitle(childMenu.title, toSpanish: toSpanish)
                    ?? Self.translateMenuItemTitle(item.title, toSpanish: toSpanish) {
                    item.title = translatedSubTitle
                    childMenu.title = translatedSubTitle
                }
                translateSubmenuRecursively(childMenu, toSpanish: toSpanish)
            }
        }
    }

    private static func translateMenuTitle(_ rawTitle: String, toSpanish: Bool) -> String? {
        let pairs: [(es: String, en: String)] = [
            ("Archivo", "File"),
            ("Edición", "Edit"),
            ("Editar", "Edit"),
            ("Visualización", "View"),
            ("Ver", "View"),
            ("Idioma", "Language"),
            ("Ventana", "Window"),
            ("Ayuda", "Help"),
            ("Servicios", "Services"),
            ("Buscar", "Find"),
            ("Ortografía y gramática", "Spelling and Grammar"),
            ("Sustituciones", "Substitutions"),
            ("Transformaciones", "Transformations"),
            ("Habla", "Speech"),
            (" Voz", "Speech"),
            ("Mover y redimensionar", "Move & Resize"),
            ("Mosaico en pantalla completa", "Full Screen Tile")
        ]
        for pair in pairs {
            if rawTitle.caseInsensitiveCompare(pair.es) == .orderedSame ||
               rawTitle.caseInsensitiveCompare(pair.en) == .orderedSame {
                return toSpanish ? pair.es : pair.en
            }
        }
        return nil
    }

    private static func translateBySelector(_ selector: Selector, currentTitle: String, toSpanish: Bool) -> String? {
        let selName = NSStringFromSelector(selector)
        switch selName {
        case "newWindowForTab:":
            return toSpanish ? "Nueva ventana" : "New Window"
        case "performClose:":
            if currentTitle.lowercased().contains("pestaña") || currentTitle.lowercased().contains("tab") {
                return toSpanish ? "Cerrar pestaña" : "Close Tab"
            }
            return toSpanish ? "Cerrar ventana" : "Close Window"
        case "closeAll:":
            return toSpanish ? "Cerrar todo" : "Close All"
        case "undo:":
            return toSpanish ? "Deshacer" : "Undo"
        case "redo:":
            return toSpanish ? "Rehacer" : "Redo"
        case "cut:":
            return toSpanish ? "Cortar" : "Cut"
        case "copy:":
            return toSpanish ? "Copiar" : "Copy"
        case "paste:":
            return toSpanish ? "Pegar" : "Paste"
        case "pasteAsPlainText:":
            return toSpanish ? "Pegar con el mismo estilo" : "Paste and Match Style"
        case "delete:":
            return toSpanish ? "Eliminar" : "Delete"
        case "selectAll:":
            return toSpanish ? "Seleccionar todo" : "Select All"
        case "hide:":
            return toSpanish ? "Ocultar MacFileExplorer" : "Hide MacFileExplorer"
        case "hideOtherApplications:":
            return toSpanish ? "Ocultar otros" : "Hide Others"
        case "unhideAllApplications:":
            return toSpanish ? "Mostrar todo" : "Show All"
        case "terminate:":
            return toSpanish ? "Salir de MacFileExplorer" : "Quit MacFileExplorer"
        case "performMiniaturize:":
            return toSpanish ? "Minimizar" : "Minimize"
        case "miniaturizeAll:":
            return toSpanish ? "Minimizar todo" : "Minimize All"
        case "performZoom:":
            return "Zoom"
        case "arrangeInFront:":
            return toSpanish ? "Traer todo al frente" : "Bring All to Front"
        case "toggleTabBar:":
            let isHide = currentTitle.lowercased().contains("ocultar") || currentTitle.lowercased().contains("hide")
            if isHide {
                return toSpanish ? "Ocultar barra de pestañas" : "Hide Tab Bar"
            }
            return toSpanish ? "Mostrar barra de pestañas" : "Show Tab Bar"
        case "toggleTabOverview:":
            return toSpanish ? "Mostrar todas las pestañas" : "Show All Tabs"
        case "toggleToolbarShown:":
            let isHide = currentTitle.lowercased().contains("ocultar") || currentTitle.lowercased().contains("hide")
            if isHide {
                return toSpanish ? "Ocultar barra de herramientas" : "Hide Toolbar"
            }
            return toSpanish ? "Mostrar barra de herramientas" : "Show Toolbar"
        case "runToolbarCustomizationPalette:":
            return toSpanish ? "Personalizar barra de herramientas…" : "Customize Toolbar…"
        case "toggleSidebar:":
            let isHide = currentTitle.lowercased().contains("ocultar") || currentTitle.lowercased().contains("hide")
            if isHide {
                return toSpanish ? "Ocultar barra lateral" : "Hide Sidebar"
            }
            return toSpanish ? "Mostrar barra lateral" : "Show Sidebar"
        case "toggleFullScreen:":
            let isExit = currentTitle.lowercased().contains("salir") || currentTitle.lowercased().contains("exit")
            if isExit {
                return toSpanish ? "Salir de pantalla completa" : "Exit Full Screen"
            }
            return toSpanish ? "Usar pantalla completa" : "Enter Full Screen"
        case "selectPreviousTabViewItem:":
            return toSpanish ? "Mostrar pestaña anterior" : "Show Previous Tab"
        case "selectNextTabViewItem:":
            return toSpanish ? "Mostrar pestaña siguiente" : "Show Next Tab"
        case "moveTabToNewWindow:":
            return toSpanish ? "Mover pestaña a una ventana nueva" : "Move Tab to New Window"
        case "mergeAllWindows:":
            return toSpanish ? "Fusionar todas las ventanas" : "Merge All Windows"
        case "showHelp:":
            return toSpanish ? "Ayuda de MacFileExplorer" : "MacFileExplorer Help"
        case "orderFrontCharacterPalette:":
            return toSpanish ? "Emoji y símbolos" : "Emoji & Symbols"
        default:
            return nil
        }
    }

    private static func translateMenuItemTitle(_ rawTitle: String, toSpanish: Bool) -> String? {
        if rawTitle.hasPrefix("Nueva ventana") || rawTitle.hasPrefix("New ") && rawTitle.hasSuffix("Window") {
            return toSpanish ? "Nueva ventana" : "New Window"
        }

        let exactPairs: [(es: String, en: String)] = [
            ("Acerca de MacFileExplorer", "About MacFileExplorer"),
            ("Ajustes…", "Settings…"),
            ("Preferencias…", "Preferences…"),
            ("Servicios", "Services"),
            ("Ocultar MacFileExplorer", "Hide MacFileExplorer"),
            ("Ocultar otros", "Hide Others"),
            ("Mostrar todo", "Show All"),
            ("Salir de MacFileExplorer", "Quit MacFileExplorer"),
            ("Nueva ventana", "New Window"),
            ("Cerrar", "Close"),
            ("Cerrar ventana", "Close Window"),
            ("Cerrar pestaña", "Close Tab"),
            ("Cerrar todo", "Close All"),
            ("Deshacer", "Undo"),
            ("Rehacer", "Redo"),
            ("Cortar", "Cut"),
            ("Copiar", "Copy"),
            ("Pegar", "Paste"),
            ("Pegar con el mismo estilo", "Paste and Match Style"),
            ("Eliminar", "Delete"),
            ("Seleccionar todo", "Select All"),
            ("Buscar", "Find"),
            ("Buscar…", "Find…"),
            ("Buscar y reemplazar…", "Find and Replace…"),
            ("Buscar siguiente", "Find Next"),
            ("Buscar anterior", "Find Previous"),
            ("Usar selección para buscar", "Use Selection for Find"),
            ("Ir a la selección", "Jump to Selection"),
            ("Ortografía y gramática", "Spelling and Grammar"),
            ("Mostrar ortografía y gramática", "Show Spelling and Grammar"),
            ("Comprobar documento ahora", "Check Document Now"),
            ("Comprobar ortografía mientras se escribe", "Check Spelling While Typing"),
            ("Comprobar gramática con la ortografía", "Check Grammar With Spelling"),
            ("Corregir ortografía automáticamente", "Correct Spelling Automatically"),
            ("Sustituciones", "Substitutions"),
            ("Mostrar sustituciones", "Show Substitutions"),
            ("Copiado y pegado inteligente", "Smart Copy/Paste"),
            ("Comillas tipográficas", "Smart Quotes"),
            ("Guiones inteligentes", "Smart Dashes"),
            ("Enlaces inteligentes", "Smart Links"),
            ("Detectores de datos", "Data Detectors"),
            ("Reemplazo de texto", "Text Replacement"),
            ("Transformaciones", "Transformations"),
            ("Convertir en mayúsculas", "Make Upper Case"),
            ("Convertir en minúsculas", "Make Lower Case"),
            ("Poner mayúsculas iniciales", "Capitalize"),
            ("Habla", "Speech"),
            ("Iniciar locución", "Start Speaking"),
            ("Detener locución", "Stop Speaking"),
            ("Autorrelleno", "AutoFill"),
            ("Iniciar dictado…", "Start Dictation…"),
            ("Emoji y símbolos", "Emoji & Symbols"),
            ("Mostrar barra de pestañas", "Show Tab Bar"),
            ("Ocultar barra de pestañas", "Hide Tab Bar"),
            ("Mostrar todas las pestañas", "Show All Tabs"),
            ("Mostrar barra de herramientas", "Show Toolbar"),
            ("Ocultar barra de herramientas", "Hide Toolbar"),
            ("Personalizar barra de herramientas…", "Customize Toolbar…"),
            ("Mostrar barra lateral", "Show Sidebar"),
            ("Ocultar barra lateral", "Hide Sidebar"),
            ("Usar pantalla completa", "Enter Full Screen"),
            ("Entrar en pantalla completa", "Enter Full Screen"),
            ("Salir de pantalla completa", "Exit Full Screen"),
            ("Minimizar", "Minimize"),
            ("Minimizar todo", "Minimize All"),
            ("Rellenar", "Fill"),
            ("Centrar", "Center"),
            ("Mover y redimensionar", "Move & Resize"),
            ("Mosaico en pantalla completa", "Full Screen Tile"),
            ("Quitar ventana del conjunto", "Remove Window from Set"),
            ("Cambiar entre ventanas", "Cycle Through Windows"),
            ("Mostrar pestaña anterior", "Show Previous Tab"),
            ("Mostrar pestaña siguiente", "Show Next Tab"),
            ("Mover pestaña a una ventana nueva", "Move Tab to New Window"),
            ("Fusionar todas las ventanas", "Merge All Windows"),
            ("Traer todo al frente", "Bring All to Front"),
            ("Ayuda de MacFileExplorer", "MacFileExplorer Help")
        ]

        for pair in exactPairs {
            if rawTitle.caseInsensitiveCompare(pair.es) == .orderedSame ||
               rawTitle.caseInsensitiveCompare(pair.en) == .orderedSame {
                return toSpanish ? pair.es : pair.en
            }
        }
        return nil
    }

    // MARK: - Traducciones de Columnas y Modos de Vista

    public func sortFieldTitle(_ field: FileItem.SortField) -> String {
        switch field {
        case .name:
            return text(es: "Nombre", en: "Name")
        case .modificationDate:
            return text(es: "Fecha de modificación", en: "Date modified")
        case .modificationDateMix:
            return text(es: "Fecha de modificación mix", en: "Date modified mix")
        case .kind:
            return text(es: "Tipo", en: "Type")
        case .size:
            return text(es: "Tamaño", en: "Size")
        }
    }

    public func viewModeTitle(_ mode: ExplorerViewMode) -> String {
        switch mode {
        case .details:
            return text(es: "Detalles", en: "Details")
        case .largeIcons:
            return text(es: "Iconos grandes", en: "Large icons")
        }
    }

    public func listIconDisplayModeTitle(_ mode: ListIconDisplayMode) -> String {
        switch mode {
        case .basic:
            return text(es: "Básico", en: "Basic")
        case .appIcon:
            return text(es: "Icono de app (App Icon)", en: "App Icon")
        case .thumbnail:
            return text(es: "Miniatura (Thumbnail)", en: "Thumbnail")
        }
    }

    // MARK: - Traducciones de Nodos del Panel Lateral

    public func sidebarNodeTitle(for node: NavigationNode) -> String {
        guard node.section == .quickAccess, !node.isCustomQuickAccessFavorite else {
            return node.title
        }
        let path = node.url.standardizedFileURL.path(percentEncoded: false)
        for folder in QuickAccessFolder.allCases {
            if let folderPath = folder.directoryURL?.path(percentEncoded: false), folderPath == path {
                return folder.localizedTitle(using: self)
            }
            if folder == .applications && (path == "/Applications" || path == "/Applications/" || node.title == "Aplicaciones") {
                return folder.localizedTitle(using: self)
            }
        }
        return node.title
    }

    public func localizedKindDescription(for item: FileItem) -> String {
        if item.isNavigableFolder {
            return text(es: "Carpeta de archivos", en: "File folder")
        }
        if item.isPackage && item.fileExtension == "app" {
            return text(es: "Aplicación", en: "Application")
        }
        let raw = item.kindDescription
        if raw == "Carpeta de archivos" || raw == "File folder" || raw == "Folder" {
            return text(es: "Carpeta de archivos", en: "File folder")
        }
        if raw == "Aplicación" || raw == "Application" {
            return text(es: "Aplicación", en: "Application")
        }
        if raw == "Archivo" || raw == "File" {
            return text(es: "Archivo", en: "File")
        }
        return raw
    }
}
