import Foundation

/// Categoría del archivo oculto `.macfileexplorer_*.cache` encontrado en disco.
public enum HiddenCacheKind: String, CaseIterable, Identifiable, Sendable {
    case directoryIndex
    case thumbnails
    case ocrIndex
    case otherCache

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .directoryIndex: return "folder.badge.gearshape"
        case .thumbnails: return "photo.stack"
        case .ocrIndex: return "text.viewfinder"
        case .otherCache: return "internaldrive"
        }
    }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .directoryIndex:
            return loc.text(es: "Índices de carpetas", en: "Folder Indexes")
        case .thumbnails:
            return loc.text(es: "Miniaturas", en: "Thumbnails")
        case .ocrIndex:
            return loc.text(es: "Índices OCR de imágenes", en: "OCR Image Indexes")
        case .otherCache:
            return loc.text(es: "Caché auxiliar", en: "Auxiliary Cache")
        }
    }
}

/// Alcance del escaneo de archivos ocultos `.macfileexplorer`.
public enum HiddenCacheScanScope: String, CaseIterable, Identifiable, Sendable {
    case homeAndCurrentFolder
    case currentFolderOnly

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .homeAndCurrentFolder:
            return loc.text(es: "Carpeta personal (~) y actual", en: "Home (~) & Current Folder")
        case .currentFolderOnly:
            return loc.text(es: "Solo carpeta actual", en: "Current Folder Only")
        }
    }
}

/// Representa un archivo oculto de caché encontrado en disco.
public struct HiddenCacheFileEntry: Identifiable, Hashable, Sendable {
    public let url: URL
    public let kind: HiddenCacheKind
    public let sizeBytes: Int64
    public let modificationDate: Date

    public var id: URL { url }
    public var fileName: String { url.lastPathComponent }
    public var folderURL: URL { url.deletingLastPathComponent() }
}

/// Resumen completo del escaneo de archivos ocultos `.macfileexplorer_*.cache`.
public struct HiddenCacheScanReport: Sendable {
    public let entries: [HiddenCacheFileEntry]
    public let totalSizeBytes: Int64
    public let countsByKind: [HiddenCacheKind: Int]
    public let sizesByKind: [HiddenCacheKind: Int64]

    public var totalCount: Int { entries.count }
}

/// Resultado tras eliminar archivos ocultos de caché para su regeneración limpia.
public struct HiddenCacheClearResult: Sendable {
    public let deletedCount: Int
    public let freedBytes: Int64
    public let failedCount: Int
}

/// Servicio encargado de buscar, contabilizar y eliminar todos los archivos de caché ocultos
/// `.macfileexplorer_*.cache` (índices de carpeta, miniaturas y OCR) sin tocar logs internos.
public enum HiddenCacheManagerService {

    private static let skipDirectoryNames: Set<String> = [
        "node_modules", ".git", ".hg", ".svn", ".build", ".swiftpm",
        "DerivedData", "Pods", ".Trash", "CoreSimulator", ".venv", "venv",
        "__pycache__", ".next", ".nuxt", "target", "dist"
    ]

    public static func classifyCacheFileName(_ name: String) -> HiddenCacheKind? {
        if name == DirectoryIndexCacheService.hiddenCacheFileName || name.hasPrefix("dir_") && name.hasSuffix(".cache") {
            return .directoryIndex
        }
        if name == ThumbnailDiskCoordinator.hiddenCacheFileName || name.hasPrefix("thumbs_") && name.hasSuffix(".cache") {
            return .thumbnails
        }
        if name == OCRIndexCacheService.hiddenCacheFileName || name.hasPrefix("ocr_") && name.hasSuffix(".cache") {
            return .ocrIndex
        }
        if name.hasPrefix(".macfileexplorer_") && name.contains(".cache") {
            return .otherCache
        }
        return nil
    }

