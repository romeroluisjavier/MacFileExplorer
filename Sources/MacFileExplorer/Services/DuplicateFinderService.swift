import CryptoKit
import Foundation

public struct DuplicateGroup: Identifiable, Sendable {
    public let id: String
    public let fileSize: Int64
    public let items: [FileItem]

    public var wastedBytes: Int64 {
        Int64(max(0, items.count - 1)) * fileSize
    }
}

/// Servicio de detección rápida de archivos duplicados en 3 fases:
/// 1) Tamaño exacto -> 2) Hash parcial (64 KB inicio + fin) -> 3) SHA-256 completo por streaming.
public enum DuplicateFinderService {

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

            var candidates: [(url: URL, size: Int64, values: URLResourceValues)] = []
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
                        guard let vals = try? nextURL.resourceValues(forKeys: keySet),
                              vals.isRegularFile == true,
                              let size = vals.fileSize, size > 0 else { continue }
                        candidates.append((nextURL.standardizedFileURL, Int64(size), vals))
                    }
                }
            } else {
                let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
                let urls = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: keys, options: options)) ?? []
                for url in urls {
                    if Task.isCancelled { return [] }
                    guard let vals = try? url.resourceValues(forKeys: keySet),
                          vals.isRegularFile == true,
                          let size = vals.fileSize, size > 0 else { continue }
                    candidates.append((url.standardizedFileURL, Int64(size), vals))
                }
            }

            // Paso 1: Agrupar por tamaño exacto
            var bySize: [Int64: [(url: URL, size: Int64, values: URLResourceValues)]] = [:]
            for entry in candidates {
                bySize[entry.size, default: []].append(entry)
            }
            let sizeGroups = bySize.values.filter { $0.count > 1 }
            if sizeGroups.isEmpty { return [] }

            // Paso 2: Hash parcial rápido (primeros + últimos 64 KB)
            var byPartialHash: [String: [(url: URL, size: Int64, values: URLResourceValues)]] = [:]
            for group in sizeGroups {
                for entry in group {
                    if Task.isCancelled { return [] }
                    if let partial = partialHash(for: entry.url, size: entry.size) {
                        byPartialHash["\(entry.size):\(partial)", default: []].append(entry)
                    }
                }
            }
            let partialGroups = byPartialHash.values.filter { $0.count > 1 }
            if partialGroups.isEmpty { return [] }

            // Paso 3: SHA-256 completo por streaming
            var byFullHash: [String: [(url: URL, size: Int64, values: URLResourceValues)]] = [:]
            for group in partialGroups {
                for entry in group {
                    if Task.isCancelled { return [] }
                    if let full = fullSHA256(for: entry.url) {
                        byFullHash[full, default: []].append(entry)
                    }
                }
            }

            var finalGroups: [DuplicateGroup] = []
            for (hash, entries) in byFullHash where entries.count > 1 {
                var items = entries.map { entry in
                    FileItem(
                        url: entry.url,
                        name: entry.url.lastPathComponent,
                        fileExtension: entry.url.pathExtension,
                        isDirectory: false,
                        isPackage: entry.values.isPackage ?? false,
                        isHidden: entry.values.isHidden ?? false,
                        isSymbolicLink: entry.values.isSymbolicLink ?? false,
                        modificationDate: entry.values.contentModificationDate ?? .distantPast,
                        size: entry.size,
                        contentType: entry.values.contentType,
                        kindDescription: entry.values.localizedTypeDescription ?? "Archivo"
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
