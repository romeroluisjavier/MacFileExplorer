import AppKit
import CoreGraphics
import Foundation
import Observation
@preconcurrency import ScreenCaptureKit

/// Servicio compartido de captura de miniaturas y vistas previas a tamaño completo usando `ScreenCaptureKit`
/// (`SCScreenshotManager`, macOS 14+), reutilizado tanto por **Barra de tareas (`Taskbar`)** como por **AltTab**.
///
/// Optimizaciones de performance:
/// - Caché LRU única de 64 miniaturas (evita duplicar memoria y capturas entre Taskbar y AltTab).
/// - Pre-calentamiento por evento al perder foco (0% CPU en reposo; las miniaturas ya están en RAM al abrir AltTab).
/// - Captura en lote con concurrencia acotada (`maxConcurrency = 4`) para refrescar sin saturar GPU/WindowServer.
/// - Caché dedicada de vistas previas full-size (hasta 6 entradas, TTL breve) para AltTab.
@MainActor
@Observable
public final class TaskbarThumbnailService {

    public static let shared = TaskbarThumbnailService()

    public private(set) var hasScreenRecordingPermission: Bool = CGPreflightScreenCaptureAccess()

    /// Contador reactivo incrementado cuando llega una nueva miniatura a caché para refrescar tarjetas de AltTab/Taskbar.
    public private(set) var cacheRevision: UInt64 = 0

    private struct CachedThumbnail {
        let image: NSImage
        let capturedAt: Date
        let maxDimension: CGFloat
    }

    private var cache: [CGWindowID: CachedThumbnail] = [:]
    private var lruOrder: [CGWindowID] = []
    private let maxCachedEntries = 64

    private var fullSizeCache: [CGWindowID: CachedThumbnail] = [:]
    private var fullSizeLRU: [CGWindowID] = []
    private let maxFullSizeEntries = 6

    private var cachedShareableWindows: [SCWindow] = []
    private var shareableContentFetchedAt: Date = .distantPast
    private var inFlightShareableTask: Task<[SCWindow], Error>?
    private var inFlightThumbnailTasks: [CGWindowID: Task<NSImage?, Never>] = [:]
    private var inFlightPrewarmIDs: Set<CGWindowID> = []

    private init() {}

    // MARK: - Permiso Opcional de Grabación de Pantalla

    @discardableResult
    public func refreshPermissionStatus() -> Bool {
        let granted = CGPreflightScreenCaptureAccess()
        hasScreenRecordingPermission = granted
        return granted
    }