    public static func scanHiddenCaches(
        scope: HiddenCacheScanScope,
        currentDirectoryURL: URL
    ) async -> HiddenCacheScanReport {
        await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let homeURL = fm.homeDirectoryForCurrentUser.standardizedFileURL
            let homePath = homeURL.path(percentEncoded: false)
            let libraryPath = homeURL.appendingPathComponent("Library").path(percentEncoded: false)
            let appCachesDir = homeURL
                .appendingPathComponent("Library/Caches/MacFileExplorer", isDirectory: true)
                .standardizedFileURL
            let standardizedCurrent = currentDirectoryURL.standardizedFileURL
            let currentPath = standardizedCurrent.path(percentEncoded: false)

            var rootsToScan: [URL] = []
            switch scope {
            case .homeAndCurrentFolder:
                rootsToScan.append(homeURL)
                if !(currentPath == homePath || currentPath.hasPrefix(homePath + "/")) {
                    rootsToScan.append(standardizedCurrent)
                }
            case .currentFolderOnly:
                rootsToScan.append(standardizedCurrent)
            }

            let resourceKeys: Set<URLResourceKey> = [
                .isDirectoryKey,
                .isRegularFileKey,
                .fileSizeKey,
                .totalFileAllocatedSizeKey,
                .contentModificationDateKey
            ]

            var seenPaths = Set<String>()
            var entries: [HiddenCacheFileEntry] = []

            for root in rootsToScan {
                if Task.isCancelled { break }
                let rootIsHome = (root == homeURL)
                guard let enumerator = fm.enumerator(
                    at: root,
                    includingPropertiesForKeys: Array(resourceKeys),
                    options: [.skipsPackageDescendants]
                ) else {
                    continue
                }

                while let fileURL = enumerator.nextObject() as? URL {
                    if Task.isCancelled { break }
                    let name = fileURL.lastPathComponent
                    let fullPath = fileURL.standardizedFileURL.path(percentEncoded: false)

                    guard let values = try? fileURL.resourceValues(forKeys: resourceKeys) else { continue }

                    if values.isDirectory == true {
                        // Evitar entrar en carpetas de sistema/TCC dentro de ~/Library salvo Caches/MacFileExplorer
                        if rootIsHome && fullPath == libraryPath {
                            enumerator.skipDescendants()
                            continue
                        }
                        if skipDirectoryNames.contains(name) {
                            enumerator.skipDescendants()
                        }
                        continue
                    }

                    guard values.isRegularFile == true,
                          let kind = classifyCacheFileName(name),
                          seenPaths.insert(fullPath).inserted else {
                        continue
                    }

                    let bytes = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                    let mtime = values.contentModificationDate ?? .distantPast
                    entries.append(
                        HiddenCacheFileEntry(
                            url: fileURL.standardizedFileURL,
                            kind: kind,
                            sizeBytes: max(0, bytes),
                            modificationDate: mtime
                        )
                    )
                }
            }

            // Incluir respaldos en ~/Library/Caches/MacFileExplorer cuando se escanea Home
            if scope == .homeAndCurrentFolder,
               fm.fileExists(atPath: appCachesDir.path(percentEncoded: false)),
               let cacheEnumerator = fm.enumerator(
                   at: appCachesDir,
                   includingPropertiesForKeys: Array(resourceKeys),
                   options: [.skipsPackageDescendants]
               ) {
                while let fileURL = cacheEnumerator.nextObject() as? URL {
                    if Task.isCancelled { break }
                    guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                          values.isRegularFile == true else {
                        continue
                    }
                    let fullPath = fileURL.standardizedFileURL.path(percentEncoded: false)
                    guard let kind = classifyCacheFileName(fileURL.lastPathComponent),
                          seenPaths.insert(fullPath).inserted else {
                        continue
                    }
                    let bytes = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                    let mtime = values.contentModificationDate ?? .distantPast
                    entries.append(
                        HiddenCacheFileEntry(
                            url: fileURL.standardizedFileURL,
                            kind: kind,
                            sizeBytes: max(0, bytes),
                            modificationDate: mtime
                        )
                    )
                }
            }

            entries.sort { lhs, rhs in
                if lhs.sizeBytes != rhs.sizeBytes {
                    return lhs.sizeBytes > rhs.sizeBytes
                }
                return lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
            }

            var totalBytes: Int64 = 0
            var countsByKind: [HiddenCacheKind: Int] = [:]
            var sizesByKind: [HiddenCacheKind: Int64] = [:]

            for entry in entries {
                totalBytes += entry.sizeBytes
                countsByKind[entry.kind, default: 0] += 1
                sizesByKind[entry.kind, default: 0] += entry.sizeBytes
            }

            return HiddenCacheScanReport(
                entries: entries,
                totalSizeBytes: totalBytes,
                countsByKind: countsByKind,
                sizesByKind: sizesByKind
            )
        }.value
    }

    /// Cancela pendientes, limpia cachés en memoria y elimina del disco todos los archivos listados.
    public static func deleteAllCaches(_ entries: [HiddenCacheFileEntry]) async -> HiddenCacheClearResult {
        // 1. Cancelar escrituras/indexaciones pendientes y vaciar cachés en RAM primero
        await DirectoryIndexCacheService.shared.clearAllCaches()
        await MainActor.run {
            ThumbnailCacheService.shared.clearMemoryAndPendingCaches()
        }
        await OCRIndexCacheService.shared.clearAllCaches()

        return await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            var deleted = 0
            var freed: Int64 = 0
            var failed = 0

            for entry in entries {
                do {
                    if fm.fileExists(atPath: entry.url.path(percentEncoded: false)) {
                        try fm.removeItem(at: entry.url)
                    }
                    deleted += 1
                    freed += entry.sizeBytes
                } catch {
                    failed += 1
                }
            }

            return HiddenCacheClearResult(
                deletedCount: deleted,
                freedBytes: freed,
                failedCount: failed
            )
        }.value
    }
}
