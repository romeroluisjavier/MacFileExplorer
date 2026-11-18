import Compression
import Foundation
import UniformTypeIdentifiers

/// Entrada individual indexada dentro de `.macfileexplorer_ocr.cache`.
private struct CachedOCREntry: Codable, Sendable {
    let fileName: String
    let fileSize: Int64
    let modificationTimestamp: TimeInterval
    var lastAccessedTimestamp: TimeInterval
    let ocrVersion: Int
    let transcript: String
}

/// Contenedor binario comprimido por carpeta para almacenar texto OCR extraído de imágenes.
private struct CachedOCRArchive: Codable, Sendable {
    var version: Int = 2
    var entries: [String: CachedOCREntry] = [:]
}

/// Actor encargado de indexar en segundo plano y persistir en un archivo oculto por carpeta
/// (`.macfileexplorer_ocr.cache`) el texto reconocido mediante Vision OCR en imágenes.
///
/// Garantiza un límite estricto máximo de **5 MB por carpeta** mediante compresión LZFSE y
/// política LRU cuando una carpeta contiene miles de imágenes, con respaldo automático en
/// `~/Library/Caches/MacFileExplorer/OCRIndex` si la carpeta es de solo lectura.
public actor OCRIndexCacheService {
    public static let shared = OCRIndexCacheService()

    /// Nombre del archivo oculto guardado dentro de cada carpeta (junto a `.macfileexplorer_dir.cache`).
    public static let hiddenCacheFileName = ".macfileexplorer_ocr.cache"

    /// Límite estricto de tamaño en disco por carpeta: 5 MB.
    public static let maxArchiveSizeBytes = 5 * 1024 * 1024

    private static let archiveVersion = 2
    private static let currentOCRVersion = 2
    private static let maxTranscriptCharacters = 32_000
    private static let maxLoadedFolders = 48
    private static let magicHeader = Data("MFEOCR2\0".utf8)

    private var loadedArchives: [URL: CachedOCRArchive] = [:]
    private var memoryAccessOrder: [URL] = []
    private var dirtyFolders: Set<URL> = []
    private var saveTasks: [URL: Task<Void, Never>] = [:]
    private var activeBackgroundIndexTask: Task<Void, Never>?
    private var activeIndexedFolderURL: URL?

    private init() {}

    // MARK: - Consulta y Actualización de Índice

    /// Devuelve el texto OCR cacheado para una imagen si su tamaño y fecha de modificación coinciden.
    public func cachedTranscript(
        for fileURL: URL,
        fileSize: Int64?,
        modificationDate: Date
    ) -> String? {
        let dir = fileURL.deletingLastPathComponent().standardizedFileURL
        loadArchiveIfNeeded(for: dir)

        guard var archive = loadedArchives[dir] else { return nil }
        let fileName = fileURL.lastPathComponent
        guard var entry = archive.entries[fileName] else { return nil }

        let expectedSize = fileSize ?? -1
        let expectedMtime = modificationDate.timeIntervalSince1970
        guard entry.ocrVersion == Self.currentOCRVersion,
              entry.fileSize == expectedSize,
              abs(entry.modificationTimestamp - expectedMtime) < 1.0 else {
            return nil
        }

        entry.lastAccessedTimestamp = Date().timeIntervalSince1970
        archive.entries[fileName] = entry
        loadedArchives[dir] = archive
        touchMemoryOrder(for: dir)
        return entry.transcript
    }

    /// Almacena el texto OCR reconocido de una imagen y programa su escritura diferida en `.macfileexplorer_ocr.cache`.
    public func storeTranscript(
        _ transcript: String,
        for fileURL: URL,
        fileSize: Int64?,
        modificationDate: Date
    ) {
        let dir = fileURL.deletingLastPathComponent().standardizedFileURL
        loadArchiveIfNeeded(for: dir)

        var archive = loadedArchives[dir] ?? CachedOCRArchive(version: Self.archiveVersion, entries: [:])
        let normalizedTranscript: String
        if transcript.count > Self.maxTranscriptCharacters {
            normalizedTranscript = String(transcript.prefix(Self.maxTranscriptCharacters))
        } else {
            normalizedTranscript = transcript
        }

        let now = Date().timeIntervalSince1970
        let entry = CachedOCREntry(
            fileName: fileURL.lastPathComponent,
            fileSize: fileSize ?? -1,
            modificationTimestamp: modificationDate.timeIntervalSince1970,
            lastAccessedTimestamp: now,
            ocrVersion: Self.currentOCRVersion,
            transcript: normalizedTranscript
        )
        archive.entries[entry.fileName] = entry
        loadedArchives[dir] = archive
        touchMemoryOrder(for: dir)
        scheduleSave(for: dir)
    }

    // MARK: - Indexación en Segundo Plano por Carpeta

    /// Programa en segundo plano (baja prioridad) el análisis OCR de las imágenes aún no indexadas
    /// de una carpeta para que las búsquedas posteriores sean instantáneas.
    public func scheduleBackgroundIndexing(for directoryURL: URL, items: [FileItem]) {
        let dir = directoryURL.standardizedFileURL
        if activeIndexedFolderURL == dir, activeBackgroundIndexTask != nil {
            return
        }

        activeBackgroundIndexTask?.cancel()
        activeIndexedFolderURL = dir

        let imageCandidates = items.filter { item in
            guard !item.isDirectory else { return false }
            if let size = item.size, size > 50_000_000 { return false }
            return QuickActionsService.isImageURL(item.url)
                || item.contentType?.conforms(to: .image) == true
        }

        guard !imageCandidates.isEmpty else {
            activeBackgroundIndexTask = nil
            return
        }

        activeBackgroundIndexTask = Task(priority: .utility) { [weak self] in
            // Esperar un instante para priorizar renderizado inicial y miniaturas de la carpeta
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, let self else { return }
            await self.runBackgroundIndexing(for: dir, candidates: imageCandidates)
        }
    }

    public func cancelBackgroundIndexing() {
        activeBackgroundIndexTask?.cancel()
        activeBackgroundIndexTask = nil
        activeIndexedFolderURL = nil
    }

    public func clearAllCaches() {
        cancelBackgroundIndexing()
        for task in saveTasks.values {
            task.cancel()
        }
        saveTasks.removeAll()
        dirtyFolders.removeAll()
        loadedArchives.removeAll()
        memoryAccessOrder.removeAll()
    }

    private func runBackgroundIndexing(for dir: URL, candidates: [FileItem]) async {
        loadArchiveIfNeeded(for: dir)
        pruneDeletedEntries(in: dir, liveFileNames: Set(candidates.map(\.name)))

        var pending: [FileItem] = []
        pending.reserveCapacity(candidates.count)
        for item in candidates {
            if Task.isCancelled { return }
            if cachedTranscript(for: item.url, fileSize: item.size, modificationDate: item.modificationDate) == nil {
                pending.append(item)
            }
        }

        guard !pending.isEmpty else { return }

        for item in pending {
            if Task.isCancelled { return }

            let transcript = await Task.detached(priority: .utility) {
                AdvancedSearchService.extractOCRTranscript(at: item.url)
            }.value

            if Task.isCancelled { return }

            storeTranscript(
                transcript,
                for: item.url,
                fileSize: item.size,
                modificationDate: item.modificationDate
            )

            // Pequeña cesión cooperativa para mantener fluida la interfaz mientras indexa
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    // MARK: - Persistencia con Compresión y Tope Estricto de 5 MB

    /// Serializa y comprime un archivo OCR garantizando que el resultado nunca exceda `maxBytes`.
    public nonisolated static func encodeBoundedArchiveData(
        entries: inout [String: (fileSize: Int64, mtime: TimeInterval, accessed: TimeInterval, transcript: String)],
        maxBytes: Int = maxArchiveSizeBytes
    ) -> Data? {
        var archive = CachedOCRArchive(version: archiveVersion, entries: [:])
        for (name, val) in entries {
            archive.entries[name] = CachedOCREntry(
                fileName: name,
                fileSize: val.fileSize,
                modificationTimestamp: val.mtime,
                lastAccessedTimestamp: val.accessed,
                ocrVersion: currentOCRVersion,
                transcript: val.transcript
            )
        }
        let result = encodeBoundedArchive(&archive, maxBytes: maxBytes)
        entries = archive.entries.mapValues { ($0.fileSize, $0.modificationTimestamp, $0.lastAccessedTimestamp, $0.transcript) }
        return result
    }

    private nonisolated static func encodeBoundedArchive(_ archive: inout CachedOCRArchive, maxBytes: Int) -> Data? {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary

        while true {
            guard let rawData = try? encoder.encode(archive) else { return nil }
            let compressedData = compressData(rawData)
            if compressedData.count <= maxBytes || archive.entries.isEmpty {
                return compressedData.count <= maxBytes ? compressedData : nil
            }

            // Expulsar el 20% más antiguo (mínimo 1 entrada) mediante LRU hasta respetar <= 5 MB
            let sortedByAge = archive.entries.values.sorted { lhs, rhs in
                if lhs.lastAccessedTimestamp != rhs.lastAccessedTimestamp {
                    return lhs.lastAccessedTimestamp < rhs.lastAccessedTimestamp
                }
                return lhs.transcript.count > rhs.transcript.count
            }
            let dropCount = max(1, sortedByAge.count / 5)
            for victim in sortedByAge.prefix(dropCount) {
                archive.entries.removeValue(forKey: victim.fileName)
            }
        }
    }

    private nonisolated static func compressData(_ raw: Data) -> Data {
        if let compressed = try? (raw as NSData).compressed(using: .lzfse) as Data {
            var payload = Data(capacity: magicHeader.count + compressed.count)
            payload.append(magicHeader)
            payload.append(compressed)
            return payload
        }
        return raw
    }

    private nonisolated static func decompressArchive(from data: Data) -> CachedOCRArchive? {
        let decoder = PropertyListDecoder()
        if data.starts(with: magicHeader) {
            let body = data.dropFirst(magicHeader.count)
            guard let decompressed = try? (Data(body) as NSData).decompressed(using: .lzfse) as Data,
                  let decoded = try? decoder.decode(CachedOCRArchive.self, from: decompressed),
                  decoded.version == archiveVersion else {
                return nil
            }
            return decoded
        }
        if let decoded = try? decoder.decode(CachedOCRArchive.self, from: data),
           decoded.version == archiveVersion {
            return decoded
        }
        return nil
    }

    private func loadArchiveIfNeeded(for dir: URL) {
        if loadedArchives[dir] != nil {
            touchMemoryOrder(for: dir)
            return
        }

        let localCacheURL = dir.appendingPathComponent(Self.hiddenCacheFileName)
        let fallbackURL = fallbackCacheFileURL(for: dir)

        let decoded: CachedOCRArchive?
        if let data = try? Data(contentsOf: localCacheURL, options: [.mappedIfSafe]),
           data.count <= Self.maxArchiveSizeBytes,
           let parsed = Self.decompressArchive(from: data) {
            decoded = parsed
        } else if let data = try? Data(contentsOf: fallbackURL, options: [.mappedIfSafe]),
                  data.count <= Self.maxArchiveSizeBytes,
                  let parsed = Self.decompressArchive(from: data) {
            decoded = parsed
        } else {
            decoded = nil
        }

        loadedArchives[dir] = decoded ?? CachedOCRArchive(version: Self.archiveVersion, entries: [:])
        touchMemoryOrder(for: dir)
        evictOldestFoldersInMemoryIfNeeded()
    }

    private func pruneDeletedEntries(in dir: URL, liveFileNames: Set<String>) {
        guard var archive = loadedArchives[dir], !archive.entries.isEmpty else { return }
        let staleKeys = archive.entries.keys.filter { !liveFileNames.contains($0) }
        guard !staleKeys.isEmpty else { return }
        for key in staleKeys {
            archive.entries.removeValue(forKey: key)
        }
        loadedArchives[dir] = archive
        scheduleSave(for: dir)
    }

    private func scheduleSave(for dir: URL) {
        dirtyFolders.insert(dir)
        saveTasks[dir]?.cancel()
        saveTasks[dir] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            await self.flushFolderArchive(for: dir)
        }
    }

    public func flushFolderArchive(for folderURL: URL) {
        let dir = folderURL.standardizedFileURL
        guard dirtyFolders.contains(dir), var archive = loadedArchives[dir] else { return }
        dirtyFolders.remove(dir)
        saveTasks[dir] = nil

        guard let encoded = Self.encodeBoundedArchive(&archive, maxBytes: Self.maxArchiveSizeBytes) else {
            return
        }
        loadedArchives[dir] = archive

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
            let fallbackURL = fallbackCacheFileURL(for: dir)
            try? FileManager.default.createDirectory(
                at: fallbackURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? encoded.write(to: fallbackURL, options: [.atomic])
        }
    }

    private func touchMemoryOrder(for dir: URL) {
        memoryAccessOrder.removeAll { $0 == dir }
        memoryAccessOrder.append(dir)
    }

    private func evictOldestFoldersInMemoryIfNeeded() {
        while memoryAccessOrder.count > Self.maxLoadedFolders {
            let oldest = memoryAccessOrder.removeFirst()
            if !dirtyFolders.contains(oldest) {
                loadedArchives.removeValue(forKey: oldest)
            }
        }
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
        let fileName = String(format: "ocr_%016llx.cache", hash)
        return cachesRoot
            .appendingPathComponent("MacFileExplorer/OCRIndex", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
