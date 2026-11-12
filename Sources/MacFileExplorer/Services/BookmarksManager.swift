import AppKit
import Foundation
import Observation
import SwiftUI

/// Define dónde deben abrirse los marcadores (accesos directos) al hacer clic sobre ellos.
public enum BookmarkOpenBehavior: String, CaseIterable, Identifiable, Codable, Sendable {
    case inMacFileExplorer = "in_mac_file_explorer"
    case inNewChromeWindow = "in_new_chrome_window"

    public var id: String { rawValue }

    @MainActor
    public var localizedTitle: String {
        let loc = LocalizationManager.shared
        switch self {
        case .inMacFileExplorer:
            return loc.text(
                es: "Abrir en el mismo MacFileExplorer (Pestaña)",
                en: "Open inside MacFileExplorer (Tab)"
            )
        case .inNewChromeWindow:
            return loc.text(
                es: "Abrir en nueva ventana de Google Chrome",
                en: "Open in a new Google Chrome window"
            )
        }
    }

    @MainActor
    public var shortTitle: String {
        let loc = LocalizationManager.shared
        switch self {
        case .inMacFileExplorer:
            return loc.text(es: "En MacFileExplorer", en: "In MacFileExplorer")
        case .inNewChromeWindow:
            return loc.text(es: "Nueva ventana de Chrome", en: "New Chrome Window")
        }
    }
}

/// Modelo de un marcador / acceso directo estilo Favoritos de Chrome.
public struct ChromeBookmarkItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var urlString: String
    /// Imagen PNG compacta (`64×64`) del favicon de la web asociada, persistida con el marcador.
    public var faviconData: Data?

    public init(id: UUID = UUID(), title: String, urlString: String, faviconData: Data? = nil) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.faviconData = faviconData
    }

    public static func sanitizedURLString(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://https://", "https://http://", "http://http://", "http://https://"] {
            if trimmed.lowercased().hasPrefix(prefix) {
                trimmed = String(trimmed.dropFirst(prefix.hasPrefix("https://") ? 8 : 7))
                break
            }
        }
        return trimmed
    }

    public var resolvedURL: URL? {
        let trimmed = Self.sanitizedURLString(urlString)
        guard !trimmed.isEmpty else { return nil }
        let withScheme: String
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            withScheme = trimmed
        } else {
            withScheme = "https://\(trimmed)"
        }
        if let direct = URL(string: withScheme), direct.host != nil {
            return direct
        }
        if let encoded = withScheme.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) {
            return URL(string: encoded)
        }
        return nil
    }

    public var hostDomain: String {
        resolvedURL?.host ?? Self.sanitizedURLString(urlString)
    }
}

/// Gestor reactivo (`@MainActor @Observable`) de la barra de marcadores estilo Chrome.
/// Persiste la lista de marcadores (incluyendo sus favicons), la visibilidad de la barra (menú View)
/// y el comportamiento de apertura (en pestaña integrada de `MacFileExplorer` o en nueva ventana de `Google Chrome`).
@MainActor
@Observable
public final class BookmarksManager {

    public static let shared = BookmarksManager(userDefaults: .standard)

    /// UUID fijo para el almacén persistente `WKWebsiteDataStore` de pestañas de marcadores generales.
    public static let generalBookmarksAccountID = UUID(uuidString: "B00C4A2C-1111-4222-9333-444455556666")!

    private let userDefaults: UserDefaults
    private let bookmarksKey = "com.macfileexplorer.chromeBookmarks.v1"
    private let showBarKey = "com.macfileexplorer.showChromeBookmarksBar.v1"
    private let openBehaviorKey = "com.macfileexplorer.bookmarkOpenBehavior.v1"

    /// Lista de marcadores configurados por el usuario.
    public var bookmarks: [ChromeBookmarkItem] = [] {
        didSet {
            saveBookmarks()
        }
    }

    /// Indica si la barra de marcadores está visible en el área superior derecha (conmutable desde el menú View).
    public var isBookmarksBarVisible: Bool = true {
        didSet {
            userDefaults.set(isBookmarksBarVisible, forKey: showBarKey)
        }
    }

    /// Configuración de apertura al hacer clic en un marcador (en `MacFileExplorer` o en nueva ventana de `Google Chrome`).
    public var openBehavior: BookmarkOpenBehavior = .inMacFileExplorer {
        didSet {
            userDefaults.set(openBehavior.rawValue, forKey: openBehaviorKey)
        }
    }

    /// Caché en memoria de favicons decodificados por ID de marcador y por dominio normalizado.
    private let faviconCache = NSCache<NSString, NSImage>()
    private var inFlightFetches: [UUID: Task<NSImage?, Never>] = [:]

