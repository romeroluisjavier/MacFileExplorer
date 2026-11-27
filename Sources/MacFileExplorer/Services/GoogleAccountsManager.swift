import AppKit
import Foundation
import Observation
import SwiftUI
import WebKit

/// Ventana nativa de macOS para pestañas de `MacFileExplorer` que soporta el botón `+` de la barra de pestañas nativa.
@MainActor
public final class ExplorerNativeTabWindow: NSWindow {
    public override func newWindowForTab(_ sender: Any?) {
        GoogleAccountsManager.shared.openNewFileExplorerTabWindow(from: self)
    }
}

/// Gestor central (`@MainActor @Observable`) de cuentas de Google y pestañas web estilo Chrome
/// integradas como pestañas nativas (`NSWindow.tabGroup`) dentro de `MacFileExplorer`.
///
/// Garantiza **aislamiento total de sesiones** entre cuentas mediante:
/// 1. Un `WKWebsiteDataStore(forIdentifier: account.id)` exclusivo y persistente por cada cuenta de Google.
/// 2. Ventanas/pestañas nativas de macOS sin barra lateral izquierda para que el navegador ocupe todo el ancho.
@MainActor
@Observable
public final class GoogleAccountsManager: NSObject {

    public static let shared = GoogleAccountsManager()

    /// Identificador de grupo de pestañas nativas de macOS compartido entre el Explorador y las pestañas de Google.
    public static let mainWindowTabbingIdentifier = "MacFileExplorerMainTabGroup"

    private let accountsDefaultsKey = "com.macfileexplorer.googleAccounts.v1"
    private let expandedAccountsDefaultsKey = "com.macfileexplorer.expandedGoogleAccounts.v1"
    private let sectionExpandedDefaultsKey = "com.macfileexplorer.googleSectionExpanded.v1"
    private let defaultPageZoomDefaultsKey = "com.macfileexplorer.googleWebDefaultZoom.v1"

    /// Niveles de zoom estándar estilo Google Chrome (25% a 300%).
    public static let zoomSteps: [Double] = [
        0.25, 0.33, 0.50, 0.67, 0.75, 0.80, 0.90,
        1.00, 1.10, 1.25, 1.50, 1.75, 2.00, 2.50, 3.00
    ]

    /// Zoom predeterminado para nuevas pestañas web (persistido entre sesiones).
    public var defaultPageZoom: Double = 1.0 {
        didSet {
            UserDefaults.standard.set(defaultPageZoom, forKey: defaultPageZoomDefaultsKey)
        }
    }

    /// Cuentas de Google registradas (persistidas entre sesiones).
    public var accounts: [GoogleAccount] = [] {
        didSet {
            saveAccounts()
        }
    }

    /// Indica si la sección "Google Workspace / Cuentas de Google" en el panel lateral está expandida.
    public var isGoogleSectionExpanded: Bool = true {
        didSet {
            UserDefaults.standard.set(isGoogleSectionExpanded, forKey: sectionExpandedDefaultsKey)
        }
    }

    /// Conjunto de IDs de cuentas de Google cuyo árbol lateral (Gmail, Drive, Calendar) está desplegado.
    public var expandedAccountIDs: Set<UUID> = [] {
        didSet {
            let raw = expandedAccountIDs.map(\.uuidString)
            UserDefaults.standard.set(raw, forKey: expandedAccountsDefaultsKey)
        }
    }

    /// Pestañas web estilo Chrome abiertas actualmente dentro de `MacFileExplorer`.
    public var openTabs: [BrowserTabItem] = []

    /// ID de la pestaña web activa (`nil` significa que está activa una pestaña del Explorador de Archivos local).
    public var activeTabID: UUID? = nil

    /// Instancias vivas de `WKWebView` por `BrowserTabItem.id` para mantener el estado de cada pestaña sin recargar.
    private var webViewsByTabID: [UUID: WKWebView] = [:]

    /// Coordinadores de navegación y detección de sesión por `BrowserTabItem.id`.
    private var coordinatorsByTabID: [UUID: WebTabCoordinator] = [:]

    /// Ventanas nativas (`NSWindow` en el `tabGroup` de `MacFileExplorer`) asociadas a cada `BrowserTabItem.id`.
    private var windowsByTabID: [UUID: NSWindow] = [:]

    /// Ventanas adicionales del Explorador de Archivos abiertas desde `+` para liberarlas de forma segura al cerrarse.
    private var extraExplorerWindows: Set<NSWindow> = []

