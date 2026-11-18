import SwiftUI
import AppKit

/// Delegado de aplicación para garantizar que al ejecutarse desde SwiftPM (`swift run`) o como `.app`
/// la ventana reciba foco de teclado completo, configure el icono oficial en el Dock y traduzca la barra de menús.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSWindow.allowsAutomaticWindowTabbing = true
        if let icon = FileIconProvider.shared.currentAppIcon {
            NSApplication.shared.applicationIconImage = icon
        }
        MouseNavigationManager.shared.installIfNeeded()
        InternalErrorLogger.shared.install()
        ClipboardHistoryManager.shared.installIfNeeded()
        StatusBarManager.shared.installIfNeeded()
        LocalizationManager.shared.installMenuTrackingObserverIfNeeded()
        LocalizationManager.shared.applyLanguageToMainMenu()
        DispatchQueue.main.async {
            LocalizationManager.shared.applyLanguageToMainMenu()
        }
        AdvancedSearchService.prewarmOCRInBackground()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        LocalizationManager.shared.applyLanguageToMainMenu()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            GoogleAccountsManager.shared.openOrFocusMainWindow()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !TrayIconPreferences.shared.isTrayIconEnabled
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        GoogleAccountsManager.shared.prepareForTermination()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        GoogleAccountsManager.shared.prepareForTermination()
    }
}

