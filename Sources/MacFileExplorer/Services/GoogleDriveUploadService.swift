import AppKit
import Foundation
import Observation
import SwiftUI
import WebKit

// MARK: - Estado en Vivo del Envío Automático a Google Drive

public enum GoogleDriveUploadStage: Equatable, Sendable {
    case openingDrive
    case triggeringUpload
    case uploading
    case openingEditor
    case completed
    case failed(String)

    @MainActor
    public func localizedDescription(
        fileName: String,
        folderName: String,
        target: GoogleEditorTarget,
        openedInExternalChrome: Bool = false,
        using loc: LocalizationManager = .shared
    ) -> String {
        switch self {
        case .openingDrive:
            return loc.text(
                es: "Conectando con «\(folderName)» en Google Drive…",
                en: "Connecting to \"\(folderName)\" in Google Drive…"
            )
        case .triggeringUpload:
            return loc.text(
                es: "Iniciando subida automática de «\(fileName)» a «\(folderName)»…",
                en: "Starting automatic upload of \"\(fileName)\" to \"\(folderName)\"…"
            )
        case .uploading:
            return loc.text(
                es: "Subiendo «\(fileName)» a «\(folderName)»…",
                en: "Uploading \"\(fileName)\" to \"\(folderName)\"…"
            )
        case .openingEditor:
            if openedInExternalChrome {
                return loc.text(
                    es: "¡Subido! Abriendo en \(target.localizedName(using: loc)) (Google Chrome)…",
                    en: "Uploaded! Opening in \(target.localizedName(using: loc)) (Google Chrome)…"
                )
            }
            return loc.text(
                es: "¡Subido! Abriendo en \(target.localizedName(using: loc))…",
                en: "Uploaded! Opening in \(target.localizedName(using: loc))…"
            )
        case .completed:
            if openedInExternalChrome {
                return loc.text(
                    es: "«\(fileName)» abierto en \(target.localizedName(using: loc)) (Google Chrome)",
                    en: "\"\(fileName)\" opened in \(target.localizedName(using: loc)) (Google Chrome)"
                )
            }
            return loc.text(
                es: "«\(fileName)» abierto en \(target.localizedName(using: loc))",
                en: "\"\(fileName)\" opened in \(target.localizedName(using: loc))"
            )
        case .failed(let msg):
            return msg
        }
    }

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed: return true
        default: return false
        }
    }
}

public struct GoogleDriveActiveUpload: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let fileURL: URL
    public let accountID: UUID
    /// ID de pestaña visible de Drive dentro de MacFileExplorer (`nil` cuando se sube en segundo plano para abrir en Chrome externo).
    public let tabID: UUID?
    public let folderName: String
    public let editorTarget: GoogleEditorTarget
    public let openInExternalChrome: Bool
    public var stage: GoogleDriveUploadStage

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        accountID: UUID,
        tabID: UUID?,
        folderName: String,
        editorTarget: GoogleEditorTarget,
        openInExternalChrome: Bool,
        stage: GoogleDriveUploadStage
    ) {
        self.id = id
        self.fileURL = fileURL
        self.accountID = accountID
        self.tabID = tabID
        self.folderName = folderName
        self.editorTarget = editorTarget
        self.openInExternalChrome = openInExternalChrome
        self.stage = stage
    }
}

// MARK: - Host Invisible en Segundo Plano para Subida sin Abrir Pestaña de Drive (Modo Chrome Externo)

@MainActor
private final class BackgroundDriveUploadHost: NSObject, WKUIDelegate, WKScriptMessageHandler {
    let hostKey: String
    let accountID: UUID
    let panel: NSPanel
    let webView: WKWebView

    init(accountID: UUID) {
        self.accountID = accountID
        self.hostKey = GoogleDriveUploadService.backgroundHostKey(for: accountID)

        // Panel invisible no activador posicionado en pantalla detrás de las ventanas (`alphaValue = 0.005`,
        // `ignoresMouseEvents = true`, `orderBack`) para que macOS no lo marque como ocluido ni throttle `setInterval`
        // en WebKit, sin robar foco ni abrir una pestaña de Drive dentro de MacFileExplorer.
        let origin = NSScreen.main?.visibleFrame.origin ?? NSPoint(x: 0, y: 0)
        let panel = NSPanel(
            contentRect: NSRect(x: origin.x, y: origin.y, width: 1280, height: 800),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.alphaValue = 0.005
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.isExcludedFromWindowsMenu = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.level = .normal
        self.panel = panel

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: accountID)
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let controller = WKUserContentController()
        controller.addUserScript(
            WKUserScript(
                source: GoogleDriveUploadService.networkUploadObserverUserScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        config.userContentController = controller

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800), configuration: config)
        wv.customUserAgent = GoogleAccountsManager.chromeMacUserAgent
        wv.autoresizingMask = [.width, .height]
        self.webView = wv

        super.init()
        controller.add(self, name: GoogleDriveUploadService.networkProbeHandlerName)
        wv.uiDelegate = self
        panel.contentView = wv
        panel.orderBack(nil)
    }

    func navigateToFolder(_ url: URL) {
        let currentURLString = webView.url?.absoluteString ?? ""
        let targetFolderID = GoogleDriveUploadPreferences.extractFolderID(from: url.absoluteString)
        let currentFolderID = GoogleDriveUploadPreferences.extractFolderID(from: currentURLString)
        let alreadyInTarget: Bool = {
            if let targetFolderID {
                return currentFolderID == targetFolderID
            }
            return currentFolderID == nil && currentURLString.lowercased().contains("/my-drive")
        }()
        if !alreadyInTarget || webView.url == nil {
            webView.load(URLRequest(url: url))
        }
    }

    func teardown() {
        webView.stopLoading()
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: GoogleDriveUploadService.networkProbeHandlerName)
        panel.orderOut(nil)
        panel.close()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == GoogleDriveUploadService.networkProbeHandlerName,
              let dict = message.body as? [String: Any] else { return }
        GoogleDriveUploadService.shared.handleNetworkProbeMessage(forKey: hostKey, payload: dict)
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor ([URL]?) -> Void
    ) {
        if let automatedURL = GoogleDriveUploadService.shared.consumeAutomatedUploadURL(forKey: hostKey) {
            completionHandler([automatedURL])
            return
        }
        // Jamás abrir NSOpenPanel (Finder) desde el host en segundo plano
        completionHandler(nil)
    }
}

// MARK: - Servicio de "Send to Drive" Automático (Sesión Aislada de Gmail -> Drive -> Sheets/Docs/Slides)

@MainActor
@Observable
public final class GoogleDriveUploadService {
    public static let shared = GoogleDriveUploadService()

    public static let networkProbeHandlerName = "driveUploadProbe"

    /// Estado en vivo mostrado como banner en la pestaña de Drive (modo integrado) o en `MainExplorerView` (modo Chrome externo).
    public var activeUpload: GoogleDriveActiveUpload? = nil

    /// Cola de entrega automática para `WKUIDelegate.runOpenPanelWith` indexada por clave (`tab-<UUID>` o `bg-drive-<UUID>`).
    private var pendingAutomatedUploadURLByKey: [String: URL] = [:]
    /// Claves con una automatización actualmente en curso: mientras una clave está aquí, `runOpenPanelWith` NUNCA abre `NSOpenPanel` (Finder).
    private var activeAutomatedUploadKeys: Set<String> = []
    private var consumedUploadKeys: Set<String> = []
    /// Eventos de red recibidos vía `WKScriptMessageHandler` desde cualquier frame o iframe de Drive.
    private var networkUploadStartedByKey: [String: Bool] = [:]
    private var networkDetectedFileByKey: [String: (fileID: String, mimeType: String)] = [:]
    private var expectedFolderIDByKey: [String: String] = [:]

    /// Hosts invisibles en segundo plano reutilizables por cuenta de Google (solo para modo Google Chrome externo).
    private var backgroundHostsByAccountID: [UUID: BackgroundDriveUploadHost] = [:]
    private var isRegisteredOwnedWindowsProvider = false
    private var uploadTask: Task<Void, Never>? = nil

    private init() {}

    public static func tabKey(for tabID: UUID) -> String {
        "tab-\(tabID.uuidString)"
    }

    public static func backgroundHostKey(for accountID: UUID) -> String {
        "bg-drive-\(accountID.uuidString)"
    }

