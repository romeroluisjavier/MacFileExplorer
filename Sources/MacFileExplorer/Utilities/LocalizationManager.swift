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
public final class LocalizationManager: NSObject, NSMenuDelegate {

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

    private override init() {
        if let raw = UserDefaults.standard.string(forKey: preferenceKey),
           let saved = AppLanguagePreference(rawValue: raw) {
            self.preference = saved
        } else {
            self.preference = .system
        }
        super.init()
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

    // MARK: - NSMenuDelegate

    public func menuWillOpen(_ menu: NSMenu) {
        translateSubmenuRecursively(menu, toSpanish: isSpanish)
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        translateSubmenuRecursively(menu, toSpanish: isSpanish)
    }

    /// Traduce en vivo todos los menús principales de la barra superior de macOS y todos sus submenús.
    public func applyLanguageToMainMenu() {
        guard let mainMenu = NSApplication.shared.mainMenu else { return }
        let targetSpanish = isSpanish

        for topItem in mainMenu.items {
            if let submenu = topItem.submenu {
                if submenu.delegate == nil {
                    submenu.delegate = self
                }
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
        if menu.delegate == nil {
            menu.delegate = self
        }
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

            // 2. Aplicar icono representativo si corresponde
            Self.applyIconToMenuItem(item, parentMenuTitle: menu.title)

            // 3. Si el ítem tiene un submenú anidado, traducirlo recursivamente
            if let childMenu = item.submenu {
                if childMenu.delegate == nil {
                    childMenu.delegate = self
                }
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
            ("Zoom todo", "Zoom All"),
            ("Zoom en todas", "Zoom All"),
            ("Rellenar", "Fill"),
            ("Centrar", "Center"),
            ("Mover y redimensionar", "Move & Resize"),
            ("Mitad izquierda", "Left Half"),
            ("Mitad derecha", "Right Half"),
            ("Mitad superior", "Top Half"),
            ("Mitad inferior", "Bottom Half"),
            ("Mosaico en pantalla completa", "Full Screen Tile"),
            ("Quitar ventana del conjunto", "Remove Window from Set"),
            ("Cambiar entre ventanas", "Cycle Through Windows"),
            ("Mostrar pestaña anterior", "Show Previous Tab"),
            ("Mostrar pestaña siguiente", "Show Next Tab"),
            ("Mover pestaña a una ventana nueva", "Move Tab to New Window"),
            ("Fusionar todas las ventanas", "Merge All Windows"),
            ("Traer todo al frente", "Bring All to Front"),
            ("Ayuda de MacFileExplorer", "MacFileExplorer Help"),
            ("Añadir a Slack", "Add to Slack"),
            ("Compartir con Slack", "Share with Slack")
        ]

        for pair in exactPairs {
            if rawTitle.caseInsensitiveCompare(pair.es) == .orderedSame ||
               rawTitle.caseInsensitiveCompare(pair.en) == .orderedSame {
                return toSpanish ? pair.es : pair.en
            }
        }
        return nil
    }

    // MARK: - Iconos Representativos en la Barra de Menús (`NSMenuItem`)

    public static func symbolImage(named symbolName: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            return nil
        }
        return image.withSymbolConfiguration(config)
    }

    public static func applyIconToMenuItem(_ item: NSMenuItem, parentMenuTitle: String = "") {
        if item.image != nil {
            return
        }

        if let action = item.action,
           let symbolName = symbolNameBySelector(action, title: item.title) {
            item.image = symbolImage(named: symbolName)
            return
        }

        if let symbolName = symbolNameByTitle(item.title, parentMenuTitle: parentMenuTitle, target: item.target, action: item.action) {
            item.image = symbolImage(named: symbolName)
        }
    }

    public static func symbolNameBySelector(_ selector: Selector, title: String) -> String? {
        let selName = NSStringFromSelector(selector)
        switch selName {
        case "newWindowForTab:":
            return "macwindow.badge.plus"
        case "performClose:":
            let lower = title.lowercased()
            if lower.contains("pestaña") || lower.contains("tab") {
                return "xmark.circle"
            }
            return "xmark.rectangle"
        case "closeAll:":
            return "rectangle.badge.xmark"
        case "undo:":
            return "arrow.uturn.backward"
        case "redo:":
            return "arrow.uturn.forward"
        case "cut:":
            return "scissors"
        case "copy:":
            return "doc.on.doc"
        case "paste:":
            return "doc.on.clipboard"
        case "pasteAsPlainText:":
            return "doc.badge.arrow.up"
        case "delete:":
            return "trash"
        case "selectAll:":
            return "checkmark.circle"
        case "hide:":
            return "eye.slash"
        case "hideOtherApplications:":
            return "circle.slash"
        case "unhideAllApplications:":
            return "eye"
        case "terminate:":
            return "power"
        case "performMiniaturize:":
            return "minus.circle"
        case "miniaturizeAll:":
            return "arrow.down.right.and.arrow.up.left"
        case "performZoom:":
            return "arrow.up.left.and.arrow.down.right"
        case "zoomAll:":
            return "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left"
        case "arrangeInFront:":
            return "square.3.layers.3d.top.filled"
        case "toggleTabBar:":
            return "menubar.rectangle"
        case "toggleTabOverview:":
            return "square.grid.2x2"
        case "toggleToolbarShown:":
            return "hammer"
        case "runToolbarCustomizationPalette:":
            return "slider.horizontal.3"
        case "toggleSidebar:":
            return "sidebar.left"
        case "toggleFullScreen:":
            return "arrow.up.left.and.arrow.down.right"
        case "selectPreviousTabViewItem:":
            return "chevron.left"
        case "selectNextTabViewItem:":
            return "chevron.right"
        case "moveTabToNewWindow:":
            return "macwindow.badge.plus"
        case "mergeAllWindows:":
            return "macwindow.on.rectangle"
        case "showHelp:":
            return "questionmark.circle"
        case "orderFrontCharacterPalette:":
            return "face.smiling"
        case "startDictation:":
            return "mic"
        case "startSpeaking:":
            return "play.circle"
        case "stopSpeaking:":
            return "stop.circle"
        case "checkSpelling:":
            return "checkmark.bubble"
        case "showGuessPanel:":
            return "character.cursor.ibeam"
        default:
            return nil
        }
    }

    public static func symbolNameByTitle(_ rawTitle: String, parentMenuTitle: String = "", target: AnyObject? = nil, action: Selector? = nil) -> String? {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if parentMenuTitle.lowercased().contains("window") || parentMenuTitle.lowercased().contains("ventana") {
            if target is NSWindow || (action != nil && NSStringFromSelector(action!) == "makeKeyAndOrderFront:") {
                return "macwindow"
            }
        }

        switch lower {
        // App
        case "acerca de macfileexplorer", "about macfileexplorer":
            return "info.circle"
        case "ajustes…", "preferencias…", "settings…", "preferences…":
            return "gearshape"
        case "servicios", "services":
            return "gearshape.2"
        case "ocultar macfileexplorer", "hide macfileexplorer":
            return "eye.slash"
        case "ocultar otros", "hide others":
            return "circle.slash"
        case "mostrar todo", "show all":
            return "eye"
        case "salir de macfileexplorer", "quit macfileexplorer":
            return "power"

        // File / Archivo
        case "nueva ventana", "new window":
            return "macwindow.badge.plus"
        case "nueva pestaña de carpetas", "new folder tab":
            return "folder.badge.plus"
        case "cerrar", "close":
            return "xmark.circle"
        case "cerrar ventana", "close window":
            return "xmark.rectangle"
        case "cerrar pestaña", "cerrar pestaña actual", "close tab", "close current tab":
            return "xmark.circle"
        case "cerrar todo", "close all":
            return "rectangle.badge.xmark"

        // Edit / Edición
        case "deshacer", "undo":
            return "arrow.uturn.backward"
        case "rehacer", "redo":
            return "arrow.uturn.forward"
        case "cortar", "cut":
            return "scissors"
        case "copiar", "copy":
            return "doc.on.doc"
        case "pegar", "paste":
            return "doc.on.clipboard"
        case "pegar con el mismo estilo", "paste and match style":
            return "doc.badge.arrow.up"
        case "eliminar", "delete":
            return "trash"
        case "seleccionar todo", "select all":
            return "checkmark.circle"

        // Buscar / Find
        case "buscar", "find", "buscar…", "find…":
            return "magnifyingglass"
        case "buscar y reemplazar…", "find and replace…":
            return "doc.text.magnifyingglass"
        case "buscar siguiente", "find next":
            return "chevron.down"
        case "buscar anterior", "find previous":
            return "chevron.up"
        case "usar selección para buscar", "use selection for find":
            return "selection.pin.in.out"
        case "ir a la selección", "jump to selection":
            return "arrow.right.to.line"

        // Ortografía / Spelling
        case "ortografía y gramática", "spelling and grammar":
            return "textformat.abc.dottedunderline"
        case "mostrar ortografía y gramática", "show spelling and grammar":
            return "character.cursor.ibeam"
        case "comprobar documento ahora", "check document now":
            return "checkmark.bubble"
        case "comprobar ortografía mientras se escribe", "check spelling while typing":
            return "checkmark.circle"
        case "comprobar gramática con la ortografía", "check grammar with spelling":
            return "text.badge.checkmark"
        case "corregir ortografía automáticamente", "correct spelling automatically":
            return "wand.and.stars"

        // Sustituciones / Substitutions
        case "sustituciones", "substitutions":
            return "arrow.left.arrow.right"
        case "mostrar sustituciones", "show substitutions":
            return "list.bullet.rectangle"
        case "copiado y pegado inteligente", "smart copy/paste":
            return "doc.on.clipboard"
        case "comillas tipográficas", "smart quotes":
            return "quote.bubble"
        case "guiones inteligentes", "smart dashes":
            return "minus"
        case "enlaces inteligentes", "smart links":
            return "link"
        case "detectores de datos", "data detectors":
            return "binoculars"
        case "reemplazo de texto", "text replacement":
            return "character.textbox"

        // Transformaciones / Transformations
        case "transformaciones", "transformations":
            return "character.circle"
        case "convertir en mayúsculas", "make upper case":
            return "textformat.size.larger"
        case "convertir en minúsculas", "make lower case":
            return "textformat.size.smaller"
        case "poner mayúsculas iniciales", "capitalize":
            return "textformat"

        // Habla / Speech
        case "habla", "speech", "voz":
            return "waveform"
        case "iniciar locución", "start speaking":
            return "play.circle"
        case "detener locución", "stop speaking":
            return "stop.circle"

        // Dictado / Dictation & Emoji
        case "iniciar dictado…", "start dictation…":
            return "mic"
        case "emoji y símbolos", "emoji & symbols":
            return "face.smiling"

        // AutoFill / Autorrelleno
        case "autorrelleno", "autofill":
            return "person.text.rectangle"
        case "contraseñas", "passwords":
            return "key"
        case "contactos", "contacts":
            return "person.crop.circle"

        // View / Visualización
        case "mostrar barra de pestañas", "show tab bar", "ocultar barra de pestañas", "hide tab bar":
            return "menubar.rectangle"
        case "mostrar todas las pestañas", "show all tabs":
            return "square.grid.2x2"
        case "mostrar barra de herramientas", "show toolbar", "ocultar barra de herramientas", "hide toolbar":
            return "hammer"
        case "personalizar barra de herramientas…", "customize toolbar…":
            return "slider.horizontal.3"
        case "mostrar barra lateral", "show sidebar", "ocultar barra lateral", "hide sidebar":
            return "sidebar.left"
        case "usar pantalla completa", "enter full screen", "entrar en pantalla completa", "salir de pantalla completa", "exit full screen":
            return "arrow.up.left.and.arrow.down.right"

        // Custom View options
        case "iconos en vista lista", "list view icons":
            return "app.badge.checkmark"
        case "básico", "basic":
            return "app"
        case "icono de app (app icon)", "app icon":
            return "app.badge.checkmark"
        case "miniatura (thumbnail)", "thumbnail":
            return "photo"
        case "tamaño de iconos (cuadrícula)", "icon size (grid)":
            return "photo"
        case "pequeño", "small":
            return "circle.grid.2x2"
        case "mediano", "medium":
            return "square.grid.2x2"
        case "grande", "large":
            return "square.grid.3x3"
        case "extra grande", "extra large":
            return "square.grid.3x3.fill"
        case "abrir marcadores web en...", "open bookmarks in...":
            return "arrow.up.right.square"
        case "navegador web por defecto del sistema", "system default web browser":
            return "safari"
        case "pestaña interna de macfileexplorer", "macfileexplorer tab":
            return "macwindow"
        case "carpetas en acceso rápido", "quick access folders":
            return "star"
        case "descargas", "downloads":
            return "arrow.down.circle"
        case "documentos", "documents":
            return "doc"
        case "escritorio", "desktop":
            return "desktopcomputer"
        case "aplicaciones", "applications":
            return "app.gift"
        case "música", "music":
            return "music.note"
        case "películas", "movies":
            return "film"
        case "imágenes", "pictures":
            return "photo"
        case "papelera", "trash":
            return "trash"
        case "añadir a slack", "add to slack", "compartir con slack", "share with slack":
            return "bubble.left.and.bubble.right.fill"

        // Window / Ventana
        case "minimizar", "minimize":
            return "minus.circle"
        case "minimizar todo", "minimize all":
            return "arrow.down.right.and.arrow.up.left"
        case "zoom":
            return "arrow.up.left.and.arrow.down.right"
        case "zoom all", "zoom todo", "zoom en todas":
            return "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left"
        case "rellenar", "fill":
            return "rectangle.inset.filled"
        case "centrar", "center":
            return "scope"
        case "mover y redimensionar", "move & resize":
            return "arrow.up.and.down.and.arrow.left.and.right"
        case "mitad izquierda", "left half", "izquierda", "left":
            return "rectangle.leadinghalf.filled"
        case "mitad derecha", "right half", "derecha", "right":
            return "rectangle.trailinghalf.filled"
        case "mitad superior", "top half", "superior", "top":
            return "rectangle.tophalf.filled"
        case "mitad inferior", "bottom half", "inferior", "bottom":
            return "rectangle.bottomhalf.filled"
        case "superior izquierda", "top left":
            return "rectangle.split.2x2"
        case "superior derecha", "top right":
            return "rectangle.split.2x2"
        case "inferior izquierda", "bottom left":
            return "rectangle.split.2x2"
        case "inferior derecha", "bottom right":
            return "rectangle.split.2x2"
        case "mosaico en pantalla completa", "full screen tile":
            return "square.split.2x1"
        case "quitar ventana del conjunto", "remove window from set":
            return "minus.rectangle"
        case "cambiar entre ventanas", "cycle through windows":
            return "arrow.2.squarepath"
        case "mostrar pestaña anterior", "show previous tab":
            return "chevron.left"
        case "mostrar pestaña siguiente", "show next tab":
            return "chevron.right"
        case "mover pestaña a una ventana nueva", "move tab to new window":
            return "macwindow.badge.plus"
        case "fusionar todas las ventanas", "merge all windows":
            return "macwindow.on.rectangle"
        case "traer todo al frente", "bring all to front", "arrange in front":
            return "square.3.layers.3d.top.filled"

        // Help / Ayuda
        case "ayuda de macfileexplorer", "macfileexplorer help":
            return "questionmark.circle"

        // Language / Idioma
        case "idioma", "language":
            return "globe"
        case "español":
            return "globe.americas.fill"
        case "english":
            return "globe.europe.africa.fill"

        default:
            if lower.hasPrefix("automático del sistema") || lower.hasPrefix("system default") {
                return "gearshape.2"
            }
            if lower.hasPrefix("nueva ventana") || (lower.hasPrefix("new ") && lower.hasSuffix("window")) {
                return "macwindow.badge.plus"
            }
            if lower.contains("pestaña") || lower.contains("tab") {
                return "macwindow"
            }
            if lower.contains("ventana") || lower.contains("window") {
                return "macwindow"
            }
            return nil
        }
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
