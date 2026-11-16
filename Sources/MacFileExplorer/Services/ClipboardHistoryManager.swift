import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

/// Preferencias reactivas y persistentes del Historial del Portapapeles estilo Maccy.
@MainActor
@Observable
public final class ClipboardHistoryPreferences {

    public static let shared = ClipboardHistoryPreferences()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let isEnabled = "com.macfileexplorer.clipboardHistory.isEnabled"
        static let maxItems = "com.macfileexplorer.clipboardHistory.maxItems"
        static let retentionPeriod = "com.macfileexplorer.clipboardHistory.retentionPeriod"
        static let shortcutPreset = "com.macfileexplorer.clipboardHistory.shortcutPreset"
        static let isSidebarSectionExpanded = "com.macfileexplorer.clipboardHistory.isSidebarSectionExpanded"
    }

    /// Activa o desactiva la captura y la sección del Historial del Portapapeles en el panel lateral izquierdo.
    public var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            ClipboardHistoryManager.shared.syncMonitoringState()
            StatusBarManager.shared.refreshTooltipAndMenu()
        }
    }

    /// Cantidad máxima de elementos no fijados a conservar en el historial.
    public var maxItemsOption: ClipboardMaxItemsOption {
        didSet {
            guard maxItemsOption != oldValue else { return }
            defaults.set(maxItemsOption.rawValue, forKey: Keys.maxItems)
            ClipboardHistoryManager.shared.enforceRetentionPolicy()
        }
    }

    /// Tiempo máximo que se conservan los elementos no fijados en el historial.
    public var retentionPeriod: ClipboardRetentionPeriod {
        didSet {
            guard retentionPeriod != oldValue else { return }
            defaults.set(retentionPeriod.rawValue, forKey: Keys.retentionPeriod)
            ClipboardHistoryManager.shared.enforceRetentionPolicy()
        }
    }

    /// Atajo de teclado rápido para abrir el buscador flotante estilo Maccy (`⇧⌘C` por defecto).
    public var popupShortcutPreset: ClipboardPopupShortcutPreset {
        didSet {
            guard popupShortcutPreset != oldValue else { return }
            defaults.set(popupShortcutPreset.rawValue, forKey: Keys.shortcutPreset)
            StatusBarManager.shared.refreshTooltipAndMenu()
        }
    }

    /// Estado de expansión de la sección "Historial del Portapapeles" debajo de Google Accounts en la barra lateral.
    public var isSidebarSectionExpanded: Bool {
        didSet {
            guard isSidebarSectionExpanded != oldValue else { return }
            defaults.set(isSidebarSectionExpanded, forKey: Keys.isSidebarSectionExpanded)
        }
    }

    private init() {
        if defaults.object(forKey: Keys.isEnabled) == nil {
            self.isEnabled = true
        } else {
            self.isEnabled = defaults.bool(forKey: Keys.isEnabled)
        }

        if let rawMax = defaults.object(forKey: Keys.maxItems) as? Int,
           let parsedMax = ClipboardMaxItemsOption(rawValue: rawMax) {
            self.maxItemsOption = parsedMax
        } else {
            self.maxItemsOption = .twoHundred
        }

        if let rawRetention = defaults.string(forKey: Keys.retentionPeriod),
           let parsedRetention = ClipboardRetentionPeriod(rawValue: rawRetention) {
            self.retentionPeriod = parsedRetention
        } else {
            self.retentionPeriod = .thirtyDays
        }

        if let rawShortcut = defaults.string(forKey: Keys.shortcutPreset),
           let parsedShortcut = ClipboardPopupShortcutPreset(rawValue: rawShortcut) {
            self.popupShortcutPreset = parsedShortcut
        } else {
            self.popupShortcutPreset = .shiftCommandC
        }

        if defaults.object(forKey: Keys.isSidebarSectionExpanded) == nil {
            self.isSidebarSectionExpanded = true
        } else {
            self.isSidebarSectionExpanded = defaults.bool(forKey: Keys.isSidebarSectionExpanded)
        }
    }
}

/// Gestor central (`@MainActor @Observable`) del Historial del Portapapeles estilo Maccy.
/// Monitorea automáticamente `NSPasteboard.general` (texto, enlaces, archivos e imágenes/capturas de pantalla),
/// almacena imágenes en disco en formato PNG, aplica deduplicación por hash SHA-256 y ejecuta políticas
/// configurables de límite por cantidad y por antigüedad.
@MainActor
@Observable
public final class ClipboardHistoryManager {

