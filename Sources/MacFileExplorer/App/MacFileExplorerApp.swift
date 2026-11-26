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
        ToolsShortcutManager.shared.installIfNeeded()
        TaskbarManager.shared.installIfNeeded()
        AltTabManager.shared.installIfNeeded()
        NotchManager.shared.installIfNeeded()
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
        !(TrayIconPreferences.shared.isTrayIconEnabled
            || TaskbarPreferences.shared.isEnabled
            || AltTabPreferences.shared.isEnabled
            || NotchPreferences.shared.isEnabled)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        ToolsShortcutManager.shared.unregisterGlobalHotKeys()
        TaskbarManager.shared.prepareForTermination()
        AltTabManager.shared.prepareForTermination()
        NotchManager.shared.prepareForTermination()
        GoogleAccountsManager.shared.prepareForTermination()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        ToolsShortcutManager.shared.unregisterGlobalHotKeys()
        TaskbarManager.shared.prepareForTermination()
        AltTabManager.shared.prepareForTermination()
        NotchManager.shared.prepareForTermination()
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
    @Bindable private var appShortcutPrefs = AppShortcutPreferences.shared
    @Bindable private var taskbarPrefs = TaskbarPreferences.shared
    @Bindable private var altTabPrefs = AltTabPreferences.shared
    @Bindable private var notchPrefs = NotchPreferences.shared
    @Bindable private var notchMedia = NotchMediaService.shared
    @Bindable private var notchManager = NotchManager.shared
    @Bindable private var officePrefs = OfficePreferences.shared
    @Bindable private var drivePrefs = GoogleDriveUploadPreferences.shared
    @Bindable private var googleManager = GoogleAccountsManager.shared
    @Bindable private var fileIconProvider = FileIconProvider.shared
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
                    Label(loc.text(es: "Buscar actualizaciones…", en: "Check for Updates…"), systemImage: "arrow.down.circle")
                }

                Button {
                    MonthlySupportCheckManager.shared.presentPopup(triggerUpdateCheck: true)
                } label: {
                    Label(loc.text(es: "Apoyar proyecto (Propina Ko-fi)…", en: "Support Project (Ko-fi Tip)…"), systemImage: "heart.circle")
                }

                Menu {
                    Picker(
                        loc.text(es: "Ícono de la aplicación", en: "App Icon"),
                        selection: $fileIconProvider.selectedAppIcon
                    ) {
                        ForEach(MacFileExplorerAppIcon.allCases) { option in
                            Label(option.localizedTitle(using: loc), systemImage: option.menuSymbolName)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.inline)

                    Divider()

                    Button {
                        AppIconPickerWindowController.shared.show()
                    } label: {
                        Label(
                            loc.text(es: "Elegir ícono con vista previa…", en: "Choose Icon with Preview…"),
                            systemImage: "app.dashed"
                        )
                    }
                } label: {
                    Label(
                        loc.text(es: "Ícono de la aplicación", en: "App Icon"),
                        systemImage: "app.badge.checkmark"
                    )
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
                .optionalKeyboardShortcut(appShortcutPrefs.swiftUIShortcut(for: .newFolderTab))

                Button {
                    let sourceWindow = NSApp.keyWindow ?? NSApp.mainWindow
                    GoogleAccountsManager.shared.closeCurrentTabWindow(from: sourceWindow)
                } label: {
                    Label(loc.text(es: "Cerrar pestaña actual", en: "Close Current Tab"), systemImage: "xmark.circle")
                }
                .optionalKeyboardShortcut(appShortcutPrefs.swiftUIShortcut(for: .closeCurrentTab))
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
                .optionalKeyboardShortcut(appShortcutPrefs.swiftUIShortcut(for: .findDuplicateFiles))
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
                .optionalKeyboardShortcut(appShortcutPrefs.swiftUIShortcut(for: .openHiddenCache))
                .disabled((focusedExplorerViewModel ?? activeExplorerViewModel) == nil)

                Divider()

                Button {
                    AppShortcutsWindowController.shared.show(initialCategory: .all)
                } label: {
                    Label(
                        loc.text(es: "Administrar todos los atajos de teclado…", en: "Manage All Keyboard Shortcuts…"),
                        systemImage: "keyboard"
                    )
                }

                Menu {
                    Toggle(isOn: $appShortcutPrefs.isViewDesktopShortcutEnabled) {
                        Label(
                            loc.text(
                                es: "View Desktop Shortcut (\(appShortcutPrefs.viewDesktopShortcut.displayString))",
                                en: "View Desktop Shortcut (\(appShortcutPrefs.viewDesktopShortcut.displayString))"
                            ),
                            systemImage: "macwindow.on.rectangle"
                        )
                    }

                    Button {
                        ToolsShortcutManager.shared.triggerViewDesktop()
                    } label: {
                        Label(
                            loc.text(es: "Ver Escritorio ahora", en: "View Desktop Now"),
                            systemImage: "menubar.dock.rectangle"
                        )
                    }

                    Menu {
                        Picker(
                            loc.text(es: "Modo de «Ver Escritorio»", en: "View Desktop Mode"),
                            selection: $appShortcutPrefs.viewDesktopBehavior
                        ) {
                            ForEach(ViewDesktopBehavior.allCases) { mode in
                                Label(mode.localizedTitle(using: loc), systemImage: mode.systemImage)
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label(
                            loc.text(es: "Modo de «Ver Escritorio»", en: "View Desktop Mode"),
                            systemImage: "rectangle.inset.bottomleft.filled"
                        )
                    }

                    Divider()

                    Button {
                        ToolsSettingsWindowController.shared.show(initialSection: .viewDesktop)
                    } label: {
                        Label(
                            loc.text(es: "Configuración de Herramientas…", en: "Tools Settings…"),
                            systemImage: "slider.horizontal.3"
                        )
                    }

                    Button {
                        AppShortcutsWindowController.shared.show(initialCategory: .tools)
                    } label: {
                        Label(
                            loc.text(es: "Administrar todos los atajos…", en: "Manage All Shortcuts…"),
                            systemImage: "keyboard"
                        )
                    }
                } label: {
                    Label(
                        loc.text(es: "Herramientas", en: "Tools"),
                        systemImage: "wrench.and.screwdriver"
                    )
                }
            }

            CommandGroup(after: .toolbar) {
                Divider()
                Toggle(isOn: $bookmarksManager.isBookmarksBarVisible) {
                    Label(loc.text(es: "Mostrar barra de marcadores", en: "Show Bookmarks Bar"), systemImage: "bookmark")
                }
                .optionalKeyboardShortcut(appShortcutPrefs.swiftUIShortcut(for: .toggleBookmarksBar))

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
                .optionalKeyboardShortcut(appShortcutPrefs.swiftUIShortcut(for: .zoomInWeb))
                .disabled(GoogleAccountsManager.shared.activeTabID == nil)

                Button {
                    if let activeID = GoogleAccountsManager.shared.activeTabID {
                        GoogleAccountsManager.shared.zoomOutTab(activeID)
                    }
                } label: {
                    Label(loc.text(es: "Alejar página web", en: "Zoom Out Web Page"), systemImage: "minus.magnifyingglass")
                }
                .optionalKeyboardShortcut(appShortcutPrefs.swiftUIShortcut(for: .zoomOutWeb))
                .disabled(GoogleAccountsManager.shared.activeTabID == nil)

                Button {
                    if let activeID = GoogleAccountsManager.shared.activeTabID {
                        GoogleAccountsManager.shared.resetZoomInTab(activeID)
                    }
                } label: {
                    Label(loc.text(es: "Restablecer zoom web (100%)", en: "Reset Web Zoom (100%)"), systemImage: "arrow.counterclockwise")
                }
                .optionalKeyboardShortcut(appShortcutPrefs.swiftUIShortcut(for: .resetZoomWeb))
                .disabled(GoogleAccountsManager.shared.activeTabID == nil)

                Divider()
            }

            CommandMenu(loc.text(es: "Ir", en: "Go")) {
                Button {
                    navigateBack()
                } label: {
                    Label(loc.text(es: "Atrás", en: "Back"), systemImage: "chevron.backward")
                }
                .optionalKeyboardShortcut(appShortcutPrefs.swiftUIShortcut(for: .goBack))
                .disabled(!canNavigateBack)

                Button {
                    navigateForward()
                } label: {
                    Label(loc.text(es: "Adelante", en: "Forward"), systemImage: "chevron.forward")
                }
                .optionalKeyboardShortcut(appShortcutPrefs.swiftUIShortcut(for: .goForward))
                .disabled(!canNavigateForward)

                Divider()

                Button {
                    navigateUp()
                } label: {
                    Label(loc.text(es: "Subir un nivel", en: "Enclosing Folder"), systemImage: "arrow.up")
                }
                .optionalKeyboardShortcut(appShortcutPrefs.swiftUIShortcut(for: .goUp))
                .disabled(!canNavigateUp)

                Divider()

                Button {
                    navigateToHome()
                } label: {
                    Label(loc.text(es: "Inicio", en: "Home"), systemImage: "house")
                }
                .optionalKeyboardShortcut(appShortcutPrefs.swiftUIShortcut(for: .goHome))
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
                        loc.text(es: "Configuración del Portapapeles…", en: "Clipboard Settings…"),
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

            CommandMenu(loc.text(es: "Barra de tareas", en: "Taskbar")) {
                Toggle(isOn: Binding(
                    get: { taskbarPrefs.isEnabled },
                    set: { TaskbarManager.shared.setEnabled($0) }
                )) {
                    Label(
                        loc.text(es: "Activar barra de tareas", en: "Enable Taskbar"),
                        systemImage: "dock.rectangle"
                    )
                }

                Toggle(isOn: $taskbarPrefs.startEnabledByDefault) {
                    Label(
                        loc.text(es: "Activar por defecto al iniciar MacFileExplorer", en: "Enable by Default on Launch"),
                        systemImage: "power.circle"
                    )
                }

                Divider()

                Button {
                    TaskbarManager.shared.toggleStartMenu()
                } label: {
                    Label(loc.text(es: "Abrir Menú Inicio", en: "Open Start Menu"), systemImage: "square.grid.2x2")
                }
                .disabled(!taskbarPrefs.isEnabled)

                Button {
                    TaskbarSettingsWindowController.shared.show()
                } label: {
                    Label(
                        loc.text(es: "Configuración de la barra de tareas…", en: "Taskbar Settings…"),
                        systemImage: "slider.horizontal.3"
                    )
                }

                Button {
                    TaskbarSetupWizardWindowController.shared.show()
                } label: {
                    Label(
                        loc.text(es: "Asistente de permisos y configuración…", en: "Setup & Permissions Assistant…"),
                        systemImage: "lock.shield"
                    )
                }

                Divider()

                Toggle(isOn: $taskbarPrefs.showHoverPreviews) {
                    Label(
                        loc.text(es: "Vista previa al pasar el cursor", en: "Hover Window Previews"),
                        systemImage: "rectangle.on.rectangle.angled"
                    )
                }

                Toggle(isOn: $taskbarPrefs.groupWindowsByApp) {
                    Label(
                        loc.text(
                            es: "Mantener ventanas de la misma app juntas (lado a lado)",
                            en: "Keep Same-App Windows Side by Side"
                        ),
                        systemImage: "rectangle.split.2x1"
                    )
                }

                Toggle(isOn: $taskbarPrefs.orderWindowsByPinnedApps) {
                    Label(
                        loc.text(
                            es: "Apps fijadas primero en la barra (en su mismo orden)",
                            en: "Pinned Apps' Windows First (in Pinned Order)"
                        ),
                        systemImage: "pin.circle"
                    )
                }

                Toggle(isOn: Binding(
                    get: { taskbarPrefs.overflowMode == .shrinkToFit },
                    set: { taskbarPrefs.overflowMode = $0 ? .shrinkToFit : .horizontalScroll }
                )) {
                    Label(
                        loc.text(
                            es: "Ajustar ancho sin scroll horizontal",
                            en: "Auto-Shrink Buttons (No Scroll)"
                        ),
                        systemImage: "arrow.right.and.line.vertical.and.arrow.left"
                    )
                }

                Toggle(isOn: $taskbarPrefs.iconsOnlyMode) {
                    Label(
                        loc.text(es: "Mostrar solo íconos", en: "Show Icons Only"),
                        systemImage: "square.grid.2x2"
                    )
                }

                Toggle(isOn: Binding(
                    get: { taskbarPrefs.minimizedWindowDisplayMode == .iconOnly },
                    set: { taskbarPrefs.minimizedWindowDisplayMode = $0 ? .iconOnly : .sameAsNormal }
                )) {
                    Label(
                        loc.text(es: "Solo ícono en ventanas minimizadas", en: "Icon Only for Minimized Windows"),
                        systemImage: "app.dashed"
                    )
                }
                .disabled(taskbarPrefs.iconsOnlyMode)

                Toggle(isOn: $taskbarPrefs.autoResizeOverlappingWindows) {
                    Label(
                        loc.text(es: "Redimensionar ventanas superpuestas", en: "Auto-Resize Overlapping Windows"),
                        systemImage: "arrow.up.left.and.arrow.down.right"
                    )
                }

                Divider()

                Menu {
                    Picker(
                        loc.text(es: "Mostrar barra en", en: "Show Bar On"),
                        selection: $taskbarPrefs.displayMode
                    ) {
                        ForEach(TaskbarDisplayMode.allCases) { mode in
                            Label(mode.localizedTitle(using: loc), systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.inline)

                    Divider()

                    Picker(
                        loc.text(es: "Ventanas por barra", en: "Windows Per Bar"),
                        selection: $taskbarPrefs.windowScopeMode
                    ) {
                        ForEach(TaskbarWindowScopeMode.allCases) { scope in
                            Label(scope.localizedTitle(using: loc), systemImage: scope.systemImage)
                                .tag(scope)
                        }
                    }
                    .pickerStyle(.inline)

                    Divider()

                    Toggle(isOn: $taskbarPrefs.syncWithActiveSpace) {
                        Label(
                            loc.text(es: "Sincronizar con Espacios (Spaces)", en: "Sync with macOS Spaces"),
                            systemImage: "squares.leading.rectangle"
                        )
                    }

                    if !taskbarPrefs.hiddenDisplayIDs.isEmpty {
                        Divider()
                        Button {
                            taskbarPrefs.showAllHiddenDisplays()
                        } label: {
                            Label(
                                loc.text(es: "Mostrar todas las pantallas ocultas", en: "Show All Hidden Displays"),
                                systemImage: "eye"
                            )
                        }
                    }
                } label: {
                    Label(loc.text(es: "Monitores y Espacios", en: "Displays & Spaces"), systemImage: "display.2")
                }

                Menu {
                    Picker(loc.text(es: "Tema", en: "Theme"), selection: $taskbarPrefs.themeMode) {
                        ForEach(TaskbarThemeMode.allCases) { mode in
                            Label(mode.localizedTitle(using: loc), systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.inline)

                    Divider()

                    Picker(loc.text(es: "Alineación", en: "Alignment"), selection: $taskbarPrefs.alignment) {
                        ForEach(TaskbarAlignment.allCases) { alignment in
                            Label(alignment.localizedTitle(using: loc), systemImage: alignment.systemImage)
                                .tag(alignment)
                        }
                    }
                    .pickerStyle(.inline)

                    Divider()

                    Menu {
                        Picker(
                            loc.text(es: "Ícono del botón Inicio", en: "Start Button Icon"),
                            selection: $taskbarPrefs.startButtonIcon
                        ) {
                            ForEach(TaskbarStartButtonIcon.allCases) { iconOption in
                                Label(iconOption.localizedTitle(using: loc), systemImage: iconOption.menuSymbolName)
                                    .tag(iconOption)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label(
                            loc.text(es: "Ícono del botón Inicio", en: "Start Button Icon"),
                            systemImage: "sparkles.square.filled.on.square"
                        )
                    }

                    Menu {
                        Picker(
                            loc.text(es: "Animación de notificaciones", en: "Notification Animation"),
                            selection: $taskbarPrefs.notificationAnimation
                        ) {
                            ForEach(TaskbarNotificationAnimation.allCases) { animOption in
                                Label(animOption.localizedTitle(using: loc), systemImage: animOption.symbolName)
                                    .tag(animOption)
                            }
                        }
                        .pickerStyle(.inline)

                        if taskbarPrefs.notificationAnimation != .none {
                            Divider()

                            Picker(
                                loc.text(es: "Frecuencia", en: "Cadence"),
                                selection: $taskbarPrefs.notificationAnimationCadence
                            ) {
                                ForEach(TaskbarNotificationAnimationCadence.allCases) { cadence in
                                    Label(cadence.localizedTitle(using: loc), systemImage: cadence.symbolName)
                                        .tag(cadence)
                                }
                            }
                            .pickerStyle(.inline)
                        }
                    } label: {
                        Label(
                            loc.text(es: "Animación de notificaciones", en: "Notification Animation"),
                            systemImage: "bell.badge.fill"
                        )
                    }

                    Menu {
                        Picker(
                            loc.text(es: "Animación de vista previa", en: "Hover Preview Animation"),
                            selection: $taskbarPrefs.hoverPreviewAnimation
                        ) {
                            ForEach(TaskbarHoverPreviewAnimation.allCases) { animOption in
                                Label(animOption.localizedTitle(using: loc), systemImage: animOption.symbolName)
                                    .tag(animOption)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label(
                            loc.text(es: "Animación de vista previa", en: "Hover Preview Animation"),
                            systemImage: "rectangle.on.rectangle.angled"
                        )
                    }

                    Menu {
                        Picker(
                            loc.text(es: "Animación del Menú Inicio", en: "Start Menu Animation"),
                            selection: $taskbarPrefs.startMenuAnimation
                        ) {
                            ForEach(TaskbarStartMenuAnimation.allCases) { animOption in
                                let badge = animOption.category.localizedBadge(using: loc)
                                let title = badge.map { "\(animOption.localizedTitle(using: loc)) (\($0))" } ?? animOption.localizedTitle(using: loc)
                                Label(title, systemImage: animOption.symbolName)
                                    .tag(animOption)
                            }
                        }
                        .pickerStyle(.inline)

                        Divider()

                        Button {
                            taskbarPrefs.startMenuAnimationDuration = 0.0
                        } label: {
                            Label(
                                loc.text(es: "Velocidad: Instantáneo (0 ms)", en: "Speed: Instant (0 ms)"),
                                systemImage: taskbarPrefs.startMenuAnimationDuration <= 0.001 ? "checkmark.circle.fill" : "bolt.fill"
                            )
                        }
                        Button {
                            taskbarPrefs.startMenuAnimationDuration = 0.15
                        } label: {
                            Label(
                                loc.text(es: "Velocidad: Rápido (150 ms)", en: "Speed: Fast (150 ms)"),
                                systemImage: abs(taskbarPrefs.startMenuAnimationDuration - 0.15) < 0.013 ? "checkmark.circle.fill" : "hare"
                            )
                        }
                        Button {
                            taskbarPrefs.startMenuAnimationDuration = 0.22
                        } label: {
                            Label(
                                loc.text(es: "Velocidad: Normal (220 ms)", en: "Speed: Normal (220 ms)"),
                                systemImage: abs(taskbarPrefs.startMenuAnimationDuration - 0.22) < 0.013 ? "checkmark.circle.fill" : "gauge.with.needle"
                            )
                        }
                        Button {
                            taskbarPrefs.startMenuAnimationDuration = 0.42
                        } label: {
                            Label(
                                loc.text(es: "Velocidad: Suave (420 ms)", en: "Speed: Smooth (420 ms)"),
                                systemImage: abs(taskbarPrefs.startMenuAnimationDuration - 0.42) < 0.013 ? "checkmark.circle.fill" : "tortoise"
                            )
                        }
                    } label: {
                        Label(
                            loc.text(es: "Animación del Menú Inicio", en: "Start Menu Animation"),
                            systemImage: "sparkles.rectangle.stack"
                        )
                    }

                    Divider()

                    Toggle(
                        loc.text(es: "Mostrar línea divisoria superior", en: "Show Top Divider Line"),
                        isOn: $taskbarPrefs.showTopBorder
                    )

                    Menu {
                        Picker(
                            loc.text(es: "Estilo de la barra", en: "Bar Style"),
                            selection: $taskbarPrefs.barStyle
                        ) {
                            ForEach(TaskbarBarStyle.allCases) { style in
                                Text(style.localizedTitle(using: loc)).tag(style)
                            }
                        }
                        .pickerStyle(.inline)

                        Divider()

                        Picker(
                            loc.text(es: "Material de fondo", en: "Background Material"),
                            selection: $taskbarPrefs.backgroundMaterial
                        ) {
                            ForEach(TaskbarBackgroundMaterial.allCases) { material in
                                Text(material.localizedTitle(using: loc)).tag(material)
                            }
                        }
                        .pickerStyle(.inline)

                        Divider()

                        Picker(
                            loc.text(es: "Estilo de botones", en: "Button Style"),
                            selection: $taskbarPrefs.buttonStyle
                        ) {
                            ForEach(TaskbarButtonStyle.allCases) { style in
                                Text(style.localizedTitle(using: loc)).tag(style)
                            }
                        }
                        .pickerStyle(.inline)

                        Divider()

                        Picker(
                            loc.text(es: "Indicador de ventana activa", en: "Active Window Indicator"),
                            selection: $taskbarPrefs.activeIndicatorStyle
                        ) {
                            ForEach(TaskbarActiveIndicatorStyle.allCases) { style in
                                Text(style.localizedTitle(using: loc)).tag(style)
                            }
                        }
                        .pickerStyle(.inline)

                        Divider()

                        Picker(
                            loc.text(es: "Color del indicador activo", en: "Active Indicator Color"),
                            selection: $taskbarPrefs.activeIndicatorColor
                        ) {
                            ForEach(TaskbarActiveIndicatorColor.allCases) { color in
                                Text(color.localizedTitle(using: loc)).tag(color)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label(
                            loc.text(es: "Estilo visual de la barra", en: "Bar Visual Style"),
                            systemImage: "slider.horizontal.below.rectangle"
                        )
                    }

                    Divider()

                    Button {
                        taskbarPrefs.barHeight = 36
                    } label: {
                        Label(loc.text(es: "Tamaño Compacto (36 px)", en: "Compact Size (36 px)"), systemImage: "rectangle.compress.vertical")
                    }
                    Button {
                        taskbarPrefs.barHeight = 42
                    } label: {
                        Label(loc.text(es: "Tamaño Normal (42 px)", en: "Normal Size (42 px)"), systemImage: "rectangle")
                    }
                    Button {
                        taskbarPrefs.barHeight = 50
                    } label: {
                        Label(loc.text(es: "Tamaño Grande (50 px)", en: "Large Size (50 px)"), systemImage: "rectangle.expand.vertical")
                    }
                    Button {
                        taskbarPrefs.barHeight = 58
                    } label: {
                        Label(loc.text(es: "Tamaño Extra grande (58 px)", en: "Extra Large Size (58 px)"), systemImage: "rectangle.expand.vertical")
                    }
                } label: {
                    Label(loc.text(es: "Tema y tamaño", en: "Theme & Size"), systemImage: "paintbrush")
                }

                Menu {
                    ForEach(TaskbarDockMode.allCases) { mode in
                        Button {
                            TaskbarDockManager.shared.applyUserSelectedDockMode(mode)
                        } label: {
                            Label(
                                mode.localizedTitle(using: loc),
                                systemImage: taskbarPrefs.dockMode == mode ? "checkmark.circle.fill" : mode.systemImage
                            )
                        }
                    }

                    Divider()

                    Button {
                        TaskbarDockManager.shared.emergencyRestoreOriginalMacOSDock(forceFactoryDefaults: false)
                    } label: {
                        Label(
                            loc.text(es: "Emergencia: Restaurar Dock original de macOS", en: "Emergency: Restore Original macOS Dock"),
                            systemImage: "arrow.uturn.backward.circle"
                        )
                    }

                    Button {
                        TaskbarDockManager.shared.emergencyRestoreOriginalMacOSDock(forceFactoryDefaults: true)
                    } label: {
                        Label(
                            loc.text(es: "Forzar Dock de fábrica (Abajo y visible)", en: "Force Factory macOS Dock (Bottom & Visible)"),
                            systemImage: "exclamationmark.shield"
                        )
                    }
                } label: {
                    Label(loc.text(es: "Gestión del Dock de macOS", en: "macOS Dock Management"), systemImage: "dock.rectangle")
                }

                Divider()

                Button {
                    TaskbarDockManager.shared.emergencyRestoreOriginalMacOSDock(forceFactoryDefaults: false)
                } label: {
                    Label(
                        loc.text(es: "Emergencia: Restaurar Dock original de macOS", en: "Emergency: Restore Original macOS Dock"),
                        systemImage: "arrow.uturn.backward.circle"
                    )
                }
            }

            CommandMenu("AltTab") {
                Toggle(isOn: Binding(
                    get: { altTabPrefs.isEnabled },
                    set: { AltTabManager.shared.setEnabled($0) }
                )) {
                    Label(
                        loc.text(
                            es: "Activar AltTab (\(altTabPrefs.primaryShortcutDisplay))",
                            en: "Enable AltTab (\(altTabPrefs.primaryShortcutDisplay))"
                        ),
                        systemImage: "rectangle.stack.fill"
                    )
                }

                Toggle(isOn: $altTabPrefs.startEnabledByDefault) {
                    Label(
                        loc.text(es: "Activar por defecto al iniciar MacFileExplorer", en: "Enable by Default on Launch"),
                        systemImage: "power.circle"
                    )
                }

                Divider()

                Button {
                    AltTabManager.shared.openInteractiveTestSwitcher()
                } label: {
                    Label(
                        loc.text(es: "Probar selector de ventanas ahora", en: "Test Window Switcher Now"),
                        systemImage: "play.rectangle"
                    )
                }

                Button {
                    AltTabSettingsWindowController.shared.show(tab: .general)
                } label: {
                    Label(
                        loc.text(es: "Configuración de AltTab…", en: "AltTab Settings…"),
                        systemImage: "slider.horizontal.3"
                    )
                }

                Divider()

                Menu {
                    Picker(
                        loc.text(es: "Estilo de visualización", en: "Display Style"),
                        selection: $altTabPrefs.displayStyle
                    ) {
                        ForEach(AltTabDisplayStyle.allCases) { style in
                            Label(style.localizedTitle(using: loc), systemImage: style.systemImage)
                                .tag(style)
                        }
                    }
                    .pickerStyle(.inline)

                    Divider()

                    Toggle(isOn: $altTabPrefs.autoSizeEnabled) {
                        Label(
                            loc.text(es: "Ajuste de tamaño automático", en: "Automatic Sizing"),
                            systemImage: "arrow.up.left.and.arrow.down.right"
                        )
                    }
                } label: {
                    Label(loc.text(es: "Estilo de visualización", en: "Display Style"), systemImage: "rectangle.grid.2x2")
                }

                Toggle(isOn: $altTabPrefs.showFullSizePreview) {
                    Label(
                        loc.text(es: "Vista previa a tamaño completo", en: "Full-Size Window Preview"),
                        systemImage: "macwindow.on.rectangle"
                    )
                }

                Toggle(isOn: $altTabPrefs.showSearchBar) {
                    Label(
                        loc.text(es: "Mostrar buscador en el selector", en: "Show Search Bar in Switcher"),
                        systemImage: "magnifyingglass"
                    )
                }

                Divider()

                Menu {
                    Button {
                        altTabPrefs.setPrimaryShortcutPreset(command: false, option: true, control: false)
                    } label: {
                        Label("⌥ ⇥ (Option + Tab)", systemImage: "option")
                    }

                    Button {
                        altTabPrefs.setPrimaryShortcutPreset(command: true, option: false, control: false)
                    } label: {
                        Label("⌘ ⇥ (Command + Tab)", systemImage: "command")
                    }

                    Button {
                        altTabPrefs.setPrimaryShortcutPreset(command: false, option: false, control: true)
                    } label: {
                        Label("⌃ ⇥ (Control + Tab)", systemImage: "control")
                    }

                    Divider()

                    Button {
                        AltTabSettingsWindowController.shared.show(tab: .shortcuts)
                    } label: {
                        Label(
                            loc.text(es: "Personalizar atajos y filtros…", en: "Customize Shortcuts & Filters…"),
                            systemImage: "keyboard"
                        )
                    }
                } label: {
                    Label(
                        loc.text(es: "Atajo principal (\(altTabPrefs.primaryShortcutDisplay))", en: "Primary Shortcut (\(altTabPrefs.primaryShortcutDisplay))"),
                        systemImage: "keyboard"
                    )
                }

                Menu {
                    Toggle(isOn: $altTabPrefs.showSpaceBadges) {
                        Label(
                            loc.text(es: "Mostrar etiquetas de Spaces (Space 2, 3…)", en: "Show Space Badges (Space 2, 3…)"),
                            systemImage: "squares.leading.rectangle"
                        )
                    }

                    Toggle(isOn: $altTabPrefs.showWindowStateBadges) {
                        Label(
                            loc.text(es: "Mostrar etiquetas de minimizadas y ocultas", en: "Show Minimized & Hidden Badges"),
                            systemImage: "tag"
                        )
                    }

                    Toggle(isOn: $altTabPrefs.showHoverQuickActions) {
                        Label(
                            loc.text(es: "Botones rápidos al pasar el mouse", en: "Hover Quick Actions"),
                            systemImage: "cursorarrow.click.2"
                        )
                    }
                } label: {
                    Label(loc.text(es: "Etiquetas y controles", en: "Badges & Controls"), systemImage: "tag")
                }
            }

            CommandMenu("Notch") {
                Toggle(isOn: Binding(
                    get: { notchPrefs.isEnabled },
                    set: { NotchManager.shared.setEnabled($0) }
                )) {
                    Label(
                        loc.text(es: "Activar Notch (Reproductor de música)", en: "Enable Notch (Now Playing)"),
                        systemImage: "waveform"
                    )
                }

                Toggle(isOn: $notchPrefs.startEnabledByDefault) {
                    Label(
                        loc.text(es: "Activar por defecto al iniciar MacFileExplorer", en: "Enable by Default on Launch"),
                        systemImage: "power.circle"
                    )
                }

                Divider()

                Button {
                    NotchMediaService.shared.togglePlayPause()
                } label: {
                    Label(
                        loc.text(es: "Reproducir / Pausar", en: "Play / Pause"),
                        systemImage: notchMedia.isPlaying ? "pause.fill" : "play.fill"
                    )
                }
                .disabled(!notchPrefs.isEnabled && !notchMedia.hasActiveTrack)

                Button {
                    NotchMediaService.shared.nextTrack()
                } label: {
                    Label(
                        loc.text(es: "Siguiente canción", en: "Next Track"),
                        systemImage: "forward.fill"
                    )
                }
                .disabled(!notchPrefs.isEnabled && !notchMedia.hasActiveTrack)

                Button {
                    NotchMediaService.shared.previousTrack()
                } label: {
                    Label(
                        loc.text(es: "Canción anterior", en: "Previous Track"),
                        systemImage: "backward.fill"
                    )
                }
                .disabled(!notchPrefs.isEnabled && !notchMedia.hasActiveTrack)

                Button {
                    NotchManager.shared.toggleExpanded()
                } label: {
                    Label(
                        loc.text(es: "Expandir / Contraer Notch", en: "Expand / Collapse Notch"),
                        systemImage: notchManager.isAnyPanelExpanded ? "chevron.up.circle" : "chevron.down.circle"
                    )
                }
                .disabled(!notchPrefs.isEnabled)

                Button {
                    NotchManager.shared.toggleDemoPreviewAndReveal()
                } label: {
                    Label(
                        notchMedia.isDemoMode
                            ? loc.text(es: "Detener canción demo", en: "Stop Demo Track")
                            : loc.text(es: "Probar con canción demo", en: "Preview with Demo Track"),
                        systemImage: notchMedia.isDemoMode ? "stop.circle" : "sparkles"
                    )
                }

                Divider()

                Toggle(isOn: $notchPrefs.showSyncedLyrics) {
                    Label(
                        loc.text(es: "Mostrar letras sincronizadas", en: "Show Synced Lyrics"),
                        systemImage: "quote.bubble"
                    )
                }

                Toggle(isOn: $notchPrefs.announceNewTracks) {
                    Label(
                        loc.text(es: "Anunciar nuevas canciones", en: "Announce New Tracks"),
                        systemImage: "bell.badge"
                    )
                }

                Toggle(isOn: $notchPrefs.showAmbientArtworkGlow) {
                    Label(
                        loc.text(es: "Efecto de brillo del álbum", en: "Ambient Album Glow"),
                        systemImage: "sun.max"
                    )
                }

                Toggle(isOn: $notchPrefs.hideInFullScreen) {
                    Label(
                        loc.text(es: "Ocultar en pantalla completa", en: "Hide in Full Screen"),
                        systemImage: "rectangle.dashed"
                    )
                }

                Menu {
                    Picker(
                        loc.text(es: "Estilo de carátula", en: "Artwork Style"),
                        selection: $notchPrefs.artworkStyle
                    ) {
                        ForEach(NotchArtworkStyle.allCases) { style in
                            Label(style.localizedTitle(using: loc), systemImage: style.symbolName)
                                .tag(style)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(
                        loc.text(es: "Estilo de carátula", en: "Artwork Style"),
                        systemImage: "photo.circle"
                    )
                }

                Menu {
                    Picker(
                        loc.text(es: "Pantallas", en: "Displays"),
                        selection: $notchPrefs.displayMode
                    ) {
                        ForEach(NotchDisplayMode.allCases) { mode in
                            Label(mode.localizedTitle(using: loc), systemImage: mode.symbolName)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(
                        loc.text(es: "Pantallas", en: "Displays"),
                        systemImage: "display.2"
                    )
                }

                Divider()

                Button {
                    NotchSettingsWindowController.shared.show()
                } label: {
                    Label(
                        loc.text(es: "Configuración de Notch…", en: "Notch Settings…"),
                        systemImage: "slider.horizontal.3"
                    )
                }
            }

            CommandMenu("Office") {
                Toggle(isOn: $officePrefs.isOfficeEditingEnabled) {
                    Label(
                        loc.text(es: "Activar modo edición en Vista Rápida", en: "Enable Editing Mode in Quick Look"),
                        systemImage: "pencil.and.outline"
                    )
                }

                Menu {
                    Picker(
                        loc.text(es: "Abrir documentos Office en", en: "Open Office Documents In"),
                        selection: $officePrefs.defaultOpenMode
                    ) {
                        ForEach(OfficePreviewOpenMode.allCases) { mode in
                            Label(mode.localizedTitle(using: loc), systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(
                        loc.text(es: "Modo de apertura por defecto", en: "Default Preview Mode"),
                        systemImage: "eye"
                    )
                }
                .disabled(!officePrefs.isOfficeEditingEnabled)

                Menu {
                    Toggle(isOn: $officePrefs.enableWordPreview) {
                        Label(
                            loc.text(es: "Word (.docx, .doc, .rtf, .odt)", en: "Word (.docx, .doc, .rtf, .odt)"),
                            systemImage: OfficeDocumentKind.word.symbolName
                        )
                    }

                    Toggle(isOn: $officePrefs.enableExcelPreview) {
                        Label(
                            loc.text(es: "Excel (.xlsx, .xls, .ods)", en: "Excel (.xlsx, .xls, .ods)"),
                            systemImage: OfficeDocumentKind.excel.symbolName
                        )
                    }

                    Toggle(isOn: $officePrefs.enablePowerPointPreview) {
                        Label(
                            loc.text(es: "PowerPoint (.pptx, .ppt, .odp)", en: "PowerPoint (.pptx, .ppt, .odp)"),
                            systemImage: OfficeDocumentKind.powerpoint.symbolName
                        )
                    }

                    Divider()

                    Toggle(isOn: $officePrefs.isInteractiveCSVEnabled) {
                        Label(
                            loc.text(es: "Planillas CSV / TSV interactivas", en: "Interactive CSV / TSV Spreadsheets"),
                            systemImage: OfficeDocumentKind.csv.symbolName
                        )
                    }
                } label: {
                    Label(loc.text(es: "Formatos habilitados", en: "Enabled Formats"), systemImage: "doc.richtext")
                }

                Menu {
                    Toggle(isOn: $officePrefs.csvFirstRowIsHeaderByDefault) {
                        Label(
                            loc.text(es: "Primera fila como encabezado fijo en CSV", en: "Freeze First Row as Header in CSV"),
                            systemImage: "rectangle.topthird.inset.filled"
                        )
                    }

                    Toggle(isOn: $officePrefs.spreadsheetWrapTextByDefault) {
                        Label(
                            loc.text(es: "Ajustar texto en varias líneas (Wrap)", en: "Wrap Text in Cells by Default"),
                            systemImage: "text.justify.left"
                        )
                    }
                } label: {
                    Label(loc.text(es: "Opciones de planillas (CSV / Excel)", en: "Spreadsheet Options (CSV / Excel)"), systemImage: "tablecells")
                }

                Divider()

                Toggle(isOn: $officePrefs.isSendToDriveEnabled) {
                    Label(
                        loc.text(es: "Activar «Enviar a Drive»", en: "Enable \"Send to Drive\""),
                        systemImage: "icloud.and.arrow.up"
                    )
                }

                Menu {
                    Picker(
                        loc.text(es: "Abrir Google Sheets / Docs / Slides en", en: "Open Google Sheets / Docs / Slides In"),
                        selection: $drivePrefs.openInExternalChrome
                    ) {
                        Label(
                            loc.text(es: "Pestaña de MacFileExplorer (misma cuenta)", en: "MacFileExplorer Tab (Same Session)"),
                            systemImage: "macwindow"
                        )
                        .tag(false)

                        Label(
                            loc.text(es: "Google Chrome externo", en: "External Google Chrome"),
                            systemImage: "safari"
                        )
                        .tag(true)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(
                        loc.text(es: "Abrir Google Sheets / Docs / Slides en...", en: "Open Google Sheets / Docs / Slides In..."),
                        systemImage: "arrow.up.right.square"
                    )
                }
                .disabled(!officePrefs.isSendToDriveEnabled)

                Menu {
                    if googleManager.accounts.isEmpty {
                        Button {
                            googleManager.startAddGoogleAccount()
                        } label: {
                            Label(
                                loc.text(es: "Conectar cuenta de Google…", en: "Sign in to Google Account…"),
                                systemImage: "person.badge.plus"
                            )
                        }
                    } else {
                        let resolvedID = GoogleDriveUploadService.shared.resolvePreferredAccount()?.id
                        ForEach(googleManager.accounts) { account in
                            let folderLabel = drivePrefs.displayFolderName(for: account.id, using: loc)
                            Button {
                                drivePrefs.defaultAccountID = account.id
                            } label: {
                                Label(
                                    "\(resolvedID == account.id ? "✓ " : "")\(account.displayLabel) · \(folderLabel)",
                                    systemImage: "person.crop.circle"
                                )
                            }
                        }

                        Divider()

                        Button {
                            googleManager.startAddGoogleAccount()
                        } label: {
                            Label(
                                loc.text(es: "Agregar otra cuenta de Google…", en: "Add Another Google Account…"),
                                systemImage: "person.badge.plus"
                            )
                        }
                    }
                } label: {
                    Label(
                        loc.text(es: "Cuenta de Google para «Enviar a Drive»", en: "Google Account for \"Send to Drive\""),
                        systemImage: "person.crop.circle"
                    )
                }
                .disabled(!officePrefs.isSendToDriveEnabled)

                Button {
                    GoogleDriveSettingsWindowController.shared.show()
                } label: {
                    Label(
                        loc.text(es: "Configuración de «Enviar a Drive»…", en: "Send to Drive Settings…"),
                        systemImage: "slider.horizontal.3"
                    )
                }
                .disabled(!officePrefs.isSendToDriveEnabled)

                if let preferredAccount = GoogleDriveUploadService.shared.resolvePreferredAccount() {
                    let currentFolder = drivePrefs.displayFolderName(for: preferredAccount.id, using: loc)
                    Button {
                        let dest = drivePrefs.destination(for: preferredAccount.id)
                        _ = googleManager.openOrFocusDriveFolderTab(url: dest.targetURL, for: preferredAccount.id)
                    } label: {
                        Label(
                            loc.text(
                                es: "Abrir carpeta destino en Drive (\(currentFolder))",
                                en: "Open Target Folder in Drive (\(currentFolder))"
                            ),
                            systemImage: "folder"
                        )
                    }
                    .disabled(!officePrefs.isSendToDriveEnabled)

                    if drivePrefs.destination(for: preferredAccount.id).folderID != nil {
                        Button {
                            drivePrefs.setFolder(fromUserInput: "", customName: "", for: preferredAccount.id)
                        } label: {
                            Label(
                                loc.text(es: "Restablecer carpeta destino a Mi unidad", en: "Reset Target Folder to My Drive"),
                                systemImage: "arrow.counterclockwise"
                            )
                        }
                        .disabled(!officePrefs.isSendToDriveEnabled)
                    }
                }

                Divider()

                Button {
                    officePrefs.resetToDefaults()
                } label: {
                    Label(
                        loc.text(es: "Restablecer ajustes de Office", en: "Reset Office Settings"),
                        systemImage: "arrow.counterclockwise"
                    )
                }
                .disabled(officePrefs.isDefaultConfiguration)
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

                Button {
                    HelpWindowController.shared.show(section: .permissions)
                } label: {
                    Label(loc.text(es: "Permisos de macOS y Privacidad…", en: "macOS Permissions & Privacy…"), systemImage: "lock.shield")
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