@main
struct MacFileExplorerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Bindable private var loc = LocalizationManager.shared
    @Bindable private var bookmarksManager = BookmarksManager.shared
    @Bindable private var quickAccessPrefs = QuickAccessPreferences.shared
    @Bindable private var toolbarPrefs = ToolbarPreferences.shared
    @Bindable private var listIconPrefs = ListIconPreferences.shared
    @Bindable private var slackPrefs = SlackPreferences.shared
    @Bindable private var mousePrefs = MousePreferences.shared
    @Bindable private var sessionPrefs = SessionPreferences.shared
    @Bindable private var trayIconPrefs = TrayIconPreferences.shared
    @Bindable private var clipboardPrefs = ClipboardHistoryPreferences.shared
    @FocusedValue(\.explorerViewModel) private var focusedExplorerViewModel

    var body: some Scene {
        WindowGroup(loc.text(es: "Explorador de archivos", en: "File Explorer")) {
            MainExplorerView()
                .frame(minWidth: 880, minHeight: 540)
                .onChange(of: loc.preference) { _, _ in
                    DispatchQueue.main.async {
                        LocalizationManager.shared.applyLanguageToMainMenu()
                    }
                }
        }
        .defaultSize(width: 1160, height: 720)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button {
                    showAboutPanel()
                } label: {
                    Label(loc.text(es: "Acerca de MacFileExplorer", en: "About MacFileExplorer"), systemImage: "info.circle")
                }
            }

            CommandGroup(after: .appInfo) {
                Button {
                    UpdateWindowController.shared.showAndCheck()
                } label: {
                    Label(loc.text(es: "Buscar actualizaciones…", en: "Check Upgrades…"), systemImage: "arrow.down.circle")
                }

                Divider()
                Menu {
                    languageSelectionPicker
                } label: {
                    Label(loc.text(es: "Idioma", en: "Language"), systemImage: "globe")
                }
            }

            CommandGroup(after: .newItem) {
                Button {
                    let sourceWindow = NSApp.keyWindow ?? NSApp.mainWindow
                    GoogleAccountsManager.shared.openNewFileExplorerTabWindow(from: sourceWindow)
                } label: {
                    Label(loc.text(es: "Nueva pestaña de carpetas", en: "New Folder Tab"), systemImage: "folder.badge.plus")
                }
                .keyboardShortcut("t", modifiers: [.command])

                Button {
                    let sourceWindow = NSApp.keyWindow ?? NSApp.mainWindow
                    GoogleAccountsManager.shared.closeCurrentTabWindow(from: sourceWindow)
                } label: {
                    Label(loc.text(es: "Cerrar pestaña actual", en: "Close Current Tab"), systemImage: "xmark.circle")
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .undoRedo) {
                Button {
                    if isTextOrWebResponderActive || activeExplorerViewModel == nil {
                        NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                    } else {
                        activeExplorerViewModel?.undoLastOperation()
                    }
                } label: {
                    Label(undoMenuItemTitle, systemImage: "arrow.uturn.backward")
                }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(activeExplorerViewModel != nil && activeExplorerViewModel?.canUndo != true && !isTextOrWebResponderActive)

                Button {
                    if isTextOrWebResponderActive || activeExplorerViewModel == nil {
                        NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                    } else {
                        activeExplorerViewModel?.redoLastOperation()
                    }
                } label: {
                    Label(redoMenuItemTitle, systemImage: "arrow.uturn.forward")
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(activeExplorerViewModel != nil && activeExplorerViewModel?.canRedo != true && !isTextOrWebResponderActive)
            }

            CommandGroup(replacing: .pasteboard) {
                Button {
                    if isTextOrWebResponderActive || activeExplorerViewModel == nil {
                        NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                    } else {
                        activeExplorerViewModel?.cutSelectedItems()
                    }
                } label: {
                    Label(loc.text(es: "Cortar", en: "Cut"), systemImage: "scissors")
                }
                .keyboardShortcut("x", modifiers: [.command])
                .disabled(activeExplorerViewModel != nil && activeExplorerViewModel?.canCutOrCopy != true && !isTextOrWebResponderActive)

                Button {
                    if isTextOrWebResponderActive || activeExplorerViewModel == nil {
                        NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                    } else {
                        activeExplorerViewModel?.copySelectedItems()
                    }
                } label: {
                    Label(loc.text(es: "Copiar", en: "Copy"), systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command])
                .disabled(activeExplorerViewModel != nil && activeExplorerViewModel?.canCutOrCopy != true && !isTextOrWebResponderActive)

                Button {
                    if isTextOrWebResponderActive || activeExplorerViewModel == nil {
                        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                    } else {
                        activeExplorerViewModel?.pasteItems()
                    }
                } label: {
                    Label(loc.text(es: "Pegar", en: "Paste"), systemImage: "doc.on.clipboard")
                }
                .keyboardShortcut("v", modifiers: [.command])
                .disabled(activeExplorerViewModel != nil && activeExplorerViewModel?.canPaste != true && !isTextOrWebResponderActive)

                Button {
                    if isTextOrWebResponderActive || activeExplorerViewModel == nil {
                        NSApp.sendAction(#selector(NSText.delete(_:)), to: nil, from: nil)
                    } else {
                        activeExplorerViewModel?.moveSelectedItemsToTrash()
                    }
                } label: {
                    Label(loc.text(es: "Eliminar", en: "Delete"), systemImage: "trash")
                }
                .disabled(activeExplorerViewModel != nil && activeExplorerViewModel?.canDelete != true && !isTextOrWebResponderActive)

                Button {
                    if isTextOrWebResponderActive || activeExplorerViewModel == nil {
                        NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                    } else {
                        activeExplorerViewModel?.selectAll()
                    }
                } label: {
                    Label(loc.text(es: "Seleccionar todo", en: "Select All"), systemImage: "checkmark.circle")
                }
                .keyboardShortcut("a", modifiers: [.command])
                .disabled(activeExplorerViewModel != nil && activeExplorerViewModel?.displayedItems.isEmpty == true && !isTextOrWebResponderActive)
            }

            CommandGroup(after: .newItem) {
                Divider()
                Button {
                    (focusedExplorerViewModel ?? activeExplorerViewModel)?.isDuplicateFinderPresented = true
                } label: {
                    Label(
                        loc.text(es: "Buscar archivos duplicados…", en: "Find Duplicate Files…"),
                        systemImage: "doc.on.doc"
                    )
                }
                .disabled((focusedExplorerViewModel ?? activeExplorerViewModel) == nil)

                Button {
                    (focusedExplorerViewModel ?? activeExplorerViewModel)?.isHiddenCacheManagerPresented = true
                } label: {
                    Label(
                        loc.text(
                            es: "Caché oculta (.macfileexplorer)…",
                            en: "Hidden Cache (.macfileexplorer)…"
                        ),
                        systemImage: "internaldrive"
                    )
                }
                .disabled((focusedExplorerViewModel ?? activeExplorerViewModel) == nil)
            }

            CommandGroup(after: .toolbar) {
                Divider()
                Toggle(isOn: $bookmarksManager.isBookmarksBarVisible) {
                    Label(loc.text(es: "Mostrar barra de marcadores", en: "Show Bookmarks Bar"), systemImage: "bookmark")
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Toggle(isOn: $toolbarPrefs.isNewButtonVisible) {
                    Label(loc.text(es: "Mostrar botón Nuevo", en: "Show New Button"), systemImage: "plus.circle")
                }

                Menu {
                    Picker(
                        loc.text(es: "Modo de icono", en: "Icon Mode"),
                        selection: $listIconPrefs.mode
                    ) {
                        ForEach(ListIconDisplayMode.allCases) { mode in
                            Label(loc.listIconDisplayModeTitle(mode), systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(loc.text(es: "Iconos en vista Lista", en: "List View Icons"), systemImage: "app.badge.checkmark")
                }

                Menu {
                    Button {
                        GridIconPreferences.shared.iconSize = 48
                    } label: {
                        Label(loc.text(es: "Pequeño (48 px)", en: "Small (48 px)"), systemImage: "photo")
                    }
                    Button {
                        GridIconPreferences.shared.iconSize = 64
                    } label: {
                        Label(loc.text(es: "Mediano (64 px - Predeterminado)", en: "Medium (64 px - Default)"), systemImage: "photo")
                    }
                    Button {
                        GridIconPreferences.shared.iconSize = 96
                    } label: {
                        Label(loc.text(es: "Grande (96 px)", en: "Large (96 px)"), systemImage: "photo")
                    }
                    Button {
                        GridIconPreferences.shared.iconSize = 144
                    } label: {
                        Label(loc.text(es: "Muy grande (144 px)", en: "Extra Large (144 px)"), systemImage: "photo")
                    }
                    Button {
                        GridIconPreferences.shared.iconSize = 192
                    } label: {
                        Label(loc.text(es: "Máximo (192 px)", en: "Maximum (192 px)"), systemImage: "photo")
                    }

                    Divider()

                    Button {
                        GridIconPreferences.shared.resetToDefault()
                    } label: {
                        Label(loc.text(es: "Restablecer tamaño predeterminado", en: "Reset to Default Size"), systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    Label(loc.text(es: "Tamaño de iconos (Cuadrícula)", en: "Grid Icon Size"), systemImage: "photo")
                }

                Menu {
                    Picker(
                        loc.text(es: "Abrir marcadores en", en: "Open bookmarks in"),
                        selection: $bookmarksManager.openBehavior
                    ) {
                        ForEach(BookmarkOpenBehavior.allCases) { behavior in
                            Label(behavior.localizedTitle, systemImage: behavior.systemImage)
                                .tag(behavior)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(loc.text(es: "Abrir marcadores web en...", en: "Open web bookmarks in..."), systemImage: "arrow.up.right.square")
                }

                Menu {
                    Toggle(isOn: Binding(
                        get: { quickAccessPrefs.showModifiedToday },
                        set: { quickAccessPrefs.showModifiedToday = $0 }
                    )) {
                        Label(
                            loc.text(es: "Modificados hoy (24h)", en: "Modified Today (24h)"),
                            systemImage: "clock.arrow.2.circlepath"
                        )
                    }

                    Divider()

                    ForEach(QuickAccessFolder.allCases) { folder in
                        Toggle(isOn: quickAccessPrefs.binding(for: folder)) {
                            Label(folder.localizedTitle(using: loc), systemImage: folder.systemImage)
                        }
                    }

                    Divider()

                    Button {
                        quickAccessPrefs.resetToDefaults()
                    } label: {
                        Label(loc.text(es: "Restablecer predeterminadas", en: "Reset to Defaults"), systemImage: "arrow.counterclockwise")
                    }
                    .disabled(quickAccessPrefs.visibleFolders == QuickAccessFolder.defaultFolders && quickAccessPrefs.showModifiedToday)
                } label: {
                    Label(loc.text(es: "Carpetas en Acceso rápido", en: "Quick Access Folders"), systemImage: "star")
                }

                Toggle(isOn: $sessionPrefs.rememberOpenTabsOnLaunch) {
                    Label(loc.text(es: "Recordar carpetas y pestañas abiertas al iniciar", en: "Remember open folders & tabs on launch"), systemImage: "clock.arrow.circlepath")
                }

                Toggle(isOn: $trayIconPrefs.isTrayIconEnabled) {
                    Label(loc.text(es: "Mostrar icono en la barra de menús (Tray Icon)", en: "Show icon in menu bar (Tray Icon)"), systemImage: "menubar.rectangle")
                }

                Toggle(isOn: $clipboardPrefs.isEnabled) {
                    Label(loc.text(es: "Mostrar Historial del Portapapeles (Maccy)", en: "Show Clipboard History (Maccy)"), systemImage: "doc.on.clipboard")
                }

                Toggle(isOn: $slackPrefs.isShareToSlackEnabled) {
                    Label(loc.text(es: "Mostrar «Añadir a Slack» (Compartir con Slack)", en: "Show «Add to Slack» (Share with Slack)"), systemImage: "bubble.left.and.bubble.right")
                }

                Toggle(isOn: $mousePrefs.swapSideButtons) {
                    Label(loc.text(es: "Invertir botones laterales del ratón (Atrás/Adelante)", en: "Swap mouse side buttons (Back/Forward)"), systemImage: "computermouse")
                }

                Divider()

                Button {
                    if let activeID = GoogleAccountsManager.shared.activeTabID {
                        GoogleAccountsManager.shared.zoomInTab(activeID)
                    }
                } label: {
                    Label(loc.text(es: "Acercar página web", en: "Zoom In Web Page"), systemImage: "plus.magnifyingglass")
                }
                .keyboardShortcut("+", modifiers: [.command])
                .disabled(GoogleAccountsManager.shared.activeTabID == nil)

                Button {
                    if let activeID = GoogleAccountsManager.shared.activeTabID {
                        GoogleAccountsManager.shared.zoomOutTab(activeID)
                    }
                } label: {
                    Label(loc.text(es: "Alejar página web", en: "Zoom Out Web Page"), systemImage: "minus.magnifyingglass")
                }
                .keyboardShortcut("-", modifiers: [.command])
                .disabled(GoogleAccountsManager.shared.activeTabID == nil)

                Button {
                    if let activeID = GoogleAccountsManager.shared.activeTabID {
                        GoogleAccountsManager.shared.resetZoomInTab(activeID)
                    }
                } label: {
                    Label(loc.text(es: "Restablecer zoom web (100%)", en: "Reset Web Zoom (100%)"), systemImage: "arrow.counterclockwise")
                }
                .keyboardShortcut("0", modifiers: [.command])
                .disabled(GoogleAccountsManager.shared.activeTabID == nil)

                Divider()
            }

            CommandMenu(loc.text(es: "Ir", en: "Go")) {
                Button {
                    navigateBack()
                } label: {
                    Label(loc.text(es: "Atrás", en: "Back"), systemImage: "chevron.backward")
                }
                .keyboardShortcut("[", modifiers: [.command])
                .disabled(!canNavigateBack)

                Button {
                    navigateForward()
                } label: {
                    Label(loc.text(es: "Adelante", en: "Forward"), systemImage: "chevron.forward")
                }
                .keyboardShortcut("]", modifiers: [.command])
                .disabled(!canNavigateForward)

                Divider()

                Button {
                    navigateUp()
                } label: {
                    Label(loc.text(es: "Subir un nivel", en: "Enclosing Folder"), systemImage: "arrow.up")
                }
                .keyboardShortcut(.upArrow, modifiers: [.command])
                .disabled(!canNavigateUp)

                Divider()

                Button {
                    navigateToHome()
                } label: {
                    Label(loc.text(es: "Inicio", en: "Home"), systemImage: "house")
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            }

            CommandMenu(loc.text(es: "Portapapeles", en: "Clipboard")) {
                Toggle(isOn: $clipboardPrefs.isEnabled) {
                    Label(
                        loc.text(es: "Activar Historial del Portapapeles", en: "Enable Clipboard History"),
                        systemImage: "doc.on.clipboard"
                    )
                }

                Divider()

                Button {
                    ClipboardQuickPopupController.shared.showPopup()
                } label: {
                    Label(
                        loc.text(
                            es: "Abrir menú desplegable rápido (\(clipboardPrefs.quickPasteDropdownShortcut.displayString))",
                            en: "Open Quick Paste Dropdown (\(clipboardPrefs.quickPasteDropdownShortcut.displayString))"
                        ),
                        systemImage: "macwindow.on.rectangle"
                    )
                }
                .disabled(!clipboardPrefs.isEnabled)

                Button {
                    ClipboardQuickPopupController.shared.openFullHistoryInMainWindow()
                } label: {
                    Label(
                        loc.text(
                            es: "Buscar en todo el historial… (\(clipboardPrefs.fullHistorySearchShortcut.displayString))",
                            en: "Search Full Clipboard History… (\(clipboardPrefs.fullHistorySearchShortcut.displayString))"
                        ),
                        systemImage: "magnifyingglass"
                    )
                }
                .disabled(!clipboardPrefs.isEnabled)

                Divider()

                Menu {
                    Picker(
                        loc.text(es: "Tiempo de guardado", en: "Retention Time"),
                        selection: $clipboardPrefs.retentionPeriod
                    ) {
                        ForEach(ClipboardRetentionPeriod.allCases) { period in
                            Label(period.localizedTitle(using: loc), systemImage: "clock")
                                .tag(period)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(loc.text(es: "Tiempo de guardado", en: "Retention Time"), systemImage: "clock")
                }

                Menu {
                    Picker(
                        loc.text(es: "Cantidad máxima", en: "Maximum Items"),
                        selection: $clipboardPrefs.maxItemsOption
                    ) {
                        ForEach(ClipboardMaxItemsOption.allCases) { option in
                            Label(option.localizedTitle(using: loc), systemImage: "number.circle")
                                .tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(loc.text(es: "Cantidad máxima", en: "Maximum Items"), systemImage: "number.circle")
                }

                Menu {
                    Picker(
                        loc.text(es: "Elementos en menú desplegable", en: "Items in Quick Dropdown"),
                        selection: $clipboardPrefs.dropdownCountOption
                    ) {
                        ForEach(ClipboardDropdownCountOption.allCases) { option in
                            Label(option.localizedTitle(using: loc), systemImage: "list.number")
                                .tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(
                        loc.text(es: "Elementos en menú desplegable (últimos 10)", en: "Items in Quick Dropdown (Last 10)"),
                        systemImage: "list.number"
                    )
                }

                Divider()

                Menu {
                    Button {
                        ClipboardShortcutsWindowController.shared.show()
                    } label: {
                        Label(
                            loc.text(es: "Personalizar todos los atajos de teclado…", en: "Customize All Keyboard Shortcuts…"),
                            systemImage: "keyboard"
                        )
                    }

                    Divider()

                    Picker(
                        loc.text(es: "Atajo de Pegar (Menú desplegable)", en: "Paste Dropdown Shortcut"),
                        selection: $clipboardPrefs.popupShortcutPreset
                    ) {
                        ForEach(ClipboardPopupShortcutPreset.allCases) { preset in
                            Label(preset.localizedTitle(using: loc), systemImage: "command")
                                .tag(preset)
                        }
                    }
                    .pickerStyle(.inline)

                    Divider()

                    Button {
                        clipboardPrefs.resetShortcutsToDefaults()
                    } label: {
                        Label(
                            loc.text(es: "Restablecer atajos predeterminados (Maccy)", en: "Reset Shortcuts to Defaults (Maccy)"),
                            systemImage: "arrow.counterclockwise"
                        )
                    }
                } label: {
                    Label(
                        loc.text(es: "Configuración de atajos (Shortcuts)", en: "Shortcuts Configuration"),
                        systemImage: "keyboard"
                    )
                }

                Button {
                    ClipboardShortcutsWindowController.shared.show()
                } label: {
                    Label(
                        loc.text(es: "Abrir panel de atajos y ajustes…", en: "Open Shortcuts & Settings Panel…"),
                        systemImage: "slider.horizontal.3"
                    )
                }

                Toggle(isOn: $clipboardPrefs.autoPasteOnSelect) {
                    Label(
                        loc.text(
                            es: "Pegar automáticamente al elegir del menú desplegable",
                            en: "Auto-paste on dropdown selection"
                        ),
                        systemImage: "arrow.turn.down.left"
                    )
                }

                Divider()

                Button(role: .destructive) {
                    ClipboardHistoryManager.shared.clearUnpinnedHistory()
                } label: {
                    Label(
                        loc.text(
                            es: "Limpiar historial no fijado (\(clipboardPrefs.clearHistoryShortcut.displayString))",
                            en: "Clear Unpinned History (\(clipboardPrefs.clearHistoryShortcut.displayString))"
                        ),
                        systemImage: "trash"
                    )
                }
                .disabled(ClipboardHistoryManager.shared.items.allSatisfy(\.isPinned))
            }

            CommandMenu(loc.text(es: "Idioma", en: "Language")) {
                languageSelectionPicker
            }

            CommandGroup(replacing: .help) {
                Button {
                    HelpWindowController.shared.show(section: .highlights)
                } label: {
                    Label(loc.text(es: "Ayuda de MacFileExplorer", en: "MacFileExplorer Help"), systemImage: "questionmark.circle")
                }
                .keyboardShortcut("?", modifiers: [.command])

                Divider()

                Button {
                    HelpWindowController.shared.show(section: .sidebar)
                } label: {
                    Label(loc.text(es: "Guía del Menú Lateral…", en: "Sidebar Menu Guide…"), systemImage: "sidebar.left")
                }

                Button {
                    HelpWindowController.shared.show(section: .search)
                } label: {
                    Label(loc.text(es: "Guía de Búsqueda y OCR…", en: "Search & OCR Guide…"), systemImage: "magnifyingglass")
                }

                Button {
                    HelpWindowController.shared.show(section: .shortcuts)
                } label: {
                    Label(loc.text(es: "Atajos de teclado…", en: "Keyboard Shortcuts…"), systemImage: "keyboard")
                }

                Button {
                    HelpWindowController.shared.show(section: .settings)
                } label: {
                    Label(loc.text(es: "Configuraciones posibles…", en: "Available Settings…"), systemImage: "slider.horizontal.3")
                }

                Divider()

                Button {
                    HelpWindowController.shared.show(section: .releases)
                } label: {
                    Label(loc.text(es: "Historial de releases…", en: "Release History…"), systemImage: "sparkles")
                }
            }
        }
    }

    @ViewBuilder
    private var languageSelectionPicker: some View {
        Picker(loc.text(es: "Idioma", en: "Language"), selection: $loc.preference) {
            ForEach(AppLanguagePreference.allCases) { option in
                Label(
                    loc.displayName(for: option),
                    systemImage: option == .spanish ? "globe.americas.fill" : "globe.europe.africa.fill"
                )
                .tag(option)
            }
        }
        .pickerStyle(.inline)
    }

    private var activeExplorerViewModel: ExplorerViewModel? {
        focusedExplorerViewModel
            ?? ExplorerWindowRegistry.shared.viewModel(for: NSApp.keyWindow)
            ?? ExplorerWindowRegistry.shared.viewModel(for: NSApp.mainWindow)
            ?? ExplorerWindowRegistry.shared.activeViewModel
    }

    private var activeGoogleWebTabID: UUID? {
        let activeWindow = NSApp.keyWindow ?? NSApp.mainWindow
        let effective = activeWindow?.tabGroup?.selectedWindow ?? activeWindow
        return GoogleAccountsManager.shared.activeTabID(for: effective)
            ?? (effective == nil ? GoogleAccountsManager.shared.activeTabID : nil)
    }

    private var canNavigateBack: Bool {
        if let activeID = activeGoogleWebTabID {
            return GoogleAccountsManager.shared.tab(for: activeID)?.canGoBack ?? false
        }
        return activeExplorerViewModel?.canGoBack ?? false
    }

    private var canNavigateForward: Bool {
        if let activeID = activeGoogleWebTabID {
            return GoogleAccountsManager.shared.tab(for: activeID)?.canGoForward ?? false
        }
        return activeExplorerViewModel?.canGoForward ?? false
    }

    private var canNavigateUp: Bool {
        if activeGoogleWebTabID != nil {
            return false
        }
        return activeExplorerViewModel?.canGoUp ?? false
    }

    private func navigateBack() {
        MouseNavigationManager.shared.navigate(isBack: true)
    }

    private func navigateForward() {
        MouseNavigationManager.shared.navigate(isBack: false)
    }

    private func navigateUp() {
        activeExplorerViewModel?.goUp()
    }

    private func navigateToHome() {
        activeExplorerViewModel?.navigate(to: FileManager.default.homeDirectoryForCurrentUser)
    }

    private var undoMenuItemTitle: String {
        if isTextOrWebResponderActive || activeExplorerViewModel == nil {
            return loc.text(es: "Deshacer", en: "Undo")
        }
        return activeExplorerViewModel?.undoMenuTitle ?? loc.text(es: "Deshacer", en: "Undo")
    }

    private var redoMenuItemTitle: String {
        if isTextOrWebResponderActive || activeExplorerViewModel == nil {
            return loc.text(es: "Rehacer", en: "Redo")
        }
        return activeExplorerViewModel?.redoMenuTitle ?? loc.text(es: "Rehacer", en: "Redo")
    }

    private var isTextOrWebResponderActive: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder is NSTextView || responder is NSText {
            return true
        }
        return NSStringFromClass(type(of: responder)).contains("WK")
    }

    private func showAboutPanel() {
        AboutWindowController.shared.show()
    }
}