    public static let shared = ClipboardHistoryManager()

    /// Lista completa de entradas ordenadas (fijadas primero, luego por fecha de última copia descendente).
    public private(set) var items: [ClipboardHistoryEntry] = []

    /// Texto de búsqueda activo dentro de la sección de Historial del Portapapeles.
    public var searchQuery: String = ""

    /// Categoría de filtro activa (`Todos`, `Texto`, `Imágenes`, `Archivos`, `Enlaces`, `Fijados`).
    public var selectedFilter: ClipboardHistoryFilter = .all

    /// ID de la entrada seleccionada actualmente en el panel de inspección o en el popup estilo Maccy.
    public var selectedEntryID: UUID?

    /// ID de la última entrada copiada mediante clic rápido para mostrar feedback visual ("¡Copiado!").
    public var recentlyCopiedFeedbackEntryID: UUID?

    private let storageDirectoryURL: URL
    private let imagesDirectoryURL: URL
    private let historyFileURL: URL
    private let imageCache = NSCache<NSString, NSImage>()

    private var pollTimer: Timer?
    private var lastObservedChangeCount: Int = -1
    private var lastSelfWrittenChangeCount: Int = -1
    private var localShortcutMonitor: Any?
    private var globalShortcutMonitor: Any?

    /// Tipos de `NSPasteboard` confidenciales o transitorios (gestores de contraseñas como 1Password, Keychain, etc.) que deben ignorarse.
    private static let ignoredPasteboardTypeRawValues: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword",
        "de.ashima.PasswordPboardType"
    ]

    public init(
        storageDirectoryURL: URL? = nil,
        startMonitoringImmediately: Bool = true
    ) {
        let resolvedBaseDir: URL = storageDirectoryURL ?? {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
            return appSupport
                .appendingPathComponent("MacFileExplorer", isDirectory: true)
                .appendingPathComponent("ClipboardHistory", isDirectory: true)
        }()

        self.storageDirectoryURL = resolvedBaseDir
        self.imagesDirectoryURL = resolvedBaseDir.appendingPathComponent("Images", isDirectory: true)
        self.historyFileURL = resolvedBaseDir.appendingPathComponent("history.json", isDirectory: false)
        self.imageCache.countLimit = 256

        ensureDirectoriesExist()
        loadFromDisk()
        enforceRetentionPolicy()

        if startMonitoringImmediately {
            lastObservedChangeCount = NSPasteboard.general.changeCount
            syncMonitoringState()
            installShortcutMonitorsIfNeeded()
        }
    }

    // MARK: - Consultas Filtradas

    /// Entradas que coinciden con `searchQuery` y `selectedFilter` manteniendo primero los elementos fijados.
    public var filteredItems: [ClipboardHistoryEntry] {
        items.filter { $0.matches(query: searchQuery, filter: selectedFilter) }
    }

    /// Entrada actualmente seleccionada para previsualizar en el panel derecho (o la primera disponible).
    public var selectedEntry: ClipboardHistoryEntry? {
        if let selectedEntryID, let match = filteredItems.first(where: { $0.id == selectedEntryID }) {
            return match
        }
        return filteredItems.first
    }

    /// Cantidad de elementos fijados actualmente.
    public var pinnedCount: Int {
        items.filter(\.isPinned).count
    }

    // MARK: - Control de Monitoreo en Segundo Plano y Atajos Globales

    public func installIfNeeded() {
        syncMonitoringState()
        installShortcutMonitorsIfNeeded()
    }

    public func syncMonitoringState() {
        if ClipboardHistoryPreferences.shared.isEnabled {
            startPollingIfNeeded()
        } else {
            stopPolling()
        }
    }

    private func startPollingIfNeeded() {
        guard pollTimer == nil else { return }
        lastObservedChangeCount = NSPasteboard.general.changeCount
        let timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkGeneralPasteboardIfChanged()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func installShortcutMonitorsIfNeeded() {
        if localShortcutMonitor == nil {
            localShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                let keyCode = event.keyCode
                let chars = event.charactersIgnoringModifiers
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let handled = MainActor.assumeIsolated {
                    self.handleShortcutKeyDown(keyCode: keyCode, charactersIgnoringModifiers: chars, flags: flags)
                }
                return handled ? nil : event
            }
        }

        if globalShortcutMonitor == nil {
            globalShortcutMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let keyCode = event.keyCode
                let chars = event.charactersIgnoringModifiers
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    _ = self.handleShortcutKeyDown(keyCode: keyCode, charactersIgnoringModifiers: chars, flags: flags)
                }
            }
        }
    }

    private func handleShortcutKeyDown(
        keyCode: UInt16,
        charactersIgnoringModifiers: String?,
        flags: NSEvent.ModifierFlags
    ) -> Bool {
        let prefs = ClipboardHistoryPreferences.shared
        guard prefs.isEnabled else { return false }
        guard prefs.popupShortcutPreset.matches(
            keyCode: keyCode,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            flags: flags
        ) else {
            return false
        }
        ClipboardQuickPopupController.shared.togglePopup()
        return true
    }

    // MARK: - Captura del Portapapeles (`NSPasteboard`)

    /// Verifica si `NSPasteboard.general.changeCount` cambió y registra el nuevo contenido si corresponde.
    public func checkGeneralPasteboardIfChanged() {
        guard ClipboardHistoryPreferences.shared.isEnabled else { return }
        let pb = NSPasteboard.general
        let currentCount = pb.changeCount
        guard currentCount != lastObservedChangeCount else { return }
        lastObservedChangeCount = currentCount

        if currentCount == lastSelfWrittenChangeCount {
            return
        }

        let frontApp = NSWorkspace.shared.frontmostApplication
        _ = captureFromPasteboard(
            pb,
            sourceAppName: frontApp?.localizedName,
            sourceAppBundleID: frontApp?.bundleIdentifier
        )
    }

    /// Extrae el contenido de cualquier `NSPasteboard` (imágenes, archivos, enlaces o texto) y lo incorpora al historial.
    @discardableResult
    public func captureFromPasteboard(
        _ pasteboard: NSPasteboard = .general,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        now: Date = Date()
    ) -> ClipboardHistoryEntry? {
        guard ClipboardHistoryPreferences.shared.isEnabled else { return nil }

        // Ignorar contenido confidencial o transitorio (ej. contraseñas de 1Password / Keychain)
        if let types = pasteboard.types {
            for type in types where Self.ignoredPasteboardTypeRawValues.contains(type.rawValue) {
                return nil
            }
        }

        let resolvedAppName = sourceAppName ?? NSWorkspace.shared.frontmostApplication?.localizedName
        let resolvedBundleID = sourceAppBundleID ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // 1. Verificar si hay URLs de archivos locales copiadas
        let fileURLOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: fileURLOptions) as? [URL],
           !urls.isEmpty {
            return recordFileURLs(
                urls,
                sourceAppName: resolvedAppName,
                sourceAppBundleID: resolvedBundleID,
                now: now
            )
        }

        // 2. Verificar si hay una imagen copiada directamente al portapapeles (capturas de pantalla, navegador, Preview, etc.)
        if let rawImage = extractImageFromPasteboard(pasteboard) {
            let optionalText = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return recordImage(
                rawImage,
                captionText: optionalText,
                sourceAppName: resolvedAppName,
                sourceAppBundleID: resolvedBundleID,
                now: now
            )
        }

        // 3. Verificar si hay texto o enlace web copiado
        if let rawString = pasteboard.string(forType: .string) {
            return recordText(
                rawString,
                sourceAppName: resolvedAppName,
                sourceAppBundleID: resolvedBundleID,
                now: now
            )
        }

        return nil
    }

    /// Registra directamente un texto o URL en el historial del portapapeles.
    @discardableResult
    public func recordText(
        _ rawText: String,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        now: Date = Date()
    ) -> ClipboardHistoryEntry? {
        guard ClipboardHistoryPreferences.shared.isEnabled else { return nil }
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let isWebLink: Bool = {
            guard !trimmed.contains(where: \.isWhitespace),
                  let url = URL(string: trimmed),
                  let scheme = url.scheme?.lowercased(),
                  (scheme == "http" || scheme == "https"),
                  let host = url.host,
                  !host.isEmpty else {
                return false
            }
            return true
        }()

        let kind: ClipboardItemKind = isWebLink ? .link : .text
        let utf8Data = Data(rawText.utf8)
        let hash = ClipboardHistoryEntry.sha256Hex(Data("\(kind.rawValue)::\(rawText)".utf8))

        let entry = ClipboardHistoryEntry(
            kind: kind,
            contentHash: hash,
            textContent: rawText,
            byteSize: utf8Data.count,
            createdAt: now,
            lastCopiedAt: now,
            copyCount: 1,
            isPinned: false,
            sourceAppName: sourceAppName,
            sourceAppBundleID: sourceAppBundleID
        )
        return insertOrBumpEntry(entry, now: now)
    }

    /// Registra directamente una imagen (`NSImage`) en el historial del portapapeles guardando su PNG en disco.
    @discardableResult
    public func recordImage(
        _ image: NSImage,
        captionText: String? = nil,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        now: Date = Date()
    ) -> ClipboardHistoryEntry? {
        guard ClipboardHistoryPreferences.shared.isEnabled else { return nil }
        guard let normalized = Self.normalizedPNGAndDimensions(from: image) else { return nil }

        let hash = ClipboardHistoryEntry.sha256Hex(normalized.pngData)
        if let existingIdx = items.firstIndex(where: { $0.contentHash == hash && $0.kind == .image }) {
            var updated = items[existingIdx]
            updated.lastCopiedAt = now
            updated.copyCount += 1
            if let sourceAppName, !sourceAppName.isEmpty {
                updated.sourceAppName = sourceAppName
            }
            items.remove(at: existingIdx)
            insertSorted(updated)
            selectedEntryID = updated.id
            enforceRetentionPolicy(now: now)
            saveToDisk()
            return updated
        }

        ensureDirectoriesExist()
        let entryID = UUID()
        let fileName = "\(entryID.uuidString).png"
        let fileURL = imagesDirectoryURL.appendingPathComponent(fileName)
        do {
            try normalized.pngData.write(to: fileURL, options: .atomic)
        } catch {
            return nil
        }

        if let loadedImage = NSImage(data: normalized.pngData) {
            imageCache.setObject(loadedImage, forKey: fileName as NSString)
        }

        let cleanCaption: String? = {
            guard let captionText else { return nil }
            let t = captionText.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }()

        let entry = ClipboardHistoryEntry(
            id: entryID,
            kind: .image,
            contentHash: hash,
            textContent: cleanCaption,
            filePaths: [],
            imageFileName: fileName,
            imagePixelWidth: normalized.width,
            imagePixelHeight: normalized.height,
            byteSize: normalized.pngData.count,
            createdAt: now,
            lastCopiedAt: now,
            copyCount: 1,
            isPinned: false,
            sourceAppName: sourceAppName,
            sourceAppBundleID: sourceAppBundleID
        )
        return insertOrBumpEntry(entry, now: now)
    }

    /// Registra una lista de archivos o carpetas copiados al portapapeles (con miniatura si es un archivo de imagen).
    @discardableResult
    public func recordFileURLs(
        _ urls: [URL],
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        now: Date = Date()
    ) -> ClipboardHistoryEntry? {
        guard ClipboardHistoryPreferences.shared.isEnabled else { return nil }
        let standardizedPaths = urls
            .map { $0.standardizedFileURL.path(percentEncoded: false) }
            .filter { !$0.isEmpty }
        guard !standardizedPaths.isEmpty else { return nil }

        let joinedKey = "files::" + standardizedPaths.joined(separator: "\n")
        let hash = ClipboardHistoryEntry.sha256Hex(Data(joinedKey.utf8))

        if let existingIdx = items.firstIndex(where: { $0.contentHash == hash }) {
            var updated = items[existingIdx]
            updated.lastCopiedAt = now
            updated.copyCount += 1
            if let sourceAppName, !sourceAppName.isEmpty {
                updated.sourceAppName = sourceAppName
            }
            items.remove(at: existingIdx)
            insertSorted(updated)
            selectedEntryID = updated.id
            enforceRetentionPolicy(now: now)
            saveToDisk()
            return updated
        }

        var totalBytes = 0
        let fm = FileManager.default
        for path in standardizedPaths {
            if let attrs = try? fm.attributesOfItem(atPath: path),
               let size = attrs[.size] as? NSNumber {
                totalBytes += size.intValue
            }
        }

        let entryID = UUID()
        var previewFileName: String?
        var pixelW: Int?
        var pixelH: Int?

        // Si se copió un archivo de imagen individual, guardar también su vista previa PNG para mostrarla en el historial
        if standardizedPaths.count == 1,
           let firstPath = standardizedPaths.first {
            let ext = URL(fileURLWithPath: firstPath).pathExtension.lowercased()
            let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "tif", "bmp"]
            if imageExts.contains(ext),
               let fileImage = NSImage(contentsOfFile: firstPath),
               let normalized = Self.normalizedPNGAndDimensions(from: fileImage) {
                ensureDirectoriesExist()
                let fName = "\(entryID.uuidString).png"
                let fURL = imagesDirectoryURL.appendingPathComponent(fName)
                if (try? normalized.pngData.write(to: fURL, options: .atomic)) != nil {
                    previewFileName = fName
                    pixelW = normalized.width
                    pixelH = normalized.height
                    if let cached = NSImage(data: normalized.pngData) {
                        imageCache.setObject(cached, forKey: fName as NSString)
                    }
                }
            }
        }

        let entry = ClipboardHistoryEntry(
            id: entryID,
            kind: .files,
            contentHash: hash,
            textContent: standardizedPaths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", "),
            filePaths: standardizedPaths,
            imageFileName: previewFileName,
            imagePixelWidth: pixelW,
            imagePixelHeight: pixelH,
            byteSize: totalBytes,
            createdAt: now,
            lastCopiedAt: now,
            copyCount: 1,
            isPinned: false,
            sourceAppName: sourceAppName,
            sourceAppBundleID: sourceAppBundleID
        )
        return insertOrBumpEntry(entry, now: now)
    }

    // MARK: - Acciones sobre Entradas del Historial (Compatibles con Maccy)

    /// Copia cualquier entrada del historial de vuelta al portapapeles del sistema (`Enter` o clic, o `⌘1`..`⌘9`).
    public func copyEntryToPasteboard(
        _ entry: ClipboardHistoryEntry,
        plainTextOnly: Bool = false,
        targetPasteboard: NSPasteboard = .general
    ) {
        targetPasteboard.clearContents()

        switch entry.kind {
        case .image:
            if plainTextOnly, let text = entry.textContent, !text.isEmpty {
                targetPasteboard.setString(text, forType: .string)
            } else if let img = image(for: entry) {
                if let pngData = Self.normalizedPNGAndDimensions(from: img)?.pngData {
                    targetPasteboard.setData(pngData, forType: .png)
                }
                targetPasteboard.writeObjects([img])
            } else if let text = entry.textContent {
                targetPasteboard.setString(text, forType: .string)
            }

        case .files:
            if plainTextOnly {
                targetPasteboard.setString(entry.filePaths.joined(separator: "\n"), forType: .string)
            } else {
                let validURLs = entry.filePaths.map { URL(fileURLWithPath: $0) }
                targetPasteboard.writeObjects(validURLs as [NSURL])
            }

        case .link, .text:
            let text = entry.textContent ?? ""
            targetPasteboard.setString(text, forType: .string)
        }

        if targetPasteboard === NSPasteboard.general {
            lastSelfWrittenChangeCount = targetPasteboard.changeCount
            lastObservedChangeCount = targetPasteboard.changeCount
        }

        if let idx = items.firstIndex(where: { $0.id == entry.id }) {
            var updated = items.remove(at: idx)
            updated.lastCopiedAt = Date()
            updated.copyCount += 1
            insertSorted(updated)
            selectedEntryID = updated.id
            saveToDisk()
        }

        recentlyCopiedFeedbackEntryID = entry.id
        let feedbackID = entry.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1400))
            if self?.recentlyCopiedFeedbackEntryID == feedbackID {
                self?.recentlyCopiedFeedbackEntryID = nil
            }
        }
    }

    /// Alterna el estado fijado (`isPinned`) de una entrada (`⌥P` en Maccy).
    /// Los elementos fijados permanecen arriba y nunca se borran por antigüedad o límite de cantidad.
    public func togglePin(_ entryID: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == entryID }) else { return }
        var updated = items.remove(at: idx)
        updated.isPinned.toggle()
        insertSorted(updated)
        saveToDisk()
    }

    /// Elimina una entrada individual del historial (`⌥⌫` en Maccy) y borra su imagen asociada si existe.
    public func deleteEntry(_ entryID: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == entryID }) else { return }
        let removed = items.remove(at: idx)
        removeImageFileIfNeeded(for: removed)
        if selectedEntryID == entryID {
            selectedEntryID = filteredItems.first?.id
        }
        saveToDisk()
    }

    /// Limpia todos los elementos no fijados del historial (`⌥⌘⌫` en Maccy), conservando los fijados (`isPinned == true`).
    public func clearUnpinnedHistory() {
        let unpinned = items.filter { !$0.isPinned }
        for entry in unpinned {
            removeImageFileIfNeeded(for: entry)
        }
        items.removeAll { !$0.isPinned }
        selectedEntryID = filteredItems.first?.id
        saveToDisk()
    }

    /// Borra absolutamente todo el historial del portapapeles (incluyendo fijados si `includePinned == true`).
    public func clearAllHistory(includePinned: Bool = true) {
        if !includePinned {
            clearUnpinnedHistory()
            return
        }
        for entry in items {
            removeImageFileIfNeeded(for: entry)
        }
        items.removeAll()
        selectedEntryID = nil
        saveToDisk()
    }

    // MARK: - Política de Retención por Tiempo y por Cantidad Máxima

    /// Aplica inmediatamente las reglas configuradas de tiempo de guardado y cantidad máxima sobre los ítems no fijados.
    public func enforceRetentionPolicy(now: Date = Date()) {
        let prefs = ClipboardHistoryPreferences.shared
        let maxInterval = prefs.retentionPeriod.timeInterval
        let maxCount = prefs.maxItemsOption.rawValue

        var pinned: [ClipboardHistoryEntry] = []
        var unpinned: [ClipboardHistoryEntry] = []

        for item in items {
            if item.isPinned {
                pinned.append(item)
            } else {
                unpinned.append(item)
            }
        }

        pinned.sort { $0.lastCopiedAt > $1.lastCopiedAt }
        unpinned.sort { $0.lastCopiedAt > $1.lastCopiedAt }

        var keptUnpinned: [ClipboardHistoryEntry] = []
        var removedEntries: [ClipboardHistoryEntry] = []

        for item in unpinned {
            if let maxInterval, now.timeIntervalSince(item.lastCopiedAt) > maxInterval {
                removedEntries.append(item)
                continue
            }
            if maxCount > 0 && keptUnpinned.count >= maxCount {
                removedEntries.append(item)
                continue
            }
            keptUnpinned.append(item)
        }

        if !removedEntries.isEmpty {
            for removed in removedEntries {
                removeImageFileIfNeeded(for: removed)
            }
        }

        items = pinned + keptUnpinned
        if let selectedEntryID, !items.contains(where: { $0.id == selectedEntryID }) {
            self.selectedEntryID = filteredItems.first?.id
        }
        saveToDisk()
    }

    // MARK: - Obtención y Exportación de Imágenes del Historial

    /// Carga la `NSImage` asociada a una entrada del historial (desde caché en memoria o desde el archivo PNG en disco).
    public func image(for entry: ClipboardHistoryEntry) -> NSImage? {
        guard let fileName = entry.imageFileName, !fileName.isEmpty else { return nil }
        if let cached = imageCache.object(forKey: fileName as NSString) {
            return cached
        }
        let fileURL = imagesDirectoryURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)),
              let loaded = NSImage(contentsOf: fileURL) else {
            return nil
        }
        imageCache.setObject(loaded, forKey: fileName as NSString)
        return loaded
    }

    /// Devuelve la URL en disco del archivo PNG de una entrada de imagen del historial.
    public func imageFileURL(for entry: ClipboardHistoryEntry) -> URL? {
        guard let fileName = entry.imageFileName, !fileName.isEmpty else { return nil }
        let url = imagesDirectoryURL.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    /// Abre un diálogo `NSSavePanel` para guardar una imagen del historial como archivo `.png`.
    public func exportImageWithSavePanel(for entry: ClipboardHistoryEntry) {
        guard let sourceURL = imageFileURL(for: entry),
              let pngData = try? Data(contentsOf: sourceURL) else { return }

        let loc = LocalizationManager.shared
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        panel.nameFieldStringValue = "Clipboard_\(formatter.string(from: entry.lastCopiedAt)).png"
        panel.title = loc.text(es: "Guardar imagen del portapapeles", en: "Save Clipboard Image")

        if panel.runModal() == .OK, let targetURL = panel.url {
            try? pngData.write(to: targetURL, options: .atomic)
        }
    }

    // MARK: - Helpers Internos de Inserción y Persistencia

    private func insertOrBumpEntry(_ newEntry: ClipboardHistoryEntry, now: Date) -> ClipboardHistoryEntry {
        if let existingIdx = items.firstIndex(where: { $0.contentHash == newEntry.contentHash }) {
            var updated = items.remove(at: existingIdx)
            updated.lastCopiedAt = now
            updated.copyCount += 1
            if let app = newEntry.sourceAppName, !app.isEmpty {
                updated.sourceAppName = app
            }
            if let bundle = newEntry.sourceAppBundleID, !bundle.isEmpty {
                updated.sourceAppBundleID = bundle
            }
            // Si habíamos creado un archivo de imagen duplicado temporal, limpiarlo y conservar el original
            if let newImg = newEntry.imageFileName, newImg != updated.imageFileName {
                removeImageFileIfNeeded(for: newEntry)
            }
            insertSorted(updated)
            selectedEntryID = updated.id
            enforceRetentionPolicy(now: now)
            saveToDisk()
            return updated
        }

        insertSorted(newEntry)
        selectedEntryID = newEntry.id
        enforceRetentionPolicy(now: now)
        saveToDisk()
        return newEntry
    }

    private func insertSorted(_ entry: ClipboardHistoryEntry) {
        if entry.isPinned {
            let insertIdx = items.firstIndex(where: { !$0.isPinned || $0.lastCopiedAt < entry.lastCopiedAt }) ?? items.endIndex
            items.insert(entry, at: insertIdx)
        } else {
            let insertIdx = items.firstIndex(where: { !$0.isPinned && $0.lastCopiedAt < entry.lastCopiedAt }) ?? items.endIndex
            items.insert(entry, at: insertIdx)
        }
    }

    private func extractImageFromPasteboard(_ pasteboard: NSPasteboard) -> NSImage? {
        if let pngData = pasteboard.data(forType: .png),
           let image = NSImage(data: pngData),
           image.size.width > 0, image.size.height > 0 {
            return image
        }
        if let tiffData = pasteboard.data(forType: .tiff),
           let image = NSImage(data: tiffData),
           image.size.width > 0, image.size.height > 0 {
            return image
        }
        if NSImage.canInit(with: pasteboard),
           let image = NSImage(pasteboard: pasteboard),
           image.size.width > 0, image.size.height > 0 {
            return image
        }
        return nil
    }

    public static func normalizedPNGAndDimensions(from image: NSImage) -> (pngData: Data, width: Int, height: Int)? {
        if let bitmapRep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
           bitmapRep.pixelsWide > 0, bitmapRep.pixelsHigh > 0,
           let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            return (pngData, bitmapRep.pixelsWide, bitmapRep.pixelsHigh)
        }
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let pngData = rep.representation(using: .png, properties: [:]),
           rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return (pngData, rep.pixelsWide, rep.pixelsHigh)
        }
        var proposedRect = NSRect(origin: .zero, size: image.size)
        if let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
           cgImage.width > 0, cgImage.height > 0 {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            if let pngData = rep.representation(using: .png, properties: [:]) {
                return (pngData, cgImage.width, cgImage.height)
            }
        }
        return nil
    }

    private func ensureDirectoriesExist() {
        let fm = FileManager.default
        try? fm.createDirectory(at: storageDirectoryURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true)
    }

    private func removeImageFileIfNeeded(for entry: ClipboardHistoryEntry) {
        guard let fileName = entry.imageFileName, !fileName.isEmpty else { return }
        imageCache.removeObject(forKey: fileName as NSString)
        let url = imagesDirectoryURL.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    private func saveToDisk() {
        ensureDirectoriesExist()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: historyFileURL, options: .atomic)
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: historyFileURL.path(percentEncoded: false)),
              let data = try? Data(contentsOf: historyFileURL) else {
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([ClipboardHistoryEntry].self, from: data) {
            self.items = decoded
            self.selectedEntryID = decoded.first?.id
        }
    }
}
