import AppKit
import Foundation
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Entrada individual dentro del archivo oculto de caché de miniaturas por carpeta (`.macfileexplorer_thumbs.cache`).
public struct ThumbnailCacheEntry: Codable, Sendable {
    public let modificationTimestamp: TimeInterval
    public let fileSize: Int64
    public let pngOrJpegData: Data

    public init(modificationTimestamp: TimeInterval, fileSize: Int64, pngOrJpegData: Data) {
        self.modificationTimestamp = modificationTimestamp
        self.fileSize = fileSize
        self.pngOrJpegData = pngOrJpegData
    }
}

/// Archivo contenedor serializado en binario que se guarda oculto en cada carpeta (`.macfileexplorer_thumbs.cache`).
public struct FolderThumbnailArchive: Codable, Sendable {
    public var version: Int = 1
    public var entries: [String: ThumbnailCacheEntry]

    public init(version: Int = 1, entries: [String: ThumbnailCacheEntry] = [:]) {
        self.version = version
        self.entries = entries
    }
}

/// Actor de almacenamiento y generación de miniaturas en segundo plano.
/// Lee y escribe un archivo oculto `.macfileexplorer_thumbs.cache` dentro de cada carpeta
/// (con fallback en `~/Library/Caches` si la carpeta es de solo lectura) para que las aperturas
/// posteriores carguen todas las miniaturas de forma instantánea en una sola lectura de disco.
actor ThumbnailDiskCoordinator {
    static let shared = ThumbnailDiskCoordinator()

    /// Nombre del archivo oculto guardado en la misma carpeta (estilo `Thumbs.db` / `.DS_Store`).
    static let hiddenCacheFileName = ".macfileexplorer_thumbs.cache"

    /// Archivos de caché cargados en memoria por URL de carpeta estandarizada.
    private var loadedArchives: [URL: FolderThumbnailArchive] = [:]

    /// Carpetas que tienen cambios pendientes de persistir en disco.
    private var dirtyFolders: Set<URL> = []

    /// Tareas de guardado diferido (debounce) por carpeta para agrupar escrituras.
    private var saveTasks: [URL: Task<Void, Never>] = [:]

    /// Semáforo ligero de concurrencia para limitar decodificaciones simultáneas en carpetas con cientos de fotos.
    private var activeGenerationCount: Int = 0
    private var generationWaiters: [CheckedContinuation<Void, Never>] = []
    private let maxConcurrentGenerations: Int = 6

    // MARK: - Carga de Caché de Carpeta

    /// Carga en memoria el archivo `.macfileexplorer_thumbs.cache` de la carpeta indicada si aún no está cargado.
    func ensureFolderArchiveLoaded(for folderURL: URL) -> FolderThumbnailArchive {
        let dir = folderURL.standardizedFileURL
        if let existing = loadedArchives[dir] {
            return existing
        }

        let localCacheURL = dir.appendingPathComponent(Self.hiddenCacheFileName)
        let fallbackURL = fallbackCacheFileURL(for: dir)

        let decoder = PropertyListDecoder()
        if let data = try? Data(contentsOf: localCacheURL, options: [.mappedIfSafe]),
           let archive = try? decoder.decode(FolderThumbnailArchive.self, from: data) {
            loadedArchives[dir] = archive
            return archive
        }

        if let data = try? Data(contentsOf: fallbackURL, options: [.mappedIfSafe]),
           let archive = try? decoder.decode(FolderThumbnailArchive.self, from: data) {
            loadedArchives[dir] = archive
            return archive
        }

        let empty = FolderThumbnailArchive()
        loadedArchives[dir] = empty
        return empty
    }

    /// Obtiene los bytes comprimidos de la miniatura si existen en el archivo oculto de la carpeta y siguen vigentes.
    func cachedThumbnailData(for item: FileItem) -> Data? {
        let dir = item.url.deletingLastPathComponent().standardizedFileURL
        let archive = ensureFolderArchiveLoaded(for: dir)
        guard let entry = archive.entries[item.name] else { return nil }

        let itemSize = item.size ?? 0
        let modDiff = abs(entry.modificationTimestamp - item.modificationDate.timeIntervalSince1970)
        guard entry.fileSize == itemSize && modDiff < 1.0 else {
            return nil
        }
        return entry.pngOrJpegData
    }

    /// Genera la miniatura en segundo plano y actualiza el archivo oculto `.macfileexplorer_thumbs.cache` de la carpeta.
    func generateAndStoreThumbnailData(for item: FileItem, maxPixelSize: Int) async -> Data? {
        if let existing = cachedThumbnailData(for: item) {
            return existing
        }

        await acquireGenerationSlot()
        defer { releaseGenerationSlot() }

        if Task.isCancelled { return nil }

        // Intentar primero extracción ultra-rápida con ImageIO (submuestreo directo sin cargar los 15MB en RAM)
        var cgImage = Self.createFastImageIOThumbnail(at: item.url, maxPixelSize: maxPixelSize)

        // Si no es imagen directa (ej. PDF o video), usar QuickLookThumbnailing
        if cgImage == nil {
            cgImage = await Self.createQuickLookThumbnail(at: item.url, maxPixelSize: CGFloat(maxPixelSize))
        }

        guard let validCGImage = cgImage else {
            return nil
        }

        guard let encodedData = Self.encodeThumbnail(cgImage: validCGImage, hasAlpha: Self.imageHasAlpha(validCGImage)) else {
            return nil
        }

        // Guardar en el archivo en memoria de la carpeta y programar escritura en `.macfileexplorer_thumbs.cache`
        let dir = item.url.deletingLastPathComponent().standardizedFileURL
        var archive = ensureFolderArchiveLoaded(for: dir)
        archive.entries[item.name] = ThumbnailCacheEntry(
            modificationTimestamp: item.modificationDate.timeIntervalSince1970,
            fileSize: item.size ?? 0,
            pngOrJpegData: encodedData
        )
        loadedArchives[dir] = archive
        scheduleSave(for: dir)

        return encodedData
    }

    // MARK: - Guardado Diferido en `.macfileexplorer_thumbs.cache`

    private func scheduleSave(for folderURL: URL) {
        let dir = folderURL.standardizedFileURL
        dirtyFolders.insert(dir)
        saveTasks[dir]?.cancel()

        saveTasks[dir] = Task {
            try? await Task.sleep(nanoseconds: 350_000_000) // Agrupar escrituras durante 350ms
            guard !Task.isCancelled else { return }
            self.flushFolderArchive(for: dir)
        }
    }

    private func flushFolderArchive(for folderURL: URL) {
        let dir = folderURL.standardizedFileURL
        guard dirtyFolders.contains(dir), let archive = loadedArchives[dir] else { return }
        dirtyFolders.remove(dir)
        saveTasks[dir] = nil

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let encoded = try? encoder.encode(archive) else { return }

        var localCacheURL = dir.appendingPathComponent(Self.hiddenCacheFileName)
        var tempCacheURL = dir.appendingPathComponent("\(Self.hiddenCacheFileName).tmp.\(UUID().uuidString)")
        do {
            try encoded.write(to: tempCacheURL, options: [])
            // Asegurar atributo oculto además del prefijo '.'
            var resourceValues = URLResourceValues()
            resourceValues.isHidden = true
            try? tempCacheURL.setResourceValues(resourceValues)
            if rename(tempCacheURL.path(percentEncoded: false), localCacheURL.path(percentEncoded: false)) != 0 {
                try? FileManager.default.removeItem(at: tempCacheURL)
                try encoded.write(to: localCacheURL, options: [.atomic])
            }
            try? localCacheURL.setResourceValues(resourceValues)
        } catch {
            try? FileManager.default.removeItem(at: tempCacheURL)
            // Si la carpeta no tiene permisos de escritura (ej. volumen de solo lectura), guardar en ~/Library/Caches
            let fallbackURL = fallbackCacheFileURL(for: dir)
            try? FileManager.default.createDirectory(
                at: fallbackURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? encoded.write(to: fallbackURL, options: [.atomic])
        }
    }

    private func fallbackCacheFileURL(for folderURL: URL) -> URL {
        let cachesRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folderPath = folderURL.standardizedFileURL.path(percentEncoded: false)
        // Hash determinista FNV-1a de 64 bits para identificar la carpeta
        var hash: UInt64 = 14695981039346656037
        for byte in folderPath.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        let fileName = String(format: "thumbs_%016llx.cache", hash)
        return cachesRoot
            .appendingPathComponent("MacFileExplorer/Thumbnails", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    // MARK: - Control de Concurrencia

    private func acquireGenerationSlot() async {
        if activeGenerationCount < maxConcurrentGenerations {
            activeGenerationCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            generationWaiters.append(continuation)
        }
    }

    private func releaseGenerationSlot() {
        if !generationWaiters.isEmpty {
            let next = generationWaiters.removeFirst()
            next.resume()
        } else {
            activeGenerationCount = max(0, activeGenerationCount - 1)
        }
    }

    // MARK: - Generación Rápida con ImageIO y QuickLook

    private static func createFastImageIOThumbnail(at url: URL, maxPixelSize: Int) -> CGImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
    }

    private static func createQuickLookThumbnail(at url: URL, maxPixelSize: CGFloat) async -> CGImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: maxPixelSize, height: maxPixelSize),
            scale: 1.0,
            representationTypes: .thumbnail
        )
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.cgImage)
            }
        }
    }

    private static func imageHasAlpha(_ cgImage: CGImage) -> Bool {
        switch cgImage.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        default:
            return false
        }
    }

    private static func encodeThumbnail(cgImage: CGImage, hasAlpha: Bool) -> Data? {
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        if hasAlpha {
            return bitmapRep.representation(using: .png, properties: [:])
        } else {
            return bitmapRep.representation(
                using: .jpeg,
                properties: [.compressionFactor: 0.78]
            )
        }
    }
}

