import Foundation
import UniformTypeIdentifiers

/// Clave ligera de ordenamiento/visibilidad para reutilizar la lista ya ordenada en RAM en 0 ms.
public struct DirectorySortCacheKey: Equatable, Hashable, Sendable {
    public let showHiddenFiles: Bool
    public let sortField: FileItem.SortField
    public let sortAscending: Bool

    public init(showHiddenFiles: Bool, sortField: FileItem.SortField, sortAscending: Bool) {
        self.showHiddenFiles = showHiddenFiles
        self.sortField = sortField
        self.sortAscending = sortAscending
    }
}

/// Resultado síncrono desde la caché caliente en RAM (0 ms, sin salto de actor ni parpadeo de carga).
public struct SynchronousDirectoryCacheHit: Sendable {
    public let items: [FileItem]
    public let sortedItems: [FileItem]?
    public let sortKey: DirectorySortCacheKey?
    public let isFolderTimestampFresh: Bool
}

/// Entrada compacta serializable de cada archivo o carpeta dentro de `.macfileexplorer_dir.cache`.
private struct CachedFileEntry: Codable, Sendable {
    let name: String
    let isDirectory: Bool
    let isPackage: Bool
    let isHidden: Bool
    let isSymbolicLink: Bool
    let modificationTimestamp: TimeInterval
    let creationTimestamp: TimeInterval
    let size: Int64?
    let utTypeIdentifier: String?
    let kindDescription: String
}

/// Instantánea serializada en binario por carpeta para acelerar aperturas posteriores de directorios grandes.
private struct CachedDirectoryArchive: Codable, Sendable {
    var version: Int = 1
    let folderModificationTimestamp: TimeInterval
    let entries: [CachedFileEntry]
}

/// Resultado de lectura de caché temporal de directorio.
public struct DirectoryCacheLookupResult: Sendable {
    public let items: [FileItem]
    public let isFolderTimestampFresh: Bool
}

/// Caché caliente en RAM protegida por `NSLock` para lectura síncrona O(1) en `@MainActor`
/// al volver a cualquier carpeta ya visitada (0 ms, sin salto de `actor` ni spinner de carga).
private final class HotDirectoryMemoryCache: @unchecked Sendable {
    struct Entry {
        var items: [FileItem]
        var sortedItems: [FileItem]?
        var sortKey: DirectorySortCacheKey?
        var folderModificationTimestamp: TimeInterval
    }

    private let lock = NSLock()
    private var entries: [URL: Entry] = [:]
    private var accessOrder: [URL] = []
    private let maxEntries = 96

    func lookup(for dir: URL) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[dir] else { return nil }
        touchLocked(dir)
        return entry
    }

    func store(
        items: [FileItem],
        sortedItems: [FileItem]?,
        sortKey: DirectorySortCacheKey?,
        folderModificationTimestamp: TimeInterval,
        for dir: URL
    ) {
        lock.lock()
        defer { lock.unlock() }
        entries[dir] = Entry(
            items: items,
            sortedItems: sortedItems,
            sortKey: sortKey,
            folderModificationTimestamp: folderModificationTimestamp
        )
        touchLocked(dir)
        while accessOrder.count > maxEntries {
            let evicted = accessOrder.removeFirst()
            entries.removeValue(forKey: evicted)
        }
    }

    func updateFolderTimestamp(_ timestamp: TimeInterval, for dir: URL) {
        lock.lock()
        defer { lock.unlock() }
        guard var existing = entries[dir] else { return }
        existing.folderModificationTimestamp = timestamp
        entries[dir] = existing
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
        accessOrder.removeAll()
    }

    private func touchLocked(_ dir: URL) {
        accessOrder.removeAll { $0 == dir }
        accessOrder.append(dir)
    }
}

