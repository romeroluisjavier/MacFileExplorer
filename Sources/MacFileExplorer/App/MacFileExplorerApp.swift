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
        LocalizationManager.shared.installMenuTrackingObserverIfNeeded()
        LocalizationManager.shared.applyLanguageToMainMenu()
        DispatchQueue.main.async {
            LocalizationManager.shared.applyLanguageToMainMenu()
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        LocalizationManager.shared.applyLanguageToMainMenu()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
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
                Button(loc.text(es: "Acerca de MacFileExplorer", en: "About MacFileExplorer")) {
                    showAboutPanel()
                }
            }

            CommandGroup(after: .appInfo) {
                Divider()
                Menu(loc.text(es: "Idioma", en: "Language")) {
                    languageSelectionPicker
                }
            }

            CommandGroup(after: .newItem) {
                Button(loc.text(es: "Nueva pestaña de carpetas", en: "New Folder Tab")) {
                    let sourceWindow = NSApp.keyWindow ?? NSApp.mainWindow
                    GoogleAccountsManager.shared.openNewFileExplorerTabWindow(from: sourceWindow)
                }
                .keyboardShortcut("t", modifiers: [.command])

                Button(loc.text(es: "Cerrar pestaña actual", en: "Close Current Tab")) {
                    let sourceWindow = NSApp.keyWindow ?? NSApp.mainWindow
                    GoogleAccountsManager.shared.closeCurrentTabWindow(from: sourceWindow)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .undoRedo) {
                Button(undoMenuItemTitle) {
                    if isTextOrWebResponderActive || activeExplorerViewModel == nil {
                        NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                    } else {
                        activeExplorerViewModel?.undoLastOperation()
                    }
                }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(activeExplorerViewModel != nil && activeExplorerViewModel?.canUndo != true && !isTextOrWebResponderActive)

                Button(redoMenuItemTitle) {
                    if isTextOrWebResponderActive || activeExplorerViewModel == nil {
                        NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                    } else {
                        activeExplorerViewModel?.redoLastOperation()
                    }
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(activeExplorerViewModel != nil && activeExplorerViewModel?.canRedo != true && !isTextOrWebResponderActive)
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

                Menu(loc.text(es: "Iconos en vista Lista", en: "List View Icons")) {
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
                }

                Menu(loc.text(es: "Tamaño de iconos (Cuadrícula)", en: "Grid Icon Size")) {
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
                }

                Menu(loc.text(es: "Abrir marcadores web en...", en: "Open web bookmarks in...")) {
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
                }

                Menu(loc.text(es: "Carpetas en Acceso rápido", en: "Quick Access Folders")) {
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
                    .disabled(quickAccessPrefs.visibleFolders == QuickAccessFolder.defaultFolders)
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

            CommandMenu(loc.text(es: "Idioma", en: "Language")) {
                languageSelectionPicker
            }
        }
    }

    @ViewBuilder
    private var languageSelectionPicker: some View {
        Picker(loc.text(es: "Idioma", en: "Language"), selection: $loc.preference) {
            ForEach(AppLanguagePreference.allCases) { option in
                Text(loc.displayName(for: option))
                    .tag(option)
            }
        }
        .pickerStyle(.inline)
    }

    private var activeExplorerViewModel: ExplorerViewModel? {
        focusedExplorerViewModel ?? ExplorerWindowRegistry.shared.viewModel(for: NSApp.keyWindow)
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