// MARK: - Servicio Principal de Miniaturas para SwiftUI (`@MainActor`)

@MainActor
public final class ThumbnailCacheService {
    public static let shared = ThumbnailCacheService()

    /// Nombre del archivo oculto de caché por carpeta para que `FileSystemService` lo ignore en el listado.
    public static let cacheFileName = ThumbnailDiskCoordinator.hiddenCacheFileName

    private let memoryCache = NSCache<NSString, NSImage>()

    private static let supportedImageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tiff", "tif",
        "bmp", "icns", "ico", "svg", "raw", "cr2", "nef", "arw", "dng", "orf", "rw2"
    ]

    private static let supportedDocumentAndVideoExtensions: Set<String> = [
        "pdf", "mp4", "mov", "m4v"
    ]

    private init() {
        memoryCache.countLimit = 1500
    }

    /// Determina si un `FileItem` debe mostrar miniatura visual en la vista de Iconos Grandes.
    public func supportsThumbnail(for item: FileItem) -> Bool {
        guard !item.isNavigableFolder && !item.isPackage else { return false }
        let ext = item.fileExtension.lowercased()
        if Self.supportedImageExtensions.contains(ext) || Self.supportedDocumentAndVideoExtensions.contains(ext) {
            return true
        }
        if let contentType = item.contentType {
            return contentType.conforms(to: .image) || contentType.conforms(to: .movie) || contentType.conforms(to: .pdf)
        }
        return false
    }

    /// Devuelve la miniatura desde la RAM de forma síncrona si ya fue cargada (0ms de latencia).
    public func memoryCachedThumbnail(for item: FileItem) -> NSImage? {
        let key = memoryKey(for: item)
        return memoryCache.object(forKey: key as NSString)
    }

    /// Precarga en segundo plano el archivo `.macfileexplorer_thumbs.cache` de una carpeta y calienta
    /// los primeros elementos visibles en RAM sin bloquear la apertura del directorio.
    public func preloadFolderThumbnails(for directoryURL: URL, items: [FileItem]) async {
        let candidates = items.filter { supportsThumbnail(for: $0) }
        guard !candidates.isEmpty else { return }

        _ = await ThumbnailDiskCoordinator.shared.ensureFolderArchiveLoaded(for: directoryURL)

        let preloadLimit = min(candidates.count, 120)
        for index in 0..<preloadLimit {
            if Task.isCancelled { break }
            let item = candidates[index]
            if memoryCachedThumbnail(for: item) != nil { continue }

            if let data = await ThumbnailDiskCoordinator.shared.cachedThumbnailData(for: item),
               let image = NSImage(data: data) {
                memoryCache.setObject(image, forKey: memoryKey(for: item) as NSString)
            }

            if index > 0 && index % 20 == 0 {
                await Task.yield()
            }
        }
    }

    /// Obtiene o genera asíncronamente la miniatura de un archivo, guardándola en `.macfileexplorer_thumbs.cache`.
    public func thumbnail(for item: FileItem, maxPixelSize: Int = 160) async -> NSImage? {
        if let inMemory = memoryCachedThumbnail(for: item) {
            return inMemory
        }

        // 1. Verificar primero si está en el archivo oculto `.macfileexplorer_thumbs.cache` de la carpeta
        if let cachedData = await ThumbnailDiskCoordinator.shared.cachedThumbnailData(for: item),
           let image = NSImage(data: cachedData) {
            memoryCache.setObject(image, forKey: memoryKey(for: item) as NSString)
            return image
        }

        // 2. Generar miniatura en segundo plano y persistir en `.macfileexplorer_thumbs.cache`
        guard let generatedData = await ThumbnailDiskCoordinator.shared.generateAndStoreThumbnailData(
            for: item,
            maxPixelSize: maxPixelSize
        ), let image = NSImage(data: generatedData) else {
            return nil
        }

        memoryCache.setObject(image, forKey: memoryKey(for: item) as NSString)
        return image
    }

    private func memoryKey(for item: FileItem) -> String {
        "\(item.url.path(percentEncoded: false))::\(Int(item.modificationDate.timeIntervalSince1970))::\(item.size ?? 0)"
    }
}
