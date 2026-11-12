import Foundation
import UniformTypeIdentifiers

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

/// Actor encargado de leer y persistir un índice temporal oculto por carpeta (`.macfileexplorer_dir.cache`)
/// con respaldo automático en `~/Library/Caches/MacFileExplorer/DirectoryIndex` si la carpeta es de solo lectura,
/// más una caché caliente en memoria para navegación instantánea (Atrás/Adelante/carpetas frecuentes).
public actor DirectoryIndexCacheService {
    public static let shared = DirectoryIndexCacheService()

    /// Nombre del archivo oculto guardado dentro de la carpeta cacheada (estilo `.macfileexplorer_thumbs.cache`).
    public static let hiddenCacheFileName = ".macfileexplorer_dir.cache"

    private static let archiveVersion = 1
    private static let maxMemoryFolders = 64

    private var memoryArchives: [URL: CachedDirectoryArchive] = [:]
    private var memoryAccessOrder: [URL] = []

    private init() {}

    // MARK: - Lectura Rápida de Caché

    /// Carga los metadatos cacheados de la carpeta indicada e informa si coinciden con la fecha de modificación actual del directorio.
    public func loadCachedSnapshot(for directoryURL: URL) -> DirectoryCacheLookupResult? {
        let dir = directoryURL.standardizedFileURL
        guard let currentFolderMtime = directoryModificationTimestamp(for: dir) else {
            return nil
        }

        if let inMemory = memoryArchives[dir] {
            touchMemoryOrder(for: dir)
            let isFresh = abs(inMemory.folderModificationTimestamp - currentFolderMtime) < 1.0
            return DirectoryCacheLookupResult(
                items: reconstructItems(from: inMemory.entries, in: dir),
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

        storeInMemory(archive, for: dir)
        let isFresh = abs(archive.folderModificationTimestamp - currentFolderMtime) < 1.0
        return DirectoryCacheLookupResult(
            items: reconstructItems(from: archive.entries, in: dir),
            isFolderTimestampFresh: isFresh
        )
    }

    // MARK: - Guardado de Caché Oculta

    /// Persiste en memoria y en el archivo oculto `.macfileexplorer_dir.cache` el contenido leído de una carpeta.
    public func saveSnapshot(_ items: [FileItem], for directoryURL: URL) {
        let dir = directoryURL.standardizedFileURL
        let folderMtime = directoryModificationTimestamp(for: dir) ?? Date().timeIntervalSince1970

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

        let archive = CachedDirectoryArchive(
            version: Self.archiveVersion,
            folderModificationTimestamp: folderMtime,
            entries: entries
        )
        storeInMemory(archive, for: dir)

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let encoded = try? encoder.encode(archive) else { return }

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

    private func directoryModificationTimestamp(for directoryURL: URL) -> TimeInterval? {
        let values = try? directoryURL.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate?.timeIntervalSince1970
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
