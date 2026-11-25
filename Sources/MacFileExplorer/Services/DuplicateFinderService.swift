import CryptoKit
import Foundation
import UniformTypeIdentifiers

public struct DuplicateGroup: Identifiable, Sendable {
    public let id: String
    public let fileSize: Int64
    public let items: [FileItem]

    public var wastedBytes: Int64 {
        Int64(max(0, items.count - 1)) * fileSize
    }
}

/// Servicio de detección rápida de archivos duplicados en 3 fases:
/// 1) Tamaño exacto -> 2) Hash parcial paralelo (64 KB inicio + fin) -> 3) SHA-256 completo por streaming paralelo
/// aprovechando la aceleración criptográfica ARMv8 en Apple Silicon (M1/M2/M3/M4) con concurrencia acotada.
public enum DuplicateFinderService {

    private struct CandidateFile: Sendable {
        let url: URL
        let name: String
        let fileExtension: String
        let size: Int64
        let isPackage: Bool
        let isHidden: Bool
        let isSymbolicLink: Bool
        let modificationDate: Date
        let contentType: UTType?
        let kindDescription: String
    }

    private static func isInternalCacheFileName(_ name: String) -> Bool {
        name.hasPrefix(DirectoryIndexCacheService.hiddenCacheFileName)
            || name.hasPrefix(ThumbnailDiskCoordinator.hiddenCacheFileName)
            || name.hasPrefix(OCRIndexCacheService.hiddenCacheFileName)
    }

