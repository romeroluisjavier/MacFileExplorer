import AppKit
import Foundation

/// Gestor del icono de estado en la barra de menús superior de macOS (Tray Icon / `NSStatusItem`)
/// para acceder rápidamente a `MacFileExplorer` (Abrir, Nueva pestaña, Nueva ventana, Abrir carpeta,
/// cambiar entre pestañas abiertas, Cerrar pestaña/ventana y Salir).
@MainActor
public final class StatusBarManager: NSObject, NSMenuDelegate {

    public static let shared = StatusBarManager()

    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu(title: "MacFileExplorer")

    /// Indica si el icono de estado está actualmente instalado en la barra de menús de macOS.
    public var isStatusItemInstalled: Bool {
        statusItem != nil
    }

    /// Devuelve el menú asociado al Tray Icon (útil para inspección y pruebas).
    public var menu: NSMenu {
        statusMenu
    }

    private override init() {
        super.init()
        statusMenu.autoenablesItems = false
        statusMenu.delegate = self
    }

    /// Instala el Tray Icon si la preferencia del usuario está habilitada.
    public func installIfNeeded() {
        syncVisibility()
    }

    /// Sincroniza la presencia del icono en la barra de menús según `TrayIconPreferences.shared.isTrayIconEnabled`.
    public func syncVisibility() {
        if TrayIconPreferences.shared.isTrayIconEnabled {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                if let button = item.button {
                    button.image = Self.makeTrayTemplateIcon()
                    button.imagePosition = .imageOnly
                    button.toolTip = LocalizationManager.shared.text(
                        es: "MacFileExplorer — Explorador de archivos",
                        en: "MacFileExplorer — File Explorer"
                    )
                }
                rebuildMenu()
                item.menu = statusMenu
                statusItem = item
            } else {
                refreshTooltipAndMenu()
            }
        } else if let existing = statusItem {
            NSStatusBar.system.removeStatusItem(existing)
            statusItem = nil
        }
    }

    /// Actualiza el tooltip y el contenido del menú cuando cambia el idioma o el estado de las ventanas.
    public func refreshTooltipAndMenu() {
        statusItem?.button?.toolTip = LocalizationManager.shared.text(
            es: "MacFileExplorer — Explorador de archivos",
            en: "MacFileExplorer — File Explorer"
        )
        rebuildMenu()
    }

    // MARK: - NSMenuDelegate

    public func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        rebuildMenu()
    }

    // MARK: - Construcción Dinámica del Menú del Tray Icon

    /// Construye todos los ítems del menú del Tray Icon con iconos SF Symbol y textos localizados (ES/EN).
    public func rebuildMenu() {
        statusMenu.removeAllItems()
        let loc = LocalizationManager.shared
        let manager = GoogleAccountsManager.shared
        let hasLiveWindows = manager.hasLiveSessionWindows

        // 1. Abrir MacFileExplorer
        let openItem = NSMenuItem(
            title: loc.text(es: "Abrir MacFileExplorer", en: "Open MacFileExplorer"),
            action: #selector(handleOpenMainWindow(_:)),
            keyEquivalent: ""
        )
        openItem.target = self
        openItem.image = LocalizationManager.symbolImage(named: "macwindow")
        statusMenu.addItem(openItem)

        // 2. Nueva pestaña
        let newTabItem = NSMenuItem(
            title: loc.text(es: "Nueva pestaña", en: "New Tab"),
            action: #selector(handleNewFolderTab(_:)),
            keyEquivalent: "t"
        )
        newTabItem.keyEquivalentModifierMask = [.command]
        newTabItem.target = self
        newTabItem.image = LocalizationManager.symbolImage(named: "folder.badge.plus")
        statusMenu.addItem(newTabItem)

        // 3. Nueva ventana
        let newWindowItem = NSMenuItem(
            title: loc.text(es: "Nueva ventana", en: "New Window"),
            action: #selector(handleNewStandaloneWindow(_:)),
            keyEquivalent: "n"
        )
        newWindowItem.keyEquivalentModifierMask = [.command]
        newWindowItem.target = self
        newWindowItem.image = LocalizationManager.symbolImage(named: "macwindow.badge.plus")
        statusMenu.addItem(newWindowItem)

        statusMenu.addItem(.separator())

        // 4. Submenú: Abrir carpeta rápida (Acceso rápido)
        let quickFoldersItem = NSMenuItem(
            title: loc.text(es: "Abrir carpeta", en: "Open Folder"),
            action: nil,
            keyEquivalent: ""
        )
        quickFoldersItem.image = LocalizationManager.symbolImage(named: "folder")
        quickFoldersItem.submenu = buildQuickFoldersSubmenu(using: loc)
        statusMenu.addItem(quickFoldersItem)

        // 5. Submenú: Pestañas abiertas actualmente (si hay alguna ventana abierta)
        let openTabSummaries = manager.allOpenTabSummaries()
        if !openTabSummaries.isEmpty {
            let openTabsMenu = NSMenu(title: loc.text(es: "Pestañas abiertas", en: "Open Tabs"))
            openTabsMenu.autoenablesItems = false
            for summary in openTabSummaries {
                let tabItem = NSMenuItem(
                    title: summary.title,
                    action: #selector(handleActivateOpenTab(_:)),
                    keyEquivalent: ""
                )
                tabItem.target = self
                tabItem.representedObject = summary.window
                tabItem.state = summary.isSelected ? .on : .off
                tabItem.image = LocalizationManager.symbolImage(named: summary.symbolName)
                openTabsMenu.addItem(tabItem)
            }

            let openTabsParentItem = NSMenuItem(
                title: loc.text(
                    es: "Pestañas abiertas (\(openTabSummaries.count))",
                    en: "Open Tabs (\(openTabSummaries.count))"
                ),
                action: nil,
                keyEquivalent: ""
            )
            openTabsParentItem.image = LocalizationManager.symbolImage(named: "square.stack")
            openTabsParentItem.submenu = openTabsMenu
            statusMenu.addItem(openTabsParentItem)
        }

        // 6. Submenú: Google Workspace (si hay cuentas configuradas)
        let accounts = manager.accounts
        if !accounts.isEmpty {
            let googleMenu = buildGoogleWorkspaceSubmenu(accounts: accounts, using: loc)
            let googleParentItem = NSMenuItem(
                title: "Google Workspace",
                action: nil,
                keyEquivalent: ""
            )
            googleParentItem.image = LocalizationManager.symbolImage(named: "globe")
            googleParentItem.submenu = googleMenu
            statusMenu.addItem(googleParentItem)
        }

        // 6b. Submenú: Historial del Portapapeles estilo Maccy (si está habilitado)
        if ClipboardHistoryPreferences.shared.isEnabled {
            let clipMenu = buildClipboardHistorySubmenu(using: loc)
            let clipCount = ClipboardHistoryManager.shared.items.count
            let clipParentItem = NSMenuItem(
                title: loc.text(
                    es: "Portapapeles (\(clipCount))",
                    en: "Clipboard History (\(clipCount))"
                ),
                action: nil,
                keyEquivalent: ""
            )
            clipParentItem.image = LocalizationManager.symbolImage(named: "doc.on.clipboard")
            clipParentItem.submenu = clipMenu
            statusMenu.addItem(clipParentItem)
        }

        // 6c. Submenú: Barra de tareas estilo Windows (siempre accesible + restauración de emergencia del Dock)
        let taskbarMenu = buildTaskbarSubmenu(using: loc)
        let taskbarStateSuffix = TaskbarPreferences.shared.isEnabled
            ? loc.text(es: " (Activa)", en: " (On)")
            : ""
        let taskbarParentItem = NSMenuItem(
            title: loc.text(es: "Barra de tareas", en: "Taskbar") + taskbarStateSuffix,
            action: nil,
            keyEquivalent: ""
        )
        taskbarParentItem.image = LocalizationManager.symbolImage(named: "dock.rectangle")
        taskbarParentItem.submenu = taskbarMenu
        statusMenu.addItem(taskbarParentItem)

        // 6d. Submenú: AltTab (selector de ventanas individuales)
        let altTabMenu = buildAltTabSubmenu(using: loc)
        let altTabStateSuffix = AltTabPreferences.shared.isEnabled
            ? loc.text(es: " (Activo)", en: " (On)")
            : ""
        let altTabParentItem = NSMenuItem(
            title: "AltTab" + altTabStateSuffix,
            action: nil,
            keyEquivalent: ""
        )
        altTabParentItem.image = LocalizationManager.symbolImage(named: "rectangle.stack.fill")
        altTabParentItem.submenu = altTabMenu
        statusMenu.addItem(altTabParentItem)

        // 6e. Submenú: Notch (reproductor de música en el Notch)
        let notchMenu = buildNotchSubmenu(using: loc)
        let notchStateSuffix = NotchPreferences.shared.isEnabled
            ? loc.text(es: " (Activo)", en: " (On)")
            : ""
        let notchParentItem = NSMenuItem(
            title: "Notch" + notchStateSuffix,
            action: nil,
            keyEquivalent: ""
        )
        notchParentItem.image = LocalizationManager.symbolImage(named: "waveform")
        notchParentItem.submenu = notchMenu
        statusMenu.addItem(notchParentItem)

        statusMenu.addItem(.separator())

        // 7. Cerrar pestaña actual
        let closeTabItem = NSMenuItem(
            title: loc.text(es: "Cerrar pestaña actual", en: "Close Current Tab"),
            action: #selector(handleCloseCurrentTab(_:)),
            keyEquivalent: "T"
        )
        closeTabItem.keyEquivalentModifierMask = [.command, .shift]
        closeTabItem.target = self
        closeTabItem.isEnabled = hasLiveWindows
        closeTabItem.image = LocalizationManager.symbolImage(named: "xmark.circle")
        statusMenu.addItem(closeTabItem)

        // 8. Cerrar ventana
        let closeWindowItem = NSMenuItem(
            title: loc.text(es: "Cerrar ventana", en: "Close Window"),
            action: #selector(handleCloseActiveWindow(_:)),
            keyEquivalent: "w"
        )
        closeWindowItem.keyEquivalentModifierMask = [.command]
        closeWindowItem.target = self
        closeWindowItem.isEnabled = hasLiveWindows
        closeWindowItem.image = LocalizationManager.symbolImage(named: "xmark.rectangle")
        statusMenu.addItem(closeWindowItem)

        statusMenu.addItem(.separator())

        // 9. Acerca de MacFileExplorer y Buscar actualizaciones
        let aboutItem = NSMenuItem(
            title: loc.text(es: "Acerca de MacFileExplorer", en: "About MacFileExplorer"),
            action: #selector(handleShowAbout(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = self
        aboutItem.image = LocalizationManager.symbolImage(named: "info.circle")
        statusMenu.addItem(aboutItem)

        let checkUpgradesItem = NSMenuItem(
            title: loc.text(es: "Buscar actualizaciones…", en: "Check for Updates…"),
            action: #selector(handleCheckUpgrades(_:)),
            keyEquivalent: ""
        )
        checkUpgradesItem.target = self
        checkUpgradesItem.image = LocalizationManager.symbolImage(named: "arrow.down.circle")
        statusMenu.addItem(checkUpgradesItem)

        let setupWizardItem = NSMenuItem(
            title: loc.text(es: "Asistente de instalación inicial…", en: "Setup Wizard…"),
            action: #selector(handleOpenSetupWizard(_:)),
            keyEquivalent: ""
        )
        setupWizardItem.target = self
        setupWizardItem.image = LocalizationManager.symbolImage(named: "wand.and.stars")
        statusMenu.addItem(setupWizardItem)

        statusMenu.addItem(.separator())

        // 10. Cerrar / Salir de MacFileExplorer
        let quitItem = NSMenuItem(
            title: loc.text(es: "Salir de MacFileExplorer", en: "Quit MacFileExplorer"),
            action: #selector(handleQuitApp(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        quitItem.image = LocalizationManager.symbolImage(named: "power")
        statusMenu.addItem(quitItem)
    }

    private func buildQuickFoldersSubmenu(using loc: LocalizationManager) -> NSMenu {
        let submenu = NSMenu(title: loc.text(es: "Abrir carpeta", en: "Open Folder"))
        submenu.autoenablesItems = false

        let visibleSet = QuickAccessPreferences.shared.visibleFolders
        let foldersToDisplay = QuickAccessFolder.allCases.filter { visibleSet.contains($0) }
        let effectiveFolders = foldersToDisplay.isEmpty ? Array(QuickAccessFolder.allCases) : foldersToDisplay

        for folder in effectiveFolders {
            guard let url = folder.directoryURL else { continue }
            let item = NSMenuItem(
                title: folder.localizedTitle(using: loc),
                action: #selector(handleOpenFolderInActiveWindow(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = url
            item.image = LocalizationManager.symbolImage(named: folder.systemImage)
            submenu.addItem(item)
        }

        let customURLs = QuickAccessPreferences.shared.customFolderURLs
        if !customURLs.isEmpty {
            submenu.addItem(.separator())
            for customURL in customURLs {
                let item = NSMenuItem(
                    title: customURL.lastPathComponent,
                    action: #selector(handleOpenFolderInActiveWindow(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = customURL
                item.image = LocalizationManager.symbolImage(named: "folder.fill")
                submenu.addItem(item)
            }
        }

        // Submenú para abrir directamente en una nueva pestaña
        submenu.addItem(.separator())
        let newTabSubmenu = NSMenu(title: loc.text(es: "Abrir en nueva pestaña", en: "Open in New Tab"))
        newTabSubmenu.autoenablesItems = false
        for folder in effectiveFolders {
            guard let url = folder.directoryURL else { continue }
            let item = NSMenuItem(
                title: folder.localizedTitle(using: loc),
                action: #selector(handleOpenFolderInNewTab(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = url
            item.image = LocalizationManager.symbolImage(named: folder.systemImage)
            newTabSubmenu.addItem(item)
        }
        let openInNewTabParent = NSMenuItem(
            title: loc.text(es: "Abrir en nueva pestaña", en: "Open in New Tab"),
            action: nil,
            keyEquivalent: ""
        )
        openInNewTabParent.image = LocalizationManager.symbolImage(named: "folder.badge.plus")
        openInNewTabParent.submenu = newTabSubmenu
        submenu.addItem(openInNewTabParent)

        return submenu
    }

    private func buildGoogleWorkspaceSubmenu(
        accounts: [GoogleAccount],
        using loc: LocalizationManager
    ) -> NSMenu {
        let submenu = NSMenu(title: "Google Workspace")
        submenu.autoenablesItems = false

        for (idx, account) in accounts.enumerated() {
            if accounts.count > 1 {
                let headerItem = NSMenuItem(title: account.displayLabel, action: nil, keyEquivalent: "")
                headerItem.isEnabled = false
                headerItem.image = LocalizationManager.symbolImage(named: "person.crop.circle")
                submenu.addItem(headerItem)
            }

            for service in GoogleServiceShortcut.allCases {
                let symbolName: String
                switch service {
                case .gmail: symbolName = "envelope.fill"
                case .drive: symbolName = "externaldrive.fill.badge.icloud"
                case .calendar: symbolName = "calendar"
                }
                let item = NSMenuItem(
                    title: service.title,
                    action: #selector(handleOpenGoogleService(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = GoogleServiceMenuPayload(accountID: account.id, service: service)
                item.image = LocalizationManager.symbolImage(named: symbolName)
                submenu.addItem(item)
            }

            if idx + 1 < accounts.count {
                submenu.addItem(.separator())
            }
        }
        return submenu
    }

    private func buildClipboardHistorySubmenu(using loc: LocalizationManager) -> NSMenu {
        let submenu = NSMenu(title: loc.text(es: "Portapapeles", en: "Clipboard History"))
        submenu.autoenablesItems = false
        let prefs = ClipboardHistoryPreferences.shared

        let openQuickPopupItem = NSMenuItem(
            title: loc.text(
                es: "Menú desplegable rápido (\(prefs.quickPasteDropdownShortcut.displayString))",
                en: "Quick Paste Dropdown (\(prefs.quickPasteDropdownShortcut.displayString))"
            ),
            action: #selector(handleOpenClipboardQuickPopup(_:)),
            keyEquivalent: ""
        )
        openQuickPopupItem.target = self
        openQuickPopupItem.image = LocalizationManager.symbolImage(named: "macwindow.on.rectangle")
        submenu.addItem(openQuickPopupItem)

        let openSearchItem = NSMenuItem(
            title: loc.text(
                es: "Buscar en todo el historial… (\(prefs.fullHistorySearchShortcut.displayString))",
                en: "Search Full History… (\(prefs.fullHistorySearchShortcut.displayString))"
            ),
            action: #selector(handleOpenClipboardHistoryInMainWindow(_:)),
            keyEquivalent: ""
        )
        openSearchItem.target = self
        openSearchItem.image = LocalizationManager.symbolImage(named: "magnifyingglass")
        submenu.addItem(openSearchItem)

        let settingsItem = NSMenuItem(
            title: loc.text(es: "Configuración del Portapapeles…", en: "Clipboard Settings…"),
            action: #selector(handleOpenClipboardShortcutsSettings(_:)),
            keyEquivalent: ""
        )
        settingsItem.target = self
        settingsItem.image = LocalizationManager.symbolImage(named: "slider.horizontal.3")
        submenu.addItem(settingsItem)

        let limit = max(1, prefs.dropdownCountOption.rawValue)
        let recentItems = Array(ClipboardHistoryManager.shared.items.prefix(limit))
        if !recentItems.isEmpty {
            submenu.addItem(.separator())
            for entry in recentItems {
                let item = NSMenuItem(
                    title: entry.displayTitle(using: loc),
                    action: #selector(handleCopyClipboardEntryFromMenu(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = entry.id
                item.image = LocalizationManager.symbolImage(named: entry.kind.systemImage)
                submenu.addItem(item)
            }
        }

        return submenu
    }

    private func buildTaskbarSubmenu(using loc: LocalizationManager) -> NSMenu {
        let submenu = NSMenu(title: loc.text(es: "Barra de tareas", en: "Taskbar"))
        submenu.autoenablesItems = false
        let prefs = TaskbarPreferences.shared

        let toggleItem = NSMenuItem(
            title: loc.text(es: "Activar barra de tareas", en: "Enable Taskbar"),
            action: #selector(handleToggleTaskbar(_:)),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.state = prefs.isEnabled ? .on : .off
        toggleItem.image = LocalizationManager.symbolImage(named: "dock.rectangle")
        submenu.addItem(toggleItem)

        let defaultToggleItem = NSMenuItem(
            title: loc.text(es: "Activar por defecto al iniciar", en: "Enable by Default on Launch"),
            action: #selector(handleToggleTaskbarStartByDefault(_:)),
            keyEquivalent: ""
        )
        defaultToggleItem.target = self
        defaultToggleItem.state = prefs.startEnabledByDefault ? .on : .off
        defaultToggleItem.image = LocalizationManager.symbolImage(named: "power.circle")
        submenu.addItem(defaultToggleItem)

        submenu.addItem(.separator())

        let startMenuItem = NSMenuItem(
            title: loc.text(es: "Abrir Menú Inicio", en: "Open Start Menu"),
            action: #selector(handleOpenTaskbarStartMenu(_:)),
            keyEquivalent: ""
        )
        startMenuItem.target = self
        startMenuItem.isEnabled = prefs.isEnabled
        startMenuItem.image = LocalizationManager.symbolImage(named: "square.grid.2x2")
        submenu.addItem(startMenuItem)

        let settingsItem = NSMenuItem(
            title: loc.text(es: "Configuración de la barra de tareas…", en: "Taskbar Settings…"),
            action: #selector(handleOpenTaskbarSettings(_:)),
            keyEquivalent: ""
        )
        settingsItem.target = self
        settingsItem.image = LocalizationManager.symbolImage(named: "slider.horizontal.3")
        submenu.addItem(settingsItem)

        submenu.addItem(.separator())

        let emergencyRestoreItem = NSMenuItem(
            title: loc.text(es: "Emergencia: Restaurar Dock original de macOS", en: "Emergency: Restore Original macOS Dock"),
            action: #selector(handleEmergencyRestoreDock(_:)),
            keyEquivalent: ""
        )
        emergencyRestoreItem.target = self
        emergencyRestoreItem.image = LocalizationManager.symbolImage(named: "arrow.uturn.backward.circle")
        submenu.addItem(emergencyRestoreItem)

        return submenu
    }

    private func buildAltTabSubmenu(using loc: LocalizationManager) -> NSMenu {
        let submenu = NSMenu(title: "AltTab")
        submenu.autoenablesItems = false
        let prefs = AltTabPreferences.shared

        let toggleItem = NSMenuItem(
            title: loc.text(
                es: "Activar AltTab (\(prefs.primaryShortcutDisplay))",
                en: "Enable AltTab (\(prefs.primaryShortcutDisplay))"
            ),
            action: #selector(handleToggleAltTab(_:)),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.state = prefs.isEnabled ? .on : .off
        toggleItem.image = LocalizationManager.symbolImage(named: "rectangle.stack.fill")
        submenu.addItem(toggleItem)

        let defaultToggleItem = NSMenuItem(
            title: loc.text(es: "Activar por defecto al iniciar", en: "Enable by Default on Launch"),
            action: #selector(handleToggleAltTabStartByDefault(_:)),
            keyEquivalent: ""
        )
        defaultToggleItem.target = self
        defaultToggleItem.state = prefs.startEnabledByDefault ? .on : .off
        defaultToggleItem.image = LocalizationManager.symbolImage(named: "power.circle")
        submenu.addItem(defaultToggleItem)

        submenu.addItem(.separator())

        let testItem = NSMenuItem(
            title: loc.text(es: "Probar selector de ventanas ahora", en: "Test Window Switcher Now"),
            action: #selector(handleOpenAltTabTestSwitcher(_:)),
            keyEquivalent: ""
        )
        testItem.target = self
        testItem.image = LocalizationManager.symbolImage(named: "play.rectangle")
        submenu.addItem(testItem)

        let settingsItem = NSMenuItem(
            title: loc.text(es: "Configuración de AltTab…", en: "AltTab Settings…"),
            action: #selector(handleOpenAltTabSettings(_:)),
            keyEquivalent: ""
        )
        settingsItem.target = self
        settingsItem.image = LocalizationManager.symbolImage(named: "slider.horizontal.3")
        submenu.addItem(settingsItem)

        return submenu
    }

    private func buildNotchSubmenu(using loc: LocalizationManager) -> NSMenu {
        let submenu = NSMenu(title: "Notch")
        submenu.autoenablesItems = false
        let prefs = NotchPreferences.shared
        let media = NotchMediaService.shared

        let toggleItem = NSMenuItem(
            title: loc.text(es: "Activar Notch", en: "Enable Notch"),
            action: #selector(handleToggleNotch(_:)),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.state = prefs.isEnabled ? .on : .off
        toggleItem.image = LocalizationManager.symbolImage(named: "waveform")
        submenu.addItem(toggleItem)

        let defaultToggleItem = NSMenuItem(
            title: loc.text(es: "Activar por defecto al iniciar", en: "Enable by Default on Launch"),
            action: #selector(handleToggleNotchStartByDefault(_:)),
            keyEquivalent: ""
        )
        defaultToggleItem.target = self
        defaultToggleItem.state = prefs.startEnabledByDefault ? .on : .off
        defaultToggleItem.image = LocalizationManager.symbolImage(named: "power.circle")
        submenu.addItem(defaultToggleItem)

        submenu.addItem(.separator())

        let demoItem = NSMenuItem(
            title: media.isDemoMode
                ? loc.text(es: "Detener canción demo", en: "Stop Demo Track")
                : loc.text(es: "Probar con canción demo", en: "Preview with Demo Track"),
            action: #selector(handleToggleNotchDemo(_:)),
            keyEquivalent: ""
        )
        demoItem.target = self
        demoItem.image = LocalizationManager.symbolImage(named: media.isDemoMode ? "stop.circle" : "sparkles")
        submenu.addItem(demoItem)

        let settingsItem = NSMenuItem(
            title: loc.text(es: "Configuración de Notch…", en: "Notch Settings…"),
            action: #selector(handleOpenNotchSettings(_:)),
            keyEquivalent: ""
        )
        settingsItem.target = self
        settingsItem.image = LocalizationManager.symbolImage(named: "slider.horizontal.3")
        submenu.addItem(settingsItem)

        return submenu
    }

    // MARK: - Acciones del Menú del Tray Icon

    @objc public func handleOpenMainWindow(_ sender: Any?) {
        GoogleAccountsManager.shared.openOrFocusMainWindow()
    }

    @objc public func handleNewFolderTab(_ sender: Any?) {
        GoogleAccountsManager.shared.openNewFileExplorerTabWindow()
    }

    @objc public func handleNewStandaloneWindow(_ sender: Any?) {
        GoogleAccountsManager.shared.openStandaloneFileExplorerWindow()
    }

    @objc private func handleOpenFolderInActiveWindow(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        GoogleAccountsManager.shared.openOrFocusMainWindow(at: url)
    }

    @objc private func handleOpenFolderInNewTab(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        GoogleAccountsManager.shared.openNewFileExplorerTabWindow(directoryURL: url)
    }

    @objc private func handleActivateOpenTab(_ sender: NSMenuItem) {
        guard let window = sender.representedObject as? NSWindow else { return }
        GoogleAccountsManager.shared.activateTabWindow(window)
    }

    @objc private func handleOpenGoogleService(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? GoogleServiceMenuPayload,
              let account = GoogleAccountsManager.shared.accounts.first(where: { $0.id == payload.accountID }) else {
            return
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        GoogleAccountsManager.shared.openServiceTab(payload.service, for: account)
    }

    @objc public func handleOpenClipboardHistoryInMainWindow(_ sender: Any?) {
        GoogleAccountsManager.shared.openOrFocusMainWindow()
        ExplorerWindowRegistry.shared.activeViewModel?.openClipboardHistorySection()
    }

    @objc public func handleOpenClipboardQuickPopup(_ sender: Any?) {
        ClipboardQuickPopupController.shared.showPopup()
    }

    @objc public func handleOpenClipboardShortcutsSettings(_ sender: Any?) {
        ClipboardShortcutsWindowController.shared.show()
    }

    @objc private func handleCopyClipboardEntryFromMenu(_ sender: NSMenuItem) {
        guard let entryID = sender.representedObject as? UUID,
              let entry = ClipboardHistoryManager.shared.items.first(where: { $0.id == entryID }) else {
            return
        }
        ClipboardHistoryManager.shared.copyEntryToPasteboard(entry)
    }

    @objc public func handleCloseCurrentTab(_ sender: Any?) {
        GoogleAccountsManager.shared.closeCurrentTabWindow()
    }

    @objc public func handleCloseActiveWindow(_ sender: Any?) {
        GoogleAccountsManager.shared.closeActiveWindow()
    }

    @objc public func handleShowAbout(_ sender: Any?) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        AboutWindowController.shared.show()
    }

    @objc public func handleCheckUpgrades(_ sender: Any?) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        UpdateWindowController.shared.showAndCheck()
    }

    @objc public func handleOpenSetupWizard(_ sender: Any?) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        AppOnboardingManager.shared.startWizardManually()
    }

    @objc public func handleToggleTaskbar(_ sender: Any?) {
        TaskbarManager.shared.setEnabled(!TaskbarPreferences.shared.isEnabled)
    }

    @objc public func handleToggleTaskbarStartByDefault(_ sender: Any?) {
        TaskbarPreferences.shared.startEnabledByDefault.toggle()
        refreshTooltipAndMenu()
    }

    @objc public func handleOpenTaskbarStartMenu(_ sender: Any?) {
        TaskbarManager.shared.toggleStartMenu()
    }

    @objc public func handleOpenTaskbarSettings(_ sender: Any?) {
        TaskbarSettingsWindowController.shared.show()
    }

    @objc public func handleEmergencyRestoreDock(_ sender: Any?) {
        TaskbarDockManager.shared.emergencyRestoreOriginalMacOSDock(forceFactoryDefaults: false)
    }

    @objc public func handleToggleAltTab(_ sender: Any?) {
        AltTabManager.shared.setEnabled(!AltTabPreferences.shared.isEnabled)
    }

    @objc public func handleToggleAltTabStartByDefault(_ sender: Any?) {
        AltTabPreferences.shared.startEnabledByDefault.toggle()
        refreshTooltipAndMenu()
    }

    @objc public func handleOpenAltTabTestSwitcher(_ sender: Any?) {
        AltTabManager.shared.openInteractiveTestSwitcher()
    }

    @objc public func handleOpenAltTabSettings(_ sender: Any?) {
        AltTabSettingsWindowController.shared.show()
    }

    @objc public func handleToggleNotch(_ sender: Any?) {
        NotchManager.shared.setEnabled(!NotchPreferences.shared.isEnabled)
    }

    @objc public func handleToggleNotchStartByDefault(_ sender: Any?) {
        NotchPreferences.shared.startEnabledByDefault.toggle()
        refreshTooltipAndMenu()
    }

    @objc public func handleToggleNotchDemo(_ sender: Any?) {
        NotchManager.shared.toggleDemoPreviewAndReveal()
    }

    @objc public func handleOpenNotchSettings(_ sender: Any?) {
        NotchSettingsWindowController.shared.show()
    }

    @objc public func handleQuitApp(_ sender: Any?) {
        TaskbarManager.shared.prepareForTermination()
        AltTabManager.shared.prepareForTermination()
        NotchManager.shared.prepareForTermination()
        GoogleAccountsManager.shared.prepareForTermination()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Icono Vectorial Monocromático (`isTemplate = true`) de MacFileExplorer para la Barra de Menús

    /// Genera el icono `isTemplate = true` (18×18 pt) con la silueta característica de `MacFileExplorer`
    /// (barra lateral izquierda con indicadores + carpeta con pestaña superior y barra de exploración interna)
    /// para que macOS lo renderice automáticamente en blanco o negro nítido según el fondo de la barra de menús.
    public static func makeTrayTemplateIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()

            // 1. Píldora vertical izquierda (Sidebar de navegación de MacFileExplorer) con 3 puntos calados
            let sidebarPath = NSBezierPath()
            sidebarPath.windingRule = .evenOdd
            sidebarPath.appendRoundedRect(
                NSRect(x: 1.4, y: 2.5, width: 3.1, height: 13.0),
                xRadius: 1.55,
                yRadius: 1.55
            )
            for dotY in [12.1, 9.0, 5.9] as [CGFloat] {
                sidebarPath.appendOval(in: NSRect(x: 2.25, y: dotY - 0.7, width: 1.4, height: 1.4))
            }
            sidebarPath.fill()

            // 2. Silueta de carpeta de MacFileExplorer a la derecha con pestaña superior y barra interior calada
            let folderPath = NSBezierPath()
            folderPath.windingRule = .evenOdd

            let left: CGFloat = 5.8
            let right: CGFloat = 16.6
            let bottom: CGFloat = 2.5
            let bodyTop: CGFloat = 13.2
            let tabTop: CGFloat = 15.3
            let corner: CGFloat = 1.8

            // Contorno exterior de la carpeta con solapa superior izquierda
            folderPath.move(to: NSPoint(x: left, y: bottom + corner))
            folderPath.line(to: NSPoint(x: left, y: tabTop - 1.3))
            folderPath.curve(
                to: NSPoint(x: left + 1.3, y: tabTop),
                controlPoint1: NSPoint(x: left, y: tabTop - 0.4),
                controlPoint2: NSPoint(x: left + 0.4, y: tabTop)
            )
            folderPath.line(to: NSPoint(x: 9.9, y: tabTop))
            folderPath.curve(
                to: NSPoint(x: 11.4, y: bodyTop),
                controlPoint1: NSPoint(x: 10.6, y: tabTop),
                controlPoint2: NSPoint(x: 10.8, y: bodyTop)
            )
            folderPath.line(to: NSPoint(x: right - corner, y: bodyTop))
            folderPath.curve(
                to: NSPoint(x: right, y: bodyTop - corner),
                controlPoint1: NSPoint(x: right - 0.6, y: bodyTop),
                controlPoint2: NSPoint(x: right, y: bodyTop - 0.6)
            )
            folderPath.line(to: NSPoint(x: right, y: bottom + corner))
            folderPath.curve(
                to: NSPoint(x: right - corner, y: bottom),
                controlPoint1: NSPoint(x: right, y: bottom + 0.6),
                controlPoint2: NSPoint(x: right - 0.6, y: bottom)
            )
            folderPath.line(to: NSPoint(x: left + corner, y: bottom))
            folderPath.curve(
                to: NSPoint(x: left, y: bottom + corner),
                controlPoint1: NSPoint(x: left + 0.6, y: bottom),
                controlPoint2: NSPoint(x: left, y: bottom + 0.6)
            )
            folderPath.close()

            // Barra de ruta/herramientas superior calada dentro de la carpeta
            folderPath.appendRoundedRect(
                NSRect(x: 7.4, y: 9.7, width: 7.6, height: 1.5),
                xRadius: 0.75,
                yRadius: 0.75
            )

            // Bolsillo frontal inferior calado dentro de la carpeta
            folderPath.appendRoundedRect(
                NSRect(x: 7.4, y: 5.2, width: 7.6, height: 2.6),
                xRadius: 0.9,
                yRadius: 0.9
            )

            folderPath.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

private final class GoogleServiceMenuPayload: NSObject {
    let accountID: UUID
    let service: GoogleServiceShortcut

    init(accountID: UUID, service: GoogleServiceShortcut) {
        self.accountID = accountID
        self.service = service
    }
}
