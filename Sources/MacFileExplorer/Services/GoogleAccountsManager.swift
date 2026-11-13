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
    public func openURLInAccountTab(_ url: URL, for accountID: UUID, service: GoogleServiceShortcut? = nil) {
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

    /// Abre una nueva pestaña del Explorador de Archivos dentro de la barra de pestañas nativa de `MacFileExplorer`.
    public func openNewFileExplorerTabWindow(from sourceWindow: NSWindow? = nil) {
        let anchorWindow = resolveAnchorWindow(preferred: sourceWindow)
        let frame = anchorWindow?.frame ?? NSRect(x: 120, y: 120, width: 1160, height: 720)
        let newExplorerWindow = ExplorerNativeTabWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newExplorerWindow.isReleasedWhenClosed = false
        newExplorerWindow.minSize = NSSize(width: 880, height: 540)
        newExplorerWindow.tabbingMode = .preferred
        newExplorerWindow.tabbingIdentifier = Self.mainWindowTabbingIdentifier
        newExplorerWindow.toolbarStyle = .unifiedCompact

        let initialFolderURL = anchorWindow.flatMap {
            ExplorerWindowRegistry.shared.viewModel(for: $0)?.currentDirectoryURL
        }
        let explorerVM = ExplorerViewModel(initialDirectoryURL: initialFolderURL)
        NativeWindowTabIconBuilder.applyFolderTabAppearance(to: newExplorerWindow, title: explorerVM.currentFolderTitle)
        newExplorerWindow.contentViewController = NSHostingController(rootView: MainExplorerView(viewModel: explorerVM))

        extraExplorerWindows.insert(newExplorerWindow)
        attachWindowToTabGroup(newExplorerWindow, anchorWindow: anchorWindow)
        activeTabID = nil
    }

    /// Cierra la pestaña actual (carpeta o web) y activa una pestaña adyacente si quedan otras en el grupo.
    public func closeCurrentTabWindow(from sourceWindow: NSWindow? = nil) {
        guard let anchorWindow = resolveAnchorWindow(preferred: sourceWindow) else { return }
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

    /// Crea o activa la pestaña nativa (`NSWindow`) en la barra superior de `MacFileExplorer` para el `BrowserTabItem` dado.
    public func presentOrActivateNativeWindowTab(for tab: BrowserTabItem) {
        if let existingWindow = windowsByTabID[tab.id] {
            NativeWindowTabIconBuilder.applyWebTabAppearance(to: existingWindow, for: tab)
            existingWindow.tabGroup?.selectedWindow = existingWindow
            existingWindow.makeKeyAndOrderFront(nil)
            activeTabID = tab.id
            return
        }

        let anchorWindow = resolveAnchorWindow()
        let frame = anchorWindow?.frame ?? NSRect(x: 120, y: 120, width: 1160, height: 720)
        let webWindow = ExplorerNativeTabWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        webWindow.isReleasedWhenClosed = false
        webWindow.minSize = NSSize(width: 880, height: 540)
        webWindow.tabbingMode = .preferred
        webWindow.tabbingIdentifier = Self.mainWindowTabbingIdentifier
        webWindow.toolbarStyle = .unifiedCompact
        NativeWindowTabIconBuilder.applyWebTabAppearance(to: webWindow, for: tab)
        webWindow.contentViewController = NSHostingController(rootView: IsolatedGoogleWebTabView(tabID: tab.id))

        windowsByTabID[tab.id] = webWindow

        attachWindowToTabGroup(webWindow, anchorWindow: anchorWindow)
        activeTabID = tab.id
    }

    private func resolveAnchorWindow(preferred sourceWindow: NSWindow? = nil) -> NSWindow? {
        if let sourceWindow, sourceWindow.canBecomeMain, !sourceWindow.isSheet {
            return sourceWindow
        }
        if let key = NSApplication.shared.keyWindow, key.isVisible, key.canBecomeMain, !key.isSheet {
            return key
        }
        if let main = NSApplication.shared.mainWindow, main.isVisible, main.canBecomeMain, !main.isSheet {
            return main
        }
        let candidates = NSApplication.shared.windows.filter {
            $0.isVisible && $0.canBecomeMain && !$0.isSheet
        }
        return candidates.first(where: { $0.tabbingIdentifier == Self.mainWindowTabbingIdentifier })
            ?? candidates.first
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
            return
        }
        if let anyExplorerWindow = NSApplication.shared.windows.first(where: {
            $0.isVisible && $0.canBecomeMain && !$0.isSheet && !webWindowSet.contains($0)
        }) {
            activeTabID = nil
            anyExplorerWindow.tabGroup?.selectedWindow = anyExplorerWindow
            anyExplorerWindow.makeKeyAndOrderFront(nil)
        } else {
            openNewFileExplorerTabWindow()
        }
    }

    /// Cierra una pestaña web y libera su `WKWebView` y su `NSWindow` nativa.
    public func closeTab(_ tabID: UUID, closeNativeWindow: Bool = true) {
        if closeNativeWindow, let window = windowsByTabID.removeValue(forKey: tabID) {
            window.close()
        } else {
            windowsByTabID.removeValue(forKey: tabID)
        }

        guard let index = openTabs.firstIndex(where: { $0.id == tabID }) else { return }
        let removedTab = openTabs.remove(at: index)
        webViewsByTabID[tabID]?.stopLoading()
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
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor [weak self, weak window] in
                guard let self, let window else { return }
                if let group = window.tabGroup, group.windows.count <= 1 {
                    self.tabGroupObservations.removeValue(forKey: ObjectIdentifier(group))
                }
                self.extraExplorerWindows.remove(window)
                if let match = self.windowsByTabID.first(where: { $0.value === window }) {
                    self.closeTab(match.key, closeNativeWindow: false)
                }
            }
        }
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
            let userScript = WKUserScript(
                source: Self.profileDetectionScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
            contentController.addUserScript(userScript)
        }
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = Self.chromeMacUserAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.pageZoom = CGFloat(tab.pageZoom)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator

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

        async function scanForGoogleProfile() {
            if (scanInFlight) return;
            scanInFlight = true;
            try {
                const email = scanEmail();
                const avatarURL = scanAvatarURL(email);
                const effectiveEmail = email || lastSentEmail;
                const avatarKey = avatarURL || '';

                if (!effectiveEmail && !avatarURL) return;
                if (effectiveEmail === lastSentEmail && avatarKey === lastSentAvatarKey) return;

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
            } catch (_) {} finally {
                scanInFlight = false;
            }
        }

        scanForGoogleProfile();
        setInterval(scanForGoogleProfile, 1500);
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

    /// Dominios permitidos para permanecer dentro de las pestañas de Gmail, Drive y Calendar.
    public static let allowedServiceHosts: Set<String> = [
        "mail.google.com",
        "drive.google.com",
        "calendar.google.com"
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
        guard openTabs.first(where: { $0.id == tabID })?.service != nil else {
            return nil
        }
        let resolvedURL = Self.resolveOutboundLinkURL(linkURL)
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

    init(tabID: UUID, accountID: UUID, manager: GoogleAccountsManager) {
        self.tabID = tabID
        self.accountID = accountID
        self.manager = manager
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
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
        completionHandler: @escaping ([URL]?) -> Void
    ) {
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