    @discardableResult
    public func requestScreenRecordingPermission() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        hasScreenRecordingPermission = granted
        if !granted {
            openScreenRecordingSettings()
        }
        return granted
    }

    public func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Lectura y Limpieza de Caché Compartida

    public func cachedThumbnail(for windowID: CGWindowID) -> NSImage? {
        cache[windowID]?.image
    }

    /// Indica si ya existe una miniatura suficientemente reciente en RAM para evitar recapturas innecesarias.
    public func hasFreshThumbnail(for windowID: CGWindowID, maxAge: TimeInterval = 2.0, minDimension: CGFloat = 0) -> Bool {
        guard let entry = cache[windowID] else { return false }
        return Date().timeIntervalSince(entry.capturedAt) < maxAge && entry.maxDimension >= minDimension * 0.85
    }

    public func cachedFullSizePreview(for windowID: CGWindowID) -> NSImage? {
        if let full = fullSizeCache[windowID]?.image {
            return full
        }
        return cache[windowID]?.image
    }

    public func purgeClosedWindows(keeping liveWindowIDs: Set<CGWindowID>) {
        cache = cache.filter { liveWindowIDs.contains($0.key) }
        lruOrder.removeAll { !liveWindowIDs.contains($0) }
        fullSizeCache = fullSizeCache.filter { liveWindowIDs.contains($0.key) }
        fullSizeLRU.removeAll { !liveWindowIDs.contains($0) }
    }

    public func clearCache() {
        cache.removeAll()
        lruOrder.removeAll()
        fullSizeCache.removeAll()
        fullSizeLRU.removeAll()
        cachedShareableWindows.removeAll()
        shareableContentFetchedAt = .distantPast
        inFlightShareableTask?.cancel()
        inFlightShareableTask = nil
        for task in inFlightThumbnailTasks.values {
            task.cancel()
        }
        inFlightThumbnailTasks.removeAll()
        inFlightPrewarmIDs.removeAll()
        cacheRevision &+= 1
    }

    // MARK: - Pre-calentamiento Dirigido por Eventos (0% CPU en Reposo)

    /// Captura en segundo plano la miniatura de una ventana que acaba de perder foco o cambiar,
    /// dejándola lista en RAM para cuando el usuario pulse `⌥⇥` o pase el mouse por la barra.
    public func prewarmThumbnailInBackground(for windowID: CGWindowID, maxDimension: CGFloat = 340) {
        guard windowID != 0,
              !inFlightPrewarmIDs.contains(windowID),
              refreshPermissionStatus() else {
            return
        }
        if let existing = cache[windowID], Date().timeIntervalSince(existing.capturedAt) < 2.0 {
            return
        }
        inFlightPrewarmIDs.insert(windowID)
        Task { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.inFlightPrewarmIDs.remove(windowID)
                }
            }
            _ = await self?.captureThumbnail(for: windowID, maxDimension: maxDimension, isMinimized: false)
        }
    }

    /// Refresca concurrentemente (con concurrencia acotada) un conjunto de ventanas visibles al abrir AltTab.
    public func refreshThumbnailsBatch(
        items: [(windowID: CGWindowID, isMinimized: Bool)],
        maxDimension: CGFloat = 340,
        maxConcurrency: Int = 4
    ) async {
        guard refreshPermissionStatus(), !items.isEmpty else { return }
        let eligible = items.filter { $0.windowID != 0 && !$0.isMinimized }
        guard !eligible.isEmpty else { return }

        // Pre-cargar SCShareableContent una sola vez para todo el lote
        guard let scWindows = try? await fetchShareableWindowsIfNeeded(force: true) else { return }
        let scByID = Dictionary(scWindows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })

        let now = Date()
        var pending: [(CGWindowID, SCWindow)] = []
        for entry in eligible {
            if let existing = cache[entry.windowID],
               Date().timeIntervalSince(existing.capturedAt) < 1.2,
               existing.maxDimension >= maxDimension * 0.85 {
                continue
            }
            if let scWin = scByID[entry.windowID] {
                pending.append((entry.windowID, scWin))
            }
        }
        _ = now
        guard !pending.isEmpty else { return }

        // Procesar en bloques pequeños para mantener fluidez máxima en el HUD
        let batchSize = max(1, maxConcurrency)
        var offset = 0
        while offset < pending.count {
            if Task.isCancelled { return }
            let end = min(offset + batchSize, pending.count)
            let slice = Array(pending[offset..<end])
            await withTaskGroup(of: (CGWindowID, NSImage?).self) { group in
                for (winID, scWin) in slice {
                    group.addTask {
                        let img = await Self.renderSCWindowImage(scWindow: scWin, maxDimension: maxDimension, retinaScale: 2.0)
                        return (winID, img)
                    }
                }
                for await (winID, img) in group {
                    if let img {
                        self.storeThumbnail(image: img, for: winID, maxDimension: maxDimension)
                    }
                }
            }
            offset = end
        }
    }

    // MARK: - Captura Individual de Miniatura y Vista Previa Full-Size

    /// Captura una miniatura actualizada para `windowID` respetando `maxDimension` (puntos lógicos, Retina).
    /// Coalesce capturas simultáneas del mismo `windowID` (ej. prefetch al entrar el cursor + apertura del popover)
    /// para eliminar trabajo duplicado y reducir la latencia percibida a casi 0 ms.
    public func captureThumbnail(
        for windowID: CGWindowID,
        maxDimension: CGFloat,
        isMinimized: Bool = false,
        maxCacheAge: TimeInterval = 1.8
    ) async -> NSImage? {
        guard windowID != 0 else { return nil }
        guard refreshPermissionStatus() else {
            return nil
        }

        if isMinimized, let existing = cache[windowID]?.image {
            return existing
        }

        if let existing = cache[windowID],
           Date().timeIntervalSince(existing.capturedAt) < maxCacheAge,
           existing.maxDimension >= maxDimension * 0.85 {
            return existing.image
        }

        if let existingTask = inFlightThumbnailTasks[windowID] {
            return await existingTask.value
        }

        let retinaScale = min(2.0, max(1.0, NSScreen.main?.backingScaleFactor ?? 2.0))
        let task = Task<NSImage?, Never> { [weak self] in
            guard let self else { return nil }
            defer {
                self.inFlightThumbnailTasks.removeValue(forKey: windowID)
            }
            do {
                let scWindows = try await self.fetchShareableWindowsIfNeeded(force: false)
                guard let targetWindow = scWindows.first(where: { $0.windowID == windowID }) else {
                    return self.cache[windowID]?.image
                }
                guard let image = await Self.renderSCWindowImage(
                    scWindow: targetWindow,
                    maxDimension: maxDimension,
                    retinaScale: retinaScale
                ) else {
                    return self.cache[windowID]?.image
                }
                self.storeThumbnail(image: image, for: windowID, maxDimension: maxDimension)
                return image
            } catch {
                return self.cache[windowID]?.image
            }
        }
        inFlightThumbnailTasks[windowID] = task
        return await task.value
    }

    /// Captura una vista previa en alta resolución a tamaño completo para el overlay full-size de AltTab.
    public func captureFullSizePreview(
        for windowID: CGWindowID,
        maxScreenDimension: CGFloat,
        isMinimized: Bool = false
    ) async -> NSImage? {
        guard windowID != 0 else { return nil }
        guard refreshPermissionStatus() else { return nil }

        if isMinimized {
            return fullSizeCache[windowID]?.image ?? cache[windowID]?.image
        }

        if let existing = fullSizeCache[windowID],
           Date().timeIntervalSince(existing.capturedAt) < 1.8 {
            return existing.image
        }

        do {
            let scWindows = try await fetchShareableWindowsIfNeeded(force: false)
            guard let targetWindow = scWindows.first(where: { $0.windowID == windowID }) else {
                return fullSizeCache[windowID]?.image ?? cache[windowID]?.image
            }
            let targetDim = min(maxScreenDimension, max(targetWindow.frame.width, targetWindow.frame.height))
            // Usar escala 1.5x para balance perfecto entre nitidez cristalina y velocidad (~20ms)
            guard let image = await Self.renderSCWindowImage(scWindow: targetWindow, maxDimension: max(400, targetDim), retinaScale: 1.5) else {
                return fullSizeCache[windowID]?.image ?? cache[windowID]?.image
            }
            storeFullSize(image: image, for: windowID, maxDimension: targetDim)
            return image
        } catch {
            return fullSizeCache[windowID]?.image ?? cache[windowID]?.image
        }
    }

    private nonisolated static func renderSCWindowImage(
        scWindow: SCWindow,
        maxDimension: CGFloat,
        retinaScale: CGFloat
    ) async -> NSImage? {
        let sourceFrame = scWindow.frame
        guard sourceFrame.width >= 20, sourceFrame.height >= 20 else { return nil }

        let aspect = sourceFrame.width / max(sourceFrame.height, 1)
        let logicalWidth: CGFloat
        let logicalHeight: CGFloat
        if aspect >= 1.0 {
            logicalWidth = min(maxDimension, sourceFrame.width)
            logicalHeight = max(60, logicalWidth / aspect)
        } else {
            logicalHeight = min(maxDimension, sourceFrame.height)
            logicalWidth = max(60, logicalHeight * aspect)
        }

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let config = SCStreamConfiguration()
        config.width = max(1, Int((logicalWidth * retinaScale).rounded()))
        config.height = max(1, Int((logicalHeight * retinaScale).rounded()))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.scalesToFit = true

        guard let cgImage = try? await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        ) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: logicalWidth, height: logicalHeight))
    }

    private func fetchShareableWindowsIfNeeded(force: Bool) async throws -> [SCWindow] {
        let now = Date()
        if !force && !cachedShareableWindows.isEmpty && now.timeIntervalSince(shareableContentFetchedAt) < 1.5 {
            return cachedShareableWindows
        }
        if !force, let activeTask = inFlightShareableTask {
            return try await activeTask.value
        }
        let task = Task<[SCWindow], Error> {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            return content.windows
        }
        inFlightShareableTask = task
        do {
            let windows = try await task.value
            inFlightShareableTask = nil
            cachedShareableWindows = windows
            shareableContentFetchedAt = Date()
            return windows
        } catch {
            inFlightShareableTask = nil
            throw error
        }
    }

    private func storeThumbnail(image: NSImage, for windowID: CGWindowID, maxDimension: CGFloat) {
        cache[windowID] = CachedThumbnail(image: image, capturedAt: Date(), maxDimension: maxDimension)
        lruOrder.removeAll { $0 == windowID }
        lruOrder.append(windowID)
        while lruOrder.count > maxCachedEntries {
            let evicted = lruOrder.removeFirst()
            cache.removeValue(forKey: evicted)
        }
        cacheRevision &+= 1
    }

    private func storeFullSize(image: NSImage, for windowID: CGWindowID, maxDimension: CGFloat) {
        fullSizeCache[windowID] = CachedThumbnail(image: image, capturedAt: Date(), maxDimension: maxDimension)
        fullSizeLRU.removeAll { $0 == windowID }
        fullSizeLRU.append(windowID)
        while fullSizeLRU.count > maxFullSizeEntries {
            let evicted = fullSizeLRU.removeFirst()
            fullSizeCache.removeValue(forKey: evicted)
        }
        cacheRevision &+= 1
    }
}