    internal init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadPersistedState()
    }

    // MARK: - Acciones de Apertura (MacFileExplorer vs Nueva Ventana de Chrome)

    /// Abre un marcador respetando la preferencia configurada (`openBehavior`) o un override específico.
    public func openBookmark(_ bookmark: ChromeBookmarkItem, behaviorOverride: BookmarkOpenBehavior? = nil) {
        guard let url = bookmark.resolvedURL else { return }
        let targetBehavior = behaviorOverride ?? openBehavior

        switch targetBehavior {
        case .inMacFileExplorer:
            let initialData = bookmark.faviconData
                ?? bookmarks.first(where: { $0.id == bookmark.id })?.faviconData
            GoogleAccountsManager.shared.openBookmarkURLInTab(
                url,
                title: bookmark.title,
                bookmarkID: bookmark.id,
                initialFaviconData: initialData
            )
        case .inNewChromeWindow:
            if bookmark.faviconData == nil {
                Task { _ = await self.fetchFavicon(for: bookmark) }
            }
            openURLInNewGoogleChromeWindow(url)
        }
    }

    /// Abre una URL específicamente en una **nueva ventana** de Google Chrome (`--new-window`).
    public func openURLInNewGoogleChromeWindow(_ url: URL) {
        openURLInGoogleChrome(url, newWindow: true)
    }

    /// Abre una URL en Google Chrome (en la ventana activa como pestaña nueva o en ventana nueva).
    public func openURLInGoogleChrome(_ url: URL, newWindow: Bool = false) {
        let chromeBinaryPath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        let chromeAppURL = URL(fileURLWithPath: "/Applications/Google Chrome.app")

        if newWindow, FileManager.default.isExecutableFile(atPath: chromeBinaryPath) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: chromeBinaryPath)
            process.arguments = ["--new-window", url.absoluteString]
            do {
                try process.run()
                return
            } catch {
                // Fallback a NSWorkspace si Process falla
            }
        }

        if FileManager.default.fileExists(atPath: chromeAppURL.path(percentEncoded: false)) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            if newWindow {
                config.arguments = ["--new-window", url.absoluteString]
            }
            NSWorkspace.shared.open([url], withApplicationAt: chromeAppURL, configuration: config)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - CRUD de Marcadores

    public func addBookmark(title: String, urlString: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanURL = ChromeBookmarkItem.sanitizedURLString(urlString)
        guard !cleanURL.isEmpty else { return }

        let finalTitle: String
        if cleanTitle.isEmpty {
            let temp = ChromeBookmarkItem(title: "", urlString: cleanURL)
            finalTitle = FaviconService.normalizedHost(temp.hostDomain)
        } else {
            finalTitle = cleanTitle
        }

        let item = ChromeBookmarkItem(title: finalTitle, urlString: cleanURL)
        bookmarks.append(item)
        Task { _ = await self.fetchFavicon(for: item) }
    }

    public func updateBookmark(_ id: UUID, title: String, urlString: String) {
        guard let idx = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanURL = ChromeBookmarkItem.sanitizedURLString(urlString)
        guard !cleanURL.isEmpty else { return }

        let oldResolved = bookmarks[idx].resolvedURL?.absoluteString.lowercased()
        let oldRaw = bookmarks[idx].urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        bookmarks[idx].title = cleanTitle.isEmpty ? cleanURL : cleanTitle
        bookmarks[idx].urlString = cleanURL

        let newResolved = bookmarks[idx].resolvedURL?.absoluteString.lowercased()
        let newRaw = cleanURL.lowercased()
        if oldResolved != newResolved && oldRaw != newRaw {
            inFlightFetches.removeValue(forKey: id)?.cancel()
            faviconCache.removeObject(forKey: bookmarkCacheKey(id))
            bookmarks[idx].faviconData = nil
            let updatedItem = bookmarks[idx]
            Task { _ = await self.fetchFavicon(for: updatedItem) }
        }
    }

    public func removeBookmark(_ item: ChromeBookmarkItem) {
        inFlightFetches.removeValue(forKey: item.id)?.cancel()
        faviconCache.removeObject(forKey: bookmarkCacheKey(item.id))
        bookmarks.removeAll { $0.id == item.id }
    }

    // MARK: - Obtención y Persistencia de Favicon

    private func bookmarkCacheKey(_ id: UUID) -> NSString {
        "b:\(id.uuidString)" as NSString
    }

    private func hostCacheKey(_ host: String) -> NSString {
        "h:\(FaviconService.normalizedHost(host))" as NSString
    }

    public func cachedFavicon(for bookmark: ChromeBookmarkItem) -> NSImage? {
        if let byBookmark = faviconCache.object(forKey: bookmarkCacheKey(bookmark.id)) {
            return byBookmark
        }
        let persistedData = bookmark.faviconData
            ?? bookmarks.first(where: { $0.id == bookmark.id })?.faviconData
        if let data = persistedData, let image = NSImage(data: data) {
            cacheImage(image, forBookmarkID: bookmark.id, host: bookmark.hostDomain)
            return image
        }
        return cachedFavicon(forHost: bookmark.hostDomain)
    }

    public func cachedFavicon(forHost host: String) -> NSImage? {
        let norm = FaviconService.normalizedHost(host)
        guard !norm.isEmpty else { return nil }
        let key = hostCacheKey(norm)
        if let cached = faviconCache.object(forKey: key) {
            return cached
        }
        if let matching = bookmarks.first(where: {
            $0.faviconData != nil && FaviconService.normalizedHost($0.hostDomain) == norm
        }),
           let data = matching.faviconData,
           let image = NSImage(data: data) {
            faviconCache.setObject(image, forKey: key)
            return image
        }
        return nil
    }

    /// Descarga y persiste en disco el favicon del marcador consultando su HTML real, `/favicon.ico` y servicios de respaldo.
    public func fetchFavicon(for bookmark: ChromeBookmarkItem) async -> NSImage? {
        if let existingData = bookmark.faviconData
            ?? bookmarks.first(where: { $0.id == bookmark.id })?.faviconData,
           let image = NSImage(data: existingData) {
            cacheImage(image, forBookmarkID: bookmark.id, host: bookmark.hostDomain)
            return image
        }

        if let existingTask = inFlightFetches[bookmark.id] {
            return await existingTask.value
        }

        guard let targetURL = bookmark.resolvedURL else { return nil }
        let bookmarkID = bookmark.id
        let host = bookmark.hostDomain

        let task = Task<NSImage?, Never> { [weak self] in
            guard let pngData = await FaviconService.fetchDirectFaviconData(for: targetURL) else {
                return nil
            }
            guard let self, !Task.isCancelled else { return nil }
            return self.saveFaviconData(pngData, forBookmarkID: bookmarkID, matchedHost: host)
        }
        inFlightFetches[bookmark.id] = task
        let result = await task.value
        inFlightFetches.removeValue(forKey: bookmark.id)
        return result
    }

    /// Guarda el favicon capturado en vivo al cargar una web en `WKWebView` sobre el marcador de origen
    /// y sobre cualquier otro marcador guardado del mismo dominio.
    public func recordCapturedFavicon(_ pngData: Data, forPageURL pageURL: URL, sourceBookmarkID: UUID?) {
        guard let image = NSImage(data: pngData) else { return }

        let loadedHost = pageURL.host ?? ""
        let normLoadedHost = FaviconService.normalizedHost(loadedHost)
        if !normLoadedHost.isEmpty {
            faviconCache.setObject(image, forKey: hostCacheKey(normLoadedHost))
        }

        for idx in bookmarks.indices {
            let bookmarkHost = bookmarks[idx].hostDomain
            let isSourceBookmark = (sourceBookmarkID != nil && bookmarks[idx].id == sourceBookmarkID)
            let isSameHost = !normLoadedHost.isEmpty
                && FaviconService.hostsMatchNormalized(bookmarkHost, loadedHost)

            if isSourceBookmark {
                if FaviconService.isTransientThirdPartyAuthHost(loadedHost, bookmarkHost: bookmarkHost) {
                    continue
                }
            } else if !isSameHost {
                continue
            }

            cacheImage(image, forBookmarkID: bookmarks[idx].id, host: bookmarkHost)
            if bookmarks[idx].faviconData != pngData {
                bookmarks[idx].faviconData = pngData
            }
        }
    }

    @discardableResult
    private func saveFaviconData(_ pngData: Data, forBookmarkID bookmarkID: UUID, matchedHost: String?) -> NSImage? {
        guard let image = NSImage(data: pngData) else { return nil }
        cacheImage(image, forBookmarkID: bookmarkID, host: matchedHost)
        if let idx = bookmarks.firstIndex(where: { $0.id == bookmarkID }),
           bookmarks[idx].faviconData != pngData {
            bookmarks[idx].faviconData = pngData
        }
        return image
    }

    private func cacheImage(_ image: NSImage, forBookmarkID bookmarkID: UUID, host: String?) {
        faviconCache.setObject(image, forKey: bookmarkCacheKey(bookmarkID))
        if let host {
            let norm = FaviconService.normalizedHost(host)
            if !norm.isEmpty {
                faviconCache.setObject(image, forKey: hostCacheKey(norm))
            }
        }
    }

    // MARK: - Persistencia

    private func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            userDefaults.set(data, forKey: bookmarksKey)
        }
    }

    private func loadPersistedState() {
        if userDefaults.object(forKey: showBarKey) != nil {
            isBookmarksBarVisible = userDefaults.bool(forKey: showBarKey)
        } else {
            isBookmarksBarVisible = true
        }

        if let rawBehavior = userDefaults.string(forKey: openBehaviorKey),
           let savedBehavior = BookmarkOpenBehavior(rawValue: rawBehavior) {
            openBehavior = savedBehavior
        } else {
            openBehavior = .inMacFileExplorer
        }

        if let data = userDefaults.data(forKey: bookmarksKey),
           let decoded = try? JSONDecoder().decode([ChromeBookmarkItem].self, from: data) {
            bookmarks = decoded
        } else {
            // Marcadores iniciales de ejemplo para que la barra luzca lista desde el primer uso
            bookmarks = [
                ChromeBookmarkItem(title: "Google", urlString: "https://www.google.com"),
                ChromeBookmarkItem(title: "GitHub", urlString: "https://github.com"),
                ChromeBookmarkItem(title: "YouTube", urlString: "https://www.youtube.com")
            ]
        }
    }
}