    private func registerOwnedWindowsProviderIfNeeded() {
        guard !isRegisteredOwnedWindowsProvider else { return }
        isRegisteredOwnedWindowsProvider = true
        TaskbarWindowTracker.shared.registerOwnedWindowNumbersProvider(key: "drive-upload-host") { [weak self] in
            guard let self else { return [] }
            return Set(self.backgroundHostsByAccountID.values.map { $0.panel.windowNumber })
        }
    }

    /// Llamado desde `WebTabCoordinator.webView(_:runOpenPanelWith:...)` y `BackgroundDriveUploadHost`.
    public func consumeAutomatedUploadURL(forTabID tabID: UUID) -> URL? {
        consumeAutomatedUploadURL(forKey: Self.tabKey(for: tabID))
    }

    public func consumeAutomatedUploadURL(forKey key: String) -> URL? {
        guard let url = pendingAutomatedUploadURLByKey.removeValue(forKey: key) else {
            return nil
        }
        consumedUploadKeys.insert(key)
        return url
    }

    /// Indica si hay una subida automática activa en la pestaña/host indicado (bloquea `NSOpenPanel` de Finder).
    public func isAutomatedUploadActive(forTabID tabID: UUID) -> Bool {
        activeAutomatedUploadKeys.contains(Self.tabKey(for: tabID))
    }

    public func isAutomatedUploadActive(forKey key: String) -> Bool {
        activeAutomatedUploadKeys.contains(key)
    }

    /// Recibe mensajes de red desde `networkUploadObserverUserScript` (tanto en el frame principal como en iframes).
    public func handleNetworkProbeMessage(forTabID tabID: UUID, payload: [String: Any]) {
        handleNetworkProbeMessage(forKey: Self.tabKey(for: tabID), payload: payload)
    }

    public func handleNetworkProbeMessage(forKey key: String, payload: [String: Any]) {
        guard activeAutomatedUploadKeys.contains(key) else { return }
        let event = (payload["event"] as? String) ?? ""
        if event == "started" {
            networkUploadStartedByKey[key] = true
        } else if event == "uploaded" {
            let fileID = (payload["fileID"] as? String) ?? ""
            let mimeType = (payload["mimeType"] as? String) ?? ""
            let expectedFolder = expectedFolderIDByKey[key] ?? ""
            if Self.isValidUploadedFileID(fileID, excludingFolderID: expectedFolder) {
                networkUploadStartedByKey[key] = true
                networkDetectedFileByKey[key] = (fileID, mimeType)
            }
        }
    }

    public static func isValidUploadedFileID(_ candidate: String, excludingFolderID: String?) -> Bool {
        guard candidate.count >= 12, candidate.count <= 120 else { return false }
        if let folder = excludingFolderID, !folder.isEmpty, candidate == folder {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return candidate.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Agrega `?authuser=<email>` para que Google Chrome externo abra el documento directamente con la misma cuenta.
    public static func urlWithAuthUser(_ url: URL, email: String?) -> URL {
        guard let rawEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawEmail.isEmpty,
              rawEmail.contains("@"),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var items = components.queryItems ?? []
        if !items.contains(where: { $0.name.lowercased() == "authuser" }) {
            items.append(URLQueryItem(name: "authuser", value: rawEmail))
            components.queryItems = items
        }
        return components.url ?? url
    }

    public func cancelActiveUpload() {
        uploadTask?.cancel()
        uploadTask = nil
        if let current = activeUpload {
            let key: String
            let wv: WKWebView?
            if let tabID = current.tabID {
                key = Self.tabKey(for: tabID)
                wv = GoogleAccountsManager.shared.tab(for: tabID).map { GoogleAccountsManager.shared.webView(for: $0) }
            } else {
                key = Self.backgroundHostKey(for: current.accountID)
                wv = backgroundHostsByAccountID[current.accountID]?.webView
            }
            cleanupAutomatedUploadState(forKey: key, webView: wv)
        }
        activeUpload = nil
    }

    private func cleanupAutomatedUploadState(forKey key: String, webView: WKWebView?) {
        activeAutomatedUploadKeys.remove(key)
        pendingAutomatedUploadURLByKey.removeValue(forKey: key)
        consumedUploadKeys.remove(key)
        networkUploadStartedByKey.removeValue(forKey: key)
        networkDetectedFileByKey.removeValue(forKey: key)
        expectedFolderIDByKey.removeValue(forKey: key)
        webView?.evaluateJavaScript(Self.cleanupInputHookJS, completionHandler: nil)
    }

    /// Resuelve qué cuenta de Google usar cuando el usuario pulsa "Send to Drive" sin elegir una cuenta específica.
    public func resolvePreferredAccount() -> GoogleAccount? {
        let accounts = GoogleAccountsManager.shared.accounts
        if let defaultID = GoogleDriveUploadPreferences.shared.defaultAccountID,
           let preferred = accounts.first(where: { $0.id == defaultID }) {
            return preferred
        }
        return accounts.first(where: \.isAuthenticated) ?? accounts.first
    }

    private func backgroundHost(for accountID: UUID) -> BackgroundDriveUploadHost {
        registerOwnedWindowsProviderIfNeeded()
        if let existing = backgroundHostsByAccountID[accountID] {
            return existing
        }
        let created = BackgroundDriveUploadHost(accountID: accountID)
        backgroundHostsByAccountID[accountID] = created
        return created
    }

    /// Ejecuta el flujo completo: sube el archivo automáticamente a la carpeta de Drive configurada usando
    /// la cuenta de Google logueada (en pestaña integrada o en segundo plano si está elegido Google Chrome externo)
    /// y al terminar abre el documento directamente en Google Sheets / Docs / Slides.
    public func sendFileToDriveAndOpen(_ fileURL: URL, account: GoogleAccount? = nil) {
        let loc = LocalizationManager.shared
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return }

        guard let targetAccount = account ?? resolvePreferredAccount() else {
            let alert = NSAlert()
            alert.messageText = loc.text(
                es: "Conectá tu cuenta de Google primero",
                en: "Connect Your Google Account First"
            )
            alert.informativeText = loc.text(
                es: "Para usar «Enviar a Drive», iniciá sesión con tu cuenta de Gmail en la sección «Cuentas de Google» de MacFileExplorer. ¿Querés iniciar sesión ahora?",
                en: "To use \"Send to Drive\", sign in with your Gmail account under \"Google Accounts\" in MacFileExplorer. Would you like to sign in now?"
            )
            alert.addButton(withTitle: loc.text(es: "Iniciar sesión en Google", en: "Sign in to Google"))
            alert.addButton(withTitle: loc.text(es: "Cancelar", en: "Cancel"))
            if alert.runModal() == .alertFirstButtonReturn {
                GoogleAccountsManager.shared.startAddGoogleAccount()
            }
            return
        }

        cancelActiveUpload()

        let prefs = GoogleDriveUploadPreferences.shared
        let destination = prefs.destination(for: targetAccount.id)
        let folderName = prefs.displayFolderName(for: targetAccount.id, using: loc)
        let editorTarget = OfficePreviewSupport.googleEditorTarget(for: fileURL)
        let useExternalChrome = prefs.openInExternalChrome

        let webView: WKWebView
        let automationKey: String
        let visibleTabID: UUID?

        if useExternalChrome {
            // Modo Google Chrome externo: NO abrimos ni cambiamos a una pestaña de Drive dentro de MacFileExplorer.
            // Subimos usando el contenedor aislado de la cuenta en segundo plano y mostramos progreso inline en el Explorador.
            let host = backgroundHost(for: targetAccount.id)
            host.navigateToFolder(destination.targetURL)
            webView = host.webView
            automationKey = host.hostKey
            visibleTabID = nil
        } else {
            // Modo integrado: abrimos/enfocamos la pestaña de Drive dentro de MacFileExplorer directamente en la carpeta configurada.
            let tab = GoogleAccountsManager.shared.openOrFocusDriveFolderTab(
                url: destination.targetURL,
                for: targetAccount.id
            )
            webView = GoogleAccountsManager.shared.webView(for: tab)
            automationKey = Self.tabKey(for: tab.id)
            visibleTabID = tab.id
        }

        let uploadID = UUID()
        activeUpload = GoogleDriveActiveUpload(
            id: uploadID,
            fileURL: fileURL,
            accountID: targetAccount.id,
            tabID: visibleTabID,
            folderName: folderName,
            editorTarget: editorTarget,
            openInExternalChrome: useExternalChrome,
            stage: .openingDrive
        )

        uploadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runAutomatedUploadPipeline(
                uploadID: uploadID,
                fileURL: fileURL,
                account: targetAccount,
                automationKey: automationKey,
                webView: webView,
                destination: destination,
                editorTarget: editorTarget,
                openInExternalChrome: useExternalChrome
            )
        }
    }