    public static func findDuplicates(
        in directoryURL: URL,
        includeSubfolders: Bool,
        includeHidden: Bool
    ) async -> [DuplicateGroup] {
        await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let root = directoryURL.standardizedFileURL
            let keys: [URLResourceKey] = [
                .isRegularFileKey,
                .isDirectoryKey,
                .isPackageKey,
                .isHiddenKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .creationDateKey,
                .contentTypeKey,
                .localizedTypeDescriptionKey
            ]
            let keySet = Set(keys)

            var candidates: [CandidateFile] = []
            if includeSubfolders {
                let options: FileManager.DirectoryEnumerationOptions = includeHidden
                    ? [.skipsPackageDescendants]
                    : [.skipsHiddenFiles, .skipsPackageDescendants]
                if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: options) {
                    while let nextURL = enumerator.nextObject() as? URL {
                        if Task.isCancelled { return [] }
                        let name = nextURL.lastPathComponent
                        if name == ".git" || name == "node_modules" || name == ".build" || name == "DerivedData" {
                            enumerator.skipDescendants()
                            continue
                        }
                        if isInternalCacheFileName(name) { continue }
                        guard let vals = try? nextURL.resourceValues(forKeys: keySet),
                              vals.isRegularFile == true,
                              let size = vals.fileSize, size > 0 else { continue }
                        let stdURL = nextURL.standardizedFileURL
                        candidates.append(
                            CandidateFile(
                                url: stdURL,
                                name: stdURL.lastPathComponent,
                                fileExtension: stdURL.pathExtension,
                                size: Int64(size),
                                isPackage: vals.isPackage ?? false,
                                isHidden: vals.isHidden ?? false,
                                isSymbolicLink: vals.isSymbolicLink ?? false,
                                modificationDate: vals.contentModificationDate ?? .distantPast,
                                contentType: vals.contentType,
                                kindDescription: vals.localizedTypeDescription ?? "Archivo"
                            )
                        )
                    }
                }
            } else {
                let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
                let urls = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: keys, options: options)) ?? []
                for url in urls {
                    if Task.isCancelled { return [] }
                    if isInternalCacheFileName(url.lastPathComponent) { continue }
                    guard let vals = try? url.resourceValues(forKeys: keySet),
                          vals.isRegularFile == true,
                          let size = vals.fileSize, size > 0 else { continue }
                    let stdURL = url.standardizedFileURL
                    candidates.append(
                        CandidateFile(
                            url: stdURL,
                            name: stdURL.lastPathComponent,
                            fileExtension: stdURL.pathExtension,
                            size: Int64(size),
                            isPackage: vals.isPackage ?? false,
                            isHidden: vals.isHidden ?? false,
                            isSymbolicLink: vals.isSymbolicLink ?? false,
                            modificationDate: vals.contentModificationDate ?? .distantPast,
                            contentType: vals.contentType,
                            kindDescription: vals.localizedTypeDescription ?? "Archivo"
                        )
                    )
                }
            }

            // Paso 1: Agrupar por tamaño exacto
            var bySize: [Int64: [CandidateFile]] = [:]
            for entry in candidates {
                bySize[entry.size, default: []].append(entry)
            }
            let sizeCandidates = bySize.values.filter { $0.count > 1 }.flatMap { $0 }
            if sizeCandidates.isEmpty { return [] }

            let maxWorkers = max(2, min(ProcessInfo.processInfo.activeProcessorCount / 2, 4))

            // Paso 2: Hash parcial paralelo (primeros + últimos 64 KB)
            var byPartialHash: [String: [CandidateFile]] = [:]
            await withTaskGroup(of: (String, CandidateFile)?.self) { group in
                var iterator = sizeCandidates.makeIterator()
                for _ in 0..<maxWorkers {
                    guard let next = iterator.next() else { break }
                    group.addTask {
                        guard !Task.isCancelled,
                              let partial = partialHash(for: next.url, size: next.size) else { return nil }
                        return ("\(next.size):\(partial)", next)
                    }
                }
                while let result = await group.next() {
                    if let (key, entry) = result {
                        byPartialHash[key, default: []].append(entry)
                    }
                    if !Task.isCancelled, let next = iterator.next() {
                        group.addTask {
                            guard !Task.isCancelled,
                                  let partial = partialHash(for: next.url, size: next.size) else { return nil }
                            return ("\(next.size):\(partial)", next)
                        }
                    }
                }
            }
            if Task.isCancelled { return [] }
            let partialCandidates = byPartialHash.values.filter { $0.count > 1 }.flatMap { $0 }
            if partialCandidates.isEmpty { return [] }

            // Paso 3: SHA-256 completo por streaming en paralelo con concurrencia acotada
            var byFullHash: [String: [CandidateFile]] = [:]
            await withTaskGroup(of: (String, CandidateFile)?.self) { group in
                var iterator = partialCandidates.makeIterator()
                for _ in 0..<maxWorkers {
                    guard let next = iterator.next() else { break }
                    group.addTask {
                        guard !Task.isCancelled,
                              let full = fullSHA256(for: next.url) else { return nil }
                        return (full, next)
                    }
                }
                while let result = await group.next() {
                    if let (hash, entry) = result {
                        byFullHash[hash, default: []].append(entry)
                    }
                    if !Task.isCancelled, let next = iterator.next() {
                        group.addTask {
                            guard !Task.isCancelled,
                                  let full = fullSHA256(for: next.url) else { return nil }
                            return (full, next)
                        }
                    }
                }
            }
            if Task.isCancelled { return [] }

            var finalGroups: [DuplicateGroup] = []
            for (hash, entries) in byFullHash where entries.count > 1 {
                var items = entries.map { entry in
                    FileItem(
                        url: entry.url,
                        name: entry.name,
                        fileExtension: entry.fileExtension,
                        isDirectory: false,
                        isPackage: entry.isPackage,
                        isHidden: entry.isHidden,
                        isSymbolicLink: entry.isSymbolicLink,
                        modificationDate: entry.modificationDate,
                        size: entry.size,
                        contentType: entry.contentType,
                        kindDescription: entry.kindDescription
                    )
                }
                items.sort { $0.modificationDate < $1.modificationDate }
                finalGroups.append(DuplicateGroup(id: hash, fileSize: entries[0].size, items: items))
            }

            finalGroups.sort { $0.wastedBytes > $1.wastedBytes }
            return finalGroups
        }.value
    }

    private static func partialHash(for url: URL, size: Int64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let sampleSize = 65_536
        var hasher = SHA256()
        if let head = try? handle.read(upToCount: sampleSize), !head.isEmpty {
            hasher.update(data: head)
        }
        if size > Int64(sampleSize * 2) {
            try? handle.seek(toOffset: UInt64(size - Int64(sampleSize)))
            if let tail = try? handle.read(upToCount: sampleSize), !tail.isEmpty {
                hasher.update(data: tail)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func fullSHA256(for url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        let bufferSize = 1_048_576
        while true {
            guard let chunk = try? handle.read(upToCount: bufferSize), !chunk.isEmpty else {
                break
            }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