    /// Observadores KVO sobre `NSWindowTabGroup.selectedWindow` para sincronizar `activeTabID` al cambiar de pestaña nativa.
    private var tabGroupObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]

    /// Estado de ciclo de vida para guardar y restaurar pestañas sin sobrescribir la sesión durante cierre/arranque.
    private var isTerminating = false
    private var isRestoringSession = false
    private var didAttemptInitialSessionRestore = false
    private var sessionAutosaveTask: Task<Void, Never>?
    private var ignoredClosingWindowIDs: Set<ObjectIdentifier> = []

    /// Caché en memoria de fotos de perfil de cuentas de Google indexadas por `account.id`.
    private let avatarImageCache = NSCache<NSString, NSImage>()
    private var avatarDownloadTasks: [UUID: Task<Void, Never>] = [:]
    private var avatarHydrationSessions: [UUID: AvatarHydrationSession] = [:]

    /// User-Agent de Chrome en macOS moderno para compatibilidad completa con Google Sign-In, Gmail, Drive y Calendar.
    public static let chromeMacUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    private override init() {
        super.init()
        loadPersistedState()
        installWindowLifecycleObservers()
        scheduleMissingAvatarHydration()
    }

    /// Devuelve el avatar de perfil decodificado en caché para una cuenta de Google, o `nil` si aún no se obtuvo.
    public func avatarImage(for account: GoogleAccount) -> NSImage? {
        let key = account.id.uuidString as NSString
        if let cached = avatarImageCache.object(forKey: key) {
            return cached
        }
        guard let data = account.avatarData ?? accounts.first(where: { $0.id == account.id })?.avatarData,
              let image = NSImage(data: data) else {
            return nil
        }
        avatarImageCache.setObject(image, forKey: key)
        return image
    }

    // MARK: - Propiedades Computadas

    /// Devuelve la pestaña web actualmente visible, o `nil` si el usuario está viendo el Explorador de Archivos.
    public var activeTab: BrowserTabItem? {
        guard let activeTabID else { return nil }
        return openTabs.first(where: { $0.id == activeTabID })
    }

    /// Devuelve el modelo actualizado de una pestaña por su `id`.
    public func tab(for tabID: UUID) -> BrowserTabItem? {
        openTabs.first(where: { $0.id == tabID })
    }

    /// Devuelve la cuenta de Google a la que pertenece una pestaña web.
    public func account(for tab: BrowserTabItem) -> GoogleAccount? {
        accounts.first(where: { $0.id == tab.accountID })
    }

    /// Indica si una cuenta tiene desplegados sus accesos directos (Gmail, Drive, Calendar) en el panel lateral.
    public func isAccountExpanded(_ account: GoogleAccount) -> Bool {
        expandedAccountIDs.contains(account.id)
    }

    public func toggleAccountExpansion(_ account: GoogleAccount) {
        if expandedAccountIDs.contains(account.id) {
            expandedAccountIDs.remove(account.id)
        } else {
            expandedAccountIDs.insert(account.id)
        }
    }

    // MARK: - Gestión de Cuentas y Pestañas Nativas Aisladas

    /// Inicia el flujo para agregar una nueva cuenta de Google en un contenedor `WKWebsiteDataStore` 100% aislado.
    public func startAddGoogleAccount() {
        let nextColorIndex = accounts.count
        let newAccount = GoogleAccount(
            id: UUID(),
            email: "",
            displayName: "",
            isAuthenticated: false,
            colorIndex: nextColorIndex
        )
        accounts.append(newAccount)
        isGoogleSectionExpanded = true
        expandedAccountIDs.insert(newAccount.id)

        let langCode = LocalizationManager.shared.isSpanish ? "es" : "en"
        let loginURL = URL(
            string: "https://accounts.google.com/ServiceLogin?hl=\(langCode)&continue=https%3A%2F%2Fmyaccount.google.com%2F"
        )!

        let tabTitle = LocalizationManager.shared.text(
            es: "Iniciar sesión en Google",
            en: "Sign in to Google"
        )
        let newTab = BrowserTabItem(
            accountID: newAccount.id,
            title: tabTitle,
            currentURL: loginURL,
            service: nil,
            isLoading: true,
            pageZoom: defaultPageZoom
        )
        openTabs.append(newTab)
        presentOrActivateNativeWindowTab(for: newTab)
    }

    /// Abre un acceso directo (Gmail, Drive o Calendar) para una cuenta de Google específica como un Tab nativo de `MacFileExplorer`.
    public func openServiceTab(
        _ service: GoogleServiceShortcut,
        for account: GoogleAccount,
        forceNewTab: Bool = false
    ) {
        // Si ya existe un tab abierto de ese mismo servicio y esa misma cuenta, activarlo salvo que pida nueva pestaña
        if !forceNewTab,
           let existingTab = openTabs.first(where: { $0.accountID == account.id && $0.service == service }) {
            presentOrActivateNativeWindowTab(for: existingTab)
            return
        }

        let newTab = BrowserTabItem(
            accountID: account.id,
            title: "\(service.title) — \(account.displayLabel)",
            currentURL: service.targetURL,
            service: service,
            isLoading: true,
            pageZoom: defaultPageZoom
        )
        openTabs.append(newTab)
        presentOrActivateNativeWindowTab(for: newTab)
    }

    /// Abre cualquier URL dentro de la sesión aislada de la cuenta indicada en una nueva pestaña nativa.
    @discardableResult
    public func openURLInAccountTab(_ url: URL, for accountID: UUID, service: GoogleServiceShortcut? = nil) -> BrowserTabItem {
        let acctLabel = accounts.first(where: { $0.id == accountID })?.displayLabel ?? "Google"
        let newTab = BrowserTabItem(
            accountID: accountID,
            title: acctLabel,
            currentURL: url,
            service: service,
            isLoading: true,
            pageZoom: defaultPageZoom
        )
        openTabs.append(newTab)
        presentOrActivateNativeWindowTab(for: newTab)
        return newTab
    }

    /// Abre o enfoca la pestaña de Google Drive de una cuenta y la navega directamente a la carpeta destino para «Enviar a Drive».
    @discardableResult
    public func openOrFocusDriveFolderTab(url: URL, for accountID: UUID) -> BrowserTabItem {
        if let idx = openTabs.firstIndex(where: {
            $0.accountID == accountID
                && $0.service == .drive
                && $0.currentURL.host?.lowercased() == "drive.google.com"
        }) {
            let existingTab = openTabs[idx]
            presentOrActivateNativeWindowTab(for: existingTab)
            let wv = webView(for: existingTab)
            let currentURLString = (wv.url ?? existingTab.currentURL).absoluteString
            let targetFolderID = GoogleDriveUploadPreferences.extractFolderID(from: url.absoluteString)
            let currentFolderID = GoogleDriveUploadPreferences.extractFolderID(from: currentURLString)

            let alreadyInTargetFolder: Bool = {
                if let targetFolderID {
                    return currentFolderID == targetFolderID
                }
                return currentFolderID == nil && currentURLString.lowercased().contains("/my-drive")
            }()

            if !alreadyInTargetFolder {
                openTabs[idx].currentURL = url
                openTabs[idx].isLoading = true
                wv.load(URLRequest(url: url))
            }
            return openTabs[idx]
        }

        let acctLabel = accounts.first(where: { $0.id == accountID })?.displayLabel ?? "Google"
        let newTab = BrowserTabItem(
            accountID: accountID,
            title: "Drive — \(acctLabel)",
            currentURL: url,
            service: .drive,
            isLoading: true,
            pageZoom: defaultPageZoom
        )
        openTabs.append(newTab)
        presentOrActivateNativeWindowTab(for: newTab)
        return newTab
    }

    /// Abre un marcador (bookmark) en una pestaña nativa dentro de `MacFileExplorer`.
    public func openBookmarkURLInTab(
        _ url: URL,
        title: String,
        bookmarkID: UUID? = nil,
        initialFaviconData: Data? = nil
    ) {
        let resolvedInitialData = initialFaviconData ?? {
            guard let host = url.host,
                  let cachedImage = BookmarksManager.shared.cachedFavicon(forHost: host) else {
                return nil
            }
            return FaviconService.normalizedPNGData(from: cachedImage)
        }()

        let newTab = BrowserTabItem(
            accountID: BookmarksManager.generalBookmarksAccountID,
            title: title.isEmpty ? (url.host ?? "Web") : title,
            currentURL: url,
            service: nil,
            bookmarkID: bookmarkID,
            faviconData: resolvedInitialData,
            isLoading: true,
            pageZoom: defaultPageZoom
        )
        openTabs.append(newTab)
        presentOrActivateNativeWindowTab(for: newTab)
    }

    /// Indica si existe al menos una ventana principal de sesión abierta (visible o minimizada en el Dock).
    public var hasLiveSessionWindows: Bool {
        for entry in ExplorerWindowRegistry.shared.allRegisteredWindows() {
            if isWindowLiveInSession(entry.window, includingClosingWindow: nil) {
                return true
            }
        }
        for window in windowsByTabID.values {
            if isWindowLiveInSession(window, includingClosingWindow: nil) {
                return true
            }
        }
        return false
    }

    /// Muestra y trae al frente la ventana principal de `MacFileExplorer` (desminimizándola si estaba en el Dock,
    /// o creando/restaurando una ventana si todas habían sido cerradas). Si se especifica `directoryURL`, navega a esa carpeta.
    public func openOrFocusMainWindow(at directoryURL: URL? = nil) {
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let anchorWindow = resolveAnchorWindow(includeMiniaturized: true) {
            let selected = anchorWindow.tabGroup?.selectedWindow ?? anchorWindow
            if anchorWindow.isMiniaturized {
                anchorWindow.deminiaturize(nil)
            }
            if selected.isMiniaturized {
                selected.deminiaturize(nil)
            }

            if let directoryURL {
                if let vm = ExplorerWindowRegistry.shared.viewModel(for: selected) {
                    vm.navigate(to: directoryURL)
                    selected.tabGroup?.selectedWindow = selected
                    selected.makeKeyAndOrderFront(nil)
                    syncActiveTabID(for: selected)
                    return
                }
                let groupWindows = selected.tabGroup?.windows ?? [selected]
                if let explorerWin = groupWindows.first(where: { ExplorerWindowRegistry.shared.viewModel(for: $0) != nil }),
                   let vm = ExplorerWindowRegistry.shared.viewModel(for: explorerWin) {
                    if explorerWin.isMiniaturized {
                        explorerWin.deminiaturize(nil)
                    }
                    vm.navigate(to: directoryURL)
                    activeTabID = nil
                    explorerWin.tabGroup?.selectedWindow = explorerWin
                    explorerWin.makeKeyAndOrderFront(nil)
                    syncActiveTabID(for: explorerWin)
                    return
                }
                openNewFileExplorerTabWindow(from: selected, directoryURL: directoryURL)
                return
            }

            selected.tabGroup?.selectedWindow = selected
            selected.makeKeyAndOrderFront(nil)
            syncActiveTabID(for: selected)
            return
        }

        // No hay ninguna ventana abierta: crear ventana nueva (y restaurar sesión si corresponde)
        let savedFrame = PersistenceService.shared.loadWindowFrame() ?? NSRect(x: 120, y: 120, width: 1160, height: 720)
        let targetURL = directoryURL ?? PersistenceService.shared.loadLastDirectory()
        let created = createExplorerTabWindow(directoryURL: targetURL, frame: savedFrame)

        if directoryURL == nil,
           SessionPreferences.shared.rememberOpenTabsOnLaunch,
           let snapshot = PersistenceService.shared.loadSessionSnapshot(),
           !snapshot.windowGroups.isEmpty {
            restoreSession(
                snapshot: snapshot,
                initialWindow: created.window,
                initialViewModel: created.viewModel
            )
            return
        }

        created.window.makeKeyAndOrderFront(nil)
        observeTabGroupSelection(for: created.window)
        activeTabID = nil
        scheduleSessionAutosave()
    }

    /// Abre una nueva pestaña del Explorador de Archivos dentro de la barra de pestañas nativa de `MacFileExplorer`.
    public func openNewFileExplorerTabWindow(from sourceWindow: NSWindow? = nil, directoryURL: URL? = nil) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let anchorWindow = resolveAnchorWindow(preferred: sourceWindow, includeMiniaturized: true)
        if let anchorWindow, anchorWindow.isMiniaturized {
            anchorWindow.deminiaturize(nil)
        }
        let frame = anchorWindow?.frame
            ?? PersistenceService.shared.loadWindowFrame()
            ?? NSRect(x: 120, y: 120, width: 1160, height: 720)
        let initialFolderURL = directoryURL
            ?? anchorWindow.flatMap { ExplorerWindowRegistry.shared.viewModel(for: $0)?.currentDirectoryURL }
            ?? PersistenceService.shared.loadLastDirectory()
        let created = createExplorerTabWindow(directoryURL: initialFolderURL, frame: frame)
        attachWindowToTabGroup(created.window, anchorWindow: anchorWindow)
        activeTabID = nil
        scheduleSessionAutosave()
    }

    /// Abre una ventana independiente del Explorador de Archivos (fuera del grupo de pestañas actual).
    @discardableResult
    public func openStandaloneFileExplorerWindow(directoryURL: URL? = nil) -> NSWindow {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let baseFrame = resolveAnchorWindow(includeMiniaturized: true)?.frame
            ?? PersistenceService.shared.loadWindowFrame()
            ?? NSRect(x: 120, y: 120, width: 1160, height: 720)
        let cascadedFrame: NSRect = {
            guard hasLiveSessionWindows else { return baseFrame }
            return NSRect(
                x: baseFrame.origin.x + 26,
                y: max(40, baseFrame.origin.y - 26),
                width: baseFrame.width,
                height: baseFrame.height
            )
        }()
        let targetURL = directoryURL ?? PersistenceService.shared.loadLastDirectory()
        let created = createExplorerTabWindow(directoryURL: targetURL, frame: cascadedFrame)
        created.window.tabbingMode = .disallowed
        created.window.makeKeyAndOrderFront(nil)
        created.window.tabbingMode = .preferred
        created.window.tabbingIdentifier = Self.mainWindowTabbingIdentifier
        observeTabGroupSelection(for: created.window)
        activeTabID = nil
        scheduleSessionAutosave()
        return created.window
    }

    private func makeNativeTabWindow(frame: NSRect) -> ExplorerNativeTabWindow {
        let window = ExplorerNativeTabWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 880, height: 540)
        window.tabbingMode = .preferred
        window.tabbingIdentifier = Self.mainWindowTabbingIdentifier
        window.toolbarStyle = .unifiedCompact
        return window
    }

    private func createExplorerTabWindow(
        directoryURL: URL?,
        frame: NSRect
    ) -> (window: NSWindow, viewModel: ExplorerViewModel) {
        let explorerWindow = makeNativeTabWindow(frame: frame)
        let explorerVM = ExplorerViewModel(initialDirectoryURL: directoryURL)
        NativeWindowTabIconBuilder.applyFolderTabAppearance(to: explorerWindow, title: explorerVM.currentFolderTitle)
        explorerWindow.contentViewController = NSHostingController(rootView: MainExplorerView(viewModel: explorerVM))
        extraExplorerWindows.insert(explorerWindow)
        ExplorerWindowRegistry.shared.register(viewModel: explorerVM, for: explorerWindow)
        return (explorerWindow, explorerVM)
    }

    private func createWebTabWindow(for tab: BrowserTabItem, frame: NSRect) -> NSWindow {
        let webWindow = makeNativeTabWindow(frame: frame)
        NativeWindowTabIconBuilder.applyWebTabAppearance(to: webWindow, for: tab)
        webWindow.contentViewController = NSHostingController(rootView: IsolatedGoogleWebTabView(tabID: tab.id))
        windowsByTabID[tab.id] = webWindow
        return webWindow
    }

    /// Cierra la pestaña actual (carpeta o web) y activa una pestaña adyacente si quedan otras en el grupo.
    public func closeCurrentTabWindow(from sourceWindow: NSWindow? = nil) {
        guard let anchorWindow = resolveAnchorWindow(preferred: sourceWindow, includeMiniaturized: true) else { return }
        let targetWindow = anchorWindow.tabGroup?.selectedWindow ?? anchorWindow
        let groupWindows = targetWindow.tabGroup?.windows ?? []
        let fallbackWindow: NSWindow? = {
            guard groupWindows.count > 1,
                  let idx = groupWindows.firstIndex(where: { $0 === targetWindow }) else {
                return nil
            }
            if idx + 1 < groupWindows.count {
                return groupWindows[idx + 1]
            }
            return idx > 0 ? groupWindows[idx - 1] : nil
        }()

        targetWindow.performClose(nil)

        if !targetWindow.isVisible, let fallbackWindow {
            fallbackWindow.tabGroup?.selectedWindow = fallbackWindow
            fallbackWindow.makeKeyAndOrderFront(nil)
            syncActiveTabID(for: fallbackWindow)
        }
    }

    /// Cierra la ventana activa completa (incluyendo todas las pestañas de su grupo, preservando el snapshot de sesión si es la última ventana).
    public func closeActiveWindow(from sourceWindow: NSWindow? = nil) {
        guard let anchorWindow = resolveAnchorWindow(preferred: sourceWindow, includeMiniaturized: true) else { return }
        let groupWindows = anchorWindow.tabGroup?.windows ?? [anchorWindow]
        let groupSet = Set(groupWindows.map { ObjectIdentifier($0) })

        let hasOtherGroups: Bool = {
            for entry in ExplorerWindowRegistry.shared.allRegisteredWindows() where !groupSet.contains(ObjectIdentifier(entry.window)) {
                if isWindowLiveInSession(entry.window, includingClosingWindow: nil) { return true }
            }
            for win in windowsByTabID.values where !groupSet.contains(ObjectIdentifier(win)) {
                if isWindowLiveInSession(win, includingClosingWindow: nil) { return true }
            }
            return false
        }()

        if !hasOtherGroups,
           SessionPreferences.shared.rememberOpenTabsOnLaunch,
           let snapshot = buildCurrentSessionSnapshot(includingClosingWindow: anchorWindow) {
            PersistenceService.shared.saveSessionSnapshot(snapshot)
            if let activeVM = ExplorerWindowRegistry.shared.activeViewModel {
                PersistenceService.shared.saveLastDirectory(activeVM.currentDirectoryURL)
            }
        }

        for win in groupWindows {
            ignoredClosingWindowIDs.insert(ObjectIdentifier(win))
            win.close()
        }

        if hasOtherGroups {
            scheduleSessionAutosave()
        }
    }

    /// Activa y trae al frente una ventana/pestaña específica.
    public func activateTabWindow(_ window: NSWindow) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.tabGroup?.selectedWindow = window
        window.makeKeyAndOrderFront(nil)
        syncActiveTabID(for: window)
    }

    /// Resumen de todas las pestañas abiertas actualmente en orden para mostrarlas en el menú del Tray Icon.
    public func allOpenTabSummaries() -> [(window: NSWindow, title: String, symbolName: String, isSelected: Bool)] {
        let explorerEntries = ExplorerWindowRegistry.shared.allRegisteredWindows()
        var explorerByID: [ObjectIdentifier: ExplorerViewModel] = [:]
        for entry in explorerEntries {
            explorerByID[ObjectIdentifier(entry.window)] = entry.viewModel
        }

        let tabsByID = Dictionary(uniqueKeysWithValues: openTabs.map { ($0.id, $0) })
        var webByID: [ObjectIdentifier: BrowserTabItem] = [:]
        for (tabID, win) in windowsByTabID {
            if let tab = tabsByID[tabID] {
                webByID[ObjectIdentifier(win)] = tab
            }
        }

        guard let anchor = resolveAnchorWindow(includeMiniaturized: true) else { return [] }
        let selectedInGroup = anchor.tabGroup?.selectedWindow ?? anchor
        let windowsToList = anchor.tabGroup?.windows ?? [anchor]

        var result: [(window: NSWindow, title: String, symbolName: String, isSelected: Bool)] = []
        for win in windowsToList {
            let winID = ObjectIdentifier(win)
            let isSelected = (win === selectedInGroup)
            if let vm = explorerByID[winID] {
                result.append((win, vm.currentFolderTitle, "folder.fill", isSelected))
            } else if let tab = webByID[winID] {
                let symbol: String
                switch tab.service {
                case .gmail: symbol = "envelope.fill"
                case .drive: symbol = "externaldrive.fill.badge.icloud"
                case .calendar: symbol = "calendar"
                case .none: symbol = "globe"
                }
                result.append((win, tab.title, symbol, isSelected))
            }
        }
        return result
    }

    /// Crea o activa la pestaña nativa (`NSWindow`) en la barra superior de `MacFileExplorer` para el `BrowserTabItem` dado.
    public func presentOrActivateNativeWindowTab(for tab: BrowserTabItem) {
        if let existingWindow = windowsByTabID[tab.id] {
            if existingWindow.isMiniaturized {
                existingWindow.deminiaturize(nil)
            }
            NativeWindowTabIconBuilder.applyWebTabAppearance(to: existingWindow, for: tab)
            existingWindow.tabGroup?.selectedWindow = existingWindow
            existingWindow.makeKeyAndOrderFront(nil)
            activeTabID = tab.id
            scheduleSessionAutosave()
            return
        }

        let anchorWindow = resolveAnchorWindow(includeMiniaturized: true)
        if let anchorWindow, anchorWindow.isMiniaturized {
            anchorWindow.deminiaturize(nil)
        }
        let frame = anchorWindow?.frame
            ?? PersistenceService.shared.loadWindowFrame()
            ?? NSRect(x: 120, y: 120, width: 1160, height: 720)
        let webWindow = createWebTabWindow(for: tab, frame: frame)

        attachWindowToTabGroup(webWindow, anchorWindow: anchorWindow)
        activeTabID = tab.id
        scheduleSessionAutosave()
    }

    private func resolveAnchorWindow(preferred sourceWindow: NSWindow? = nil, includeMiniaturized: Bool = false) -> NSWindow? {
        if let sourceWindow, sourceWindow.canBecomeMain, !sourceWindow.isSheet {
            if sourceWindow.isVisible || (includeMiniaturized && isWindowLiveInSession(sourceWindow, includingClosingWindow: nil)) {
                return sourceWindow
            }
        }
        if let key = NSApplication.shared.keyWindow, key.isVisible, key.canBecomeMain, !key.isSheet {
            return key
        }
        if let main = NSApplication.shared.mainWindow, main.isVisible, main.canBecomeMain, !main.isSheet {
            return main
        }
        let visibleCandidates = NSApplication.shared.windows.filter {
            $0.isVisible && $0.canBecomeMain && !$0.isSheet
        }
        if let match = visibleCandidates.first(where: { $0.tabbingIdentifier == Self.mainWindowTabbingIdentifier })
            ?? visibleCandidates.first {
            return match
        }
        if includeMiniaturized {
            let miniCandidates = NSApplication.shared.windows.filter {
                $0.canBecomeMain && !$0.isSheet && isWindowLiveInSession($0, includingClosingWindow: nil)
            }
            return miniCandidates.first(where: { $0.tabbingIdentifier == Self.mainWindowTabbingIdentifier })
                ?? miniCandidates.first
        }
        return nil
    }

    private func attachWindowToTabGroup(_ newWindow: NSWindow, anchorWindow: NSWindow?) {
        NSWindow.allowsAutomaticWindowTabbing = true
        if let anchorWindow {
            anchorWindow.tabbingMode = .preferred
            anchorWindow.tabbingIdentifier = Self.mainWindowTabbingIdentifier
            let tailWindow = anchorWindow.tabGroup?.windows.last ?? anchorWindow
            tailWindow.addTabbedWindow(newWindow, ordered: .above)
            newWindow.tabGroup?.selectedWindow = newWindow
            observeTabGroupSelection(for: newWindow)
        }
        newWindow.makeKeyAndOrderFront(nil)
    }

    /// Activa la primera pestaña del Explorador de Archivos local en el grupo de pestañas de la ventana actual.
    public func switchToFileExplorerTab() {
        let webWindowSet = Set(windowsByTabID.values)
        if let currentGroupWindows = NSApplication.shared.keyWindow?.tabbedWindows,
           let explorerWindow = currentGroupWindows.first(where: { !webWindowSet.contains($0) }) {
            activeTabID = nil
            explorerWindow.tabGroup?.selectedWindow = explorerWindow
            explorerWindow.makeKeyAndOrderFront(nil)
            scheduleSessionAutosave()
            return
        }
        if let anyExplorerWindow = NSApplication.shared.windows.first(where: {
            $0.isVisible && $0.canBecomeMain && !$0.isSheet && !webWindowSet.contains($0)
        }) {
            activeTabID = nil
            anyExplorerWindow.tabGroup?.selectedWindow = anyExplorerWindow
            anyExplorerWindow.makeKeyAndOrderFront(nil)
            scheduleSessionAutosave()
        } else {
            openNewFileExplorerTabWindow()
        }
    }

    /// Cierra una pestaña web y libera su `WKWebView` y su `NSWindow` nativa.
    public func closeTab(_ tabID: UUID, closeNativeWindow: Bool = true) {
        let closingWindow = windowsByTabID[tabID]
        if let closingWindow,
           !isTerminating,
           !isRestoringSession,
           !ignoredClosingWindowIDs.contains(ObjectIdentifier(closingWindow)),
           SessionPreferences.shared.rememberOpenTabsOnLaunch,
           !hasOtherLiveSessionWindows(excluding: closingWindow),
           let snapshot = buildCurrentSessionSnapshot(includingClosingWindow: closingWindow) {
            PersistenceService.shared.saveSessionSnapshot(snapshot)
        }

        if closeNativeWindow, let window = windowsByTabID.removeValue(forKey: tabID) {
            ignoredClosingWindowIDs.insert(ObjectIdentifier(window))
            window.close()
        } else {
            windowsByTabID.removeValue(forKey: tabID)
        }

        guard let index = openTabs.firstIndex(where: { $0.id == tabID }) else { return }
        let removedTab = openTabs.remove(at: index)
        if let wv = webViewsByTabID[tabID] {
            wv.stopLoading()
            wv.configuration.userContentController.removeScriptMessageHandler(forName: "googleAccountDetector")
            wv.configuration.userContentController.removeScriptMessageHandler(forName: GoogleDriveUploadService.networkProbeHandlerName)
        }
        webViewsByTabID.removeValue(forKey: tabID)
        coordinatorsByTabID.removeValue(forKey: tabID)

        if activeTabID == tabID {
            activeTabID = nil
        }

        // Si el usuario cerró la pestaña de login sin haber iniciado sesión ni capturado email, limpiar el borrador vacío
        if let account = accounts.first(where: { $0.id == removedTab.accountID }),
           !account.isAuthenticated,
           account.email.isEmpty,
           !openTabs.contains(where: { $0.accountID == account.id }) {
            removeAccount(account)
        }

        if let closingWindow, hasOtherLiveSessionWindows(excluding: closingWindow) {
            scheduleSessionAutosave()
        } else if closingWindow == nil {
            scheduleSessionAutosave()
        }
    }

    /// Elimina una cuenta de Google, cierra todas sus pestañas y destruye su almacén aislado de cookies/datos en disco.
    public func removeAccount(_ account: GoogleAccount) {
        let tabsToClose = openTabs.filter { $0.accountID == account.id }.map(\.id)
        for tabID in tabsToClose {
            closeTab(tabID, closeNativeWindow: true)
        }

        avatarDownloadTasks.removeValue(forKey: account.id)?.cancel()
        avatarHydrationSessions.removeValue(forKey: account.id)?.teardown()
        avatarImageCache.removeObject(forKey: account.id.uuidString as NSString)

        expandedAccountIDs.remove(account.id)
        accounts.removeAll { $0.id == account.id }

        // Borrar permanentemente el contenedor aislado WKWebsiteDataStore de esta cuenta
        let storeID = account.id
        Task { @MainActor in
            try? await WKWebsiteDataStore.remove(forIdentifier: storeID)
        }
        scheduleSessionAutosave()
    }

    private func observeTabGroupSelection(for window: NSWindow) {
        guard let group = window.tabGroup else { return }
        let groupID = ObjectIdentifier(group)
        guard tabGroupObservations[groupID] == nil else { return }
        tabGroupObservations[groupID] = group.observe(\.selectedWindow, options: [.new]) { [weak self] _, _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.syncActiveTabFromObservedGroup(groupID: groupID)
                }
            } else {
                Task { @MainActor [weak self] in
                    self?.syncActiveTabFromObservedGroup(groupID: groupID)
                }
            }
        }
    }

    private func syncActiveTabFromObservedGroup(groupID: ObjectIdentifier) {
        if let selected = NSApplication.shared.windows
            .compactMap(\.tabGroup)
            .first(where: { ObjectIdentifier($0) == groupID })?
            .selectedWindow {
            syncActiveTabID(for: selected)
            return
        }
        if let fallback = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
            syncActiveTabID(for: fallback)
        }
    }

    /// Devuelve el ID de pestaña web correspondiente a la ventana especificada, o `nil` si la ventana no es una pestaña web de Google.
    public func activeTabID(for window: NSWindow?) -> UUID? {
        guard let window else { return nil }
        let effective = window.tabGroup?.selectedWindow ?? window
        return windowsByTabID.first(where: { $0.value === effective })?.key
    }

    private func syncActiveTabID(for window: NSWindow) {
        let effective = window.tabGroup?.selectedWindow ?? window
        if let match = windowsByTabID.first(where: { $0.value === effective }) {
            activeTabID = match.key
        } else {
            activeTabID = nil
        }
        if let vm = ExplorerWindowRegistry.shared.viewModel(for: effective),
           SessionPreferences.shared.rememberOpenTabsOnLaunch {
            PersistenceService.shared.saveLastDirectory(vm.currentDirectoryURL)
        }
        scheduleSessionAutosave()
    }

    private func installWindowLifecycleObservers() {
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification] {
            center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let window = notification.object as? NSWindow else { return }
                Task { @MainActor [weak self, weak window] in
                    guard let self, let window else { return }
                    guard window.canBecomeMain, !window.isSheet else { return }
                    self.observeTabGroupSelection(for: window)
                    self.syncActiveTabID(for: window)
                }
            }
        }

        center.addObserver(
            self,
            selector: #selector(handleAnyWindowWillCloseNotification(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    @objc private func handleAnyWindowWillCloseNotification(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let windowID = ObjectIdentifier(window)
        let isIgnored = ignoredClosingWindowIDs.remove(windowID) != nil

        let isExplorerWindow = ExplorerWindowRegistry.shared.viewModel(for: window) != nil
            || extraExplorerWindows.contains(window)
        let matchingWebTabID = windowsByTabID.first(where: { $0.value === window })?.key
        let isSessionWindow = isExplorerWindow || matchingWebTabID != nil
        let hadOtherWindows = hasOtherLiveSessionWindows(excluding: window)

        if isSessionWindow,
           !isIgnored,
           !isTerminating,
           !isRestoringSession,
           SessionPreferences.shared.rememberOpenTabsOnLaunch {
            if !hadOtherWindows,
               let snapshot = buildCurrentSessionSnapshot(includingClosingWindow: window) {
                PersistenceService.shared.saveSessionSnapshot(snapshot)
                if let vm = ExplorerWindowRegistry.shared.viewModel(for: window) {
                    PersistenceService.shared.saveLastDirectory(vm.currentDirectoryURL)
                }
            }
        }

        if let group = window.tabGroup, group.windows.count <= 1 {
            tabGroupObservations.removeValue(forKey: ObjectIdentifier(group))
        }
        extraExplorerWindows.remove(window)
        ExplorerWindowRegistry.shared.unregister(window: window)
        if let matchingWebTabID {
            closeTab(matchingWebTabID, closeNativeWindow: false)
        }

        if isSessionWindow, !isIgnored, hadOtherWindows {
            scheduleSessionAutosave()
        }
    }

    // MARK: - Persistencia y Restauración de Sesión (Carpetas y Pestañas Web)

    /// Captura sincrónicamente las pestañas y ventanas abiertas antes de cerrar la app.
    public func prepareForTermination() {
        sessionAutosaveTask?.cancel()
        sessionAutosaveTask = nil
        if SessionPreferences.shared.rememberOpenTabsOnLaunch {
            if let snapshot = buildCurrentSessionSnapshot() {
                PersistenceService.shared.saveSessionSnapshot(snapshot)
                if let activeDir = ExplorerWindowRegistry.shared.activeViewModel?.currentDirectoryURL {
                    PersistenceService.shared.saveLastDirectory(activeDir)
                }
            }
        } else {
            PersistenceService.shared.clearSavedSessionState()
        }
        isTerminating = true
    }

    /// Programa un autoguardado con debounce tras abrir, cerrar, navegar o cambiar pestañas.
    public func scheduleSessionAutosave() {
        guard !isTerminating, !isRestoringSession else { return }
        guard SessionPreferences.shared.rememberOpenTabsOnLaunch else { return }
        sessionAutosaveTask?.cancel()
        sessionAutosaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled else { return }
            self.saveCurrentSessionSnapshot()
        }
    }

    /// Guarda inmediatamente un snapshot de todas las pestañas abiertas (carpetas, Gmail, Drive, Calendar y marcadores).
    public func saveCurrentSessionSnapshot() {
        guard !isTerminating, !isRestoringSession else { return }
        guard SessionPreferences.shared.rememberOpenTabsOnLaunch else {
            PersistenceService.shared.clearSavedSessionState()
            return
        }
        guard let snapshot = buildCurrentSessionSnapshot() else { return }
        PersistenceService.shared.saveSessionSnapshot(snapshot)
    }

    private func isWindowLiveInSession(_ window: NSWindow, includingClosingWindow: NSWindow?) -> Bool {
        if window === includingClosingWindow {
            return true
        }
        if window.isVisible || window.isMiniaturized {
            return true
        }
        if let selected = window.tabGroup?.selectedWindow {
            if selected === includingClosingWindow || selected.isVisible || selected.isMiniaturized {
                return true
            }
        }
        return false
    }

    private func hasOtherLiveSessionWindows(excluding closingWindow: NSWindow) -> Bool {
        for entry in ExplorerWindowRegistry.shared.allRegisteredWindows() where entry.window !== closingWindow {
            if isWindowLiveInSession(entry.window, includingClosingWindow: nil) {
                return true
            }
        }
        for window in windowsByTabID.values where window !== closingWindow {
            if isWindowLiveInSession(window, includingClosingWindow: nil) {
                return true
            }
        }
        return false
    }

    /// Construye el snapshot actual preservando el orden exacto de pestañas de izquierda a derecha en cada grupo de ventanas.
    public func buildCurrentSessionSnapshot(includingClosingWindow: NSWindow? = nil) -> PersistedSessionSnapshot? {
        let explorerEntries = ExplorerWindowRegistry.shared.allRegisteredWindows()
        var explorerByWindowID: [ObjectIdentifier: ExplorerViewModel] = [:]
        explorerByWindowID.reserveCapacity(explorerEntries.count)
        for entry in explorerEntries {
            explorerByWindowID[ObjectIdentifier(entry.window)] = entry.viewModel
        }

        let tabsByID = Dictionary(uniqueKeysWithValues: openTabs.map { ($0.id, $0) })
        var webByWindowID: [ObjectIdentifier: BrowserTabItem] = [:]
        for (tabID, window) in windowsByTabID {
            if let tab = tabsByID[tabID] {
                webByWindowID[ObjectIdentifier(window)] = tab
            }
        }

        let registeredWindows = explorerEntries.map(\.window) + Array(windowsByTabID.values)
        var candidates: [NSWindow] = NSApplication.shared.orderedWindows
        let seenInOrdered = Set(candidates.map { ObjectIdentifier($0) })
        for win in registeredWindows where !seenInOrdered.contains(ObjectIdentifier(win)) {
            candidates.append(win)
        }

        var visitedWindowIDs = Set<ObjectIdentifier>()
        var visitedGroupIDs = Set<ObjectIdentifier>()
        var windowGroups: [PersistedWindowGroupSnapshot] = []
        var groupLeadWindows: [(groupWindows: [NSWindow], selectedWindow: NSWindow?)] = []

        for candidate in candidates {
            let candidateID = ObjectIdentifier(candidate)
            guard !visitedWindowIDs.contains(candidateID) else { continue }
            guard candidate.canBecomeMain, !candidate.isSheet, !(candidate is NSPanel) else { continue }

            let groupWindowsRaw: [NSWindow]
            let selectedInGroup: NSWindow?
            if let group = candidate.tabGroup, !group.windows.isEmpty {
                let groupID = ObjectIdentifier(group)
                guard !visitedGroupIDs.contains(groupID) else { continue }
                visitedGroupIDs.insert(groupID)
                groupWindowsRaw = group.windows
                selectedInGroup = group.selectedWindow
            } else {
                groupWindowsRaw = [candidate]
                selectedInGroup = candidate
            }

            for w in groupWindowsRaw {
                visitedWindowIDs.insert(ObjectIdentifier(w))
            }

            let isGroupLive = groupWindowsRaw.contains {
                isWindowLiveInSession($0, includingClosingWindow: includingClosingWindow)
            }
            guard isGroupLive else { continue }

            var persistedTabs: [PersistedSessionTab] = []
            var liveWindowsInGroup: [NSWindow] = []

            for win in groupWindowsRaw {
                let winID = ObjectIdentifier(win)
                if let vm = explorerByWindowID[winID] {
                    liveWindowsInGroup.append(win)
                    persistedTabs.append(
                        PersistedSessionTab(
                            kind: .folder,
                            folderPath: vm.currentDirectoryURL.standardizedFileURL.path(percentEncoded: false)
                        )
                    )
                } else if let tab = webByWindowID[winID],
                          let serializedTab = persistedTab(from: tab) {
                    liveWindowsInGroup.append(win)
                    persistedTabs.append(serializedTab)
                }
            }

            guard !persistedTabs.isEmpty else { continue }

            let rawActiveIndex = selectedInGroup.flatMap { sel in
                liveWindowsInGroup.firstIndex(where: { $0 === sel })
            } ?? 0
            let activeTabIndex = min(max(rawActiveIndex, 0), persistedTabs.count - 1)
            let frameSourceWindow = selectedInGroup ?? liveWindowsInGroup.first
            let frameString = frameSourceWindow.map { NSStringFromRect($0.frame) }

            windowGroups.append(
                PersistedWindowGroupSnapshot(
                    tabs: persistedTabs,
                    activeTabIndex: activeTabIndex,
                    frameString: frameString
                )
            )
            groupLeadWindows.append((liveWindowsInGroup, selectedInGroup ?? liveWindowsInGroup.first))
        }

        guard !windowGroups.isEmpty else { return nil }

        let frontWindow = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow
        let activeGroupIndex: Int = {
            if let frontWindow,
               let idx = groupLeadWindows.firstIndex(where: { entry in
                   entry.selectedWindow === frontWindow || entry.groupWindows.contains(where: { $0 === frontWindow })
               }) {
                return idx
            }
            return 0
        }()

        return PersistedSessionSnapshot(windowGroups: windowGroups, activeGroupIndex: activeGroupIndex)
    }

    private func persistedTab(from tab: BrowserTabItem) -> PersistedSessionTab? {
        let scheme = tab.currentURL.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }

        // No guardar pestañas vacías de borrador de login que no llegaron a autenticarse
        if tab.service == nil,
           tab.bookmarkID == nil,
           let acct = accounts.first(where: { $0.id == tab.accountID }),
           !acct.isAuthenticated,
           acct.email.isEmpty {
            return nil
        }

        return PersistedSessionTab(
            kind: .web,
            accountID: tab.accountID,
            service: tab.service,
            urlString: tab.currentURL.absoluteString,
            title: tab.title,
            bookmarkID: tab.bookmarkID,
            pageZoom: tab.pageZoom
        )
    }

    /// Restaura automáticamente la sesión guardada la primera vez que aparece la ventana principal al iniciar la app.
    public func restoreInitialSessionIfNeeded(
        initialWindow: NSWindow,
        initialViewModel: ExplorerViewModel?
    ) {
        guard !didAttemptInitialSessionRestore else { return }
        didAttemptInitialSessionRestore = true

        guard SessionPreferences.shared.rememberOpenTabsOnLaunch else { return }
        guard let snapshot = PersistenceService.shared.loadSessionSnapshot(),
              !snapshot.windowGroups.isEmpty else {
            return
        }

        restoreSession(
            snapshot: snapshot,
            initialWindow: initialWindow,
            initialViewModel: initialViewModel
        )
    }

    /// Restaura todas las ventanas, pestañas (carpetas, Gmail, Drive, Calendar y marcadores), orden y selección activa.
    public func restoreSession(
        snapshot: PersistedSessionSnapshot,
        initialWindow: NSWindow,
        initialViewModel: ExplorerViewModel?
    ) {
        enum ResolvedTabSpec {
            case folder(URL)
            case web(BrowserTabItem)
        }

        struct ResolvedGroupSpec {
            var tabs: [ResolvedTabSpec]
            var activeTabIndex: Int
            var frame: NSRect?
        }

        var resolvedGroups: [ResolvedGroupSpec] = []

        for group in snapshot.windowGroups {
            var validTabs: [ResolvedTabSpec] = []
            var mappedActiveIndex: Int?

            for (originalIdx, tab) in group.tabs.enumerated() {
                let resolved: ResolvedTabSpec?
                switch tab.kind {
                case .folder:
                    let validURL = PersistenceService.shared.resolveValidDirectoryURL(forPath: tab.folderPath)
                    resolved = .folder(validURL)
                case .web:
                    if let browserTab = makeRestoredBrowserTab(from: tab) {
                        resolved = .web(browserTab)
                    } else {
                        resolved = nil
                    }
                }

                if let resolved {
                    if originalIdx == group.activeTabIndex {
                        mappedActiveIndex = validTabs.count
                    }
                    validTabs.append(resolved)
                }
            }

            guard !validTabs.isEmpty else { continue }
            let resolvedActiveIndex = min(max(mappedActiveIndex ?? 0, 0), validTabs.count - 1)
            let parsedFrame: NSRect? = {
                guard let raw = group.frameString, !raw.isEmpty else { return nil }
                let rect = NSRectFromString(raw)
                return (rect.width >= 880 && rect.height >= 540) ? rect : nil
            }()
            resolvedGroups.append(
                ResolvedGroupSpec(tabs: validTabs, activeTabIndex: resolvedActiveIndex, frame: parsedFrame)
            )
        }

        guard !resolvedGroups.isEmpty else { return }

        // Elegir qué slot de carpeta reutiliza la `initialWindow` recién creada por SwiftUI
        let preferredReuseGroupIndex = min(max(snapshot.activeGroupIndex, 0), resolvedGroups.count - 1)
        var reuseSlot: (groupIndex: Int, tabIndex: Int)? = nil
        if initialViewModel != nil {
            if let tabIdx = resolvedGroups[preferredReuseGroupIndex].tabs.firstIndex(where: {
                if case .folder = $0 { return true }
                return false
            }) {
                reuseSlot = (preferredReuseGroupIndex, tabIdx)
            } else {
                outer: for (gIdx, group) in resolvedGroups.enumerated() {
                    for (tIdx, tab) in group.tabs.enumerated() {
                        if case .folder = tab {
                            reuseSlot = (gIdx, tIdx)
                            break outer
                        }
                    }
                }
            }
        }

        isRestoringSession = true
        defer { isRestoringSession = false }

        var groupSelectedWindows: [NSWindow] = []
        let defaultFrame = initialWindow.frame

        for (groupIdx, group) in resolvedGroups.enumerated() {
            let groupFrame = group.frame ?? defaultFrame
            var groupWindows: [NSWindow] = []

            for (tabIdx, spec) in group.tabs.enumerated() {
                switch spec {
                case .folder(let folderURL):
                    if let reuseSlot,
                       reuseSlot.groupIndex == groupIdx,
                       reuseSlot.tabIndex == tabIdx,
                       let initialViewModel {
                        if let parsedFrame = group.frame {
                            initialWindow.setFrame(parsedFrame, display: true)
                        }
                        if initialViewModel.currentDirectoryURL.standardizedFileURL != folderURL.standardizedFileURL {
                            initialViewModel.navigate(to: folderURL, recordHistory: false)
                        }
                        NativeWindowTabIconBuilder.applyFolderTabAppearance(
                            to: initialWindow,
                            title: initialViewModel.currentFolderTitle
                        )
                        ExplorerWindowRegistry.shared.register(viewModel: initialViewModel, for: initialWindow)
                        groupWindows.append(initialWindow)
                    } else {
                        let created = createExplorerTabWindow(directoryURL: folderURL, frame: groupFrame)
                        groupWindows.append(created.window)
                    }

                case .web(let browserTab):
                    openTabs.append(browserTab)
                    let webWin = createWebTabWindow(for: browserTab, frame: groupFrame)
                    groupWindows.append(webWin)
                }
            }

            guard !groupWindows.isEmpty else { continue }

            let anchorWindow: NSWindow = {
                if let reuseSlot, reuseSlot.groupIndex == groupIdx {
                    return groupWindows[reuseSlot.tabIndex]
                }
                return groupWindows[0]
            }()

            NSWindow.allowsAutomaticWindowTabbing = true
            anchorWindow.tabbingMode = .preferred
            anchorWindow.tabbingIdentifier = Self.mainWindowTabbingIdentifier
            if !anchorWindow.isVisible {
                anchorWindow.makeKeyAndOrderFront(nil)
            }

            for win in groupWindows where win !== anchorWindow {
                anchorWindow.addTabbedWindow(win, ordered: .above)
            }

            if let tabGroup = anchorWindow.tabGroup {
                for (targetIndex, win) in groupWindows.enumerated() {
                    if targetIndex < tabGroup.windows.count, tabGroup.windows[targetIndex] !== win {
                        tabGroup.insertWindow(win, at: targetIndex)
                    }
                }
            }

            observeTabGroupSelection(for: anchorWindow)

            let selectedWindow = groupWindows[group.activeTabIndex]
            selectedWindow.tabGroup?.selectedWindow = selectedWindow
            selectedWindow.makeKeyAndOrderFront(nil)
            groupSelectedWindows.append(selectedWindow)
        }

        if reuseSlot == nil, let firstRestored = groupSelectedWindows.first {
            ignoredClosingWindowIDs.insert(ObjectIdentifier(initialWindow))
            ExplorerWindowRegistry.shared.unregister(window: initialWindow)
            initialWindow.tabGroup?.removeWindow(initialWindow)
            initialWindow.close()
            firstRestored.makeKeyAndOrderFront(nil)
        }

        let targetGroupIdx = min(max(snapshot.activeGroupIndex, 0), max(groupSelectedWindows.count - 1, 0))
        if groupSelectedWindows.indices.contains(targetGroupIdx) {
            let finalActiveWindow = groupSelectedWindows[targetGroupIdx]
            finalActiveWindow.tabGroup?.selectedWindow = finalActiveWindow
            finalActiveWindow.makeKeyAndOrderFront(nil)
            syncActiveTabID(for: finalActiveWindow)
        }
    }

    private func makeRestoredBrowserTab(from tab: PersistedSessionTab) -> BrowserTabItem? {
        guard let rawURLString = tab.urlString,
              let url = URL(string: rawURLString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let resolvedAccountID = tab.accountID ?? BookmarksManager.generalBookmarksAccountID
        let isGeneralBookmark = resolvedAccountID == BookmarksManager.generalBookmarksAccountID
        if !isGeneralBookmark && !accounts.contains(where: { $0.id == resolvedAccountID }) {
            return nil
        }

        let resolvedTitle: String = {
            let trimmed = (tab.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
            if let serviceTitle = tab.service?.title { return serviceTitle }
            return url.host ?? "Web"
        }()

        let cachedFaviconData: Data? = {
            guard tab.service == nil,
                  let host = url.host,
                  let cachedImage = BookmarksManager.shared.cachedFavicon(forHost: host) else {
                return nil
            }
            return FaviconService.normalizedPNGData(from: cachedImage)
        }()

        let zoom = min(max(tab.pageZoom ?? defaultPageZoom, 0.25), 3.0)
        return BrowserTabItem(
            accountID: resolvedAccountID,
            title: resolvedTitle,
            currentURL: url,
            service: tab.service,
            bookmarkID: tab.bookmarkID,
            faviconData: cachedFaviconData,
            isLoading: true,
            pageZoom: zoom
        )
    }

    // MARK: - Obtención y Control del `WKWebView` Aislado por Pestaña

    /// Obtiene o construye el `WKWebView` para la pestaña indicada usando el `WKWebsiteDataStore(forIdentifier: accountID)` aislado.
    public func webView(for tab: BrowserTabItem) -> WKWebView {
        if let existing = webViewsByTabID[tab.id] {
            if abs(existing.pageZoom - CGFloat(tab.pageZoom)) > 0.001 {
                existing.pageZoom = CGFloat(tab.pageZoom)
            }
            return existing
        }

        let config = WKWebViewConfiguration()
        // Aislamiento criptográfico/por UUID nativo de WebKit en macOS 14+:
        // Cada cuenta de Google tiene su propio almacén persistente de cookies, LocalStorage e IndexedDB.
        let isolatedStore = WKWebsiteDataStore(forIdentifier: tab.accountID)
        config.websiteDataStore = isolatedStore
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let coordinator = WebTabCoordinator(tabID: tab.id, accountID: tab.accountID, manager: self)
        coordinatorsByTabID[tab.id] = coordinator

        let contentController = WKUserContentController()
        if tab.accountID != BookmarksManager.generalBookmarksAccountID {
            contentController.add(coordinator, name: "googleAccountDetector")
            contentController.add(coordinator, name: GoogleDriveUploadService.networkProbeHandlerName)
            let userScript = WKUserScript(
                source: Self.profileDetectionScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
            contentController.addUserScript(userScript)
            let driveObserverScript = WKUserScript(
                source: GoogleDriveUploadService.networkUploadObserverUserScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            contentController.addUserScript(driveObserverScript)
        }
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = Self.chromeMacUserAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.pageZoom = CGFloat(tab.pageZoom)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        coordinator.attachSPAObservers(to: webView)

        webViewsByTabID[tab.id] = webView
        webView.load(URLRequest(url: tab.currentURL))
        return webView
    }

    public func reloadTab(_ tabID: UUID) {
        webViewsByTabID[tabID]?.reload()
    }

    public func goBackInTab(_ tabID: UUID) {
        webViewsByTabID[tabID]?.goBack()
    }

    public func goForwardInTab(_ tabID: UUID) {
        webViewsByTabID[tabID]?.goForward()
    }

    // MARK: - Control de Zoom de Página Completa (`WKWebView.pageZoom`)

    /// Establece un nivel de zoom específico (entre 25% y 300%) en la pestaña indicada.
    public func setZoom(for tabID: UUID, zoom: Double) {
        let clamped = min(max(zoom, 0.25), 3.0)
        guard let idx = openTabs.firstIndex(where: { $0.id == tabID }) else { return }
        openTabs[idx].pageZoom = clamped
        defaultPageZoom = clamped
        webViewsByTabID[tabID]?.pageZoom = CGFloat(clamped)
        scheduleSessionAutosave()
    }

    /// Incrementa el zoom de la página completa al siguiente escalón estilo Chrome.
    public func zoomInTab(_ tabID: UUID) {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabID }) else { return }
        let current = openTabs[idx].pageZoom
        if let nextStep = Self.zoomSteps.first(where: { $0 > current + 0.01 }) {
            setZoom(for: tabID, zoom: nextStep)
        } else {
            setZoom(for: tabID, zoom: 3.0)
        }
    }

    /// Reduce el zoom de la página completa al escalón anterior estilo Chrome.
    public func zoomOutTab(_ tabID: UUID) {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabID }) else { return }
        let current = openTabs[idx].pageZoom
        if let prevStep = Self.zoomSteps.last(where: { $0 < current - 0.01 }) {
            setZoom(for: tabID, zoom: prevStep)
        } else {
            setZoom(for: tabID, zoom: 0.25)
        }
    }

    /// Restablece el zoom de la página al 100% (`1.0`).
    public func resetZoomInTab(_ tabID: UUID) {
        setZoom(for: tabID, zoom: 1.0)
    }

    public func navigateTab(_ tabID: UUID, to rawURLString: String) {
        let trimmed = rawURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let finalURL: URL?
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            finalURL = URL(string: trimmed)
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            finalURL = URL(string: "https://\(trimmed)")
        } else {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            finalURL = URL(string: "https://www.google.com/search?q=\(encoded)")
        }

        if let url = finalURL {
            if let idx = openTabs.firstIndex(where: { $0.id == tabID }) {
                openTabs[idx].bookmarkID = nil
                if !FaviconService.hostsMatchNormalized(openTabs[idx].currentURL.host, url.host) {
                    openTabs[idx].faviconData = nil
                }
            }
            webViewsByTabID[tabID]?.load(URLRequest(url: url))
        }
    }

    // MARK: - Actualización de Estado desde `WebTabCoordinator`

    fileprivate func updateTabState(
        tabID: UUID,
        title: String?,
        url: URL?,
        isLoading: Bool,
        canGoBack: Bool,
        canGoForward: Bool
    ) {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabID }) else { return }
        let oldTitle = openTabs[idx].title
        let oldURL = openTabs[idx].currentURL
        let oldFaviconData = openTabs[idx].faviconData

        if let title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                openTabs[idx].title = trimmed
            }
        }
        if let url {
            if openTabs[idx].service == nil,
               !FaviconService.hostsMatchNormalized(oldURL.host, url.host) {
                openTabs[idx].faviconData = nil
            }
            openTabs[idx].currentURL = url
        }
        openTabs[idx].isLoading = isLoading
        openTabs[idx].canGoBack = canGoBack
        openTabs[idx].canGoForward = canGoForward

        let updatedTab = openTabs[idx]
        if updatedTab.title != oldTitle || updatedTab.currentURL != oldURL {
            scheduleSessionAutosave()
        }
        if (updatedTab.title != oldTitle || updatedTab.currentURL != oldURL || updatedTab.faviconData != oldFaviconData),
           let window = windowsByTabID[tabID] {
            NativeWindowTabIconBuilder.applyWebTabAppearance(to: window, for: updatedTab)
        }
    }

    fileprivate func captureFaviconIfNeeded(for tabID: UUID, from webView: WKWebView) async {
        guard let initialTab = openTabs.first(where: { $0.id == tabID }),
              initialTab.service == nil else {
            return
        }

        let targetURL = webView.url ?? initialTab.currentURL
        var capturedPNG = await FaviconService.captureFaviconData(from: webView)

        // Algunas SPAs inyectan `<link rel="icon">` dinámicamente tras completar la hidratación JS.
        if capturedPNG == nil, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled,
                  let currentWebURL = webView.url,
                  currentWebURL == targetURL || FaviconService.hostsMatchNormalized(currentWebURL.host, targetURL.host) else {
                return
            }
            capturedPNG = await FaviconService.captureFaviconData(from: webView)
        }

        guard !Task.isCancelled,
              let pngData = capturedPNG,
              let idx = openTabs.firstIndex(where: { $0.id == tabID }),
              openTabs[idx].service == nil else {
            return
        }

        let finalURL = webView.url ?? openTabs[idx].currentURL
        let changed = (openTabs[idx].faviconData != pngData)
        openTabs[idx].faviconData = pngData

        if changed, let window = windowsByTabID[tabID] {
            NativeWindowTabIconBuilder.applyWebTabAppearance(to: window, for: openTabs[idx])
        }

        BookmarksManager.shared.recordCapturedFavicon(
            pngData,
            forPageURL: finalURL,
            sourceBookmarkID: openTabs[idx].bookmarkID
        )
    }

    fileprivate static let profileDetectionScript: String = #"""
    (function() {
        const host = (window.location.hostname || '').toLowerCase();
        const isGoogleHost = host === 'google.com' || host.endsWith('.google.com') || host.includes('.google.');
        if (!isGoogleHost) return;

        let lastSentEmail = '';
        let lastSentAvatarKey = '';
        let scanInFlight = false;

        function isInsideMailBody(el) {
            return Boolean(host === 'mail.google.com' && el && el.closest && el.closest('[role="main"]'));
        }

        function extractBgImageURL(el) {
            if (!el) return null;
            try {
                const bg = window.getComputedStyle(el).backgroundImage || el.style.backgroundImage || '';
                const m = bg.match(/url\(["']?(https?:\/\/[^"')]+|data:image\/[^"')]+)["']?\)/i);
                return m ? m[1] : null;
            } catch (_) {
                return null;
            }
        }

        function isValidAvatarURL(url) {
            if (!url || typeof url !== 'string') return false;
            const lower = url.toLowerCase();
            if (lower.startsWith('data:image/')) return true;
            if (!lower.startsWith('https://') && !lower.startsWith('http://')) return false;
            if (lower.includes('googlelogo') || lower.includes('favicon') || lower.includes('gstatic.com/images')) {
                return false;
            }
            return lower.includes('googleusercontent.com')
                || lower.includes('ggpht.com')
                || lower.includes('google.com/s2/photos');
        }

        function findImgURLInSubtree(root) {
            if (!root || isInsideMailBody(root)) return null;
            if (root.tagName === 'IMG') {
                const src = root.currentSrc || root.src || root.getAttribute('data-src');
                if (isValidAvatarURL(src)) return src;
            }
            const imgs = root.querySelectorAll ? root.querySelectorAll('img') : [];
            for (const img of imgs) {
                const src = img.currentSrc || img.src || img.getAttribute('data-src');
                if (isValidAvatarURL(src)) return src;
            }
            const bg = extractBgImageURL(root);
            if (isValidAvatarURL(bg)) return bg;
            if (root.querySelectorAll) {
                const styled = root.querySelectorAll('[style*="background"], span, div');
                for (const child of styled) {
                    const cbg = extractBgImageURL(child);
                    if (isValidAvatarURL(cbg)) return cbg;
                }
            }
            return null;
        }

        function scanEmail() {
            try {
                const selectors = [
                    '#gb a[aria-label*="@"]',
                    '#gb button[aria-label*="@"]',
                    '[data-email]',
                    '[data-identifier]',
                    'input[type="email"]',
                    '[aria-label*="@"]'
                ];
                for (const sel of selectors) {
                    const elements = document.querySelectorAll(sel);
                    for (const el of elements) {
                        if (isInsideMailBody(el)) continue;
                        const candidates = [
                            el.getAttribute('data-email'),
                            el.getAttribute('data-identifier'),
                            el.value,
                            el.getAttribute('aria-label'),
                            el.textContent
                        ];
                        for (const raw of candidates) {
                            if (!raw) continue;
                            const match = raw.match(/([a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,})/);
                            if (match && match[1]) {
                                return match[1].toLowerCase();
                            }
                        }
                    }
                }
                if (document.title) {
                    const titleMatch = document.title.match(/([a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,})/);
                    if (titleMatch && titleMatch[1]) {
                        return titleMatch[1].toLowerCase();
                    }
                }
            } catch (_) {}
            return null;
        }

        function scanAvatarURL(detectedEmail) {
            try {
                const containers = [];
                // 1) Cabecera oficial OneGoogleBar (`#gb`) o widget iframe (`ogs.google.com`)
                containers.push(
                    ...document.querySelectorAll('#gb a[href*="SignOutOptions"], #gb a[aria-label*="@"], #gb button[aria-label*="@"], a[href*="accounts.google.com/SignOutOptions"], [data-ogsr-up]')
                );
                if (detectedEmail) {
                    const matches = document.querySelectorAll('[aria-label*="@"], [data-email], [data-identifier]');
                    for (const el of matches) {
                        if (isInsideMailBody(el)) continue;
                        const aria = (el.getAttribute('aria-label') || '').toLowerCase();
                        const de = (el.getAttribute('data-email') || '').toLowerCase();
                        const di = (el.getAttribute('data-identifier') || '').toLowerCase();
                        if (aria.includes(detectedEmail) || de === detectedEmail || di === detectedEmail) {
                            containers.push(el);
                        }
                    }
                }
                for (const container of containers) {
                    const found = findImgURLInSubtree(container);
                    if (found) return found;
                }

                // 2) Clase clásica `gbii` o URL exclusiva del widget OneGoogle (`/ogw/`)
                const ogwNodes = document.querySelectorAll('img.gbii, .gbii, img[src*="googleusercontent.com/ogw/"], img[src*="googleusercontent.com/ogp/"]');
                for (const node of ogwNodes) {
                    const found = findImgURLInSubtree(node);
                    if (found) return found;
                }

                // 3) Widget iframe dedicado de cuenta de Google (`ogs.google.com`)
                if (host === 'ogs.google.com') {
                    const ogsImgs = document.querySelectorAll('img[src*="googleusercontent.com"]');
                    for (const img of ogsImgs) {
                        const found = findImgURLInSubtree(img);
                        if (found) return found;
                    }
                }

                // 4) Página principal de Mi Cuenta (`myaccount.google.com`)
                if (host === 'myaccount.google.com') {
                    const myAcctImgs = document.querySelectorAll('img[src*="googleusercontent.com/a/"], img[src*="googleusercontent.com/a-/"]');
                    for (const img of myAcctImgs) {
                        const w = img.naturalWidth || img.width || 0;
                        if (w >= 20) {
                            const found = findImgURLInSubtree(img);
                            if (found) return found;
                        }
                    }
                }
            } catch (_) {}
            return null;
        }

        async function captureAvatarDataURL(url) {
            try {
                if (url.startsWith('data:image/')) return url;
                const resp = await fetch(url, { credentials: 'include' });
                if (!resp.ok) return null;
                const blob = await resp.blob();
                if (!blob || blob.size === 0) return null;
                return await new Promise((resolve) => {
                    const reader = new FileReader();
                    reader.onloadend = () => resolve(typeof reader.result === 'string' ? reader.result : null);
                    reader.onerror = () => resolve(null);
                    reader.readAsDataURL(blob);
                });
            } catch (_) {
                return null;
            }
        }

        let pollIntervalId = null;
        let fastPollTicks = 0;

        function stopFastPolling(enableSlowBackoff) {
            if (pollIntervalId !== null) {
                clearInterval(pollIntervalId);
                pollIntervalId = null;
            }
            if (enableSlowBackoff && window === window.top) {
                pollIntervalId = setInterval(scanForGoogleProfile, 30000);
            }
        }

        async function scanForGoogleProfile() {
            if (scanInFlight) return;
            scanInFlight = true;
            try {
                const email = scanEmail();
                const avatarURL = scanAvatarURL(email);
                const effectiveEmail = email || lastSentEmail;
                const avatarKey = avatarURL || '';

                if (!effectiveEmail && !avatarURL) return;
                if (effectiveEmail === lastSentEmail && avatarKey === lastSentAvatarKey) {
                    if (lastSentEmail && lastSentAvatarKey) {
                        stopFastPolling(false);
                    }
                    return;
                }

                let avatarDataURL = null;
                if (avatarURL && avatarKey !== lastSentAvatarKey) {
                    avatarDataURL = await captureAvatarDataURL(avatarURL);
                }

                lastSentEmail = effectiveEmail;
                if (avatarURL) lastSentAvatarKey = avatarKey;

                const payload = {};
                if (effectiveEmail) payload.email = effectiveEmail;
                if (avatarURL) payload.avatarURL = avatarURL;
                if (avatarDataURL) payload.avatarDataURL = avatarDataURL;
                window.webkit.messageHandlers.googleAccountDetector.postMessage(payload);

                if (lastSentEmail && lastSentAvatarKey) {
                    stopFastPolling(false);
                }
            } catch (_) {} finally {
                scanInFlight = false;
            }
        }

        scanForGoogleProfile();
        pollIntervalId = setInterval(() => {
            fastPollTicks += 1;
            scanForGoogleProfile();
            if (lastSentEmail && lastSentAvatarKey) {
                stopFastPolling(false);
            } else if (fastPollTicks >= 12) {
                stopFastPolling(true);
            }
        }, 1500);
        document.addEventListener('change', scanForGoogleProfile, true);
        document.addEventListener('blur', scanForGoogleProfile, true);
    })();
    """#

    fileprivate func recordDetectedProfile(
        email: String?,
        avatarURL: String?,
        avatarDataURL: String?,
        for accountID: UUID
    ) {
        guard let idx = accounts.firstIndex(where: { $0.id == accountID }) else { return }

        if let email {
            let clean = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if clean.contains("@"), accounts[idx].email != clean {
                accounts[idx].email = clean
            }
        }

        if let avatarDataURL,
           let rawBytes = FaviconService.decodeDataURL(avatarDataURL),
           let pngData = FaviconService.normalizedPNGData(from: rawBytes, targetPixelSize: 64) {
            storeAvatarPNG(pngData, avatarURL: avatarURL, forAccountID: accountID)
            return
        }

        guard let avatarURL = avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !avatarURL.isEmpty,
              let remoteURL = URL(string: avatarURL) else {
            return
        }

        let needsDownload = accounts[idx].avatarData == nil || accounts[idx].avatarURLString != avatarURL
        guard needsDownload else {
            finishAvatarHydration(for: accountID)
            return
        }
        accounts[idx].avatarURLString = avatarURL

        avatarDownloadTasks[accountID]?.cancel()
        avatarDownloadTasks[accountID] = Task { [weak self] in
            guard let pngData = await Self.downloadAndNormalizeAvatarData(from: remoteURL) else {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.storeAvatarPNG(pngData, avatarURL: avatarURL, forAccountID: accountID)
        }
    }

    private func storeAvatarPNG(_ pngData: Data, avatarURL: String?, forAccountID accountID: UUID) {
        guard let image = NSImage(data: pngData),
              let idx = accounts.firstIndex(where: { $0.id == accountID }) else {
            return
        }
        avatarImageCache.setObject(image, forKey: accountID.uuidString as NSString)
        if let avatarURL, accounts[idx].avatarURLString != avatarURL {
            accounts[idx].avatarURLString = avatarURL
        }
        if accounts[idx].avatarData != pngData {
            accounts[idx].avatarData = pngData
        }
        finishAvatarHydration(for: accountID)
    }

    private nonisolated static func downloadAndNormalizeAvatarData(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://myaccount.google.com/", forHTTPHeaderField: "Referer")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse,
                  httpResp.statusCode == 200 else {
                return nil
            }
            return FaviconService.normalizedPNGData(from: data, targetPixelSize: 64)
        } catch {
            return nil
        }
    }

    private func scheduleMissingAvatarHydration() {
        let missingAccounts = accounts.filter { $0.isAuthenticated && $0.avatarData == nil }
        guard !missingAccounts.isEmpty else { return }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard let self else { return }
            for account in missingAccounts {
                guard self.accounts.contains(where: { $0.id == account.id && $0.isAuthenticated && $0.avatarData == nil }),
                      self.avatarHydrationSessions[account.id] == nil else {
                    continue
                }
                let session = AvatarHydrationSession(accountID: account.id, manager: self)
                self.avatarHydrationSessions[account.id] = session
                session.start()
            }
        }
    }

    fileprivate func finishAvatarHydration(for accountID: UUID) {
        avatarHydrationSessions.removeValue(forKey: accountID)?.teardown()
    }

    fileprivate func verifyAuthenticationStatus(for accountID: UUID, currentURL: URL?) {
        guard accounts.contains(where: { $0.id == accountID }) else { return }
        let store = WKWebsiteDataStore(forIdentifier: accountID)

        store.httpCookieStore.getAllCookies { [weak self] cookies in
            let hasGoogleAuthCookie = cookies.contains { cookie in
                let domain = cookie.domain.lowercased()
                guard domain.contains("google.com") else { return false }
                let name = cookie.name
                return name == "SID" || name == "HSID" || name == "SSID" || name == "__Secure-1PSID" || name == "LSID"
            }

            guard hasGoogleAuthCookie else { return }

            Task { @MainActor [weak self] in
                guard let self,
                      let currentIdx = self.accounts.firstIndex(where: { $0.id == accountID }) else { return }
                let wasAuthenticated = self.accounts[currentIdx].isAuthenticated
                self.accounts[currentIdx].isAuthenticated = true
                if self.accounts[currentIdx].email.isEmpty {
                    self.accounts[currentIdx].displayName = "Google Account #\(currentIdx + 1)"
                }
                if !wasAuthenticated {
                    self.expandedAccountIDs.insert(accountID)
                }
            }
        }
    }

    // MARK: - Persistencia en `UserDefaults`

    private func saveAccounts() {
        if let encoded = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(encoded, forKey: accountsDefaultsKey)
        }
    }

    private func loadPersistedState() {
        if UserDefaults.standard.object(forKey: sectionExpandedDefaultsKey) != nil {
            isGoogleSectionExpanded = UserDefaults.standard.bool(forKey: sectionExpandedDefaultsKey)
        } else {
            isGoogleSectionExpanded = true
        }

        let storedZoom = UserDefaults.standard.double(forKey: defaultPageZoomDefaultsKey)
        if storedZoom >= 0.25 && storedZoom <= 3.0 {
            defaultPageZoom = storedZoom
        } else {
            defaultPageZoom = 1.0
        }

        if let data = UserDefaults.standard.data(forKey: accountsDefaultsKey),
           let decoded = try? JSONDecoder().decode([GoogleAccount].self, from: data) {
            accounts = decoded
        }

        if let rawExpanded = UserDefaults.standard.stringArray(forKey: expandedAccountsDefaultsKey) {
            expandedAccountIDs = Set(rawExpanded.compactMap { UUID(uuidString: $0) })
        } else {
            expandedAccountIDs = Set(accounts.map(\.id))
        }
    }

    // MARK: - Enrutamiento de Enlaces Externos a Google Chrome

    /// Dominios permitidos para permanecer dentro de las pestañas de Gmail, Drive, Calendar y Google Docs/Sheets/Slides.
    public static let allowedServiceHosts: Set<String> = [
        "mail.google.com",
        "drive.google.com",
        "calendar.google.com",
        "docs.google.com"
    ]

    /// Dominios auxiliares de autenticación para permitir iniciar/renovar sesión dentro de la app.
    private static let interactiveAuthHosts: Set<String> = [
        "accounts.google.com",
        "accounts.youtube.com"
    ]

    /// Extrae la URL de destino real cuando Gmail/Google envuelve un enlace en `google.com/url?q=...` o `?url=...`.
    public static func resolveOutboundLinkURL(_ url: URL) -> URL {
        guard let host = url.host?.lowercased(),
              host == "www.google.com" || host == "google.com",
              url.path == "/url",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return url
        }

        for paramName in ["q", "url"] {
            if let rawTarget = queryItems.first(where: { $0.name == paramName })?.value,
               let decodedTarget = URL(string: rawTarget),
               let scheme = decodedTarget.scheme?.lowercased(),
               scheme == "http" || scheme == "https",
               let targetHost = decodedTarget.host,
               !targetHost.isEmpty {
                return decodedTarget
            }
        }
        return url
    }

    /// Determina si una navegación iniciada por enlace dentro de Gmail, Drive o Calendar debe permanecer en la app.
    public static func shouldKeepNavigationInServiceTab(targetURL: URL, currentWebViewURL: URL?) -> Bool {
        guard let scheme = targetURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return true
        }
        guard let targetHost = targetURL.host?.lowercased(), !targetHost.isEmpty else {
            return true
        }
        if allowedServiceHosts.contains(targetHost) {
            return true
        }
        if let currentHost = currentWebViewURL?.host?.lowercased(),
           interactiveAuthHosts.contains(currentHost),
           interactiveAuthHosts.contains(targetHost) {
            return true
        }
        return false
    }

    /// Si la pestaña es de Gmail, Drive o Calendar y el enlace apunta fuera de los 3 dominios permitidos,
    /// devuelve la URL resuelta para abrirla en Google Chrome; en caso contrario devuelve `nil`.
    fileprivate func externalChromeURLIfRedirectNeeded(
        for linkURL: URL,
        inTab tabID: UUID,
        currentWebViewURL: URL?
    ) -> URL? {
        guard let tab = openTabs.first(where: { $0.id == tabID }), tab.service != nil else {
            return nil
        }
        let resolvedURL = Self.resolveOutboundLinkURL(linkURL)
        // Si el usuario eligió abrir Google Sheets / Docs / Slides en Google Chrome externo,
        // cualquier documento de `docs.google.com` abierto desde la pestaña de Drive también se abre en Chrome externo.
        if tab.service == .drive,
           GoogleDriveUploadPreferences.shared.openInExternalChrome,
           let targetHost = resolvedURL.host?.lowercased(),
           targetHost == "docs.google.com" {
            let email = accounts.first(where: { $0.id == tab.accountID })?.email
            return GoogleDriveUploadService.urlWithAuthUser(resolvedURL, email: email)
        }
        guard !Self.shouldKeepNavigationInServiceTab(targetURL: resolvedURL, currentWebViewURL: currentWebViewURL) else {
            return nil
        }
        return resolvedURL
    }
}

// MARK: - Hidratación Silenciosa de Foto de Perfil para Cuentas Ya Autenticadas

@MainActor
private final class AvatarHydrationSession: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private let accountID: UUID
    private weak var manager: GoogleAccountsManager?
    private var webView: WKWebView?
    private var timeoutTask: Task<Void, Never>?
    private var fallbackTask: Task<Void, Never>?
    private var triedMailFallback = false
    private var isTornDown = false

    init(accountID: UUID, manager: GoogleAccountsManager) {
        self.accountID = accountID
        self.manager = manager
    }

    func start() {
        guard !isTornDown else { return }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: accountID)

        let controller = WKUserContentController()
        controller.add(self, name: "googleAccountDetector")
        controller.addUserScript(
            WKUserScript(
                source: GoogleAccountsManager.profileDetectionScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
        )
        config.userContentController = controller

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768), configuration: config)
        wv.customUserAgent = GoogleAccountsManager.chromeMacUserAgent
        wv.navigationDelegate = self
        self.webView = wv

        if let url = URL(string: "https://myaccount.google.com/?hl=en") {
            wv.load(URLRequest(url: url))
        }

        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !self.isTornDown else { return }
            self.manager?.finishAvatarHydration(for: self.accountID)
        }
    }

    func teardown() {
        guard !isTornDown else { return }
        isTornDown = true
        timeoutTask?.cancel()
        fallbackTask?.cancel()
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "googleAccountDetector")
        webView = nil
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard !isTornDown,
              message.name == "googleAccountDetector",
              let dict = message.body as? [String: Any] else { return }
        manager?.recordDetectedProfile(
            email: dict["email"] as? String,
            avatarURL: dict["avatarURL"] as? String,
            avatarDataURL: dict["avatarDataURL"] as? String,
            for: accountID
        )
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !isTornDown else { return }
        let currentURLString = webView.url?.absoluteString.lowercased() ?? ""
        if currentURLString.contains("accounts.google.com") &&
           (currentURLString.contains("servicelogin") || currentURLString.contains("signin")) {
            // La sesión expiró y pide login interactivo; cancelar hidratación silenciosa
            manager?.finishAvatarHydration(for: accountID)
            return
        }

        if !triedMailFallback {
            triedMailFallback = true
            fallbackTask?.cancel()
            fallbackTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard let self, !self.isTornDown else { return }
                if let gmailURL = URL(string: "https://mail.google.com/mail/u/0/") {
                    self.webView?.load(URLRequest(url: gmailURL))
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !isTornDown else { return }
        manager?.finishAvatarHydration(for: accountID)
    }
}

// MARK: - Coordinador de `WKWebView` por Pestaña

@MainActor
private final class WebTabCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let tabID: UUID
    let accountID: UUID
    weak var manager: GoogleAccountsManager?
    private var faviconCaptureTask: Task<Void, Never>?
    private var urlObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?

    init(tabID: UUID, accountID: UUID, manager: GoogleAccountsManager) {
        self.tabID = tabID
        self.accountID = accountID
        self.manager = manager
    }

    /// Observa cambios de URL y título por KVO para reflejar navegación SPA (`history.pushState`)
    /// en Google Drive, Gmail, Calendar y Google Docs en tiempo real.
    func attachSPAObservers(to webView: WKWebView) {
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
            Task { @MainActor [weak self, weak wv] in
                guard let self, let wv else { return }
                self.manager?.updateTabState(
                    tabID: self.tabID,
                    title: wv.title,
                    url: wv.url,
                    isLoading: wv.isLoading,
                    canGoBack: wv.canGoBack,
                    canGoForward: wv.canGoForward
                )
            }
        }
        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
            Task { @MainActor [weak self, weak wv] in
                guard let self, let wv else { return }
                self.manager?.updateTabState(
                    tabID: self.tabID,
                    title: wv.title,
                    url: wv.url,
                    isLoading: wv.isLoading,
                    canGoBack: wv.canGoBack,
                    canGoForward: wv.canGoForward
                )
            }
        }
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        if message.name == GoogleDriveUploadService.networkProbeHandlerName,
           let dict = message.body as? [String: Any] {
            GoogleDriveUploadService.shared.handleNetworkProbeMessage(forTabID: tabID, payload: dict)
            return
        }
        guard message.name == "googleAccountDetector",
              let dict = message.body as? [String: Any] else { return }
        manager?.recordDetectedProfile(
            email: dict["email"] as? String,
            avatarURL: dict["avatarURL"] as? String,
            avatarDataURL: dict["avatarDataURL"] as? String,
            for: accountID
        )
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        faviconCaptureTask?.cancel()
        manager?.updateTabState(
            tabID: tabID,
            title: webView.title,
            url: webView.url,
            isLoading: true,
            canGoBack: webView.canGoBack,
            canGoForward: webView.canGoForward
        )
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        manager?.updateTabState(
            tabID: tabID,
            title: webView.title,
            url: webView.url,
            isLoading: webView.isLoading,
            canGoBack: webView.canGoBack,
            canGoForward: webView.canGoForward
        )
        manager?.verifyAuthenticationStatus(for: accountID, currentURL: webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        manager?.updateTabState(
            tabID: tabID,
            title: webView.title,
            url: webView.url,
            isLoading: false,
            canGoBack: webView.canGoBack,
            canGoForward: webView.canGoForward
        )
        manager?.verifyAuthenticationStatus(for: accountID, currentURL: webView.url)

        faviconCaptureTask?.cancel()
        let currentTabID = tabID
        faviconCaptureTask = Task { @MainActor [weak self, weak webView] in
            guard let webView, let manager = self?.manager else { return }
            await manager.captureFaviconIfNeeded(for: currentTabID, from: webView)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        manager?.updateTabState(
            tabID: tabID,
            title: webView.title,
            url: webView.url,
            isLoading: false,
            canGoBack: webView.canGoBack,
            canGoForward: webView.canGoForward
        )
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        guard isMainFrame,
              navigationAction.navigationType == .linkActivated,
              let targetURL = navigationAction.request.url,
              let externalURL = manager?.externalChromeURLIfRedirectNeeded(
                  for: targetURL,
                  inTab: tabID,
                  currentWebViewURL: webView.url
              ) else {
            decisionHandler(.allow)
            return
        }

        BookmarksManager.shared.openURLInGoogleChrome(externalURL)
        decisionHandler(.cancel)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // Cuando un enlace dentro de Gmail, Drive o Calendar solicita abrirse en ventana/pestaña nueva (target="_blank"):
        // - Si el destino pertenece a mail.google.com, drive.google.com o calendar.google.com, cargarlo dentro de la app.
        // - Si el destino es otro dominio, abrirlo en Google Chrome sin salir de la vista del servicio.
        if navigationAction.targetFrame == nil, let targetURL = navigationAction.request.url {
            if let externalURL = manager?.externalChromeURLIfRedirectNeeded(
                for: targetURL,
                inTab: tabID,
                currentWebViewURL: webView.url
            ) {
                BookmarksManager.shared.openURLInGoogleChrome(externalURL)
                return nil
            }
            let resolvedURL = GoogleAccountsManager.resolveOutboundLinkURL(targetURL)
            webView.load(URLRequest(url: resolvedURL))
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor ([URL]?) -> Void
    ) {
        // Si «Enviar a Drive» tiene una subida automática programada en esta pestaña, inyectar el archivo directo sin diálogo manual.
        if let automatedURL = GoogleDriveUploadService.shared.consumeAutomatedUploadURL(forTabID: tabID) {
            completionHandler([automatedURL])
            return
        }
        // Si hay una subida automática activa en curso, jamás abrir NSOpenPanel (Finder).
        if GoogleDriveUploadService.shared.isAutomatedUploadActive(forTabID: tabID) {
            completionHandler(nil)
            return
        }

        // Permitir adjuntar archivos desde el Mac en Gmail o subir archivos a Google Drive
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            completionHandler(panel.urls)
        } else {
            completionHandler(nil)
        }
    }
}