/// Actor encargado de leer y persistir un índice temporal oculto por carpeta (`.macfileexplorer_dir.cache`)
/// con respaldo automático en `~/Library/Caches/MacFileExplorer/DirectoryIndex` si la carpeta es de solo lectura,
/// más una caché caliente síncrona en RAM para navegación instantánea (Atrás/Adelante/carpetas frecuentes).
public actor DirectoryIndexCacheService {
    public static let shared = DirectoryIndexCacheService()

    /// Nombre del archivo oculto guardado dentro de la carpeta cacheada (estilo `.macfileexplorer_thumbs.cache`).
    public static let hiddenCacheFileName = ".macfileexplorer_dir.cache"

    private static let archiveVersion = 1
    private static let maxMemoryFolders = 96

    private nonisolated let hotCache = HotDirectoryMemoryCache()
    private var memoryArchives: [URL: CachedDirectoryArchive] = [:]
    private var memoryAccessOrder: [URL] = []

    private init() {}

    // MARK: - Acceso Síncrono Ultrarrápido en RAM (0 ms, sin salto de actor)

    /// Devuelve la instantánea caliente en RAM de forma completamente síncrona (<0.1 ms)
    /// para eliminar cualquier parpadeo de «Cargando…» al volver a carpetas ya visitadas.
    public nonisolated func synchronousMemorySnapshot(for directoryURL: URL) -> SynchronousDirectoryCacheHit? {
        let dir = directoryURL.standardizedFileURL
        guard let entry = hotCache.lookup(for: dir) else { return nil }
        let currentMtime = Self.directoryModificationTimestamp(for: dir)
        let isFresh = Self.isTimestampFresh(
            savedTimestamp: entry.folderModificationTimestamp,
            currentFolderMtime: currentMtime,
            in: dir
        )
        return SynchronousDirectoryCacheHit(
            items: entry.items,
            sortedItems: entry.sortedItems,
            sortKey: entry.sortKey,
            isFolderTimestampFresh: isFresh
        )
    }

    /// Actualiza de inmediato la caché caliente en RAM (incluyendo la lista ya ordenada)
    /// para que cambiar de carpeta y regresar instantes después sea 100% instantáneo.
    public nonisolated func storeInSynchronousMemoryCache(
        _ items: [FileItem],
        sortedItems: [FileItem]? = nil,
        sortKey: DirectorySortCacheKey? = nil,
        for directoryURL: URL
    ) {
        let dir = directoryURL.standardizedFileURL
        let folderMtime = Self.directoryModificationTimestamp(for: dir) ?? Date().timeIntervalSince1970
        hotCache.store(
            items: items,
            sortedItems: sortedItems,
            sortKey: sortKey,
            folderModificationTimestamp: folderMtime,
            for: dir
        )
    }

    /// Sincroniza el `mtime` cacheado tras escribir un archivo oculto interno (`.macfileexplorer_*.cache`)
    /// para que nuestras propias escrituras de caché nunca invaliden la frescura de la carpeta.
    public nonisolated func recordInternalCacheWrite(in directoryURL: URL) {
        let dir = directoryURL.standardizedFileURL
        guard let updatedMtime = Self.directoryModificationTimestamp(for: dir) else { return }
        hotCache.updateFolderTimestamp(updatedMtime, for: dir)
        Task(priority: .utility) {
            await self.updateArchiveTimestampInMemory(updatedMtime, for: dir)
        }
    }

    private func updateArchiveTimestampInMemory(_ timestamp: TimeInterval, for dir: URL) {
        guard let existing = memoryArchives[dir] else { return }
        memoryArchives[dir] = CachedDirectoryArchive(
            version: existing.version,
            folderModificationTimestamp: timestamp,
            entries: existing.entries
        )
    }

    // MARK: - Lectura Rápida de Caché (RAM + Archivo Oculto en Disco)

    /// Carga los metadatos cacheados de la carpeta indicada e informa si coinciden con la fecha de modificación actual del directorio.
    public func loadCachedSnapshot(for directoryURL: URL) -> DirectoryCacheLookupResult? {
        let dir = directoryURL.standardizedFileURL
        let currentFolderMtime = Self.directoryModificationTimestamp(for: dir)

        if let hotEntry = hotCache.lookup(for: dir) {
            let isFresh = Self.isTimestampFresh(
                savedTimestamp: hotEntry.folderModificationTimestamp,
                currentFolderMtime: currentFolderMtime,
                in: dir
            )
            return DirectoryCacheLookupResult(
                items: hotEntry.items,
                isFolderTimestampFresh: isFresh
            )
        }

        if let inMemory = memoryArchives[dir] {
            touchMemoryOrder(for: dir)
            let items = reconstructItems(from: inMemory.entries, in: dir)
            let isFresh = Self.isTimestampFresh(
                savedTimestamp: inMemory.folderModificationTimestamp,
                currentFolderMtime: currentFolderMtime,
                in: dir
            )
            hotCache.store(
                items: items,
                sortedItems: nil,
                sortKey: nil,
                folderModificationTimestamp: inMemory.folderModificationTimestamp,
                for: dir
            )
            return DirectoryCacheLookupResult(
                items: items,
                isFolderTimestampFresh: isFresh
            )
        }

        let localCacheURL = dir.appendingPathComponent(Self.hiddenCacheFileName)
        let fallbackURL = fallbackCacheFileURL(for: dir)
        let decoder = PropertyListDecoder()

        let loadedArchive: CachedDirectoryArchive?
        if let data = try? Data(contentsOf: localCacheURL, options: [.mappedIfSafe]),
           let decoded = try? decoder.decode(CachedDirectoryArchive.self, from: data),
           decoded.version == Self.archiveVersion {
            loadedArchive = decoded
        } else if let data = try? Data(contentsOf: fallbackURL, options: [.mappedIfSafe]),
                  let decoded = try? decoder.decode(CachedDirectoryArchive.self, from: data),
                  decoded.version == Self.archiveVersion {
            loadedArchive = decoded
        } else {
            loadedArchive = nil
        }

        guard let archive = loadedArchive else {
            return nil
        }

        let items = reconstructItems(from: archive.entries, in: dir)
        storeInMemory(archive, for: dir)
        hotCache.store(
            items: items,
            sortedItems: nil,
            sortKey: nil,
            folderModificationTimestamp: archive.folderModificationTimestamp,
            for: dir
        )
        let isFresh = Self.isTimestampFresh(
            savedTimestamp: archive.folderModificationTimestamp,
            currentFolderMtime: currentFolderMtime,
            in: dir
        )
        return DirectoryCacheLookupResult(
            items: items,
            isFolderTimestampFresh: isFresh
        )
    }

    // MARK: - Guardado de Caché Oculta

    /// Persiste en memoria y en el archivo oculto `.macfileexplorer_dir.cache` el contenido leído de una carpeta.
    public func saveSnapshot(
        _ items: [FileItem],
        sortedItems: [FileItem]? = nil,
        sortKey: DirectorySortCacheKey? = nil,
        for directoryURL: URL
    ) {
        let dir = directoryURL.standardizedFileURL
        let folderMtime = Self.directoryModificationTimestamp(for: dir) ?? Date().timeIntervalSince1970

        var entries: [CachedFileEntry] = []
        entries.reserveCapacity(items.count)

        for item in items {
            entries.append(
                CachedFileEntry(
                    name: item.name,
                    isDirectory: item.isDirectory,
                    isPackage: item.isPackage,
                    isHidden: item.isHidden,
                    isSymbolicLink: item.isSymbolicLink,
                    modificationTimestamp: item.modificationDate.timeIntervalSince1970,
                    creationTimestamp: item.creationDate.timeIntervalSince1970,
                    size: item.size,
                    utTypeIdentifier: item.contentType?.identifier,
                    kindDescription: item.kindDescription
                )
            )
        }

        var archive = CachedDirectoryArchive(
            version: Self.archiveVersion,
            folderModificationTimestamp: folderMtime,
            entries: entries
        )
        storeInMemory(archive, for: dir)
        hotCache.store(
            items: items,
            sortedItems: sortedItems,
            sortKey: sortKey,
            folderModificationTimestamp: folderMtime,
            for: dir
        )

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let encoded = try? encoder.encode(archive) else { return }

        DirectoryWatcher.suppressInternalCacheWrites(in: dir)
        var localCacheURL = dir.appendingPathComponent(Self.hiddenCacheFileName)
        var tempCacheURL = dir.appendingPathComponent("\(Self.hiddenCacheFileName).tmp.\(UUID().uuidString)")
        do {
            try encoded.write(to: tempCacheURL, options: [])
            var resourceValues = URLResourceValues()
            resourceValues.isHidden = true
            try? tempCacheURL.setResourceValues(resourceValues)
            if rename(tempCacheURL.path(percentEncoded: false), localCacheURL.path(percentEncoded: false)) != 0 {
                try? FileManager.default.removeItem(at: tempCacheURL)
                try encoded.write(to: localCacheURL, options: [.atomic])
            }
            try? localCacheURL.setResourceValues(resourceValues)

            // Tras `rename`, APFS actualiza el mtime de la carpeta: sincronizamos el timestamp en RAM
            // para evitar autoinvalidar la caché en la siguiente visita.
            if let postWriteMtime = Self.directoryModificationTimestamp(for: dir) {
                archive = CachedDirectoryArchive(
                    version: Self.archiveVersion,
                    folderModificationTimestamp: postWriteMtime,
                    entries: entries
                )
                storeInMemory(archive, for: dir)
                hotCache.updateFolderTimestamp(postWriteMtime, for: dir)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempCacheURL)
            // Si la carpeta no permite escritura (volumen de solo lectura / protegido), usar caché de usuario.
            let fallbackURL = fallbackCacheFileURL(for: dir)
            try? FileManager.default.createDirectory(
                at: fallbackURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? encoded.write(to: fallbackURL, options: [.atomic])
        }
    }

    // MARK: - Helpers Privados

    /// Evalúa si el `mtime` actual de la carpeta sigue vigente, tolerando cambios producidos únicamente
    /// por nuestros propios archivos ocultos de caché (`.macfileexplorer_*.cache`).
    private nonisolated static func isTimestampFresh(
        savedTimestamp: TimeInterval,
        currentFolderMtime: TimeInterval?,
        in dir: URL
    ) -> Bool {
        guard let currentFolderMtime else { return false }
        if abs(savedTimestamp - currentFolderMtime) < 1.5 {
            return true
        }
        // Si el mtime de la carpeta coincide con el de alguno de nuestros archivos ocultos internos,
        // el cambio de mtime fue causado por nuestra propia caché (índice, miniaturas u OCR), no por el usuario.
        let internalCacheNames = [
            hiddenCacheFileName,
            ThumbnailDiskCoordinator.hiddenCacheFileName,
            OCRIndexCacheService.hiddenCacheFileName
        ]
        for cacheName in internalCacheNames {
            let cacheURL = dir.appendingPathComponent(cacheName)
            if let vals = try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey]),
               let cacheMtime = vals.contentModificationDate?.timeIntervalSince1970,
               abs(currentFolderMtime - cacheMtime) < 2.5 {
                return true
            }
        }
        return false
    }

    private func reconstructItems(from entries: [CachedFileEntry], in directoryURL: URL) -> [FileItem] {
        var items: [FileItem] = []
        items.reserveCapacity(entries.count)

        for entry in entries {
            let itemURL = directoryURL.appendingPathComponent(entry.name, isDirectory: entry.isDirectory)
            let utType = entry.utTypeIdentifier.flatMap { UTType($0) }
            items.append(
                FileItem(
                    url: itemURL,
                    name: entry.name,
                    isDirectory: entry.isDirectory,
                    isPackage: entry.isPackage,
                    isHidden: entry.isHidden,
                    isSymbolicLink: entry.isSymbolicLink,
                    modificationDate: Date(timeIntervalSince1970: entry.modificationTimestamp),
                    creationDate: Date(timeIntervalSince1970: entry.creationTimestamp),
                    size: entry.size,
                    contentType: utType,
                    kindDescription: entry.kindDescription
                )
            )
        }

        return items
    }

    public nonisolated static func directoryModificationTimestamp(for directoryURL: URL) -> TimeInterval? {
        let values = try? directoryURL.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate?.timeIntervalSince1970
    }

    public func clearAllCaches() {
        hotCache.removeAll()
        memoryArchives.removeAll()
        memoryAccessOrder.removeAll()
    }

    private func storeInMemory(_ archive: CachedDirectoryArchive, for dir: URL) {
        memoryArchives[dir] = archive
        touchMemoryOrder(for: dir)
        while memoryAccessOrder.count > Self.maxMemoryFolders {
            let evicted = memoryAccessOrder.removeFirst()
            memoryArchives.removeValue(forKey: evicted)
        }
    }

    private func touchMemoryOrder(for dir: URL) {
        memoryAccessOrder.removeAll { $0 == dir }
        memoryAccessOrder.append(dir)
    }

    private func fallbackCacheFileURL(for folderURL: URL) -> URL {
        let cachesRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folderPath = folderURL.standardizedFileURL.path(percentEncoded: false)
        var hash: UInt64 = 14695981039346656037
        for byte in folderPath.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        let fileName = String(format: "dir_%016llx.cache", hash)
        return cachesRoot
            .appendingPathComponent("MacFileExplorer/DirectoryIndex", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