    // MARK: - Pipeline Asíncrono de Navegación + Subida + Detección XHR Multi-Frame + Apertura Automática

    private func runAutomatedUploadPipeline(
        uploadID: UUID,
        fileURL: URL,
        account: GoogleAccount,
        automationKey: String,
        webView: WKWebView,
        destination: GoogleDriveFolderDestination,
        editorTarget: GoogleEditorTarget,
        openInExternalChrome: Bool
    ) async {
        let loc = LocalizationManager.shared
        let fileName = fileURL.lastPathComponent
        let fileStem = fileURL.deletingPathExtension().lastPathComponent
        let expectedFolderID = destination.folderID ?? ""

        // Mantener el guardia anti-NSOpenPanel (anti-Finder) activo durante TODO el ciclo de subida.
        activeAutomatedUploadKeys.insert(automationKey)
        expectedFolderIDByKey[automationKey] = expectedFolderID
        networkUploadStartedByKey[automationKey] = false
        networkDetectedFileByKey.removeValue(forKey: automationKey)
        consumedUploadKeys.remove(automationKey)

        defer {
            cleanupAutomatedUploadState(forKey: automationKey, webView: webView)
        }

        // Pequeña espera inicial para que `webView.load(...)` comience la transición hacia la carpeta destino
        try? await Task.sleep(for: .milliseconds(350))
        if Task.isCancelled { return }

        // Paso A: Esperar a que Drive cargue EXACTAMENTE en la carpeta destino (verificando `expectedFolderID` en `location.href`)
        let readyJS = Self.buildDriveReadyCheckJS(expectedFolderID: destination.folderID)
        var driveReady = false
        var retriedFolderNav = false

        for attempt in 0..<55 {
            if Task.isCancelled { return }
            if let currentHost = webView.url?.host?.lowercased(), currentHost.contains("accounts.google.com") {
                // Si la sesión expiró en modo segundo plano, abrir pestaña visible de Drive para que el usuario inicie sesión
                if openInExternalChrome {
                    _ = GoogleAccountsManager.shared.openOrFocusDriveFolderTab(
                        url: destination.targetURL,
                        for: account.id
                    )
                }
                markFailed(uploadID, message: loc.text(
                    es: "Tu sesión de Google expiró. Iniciá sesión en la pestaña de Drive y volvé a pulsar «Enviar a Drive».",
                    en: "Your Google session expired. Sign in on the Drive tab and click \"Send to Drive\" again."
                ))
                return
            }

            if !webView.isLoading, let ready = await evalBool(webView, js: readyJS), ready {
                driveReady = true
                break
            }

            // Si tras ~3.5 s la SPA quedó en otra carpeta, forzar navegación directa a la URL destino
            if attempt == 9 && !retriedFolderNav && !webView.isLoading {
                retriedFolderNav = true
                let currentURL = webView.url?.absoluteString ?? ""
                if let expectedID = destination.folderID, !currentURL.contains(expectedID) {
                    webView.load(URLRequest(url: destination.targetURL))
                }
            }

            try? await Task.sleep(for: .milliseconds(400))
        }

        guard driveReady, !Task.isCancelled else {
            markFailed(uploadID, message: loc.text(
                es: "Google Drive tardó demasiado en abrir la carpeta destino. Verificá tu conexión o los permisos de esa carpeta.",
                en: "Google Drive took too long to open the target folder. Check your connection or folder permissions."
            ))
            return
        }

        try? await Task.sleep(for: .milliseconds(450))
        if Task.isCancelled { return }

        // Paso B: Cerrar cualquier toast antiguo de una subida previa ("1 upload complete") y reiniciar observadores de red
        _ = await evalString(webView, js: Self.dismissExistingUploadToastJS)
        try? await Task.sleep(for: .milliseconds(200))
        if Task.isCancelled { return }

        _ = await evalString(webView, js: Self.networkUploadObserverUserScript)
        _ = await evalString(webView, js: Self.buildResetUploadStateJS(expectedFolderID: expectedFolderID))
        networkUploadStartedByKey[automationKey] = false
        networkDetectedFileByKey.removeValue(forKey: automationKey)
        let preUploadIDs = Set(await evalStringArray(webView, js: Self.snapshotVisibleDriveIDsJS))

        // Paso C: Preparar archivo y disparar subida real (Capa 1: hook `<input type="file">` + `runOpenPanelWith` nativo; nunca Finder)
        updateStage(uploadID, .triggeringUpload)
        pendingAutomatedUploadURLByKey[automationKey] = fileURL
        consumedUploadKeys.remove(automationKey)

        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let mime = Self.mimeType(for: fileURL)
        let canUseJSFileInjection = (fileSize >= 0 && fileSize <= 35_000_000)
        var base64Payload: String? = nil

        if canUseJSFileInjection, let data = try? Data(contentsOf: fileURL) {
            base64Payload = data.base64EncodedString()
            let installInputHookJS = Self.buildInstallInputClickHookJS(
                fileName: fileName,
                mimeType: mime,
                base64: base64Payload!
            )
            _ = await evalString(webView, js: installInputHookJS)
        }

        // Abrir menú "+ New" / "+ Nuevo" y pulsar "File upload" / "Subir archivo" con eventos Pointer+Mouse
        _ = await evalString(webView, js: Self.triggerDriveNewMenuFileUploadJS)

        // Esperar hasta 5.5 s verificando señales REALES de que ESTA subida arrancó (NUNCA contando toasts viejos "upload complete")
        var uploadConfirmedStarted = false
        for _ in 0..<22 {
            if Task.isCancelled { return }
            let probe = await readUploadProbe(webView)
            let nativeStarted = (networkUploadStartedByKey[automationKey] == true)
                || (networkDetectedFileByKey[automationKey] != nil)
                || consumedUploadKeys.contains(automationKey)

            if nativeStarted || probe.started || !probe.fileID.isEmpty || probe.domUploadingNow {
                uploadConfirmedStarted = true
                break
            }
            if probe.inputInjected {
                // El input recibió el archivo: dar margen para que Drive dispare la XHR o muestre modal de duplicado
                try? await Task.sleep(for: .milliseconds(450))
                _ = await evalString(webView, js: Self.autoResolveDuplicateUploadDialogJS)
                let after = await readUploadProbe(webView)
                let nativeAfter = (networkUploadStartedByKey[automationKey] == true)
                    || (networkDetectedFileByKey[automationKey] != nil)
                if nativeAfter || after.started || !after.fileID.isEmpty || after.domUploadingNow {
                    uploadConfirmedStarted = true
                    break
                }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }

        // Capa 2 (Fallback): Drag & Drop asíncrono multi-frame con `DataTransfer` si "+ New" no disparó la subida
        if !uploadConfirmedStarted, let base64Payload {
            // Cancelar el timer del menú "+ New" antes de lanzar el fallback Drag & Drop
            _ = await evalString(webView, js: Self.cancelMenuTimerJS)
            let dropJS = Self.buildAsyncDataTransferDropJS(fileName: fileName, mimeType: mime, base64: base64Payload)
            _ = await evalString(webView, js: dropJS)

            for _ in 0..<18 {
                if Task.isCancelled { return }
                _ = await evalString(webView, js: Self.autoResolveDuplicateUploadDialogJS)
                let probe = await readUploadProbe(webView)
                let nativeStarted = (networkUploadStartedByKey[automationKey] == true)
                    || (networkDetectedFileByKey[automationKey] != nil)
                    || consumedUploadKeys.contains(automationKey)
                if nativeStarted || probe.started || !probe.fileID.isEmpty || probe.domUploadingNow {
                    uploadConfirmedStarted = true
                    break
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }

        // Limpiar el hook de `<input>` y timer del menú ahora que la subida ya arrancó (o falló),
        // manteniendo `activeAutomatedUploadKeys` hasta el `defer` para que jamás salte Finder.
        _ = await evalString(webView, js: Self.cleanupInputHookJS)

        guard uploadConfirmedStarted else {
            markFailed(uploadID, message: loc.text(
                es: "Google Drive no inició la subida automática en esta carpeta. Verificá tu sesión y permisos de edición en Drive.",
                en: "Google Drive did not start the automatic upload in this folder. Verify your session and edit permission in Drive."
            ))
            return
        }

        updateStage(uploadID, .uploading)

        // Paso D: Esperar finalización y capturar `fileID` + `mimeType` desde XHR/fetch (main frame + iframes) o respaldo DOM
        var detectedFileID: String? = nil
        var detectedMimeType: String = ""
        let domDetectStrictJS = Self.buildDetectUploadedFileIDJS(
            fileName: fileName,
            fileStem: fileStem,
            excludedIDs: Array(preUploadIDs),
            folderID: expectedFolderID,
            allowExistingMatchOnDone: false
        )
        let domDetectExistingJS = Self.buildDetectUploadedFileIDJS(
            fileName: fileName,
            fileStem: fileStem,
            excludedIDs: [],
            folderID: expectedFolderID,
            allowExistingMatchOnDone: true
        )

        for attempt in 0..<180 {
            if Task.isCancelled { return }

            // Resolver automáticamente diálogo de archivo duplicado si Drive pregunta "Reemplazar / Mantener como archivo separado"
            if attempt % 2 == 0 {
                _ = await evalString(webView, js: Self.autoResolveDuplicateUploadDialogJS)
            }

            // 1. Fuente primaria multi-frame (0 ms): mensaje nativo `WKScriptMessageHandler` desde `/upload/drive`
            // Acepta incluso el mismo `fileID` si Drive actualizó una versión de un archivo existente con igual nombre.
            if let netHit = networkDetectedFileByKey[automationKey],
               Self.isValidUploadedFileID(netHit.fileID, excludingFolderID: expectedFolderID) {
                detectedFileID = netHit.fileID
                detectedMimeType = netHit.mimeType
                break
            }

            // 2. Fuente secundaria (0 ms): estado JS del frame principal
            let probe = await readUploadProbe(webView)
            if Self.isValidUploadedFileID(probe.fileID, excludingFolderID: expectedFolderID) {
                detectedFileID = probe.fileID
                detectedMimeType = probe.mimeType
                break
            }

            // 3. Respaldo DOM (nuevo `data-id` que apareció en la carpeta destino)
            if let domID = await evalString(webView, js: domDetectStrictJS),
               Self.isValidUploadedFileID(domID, excludingFolderID: expectedFolderID) {
                detectedFileID = domID
                break
            }

            // 4. Respaldo DOM para actualización en el sitio (mismo nombre y mismo ID) solo tras confirmar toast de subida completada
            if attempt >= 8 && probe.domUploadCompleted {
                if let existingID = await evalString(webView, js: domDetectExistingJS),
                   Self.isValidUploadedFileID(existingID, excludingFolderID: expectedFolderID) {
                    detectedFileID = existingID
                    break
                }
            }

            if attempt == 25 {
                _ = await evalString(webView, js: "window.dispatchEvent(new Event('focus')); 'ok';")
            }

            try? await Task.sleep(for: .milliseconds(500))
        }

        guard let fileID = detectedFileID else {
            markFailed(uploadID, message: loc.text(
                es: "El archivo se subió a Google Drive, pero no se pudo obtener su enlace automáticamente. Abrilo desde la lista de Drive.",
                en: "The file uploaded to Google Drive, but its link couldn't be detected automatically. Open it directly from the Drive list."
            ))
            return
        }

        // Paso E: Abrir automáticamente en Google Sheets / Docs / Slides
        updateStage(uploadID, .openingEditor)
        try? await Task.sleep(for: .milliseconds(200))
        if Task.isCancelled { return }

        let lowerMime = detectedMimeType.lowercased()
        let isGoogleNativeSheet = lowerMime == "application/vnd.google-apps.spreadsheet"
        let isUnconvertedCSV = !isGoogleNativeSheet && (
            (lowerMime == "text/csv" || lowerMime == "text/tab-separated-values")
            || (lowerMime.isEmpty && ["csv", "tsv"].contains(fileURL.pathExtension.lowercased()))
        )

        let rawTargetURL: URL?
        if isUnconvertedCSV {
            rawTargetURL = URL(string: "https://drive.google.com/file/d/\(fileID)/view")
        } else {
            rawTargetURL = editorTarget.editorURL(forFileID: fileID)
        }

        guard let baseOpenURL = rawTargetURL else {
            markFailed(uploadID, message: loc.text(es: "No se pudo construir la URL del editor.", en: "Could not build the editor URL."))
            return
        }

        if openInExternalChrome {
            let chromeURL = Self.urlWithAuthUser(baseOpenURL, email: account.email)
            BookmarksManager.shared.openURLInGoogleChrome(chromeURL, newWindow: false)
        } else {
            let openedTab = GoogleAccountsManager.shared.openURLInAccountTab(baseOpenURL, for: account.id, service: .drive)
            if isUnconvertedCSV && editorTarget == .sheets {
                Task { @MainActor in
                    await self.autoClickOpenWithGoogleSheetsIfNeeded(in: openedTab.id)
                }
            }
        }

        updateStage(uploadID, .completed)

        try? await Task.sleep(for: .seconds(4))
        if activeUpload?.id == uploadID {
            activeUpload = nil
        }
    }

    private func autoClickOpenWithGoogleSheetsIfNeeded(in tabID: UUID) async {
        for _ in 0..<24 {
            try? await Task.sleep(for: .milliseconds(500))
            guard let tab = GoogleAccountsManager.shared.tab(for: tabID) else { return }
            let wv = GoogleAccountsManager.shared.webView(for: tab)
            if let host = wv.url?.host?.lowercased(), host == "docs.google.com" {
                return
            }
            if !wv.isLoading {
                let clicked = await evalBool(wv, js: Self.clickOpenWithGoogleSheetsJS) ?? false
                if clicked {
                    return
                }
            }
        }
    }

    private struct UploadProbeResult {
        let started: Bool
        let inputInjected: Bool
        let domUploadingNow: Bool
        let domUploadCompleted: Bool
        let fileID: String
        let mimeType: String
    }

    private func readUploadProbe(_ webView: WKWebView) async -> UploadProbeResult {
        guard let jsonStr = await evalString(webView, js: Self.readUploadProbeJS),
              let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return UploadProbeResult(
                started: false,
                inputInjected: false,
                domUploadingNow: false,
                domUploadCompleted: false,
                fileID: "",
                mimeType: ""
            )
        }
        return UploadProbeResult(
            started: (obj["started"] as? Bool) ?? false,
            inputInjected: (obj["inputInjected"] as? Bool) ?? false,
            domUploadingNow: (obj["domUploadingNow"] as? Bool) ?? false,
            domUploadCompleted: (obj["domUploadCompleted"] as? Bool) ?? false,
            fileID: (obj["fileID"] as? String) ?? "",
            mimeType: (obj["mimeType"] as? String) ?? ""
        )
    }

    private func updateStage(_ uploadID: UUID, _ stage: GoogleDriveUploadStage) {
        guard activeUpload?.id == uploadID else { return }
        activeUpload?.stage = stage
    }

    private func markFailed(_ uploadID: UUID, message: String) {
        guard activeUpload?.id == uploadID else { return }
        activeUpload?.stage = .failed(message)
    }

    // MARK: - Helpers JS para `WKWebView`

    private func evalBool(_ webView: WKWebView, js: String) async -> Bool? {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(js) { result, _ in
                if let b = result as? Bool {
                    continuation.resume(returning: b)
                } else if let n = result as? NSNumber {
                    continuation.resume(returning: n.boolValue)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func evalString(_ webView: WKWebView, js: String) async -> String? {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(js) { result, _ in
                continuation.resume(returning: result as? String)
            }
        }
    }

    private func evalStringArray(_ webView: WKWebView, js: String) async -> [String] {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(js) { result, _ in
                continuation.resume(returning: result as? [String] ?? [])
            }
        }
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "csv": return "text/csv"
        case "tsv": return "text/tab-separated-values"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "xls": return "application/vnd.ms-excel"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "doc": return "application/msword"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "ppt": return "application/vnd.ms-powerpoint"
        case "rtf": return "application/rtf"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }

    // MARK: - Scripts JS Verificados en JavaScriptCore (Drive 2025/2026 + Multi-Frame)

    public static func buildDriveReadyCheckJS(expectedFolderID: String?) -> String {
        let folderJSON = (try? String(data: JSONEncoder().encode(expectedFolderID ?? ""), encoding: .utf8)) ?? "\"\""
        return """
        (() => {
          if (!location.hostname.includes('drive.google.com')) return false;
          const expectedID = \(folderJSON);
          if (expectedID) {
            if (!location.href.includes(expectedID)) return false;
          } else {
            const p = location.pathname.toLowerCase();
            if (!p.includes('/my-drive') && p !== '/drive/' && !/^\\/drive\\/u\\/\\d+\\/?$/.test(p)) return false;
          }
          const byAttr = document.querySelector('button[guidedhelpid="new_menu_button"], button[aria-label="New"], button[aria-label="Nuevo"]');
          if (byAttr && byAttr.offsetParent !== null) return true;
          const btns = Array.from(document.querySelectorAll('button, [role="button"]'));
          return btns.some((b) => {
            if (!b.offsetParent) return false;
            const r = b.getBoundingClientRect();
            if (r.left > 280 || r.width < 40) return false;
            const t = ((b.innerText || '') + ' ' + (b.getAttribute('aria-label') || '')).trim().toLowerCase();
            return t === 'new' || t === 'nuevo' || t === '+ new' || t === '+ nuevo' || t.startsWith('new ') || t.startsWith('nuevo ');
          });
        })();
        """
    }

    /// Script inyectado en `.atDocumentStart` y `forMainFrameOnly: false` para interceptar XHR y fetch en el frame principal y cualquier iframe de Drive.
    public static let networkUploadObserverUserScript = #"""
    (() => {
      try {
        const host = (location && location.hostname ? location.hostname : '').toLowerCase();
        if (host && !host.includes('google.com') && !host.includes('googleapis.com')) return 'skip';
      } catch (_) {}

      if (window.__mfeDriveUploadNetHooked) return 'already';
      window.__mfeDriveUploadNetHooked = true;
      window.__mfeUploadState = { started: false, inputInjected: false, fileID: '', mimeType: '', expectedFolderID: '' };

      const postNative = (payload) => {
        try {
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.driveUploadProbe) {
            window.webkit.messageHandlers.driveUploadProbe.postMessage(payload);
          }
        } catch (_) {}
      };

      const isDriveUploadURL = (rawUrl) => {
        if (!rawUrl) return false;
        const u = String(rawUrl).toLowerCase();
        return u.includes('/upload/drive') ||
               u.includes('upload/resumable') ||
               u.includes('uploadtype=resumable') ||
               u.includes('uploadtype=multipart') ||
               u.includes('upload_id=') ||
               (u.includes('upload') && (u.includes('clients6.google.com') || u.includes('googleapis.com') || u.includes('drive.google.com') || u.includes('docs.google.com')));
      };

      const isPlausibleFileID = (id) => {
        if (typeof id !== 'string') return false;
        if (!/^[a-zA-Z0-9_-]{12,120}$/.test(id)) return false;
        const folder = (window.__mfeUploadState && window.__mfeUploadState.expectedFolderID) || '';
        if (folder && id === folder) return false;
        return true;
      };

      const recordFoundFile = (id, mime) => {
        if (!isPlausibleFileID(id)) return false;
        if (window.__mfeUploadState) {
          window.__mfeUploadState.started = true;
          window.__mfeUploadState.fileID = id;
          if (typeof mime === 'string' && mime) window.__mfeUploadState.mimeType = mime;
        }
        postNative({ event: 'uploaded', fileID: id, mimeType: typeof mime === 'string' ? mime : '' });
        return true;
      };

      const extractFromObject = (obj, depth) => {
        if (!obj || typeof obj !== 'object' || depth > 4) return false;
        const directId = obj.id || obj.fileId || obj.resourceId || obj.docid || '';
        const directMime = obj.mimeType || obj.contentType || '';
        if (directId && isPlausibleFileID(directId)) {
          // Evitar confundir el objeto de carpeta padre `{ kind: "drive#parentReference", id: "<folder>" }`
          const kind = typeof obj.kind === 'string' ? obj.kind.toLowerCase() : '';
          if (!kind.includes('parent')) {
            return recordFoundFile(directId, directMime);
          }
        }
        for (const key of ['metadata', 'item', 'resource', 'file', 'response']) {
          if (obj[key] && typeof obj[key] === 'object') {
            if (extractFromObject(obj[key], depth + 1)) return true;
          }
        }
        return false;
      };

      const inspectUploadResponseText = (rawText) => {
        if (!rawText || typeof rawText !== 'string') return;
        const cleaned = rawText.replace(/^\)\]\}'\s*/, '').trim();
        if (!cleaned) return;
        try {
          const obj = JSON.parse(cleaned);
          if (extractFromObject(obj, 0)) return;
        } catch (_) {}
        const re = /"(?:id|fileId|resourceId|docid)"\s*:\s*"([a-zA-Z0-9_-]{15,120})"/g;
        let m;
        while ((m = re.exec(cleaned)) !== null) {
          if (isPlausibleFileID(m[1])) {
            const mimeMatch = cleaned.match(/"mimeType"\s*:\s*"([^"]+)"/);
            recordFoundFile(m[1], mimeMatch ? mimeMatch[1] : '');
            return;
          }
        }
      };

      const extractXHRText = (xhr) => {
        try {
          const rt = xhr.responseType || '';
          if (rt === '' || rt === 'text') return xhr.responseText || '';
          if (rt === 'json' && xhr.response) return JSON.stringify(xhr.response);
          if (rt === 'arraybuffer' && xhr.response && typeof TextDecoder === 'function') {
            return new TextDecoder('utf-8').decode(new Uint8Array(xhr.response));
          }
        } catch (_) {}
        return '';
      };

      const origOpen = XMLHttpRequest.prototype.open;
      const origSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(method, url) {
        this.__mfeURL = url ? String(url) : '';
        return origOpen.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function() {
        if (isDriveUploadURL(this.__mfeURL)) {
          if (window.__mfeUploadState) window.__mfeUploadState.started = true;
          postNative({ event: 'started' });
          this.addEventListener('load', function() {
            try {
              if (this.status >= 200 && this.status < 300) {
                inspectUploadResponseText(extractXHRText(this));
              }
            } catch (_) {}
          });
        }
        return origSend.apply(this, arguments);
      };

      if (typeof window.fetch === 'function') {
        const origFetch = window.fetch;
        window.fetch = function(input) {
          const url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
          const isUpload = isDriveUploadURL(url);
          if (isUpload) {
            if (window.__mfeUploadState) window.__mfeUploadState.started = true;
            postNative({ event: 'started' });
          }
          const p = origFetch.apply(this, arguments);
          if (isUpload) {
            p.then((res) => {
              try {
                if (res && res.ok) {
                  res.clone().text().then(inspectUploadResponseText).catch(() => {});
                }
              } catch (_) {}
            }).catch(() => {});
          }
          return p;
        };
      }
      return 'installed';
    })();
    """#

    public static func buildResetUploadStateJS(expectedFolderID: String) -> String {
        let folderJSON = (try? String(data: JSONEncoder().encode(expectedFolderID), encoding: .utf8)) ?? "\"\""
        return """
        (() => {
          if (window.__mfeUploadMenuTimer) {
            clearInterval(window.__mfeUploadMenuTimer);
            window.__mfeUploadMenuTimer = null;
          }
          window.__mfeUploadState = {
            started: false,
            inputInjected: false,
            fileID: '',
            mimeType: '',
            expectedFolderID: \(folderJSON)
          };
          return 'reset';
        })();
        """
    }

    /// Cierra cualquier tarjeta inferior derecha de una subida anterior ("1 upload complete" / "1 elemento subido")
    /// para que el texto residual no interfiera con la siguiente subida.
    public static let dismissExistingUploadToastJS = #"""
    (() => {
      const isVisible = (el) => {
        if (!el) return false;
        const r = el.getBoundingClientRect();
        if (r.width <= 0 || r.height <= 0) return false;
        const cs = window.getComputedStyle(el);
        return cs.display !== 'none' && cs.visibility !== 'hidden' && parseFloat(cs.opacity || '1') > 0;
      };
      const trays = Array.from(document.querySelectorAll('[role="dialog"], [role="status"], [aria-live], div'));
      for (const el of trays) {
        if (!isVisible(el)) continue;
        const r = el.getBoundingClientRect();
        if (r.width < 180 || r.width > 560 || r.height < 40 || r.height > 420) continue;
        if (r.right < window.innerWidth * 0.55 || r.bottom < window.innerHeight * 0.55) continue;
        const txt = (el.innerText || '').toLowerCase();
        const isUploadTray =
          txt.includes('upload complete') ||
          txt.includes('uploads complete') ||
          txt.includes('elemento subido') ||
          txt.includes('elementos subidos') ||
          txt.includes('subida completada') ||
          txt.includes('se completó la carga') ||
          txt.includes('carga completada');
        if (!isUploadTray) continue;
        const closeBtn = el.querySelector('button[aria-label*="Close" i], button[aria-label*="Cerrar" i], [role="button"][aria-label*="Close" i], [role="button"][aria-label*="Cerrar" i], [data-tooltip*="Close" i], [data-tooltip*="Cerrar" i]');
        if (isVisible(closeBtn)) {
          closeBtn.click();
          return 'dismissed';
        }
      }
      return 'none';
    })();
    """#

    public static func buildInstallInputClickHookJS(fileName: String, mimeType: String, base64: String) -> String {
        let nameJSON = (try? String(data: JSONEncoder().encode(fileName), encoding: .utf8)) ?? "\"file\""
        let mimeJSON = (try? String(data: JSONEncoder().encode(mimeType), encoding: .utf8)) ?? "\"application/octet-stream\""
        return """
        (() => {
          const name = \(nameJSON);
          const mime = \(mimeJSON);
          const b64 = '\(base64)';
          const makeFile = () => {
            const binary = atob(b64);
            const bytes = new Uint8Array(binary.length);
            for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
            return new File([bytes], name, { type: mime });
          };
          const injectIntoInput = (el) => {
            try {
              const dt = new DataTransfer();
              dt.items.add(makeFile());
              el.files = dt.files;
              el.dispatchEvent(new Event('input', { bubbles: true }));
              el.dispatchEvent(new Event('change', { bubbles: true }));
              if (window.__mfeUploadState) window.__mfeUploadState.inputInjected = true;
              return true;
            } catch (_) {
              return false;
            }
          };

          if (!window.__mfeOrigInputClick) {
            window.__mfeOrigInputClick = HTMLInputElement.prototype.click;
          }
          if (!window.__mfeOrigElClick) {
            window.__mfeOrigElClick = HTMLElement.prototype.click;
          }

          const restore = () => {
            if (window.__mfeOrigInputClick) {
              HTMLInputElement.prototype.click = window.__mfeOrigInputClick;
            }
            if (window.__mfeOrigElClick) {
              HTMLElement.prototype.click = window.__mfeOrigElClick;
            }
          };

          HTMLInputElement.prototype.click = function() {
            if (this.type === 'file' && !this.webkitdirectory && !this.hasAttribute('webkitdirectory')) {
              restore();
              if (injectIntoInput(this)) return;
            }
            return window.__mfeOrigInputClick.apply(this, arguments);
          };

          HTMLElement.prototype.click = function() {
            if (this.tagName === 'INPUT' && this.type === 'file' && !this.webkitdirectory && !this.hasAttribute('webkitdirectory')) {
              restore();
              if (injectIntoInput(this)) return;
            }
            return window.__mfeOrigElClick.apply(this, arguments);
          };

          return 'hooked';
        })();
        """
    }

    public static let cancelMenuTimerJS = """
    (() => {
      if (window.__mfeUploadMenuTimer) {
        clearInterval(window.__mfeUploadMenuTimer);
        window.__mfeUploadMenuTimer = null;
      }
      return 'timer_cancelled';
    })();
    """

    public static let cleanupInputHookJS = """
    (() => {
      if (window.__mfeUploadMenuTimer) {
        clearInterval(window.__mfeUploadMenuTimer);
        window.__mfeUploadMenuTimer = null;
      }
      if (window.__mfeOrigInputClick) {
        HTMLInputElement.prototype.click = window.__mfeOrigInputClick;
      }
      if (window.__mfeOrigElClick) {
        HTMLElement.prototype.click = window.__mfeOrigElClick;
      }
      return 'cleaned';
    })();
    """

    public static let triggerDriveNewMenuFileUploadJS = #"""
    (() => {
      if (window.__mfeUploadMenuTimer) {
        clearInterval(window.__mfeUploadMenuTimer);
        window.__mfeUploadMenuTimer = null;
      }

      const fullClick = (el) => {
        if (!el) return;
        const r = el.getBoundingClientRect();
        const cx = r.left + r.width / 2;
        const cy = r.top + r.height / 2;
        const downOpts = { bubbles: true, cancelable: true, view: window, button: 0, buttons: 1, clientX: cx, clientY: cy };
        const upOpts = { bubbles: true, cancelable: true, view: window, button: 0, buttons: 0, clientX: cx, clientY: cy };
        try { el.dispatchEvent(new PointerEvent('pointerdown', downOpts)); } catch (_) {}
        el.dispatchEvent(new MouseEvent('mousedown', downOpts));
        try { el.dispatchEvent(new PointerEvent('pointerup', upOpts)); } catch (_) {}
        el.dispatchEvent(new MouseEvent('mouseup', upOpts));
        el.dispatchEvent(new MouseEvent('click', upOpts));
      };

      const isVisible = (el) => {
        if (!el) return false;
        const r = el.getBoundingClientRect();
        if (r.width <= 0 || r.height <= 0) return false;
        const cs = window.getComputedStyle(el);
        return cs.display !== 'none' && cs.visibility !== 'hidden' && parseFloat(cs.opacity || '1') > 0;
      };

      const findNewButton = () => {
        const direct = document.querySelector('button[guidedhelpid="new_menu_button"], button[aria-label="New"], button[aria-label="Nuevo"]');
        if (isVisible(direct)) return direct;
        const btns = Array.from(document.querySelectorAll('button, [role="button"]'));
        return btns.find((b) => {
          if (!isVisible(b)) return false;
          const r = b.getBoundingClientRect();
          if (r.left > 280 || r.width < 40) return false;
          const t = ((b.innerText || '') + ' ' + (b.getAttribute('aria-label') || '')).trim().toLowerCase();
          return t === 'new' || t === 'nuevo' || t === '+ new' || t === '+ nuevo' || t.startsWith('new ') || t.startsWith('nuevo ');
        }) || null;
      };

      const clickFileUploadItem = () => {
        const candidates = Array.from(document.querySelectorAll('[role="menuitem"], [role="option"], [role="menu"] div, div[data-target="upload"]'));
        const visible = candidates.filter((el) => isVisible(el) && el.getBoundingClientRect().height > 14);
        const target = visible.find((el) => {
          const text = ((el.innerText || '') + ' ' + (el.getAttribute('aria-label') || '') + ' ' + (el.getAttribute('data-tooltip') || '')).toLowerCase();
          if (text.length > 90) return false;
          const matchesUpload =
            text.includes('file upload') ||
            text.includes('subir archivo') ||
            text.includes('cargar archivo') ||
            text.includes('upload file');
          const isFolder = text.includes('folder') || text.includes('carpeta');
          return matchesUpload && !isFolder;
        });
        if (target) {
          fullClick(target);
          return true;
        }
        return false;
      };

      const newBtn = findNewButton();
      if (!newBtn) return 'no_new_button';

      fullClick(newBtn);
      let tries = 0;
      window.__mfeUploadMenuTimer = setInterval(() => {
        tries += 1;
        if (clickFileUploadItem() || tries >= 24) {
          clearInterval(window.__mfeUploadMenuTimer);
          window.__mfeUploadMenuTimer = null;
        }
      }, 120);
      return 'triggered_new_menu';
    })();
    """#

    /// Si Drive muestra el diálogo "Upload options / Reemplazar o Mantener como archivo separado" al volver a subir un archivo con igual nombre,
    /// elige "Keep as separate file" y confirma "Upload" automáticamente.
    public static let autoResolveDuplicateUploadDialogJS = #"""
    (() => {
      const isVisible = (el) => {
        if (!el) return false;
        const r = el.getBoundingClientRect();
        if (r.width <= 0 || r.height <= 0) return false;
        const cs = window.getComputedStyle(el);
        return cs.display !== 'none' && cs.visibility !== 'hidden' && parseFloat(cs.opacity || '1') > 0;
      };
      const dialogs = Array.from(document.querySelectorAll('[role="dialog"], [role="alertdialog"]'));
      for (const dlg of dialogs) {
        if (!isVisible(dlg)) continue;
        const txt = (dlg.innerText || '').toLowerCase();
        const isDuplicateDlg =
          txt.includes('replace existing file') ||
          txt.includes('keep as separate file') ||
          txt.includes('reemplazar el archivo existente') ||
          txt.includes('mantener como archivo separado') ||
          txt.includes('upload options') ||
          txt.includes('opciones de carga');
        if (!isDuplicateDlg) continue;

        const radios = Array.from(dlg.querySelectorAll('[role="radio"], input[type="radio"], label'));
        const keepOpt = radios.find((el) => {
          const t = ((el.innerText || '') + ' ' + (el.getAttribute('aria-label') || '')).toLowerCase();
          return t.includes('keep as separate') || t.includes('mantener como archivo separado') || t.includes('archivo independiente');
        });
        if (keepOpt && keepOpt.getAttribute('aria-checked') !== 'true') {
          keepOpt.click();
        }

        const btns = Array.from(dlg.querySelectorAll('button, [role="button"]'));
        const confirmBtn = btns.find((b) => {
          if (!isVisible(b)) return false;
          const t = ((b.innerText || '') + ' ' + (b.getAttribute('aria-label') || '')).trim().toLowerCase();
          return t === 'upload' || t === 'subir' || t === 'cargar' || t === 'keep both' || t === 'mantener ambos';
        });
        if (confirmBtn) {
          confirmBtn.click();
          return 'resolved_duplicate';
        }
      }
      return 'none';
    })();
    """#

    public static func buildAsyncDataTransferDropJS(fileName: String, mimeType: String, base64: String) -> String {
        let nameJSON = (try? String(data: JSONEncoder().encode(fileName), encoding: .utf8)) ?? "\"file\""
        let mimeJSON = (try? String(data: JSONEncoder().encode(mimeType), encoding: .utf8)) ?? "\"application/octet-stream\""
        return """
        (() => {
          try {
            const binary = atob('\(base64)');
            const bytes = new Uint8Array(binary.length);
            for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
            const file = new File([bytes], \(nameJSON), { type: \(mimeJSON) });
            const dt = new DataTransfer();
            dt.items.add(file);
            const target = document.querySelector('[data-target="files"], [role="main"], body');
            if (!target) return 'no_target';

            const fire = (type, el) => {
              const ev = new DragEvent(type, { bubbles: true, cancelable: true, dataTransfer: dt });
              if (!ev.dataTransfer) {
                try { Object.defineProperty(ev, 'dataTransfer', { value: dt }); } catch (_) {}
              }
              el.dispatchEvent(ev);
            };

            fire('dragenter', target);
            setTimeout(() => {
              const activeDrop = document.querySelector('[data-target="files"], [role="main"], body') || target;
              fire('dragover', activeDrop);
              setTimeout(() => {
                const finalDrop = document.querySelector('[data-target="files"], [role="main"], body') || activeDrop;
                fire('drop', finalDrop);
              }, 160);
            }, 160);
            return 'dispatched';
          } catch (e) {
            return 'err:' + String(e);
          }
        })();
        """
    }

    /// Separa claramente señales de subida EN CURSO (`domUploadingNow`) de señales de subida COMPLETADA (`domUploadCompleted`),
    /// evitando que un toast residual de la subida anterior dispare un falso positivo antes de pulsar "Subir archivo".
    public static let readUploadProbeJS = #"""
    (() => {
      const s = window.__mfeUploadState || { started: false, inputInjected: false, fileID: '', mimeType: '' };
      const bodyText = (document.body && document.body.innerText ? document.body.innerText : '').toLowerCase();
      const domUploadingNow =
        bodyText.includes('starting upload') ||
        bodyText.includes('uploading 1') ||
        bodyText.includes('iniciando subida') ||
        bodyText.includes('subiendo 1') ||
        bodyText.includes('subiendo elemento') ||
        bodyText.includes('cargando 1') ||
        bodyText.includes('1 item left') ||
        bodyText.includes('queda 1 elemento');
      const domUploadCompleted =
        bodyText.includes('upload complete') ||
        bodyText.includes('uploads complete') ||
        bodyText.includes('1 elemento subido') ||
        bodyText.includes('subida completada') ||
        bodyText.includes('se completó la carga') ||
        bodyText.includes('carga completada');
      return JSON.stringify({
        started: Boolean(s.started),
        inputInjected: Boolean(s.inputInjected),
        domUploadingNow: Boolean(domUploadingNow),
        domUploadCompleted: Boolean(domUploadCompleted),
        fileID: String(s.fileID || ''),
        mimeType: String(s.mimeType || '')
      });
    })();
    """#

    private static let snapshotVisibleDriveIDsJS = """
    (() => {
      const ids = new Set();
      document.querySelectorAll('[data-id]').forEach((el) => {
        const id = el.getAttribute('data-id');
        if (id && /^[a-zA-Z0-9_-]{12,120}$/.test(id)) ids.add(id);
      });
      return Array.from(ids);
    })();
    """

    public static func buildDetectUploadedFileIDJS(
        fileName: String,
        fileStem: String,
        excludedIDs: [String],
        folderID: String,
        allowExistingMatchOnDone: Bool
    ) -> String {
        let nameJSON = (try? String(data: JSONEncoder().encode(fileName.lowercased()), encoding: .utf8)) ?? "\"\""
        let stemJSON = (try? String(data: JSONEncoder().encode(fileStem.lowercased()), encoding: .utf8)) ?? "\"\""
        let excludedJSON = (try? String(data: JSONEncoder().encode(excludedIDs), encoding: .utf8)) ?? "[]"
        let folderJSON = (try? String(data: JSONEncoder().encode(folderID), encoding: .utf8)) ?? "\"\""
        let allowExistingLiteral = allowExistingMatchOnDone ? "true" : "false"

        return """
        (() => {
          const targetName = \(nameJSON);
          const targetStem = \(stemJSON);
          const excluded = new Set(\(excludedJSON));
          const folderID = \(folderJSON);
          const allowExisting = \(allowExistingLiteral);
          const validId = (id) => Boolean(
            id &&
            /^[a-zA-Z0-9_-]{12,120}$/.test(id) &&
            id !== folderID &&
            (allowExisting || !excluded.has(id))
          );

          const bodyText = (document.body && document.body.innerText ? document.body.innerText : '').toLowerCase();
          const uploadDoneSignal =
            bodyText.includes('upload complete') ||
            bodyText.includes('uploads complete') ||
            bodyText.includes('1 elemento subido') ||
            bodyText.includes('subida completada') ||
            bodyText.includes('se completó la carga') ||
            bodyText.includes('carga completada');

          const candidates = Array.from(document.querySelectorAll('[data-id]'));
          for (const el of candidates) {
            const id = el.getAttribute('data-id');
            if (!validId(id)) continue;
            const txt = ((el.innerText || '') + ' ' + (el.getAttribute('aria-label') || '') + ' ' + (el.getAttribute('data-tooltip') || '')).toLowerCase();
            if (txt.includes(targetName) || (targetStem.length >= 3 && txt.includes(targetStem))) {
              if (!txt.includes('uploading') && !txt.includes('subiendo') && !txt.includes('cargando')) {
                return id;
              }
            }
          }

          if (uploadDoneSignal) {
            const links = Array.from(document.querySelectorAll('a[href*="/d/"], a[href*="id="]'));
            for (const a of links) {
              const href = a.getAttribute('href') || '';
              const m = href.match(/\\/d\\/([a-zA-Z0-9_-]{12,120})/) || href.match(/[?&]id=([a-zA-Z0-9_-]{12,120})/);
              if (m && validId(m[1])) {
                return m[1];
              }
            }
          }

          return '';
        })();
        """
    }

    public static let clickOpenWithGoogleSheetsJS = #"""
    (() => {
      const fullClick = (el) => {
        const r = el.getBoundingClientRect();
        const opts = { bubbles: true, cancelable: true, view: window, button: 0, clientX: r.left + r.width / 2, clientY: r.top + r.height / 2 };
        el.dispatchEvent(new MouseEvent('mousedown', opts));
        el.dispatchEvent(new MouseEvent('mouseup', opts));
        el.dispatchEvent(new MouseEvent('click', opts));
      };
      const btns = Array.from(document.querySelectorAll('button, [role="button"], [role="menuitem"]'));
      const openBtn = btns.find((b) => {
        if (!b.offsetParent) return false;
        const t = ((b.innerText || '') + ' ' + (b.getAttribute('aria-label') || '')).toLowerCase();
        return t.includes('google sheets') || t.includes('hojas de cálculo de google') || t.includes('open with google sheets') || t.includes('abrir con hojas');
      });
      if (openBtn) {
        fullClick(openBtn);
        return true;
      }
      return false;
    })();
    """#
}

// MARK: - Ventana de Configuración Rápida de "Send to Drive"

@MainActor
public final class GoogleDriveSettingsWindowController: NSObject, NSWindowDelegate {
    public static let shared = GoogleDriveSettingsWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    public func show() {
        let loc = LocalizationManager.shared
        let title = loc.text(es: "Configuración de «Enviar a Drive»", en: "Send to Drive Settings")
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let existing = window {
            existing.title = title
            existing.contentView = NSHostingView(rootView: GoogleDriveSettingsView(onClose: { [weak existing] in
                existing?.close()
            }))
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let created = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        created.title = title
        created.isReleasedWhenClosed = false
        created.delegate = self
        created.center()
        created.contentView = NSHostingView(rootView: GoogleDriveSettingsView(onClose: { [weak created] in
            created?.close()
        }))
        window = created
        created.makeKeyAndOrderFront(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
    }
}

private struct GoogleDriveSettingsView: View {
    let onClose: () -> Void

    @Bindable private var googleManager = GoogleAccountsManager.shared
    @Bindable private var drivePrefs = GoogleDriveUploadPreferences.shared
    @Bindable private var loc = LocalizationManager.shared

    @ViewState private var selectedAccountID: UUID? = nil
    @ViewState private var folderInputDraft: String = ""
    @ViewState private var folderNameDraft: String = ""
    @ViewState private var savedBanner: String? = nil
    @ViewState private var errorBanner: String? = nil

    private var activeAccount: GoogleAccount? {
        if let selectedAccountID, let found = googleManager.accounts.first(where: { $0.id == selectedAccountID }) {
            return found
        }
        return GoogleDriveUploadService.shared.resolvePreferredAccount()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                GoogleServiceIconView(service: .drive, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.text(es: "Enviar a Google Drive", en: "Send to Google Drive"))
                        .font(.system(size: 16, weight: .bold))
                    Text(loc.text(
                        es: "Elegí la carpeta destino y dónde abrir Google Sheets, Docs o Slides al terminar de subir.",
                        en: "Choose the target Drive folder and where to open Google Sheets, Docs, or Slides after uploading."
                    ))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                }
            }

            Divider()

            if googleManager.accounts.isEmpty {
                VStack(spacing: 10) {
                    Text(loc.text(
                        es: "Todavía no hay ninguna cuenta de Google conectada en MacFileExplorer.",
                        en: "No Google account is signed in to MacFileExplorer yet."
                    ))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)

                    Button(loc.text(es: "Conectar cuenta de Google…", en: "Sign in to Google…")) {
                        onClose()
                        googleManager.startAddGoogleAccount()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 1. Selector de cuenta predeterminada
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc.text(es: "Cuenta de Google:", en: "Google Account:"))
                        .font(.system(size: 12, weight: .semibold))
                    Picker("", selection: Binding(
                        get: { activeAccount?.id ?? googleManager.accounts[0].id },
                        set: { newID in
                            selectedAccountID = newID
                            drivePrefs.defaultAccountID = newID
                            loadDrafts(for: newID)
                        }
                    )) {
                        ForEach(googleManager.accounts) { acc in
                            Text(acc.displayLabel).tag(acc.id)
                        }
                    }
                    .labelsHidden()
                }

                // 2. Carpeta destino en Google Drive
                if let account = activeAccount {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(loc.text(es: "Carpeta destino en Drive:", en: "Target Drive Folder:"))
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text(drivePrefs.displayFolderName(for: account.id, using: loc))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(red: 0.20, green: 0.66, blue: 0.33))
                        }

                        TextField(
                            loc.text(
                                es: "Pegá el enlace de la carpeta (https://drive.google.com/drive/folders/…) o dejalo vacío para Mi unidad",
                                en: "Paste folder URL (https://drive.google.com/drive/folders/…) or leave blank for My Drive"
                            ),
                            text: $folderInputDraft
                        )
                        .textFieldStyle(.roundedBorder)

                        TextField(
                            loc.text(es: "Nombre visible opcional (ej. Planillas Trabajo)", en: "Optional display label (e.g. Work Spreadsheets)"),
                            text: $folderNameDraft
                        )
                        .textFieldStyle(.roundedBorder)

                        HStack(spacing: 8) {
                            Button(loc.text(es: "Guardar carpeta", en: "Save Folder")) {
                                errorBanner = nil
                                savedBanner = nil
                                let ok = drivePrefs.setFolder(
                                    fromUserInput: folderInputDraft,
                                    customName: folderNameDraft,
                                    for: account.id
                                )
                                if ok {
                                    let resolved = drivePrefs.displayFolderName(for: account.id, using: loc)
                                    savedBanner = loc.text(
                                        es: "Destino guardado: \(resolved)",
                                        en: "Target saved: \(resolved)"
                                    )
                                } else {
                                    errorBanner = loc.text(
                                        es: "Enlace o ID inválido. Pegá una URL de carpeta de Drive (…/folders/ID) o elegila directo desde la pestaña de Drive.",
                                        en: "Invalid folder URL or ID. Paste a Google Drive folder link (…/folders/ID) or set it directly from the Drive tab."
                                    )
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Button(loc.text(es: "Abrir Drive para elegir carpeta", en: "Open Drive to Pick Folder")) {
                                let dest = drivePrefs.destination(for: account.id)
                                _ = googleManager.openOrFocusDriveFolderTab(url: dest.targetURL, for: account.id)
                                onClose()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Spacer()

                            Button(loc.text(es: "Usar Mi unidad", en: "Use My Drive")) {
                                folderInputDraft = ""
                                folderNameDraft = ""
                                errorBanner = nil
                                drivePrefs.setFolder(fromUserInput: "", customName: "", for: account.id)
                                savedBanner = loc.text(es: "Restablecido a Mi unidad", en: "Reset to My Drive")
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }

                        Text(loc.text(
                            es: "Tip: abrí cualquier carpeta dentro de tu pestaña de Google Drive en MacFileExplorer y tocá «Usar para Enviar a Drive» en la barra superior.",
                            en: "Tip: open any folder inside your Google Drive tab in MacFileExplorer and click \"Set Send to Drive Folder\" in the toolbar."
                        ))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // 3. Dónde abrir Google Sheets / Docs / Slides
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc.text(es: "Al terminar de subir, abrir Sheets / Docs / Slides en:", en: "After upload completes, open Sheets / Docs / Slides in:"))
                        .font(.system(size: 12, weight: .semibold))

                    Picker("", selection: $drivePrefs.openInExternalChrome) {
                        Text(loc.text(es: "Pestaña de MacFileExplorer (misma cuenta)", en: "MacFileExplorer Tab (same session)")).tag(false)
                        Text(loc.text(es: "Google Chrome externo", en: "External Google Chrome")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            Spacer(minLength: 0)

            HStack {
                if let errorBanner {
                    Label(errorBanner, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                } else if let savedBanner {
                    Label(savedBanner, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.green)
                }
                Spacer()
                Button(loc.text(es: "Cerrar", en: "Done")) {
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 540, height: 440)
        .onAppear {
            if let acc = activeAccount {
                selectedAccountID = acc.id
                loadDrafts(for: acc.id)
            }
        }
    }

    private func loadDrafts(for accountID: UUID) {
        let dest = drivePrefs.destination(for: accountID)
        folderInputDraft = dest.folderURLString ?? dest.folderID ?? ""
        folderNameDraft = dest.folderName
        savedBanner = nil
        errorBanner = nil
    }
}
