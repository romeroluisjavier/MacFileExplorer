import Foundation
import PDFKit
import UniformTypeIdentifiers
import Vision

/// Categorías de tipo de archivo para el Buscador Avanzado.
public enum AdvancedSearchFileType: String, CaseIterable, Identifiable, Sendable {
    case all
    case folders
    case images
    case videos
    case documents
    case pdfs
    case code
    case audio
    case archives

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .all: return loc.text(es: "Todos", en: "All")
        case .folders: return loc.text(es: "Carpetas", en: "Folders")
        case .images: return loc.text(es: "Imágenes", en: "Images")
        case .videos: return loc.text(es: "Videos", en: "Videos")
        case .documents: return loc.text(es: "Documentos", en: "Documents")
        case .pdfs: return "PDF"
        case .code: return loc.text(es: "Código / Texto", en: "Code / Text")
        case .audio: return "Audio"
        case .archives: return loc.text(es: "Comprimidos", en: "Archives")
        }
    }

    public func matches(url: URL, isDirectory: Bool, isPackage: Bool) -> Bool {
        let ext = url.pathExtension.lowercased()
        switch self {
        case .all:
            return true
        case .folders:
            return isDirectory && !isPackage
        case .images:
            return !isDirectory && QuickActionsService.isImageURL(url)
        case .videos:
            return !isDirectory && QuickActionsService.isVideoURL(url)
        case .documents:
            let docExts: Set<String> = ["pdf", "doc", "docx", "txt", "md", "markdown", "rtf", "pages", "csv", "xls", "xlsx", "ppt", "pptx"]
            return !isDirectory && docExts.contains(ext)
        case .pdfs:
            return !isDirectory && ext == "pdf"
        case .code:
            let textExts: Set<String> = ["txt", "md", "markdown", "json", "csv", "log", "env", "conf"]
            return !isDirectory && (RichCodePreviewSupport.codeExtensions.contains(ext) || textExts.contains(ext))
        case .audio:
            let audioExts: Set<String> = ["mp3", "m4a", "wav", "aac", "flac", "ogg", "aiff"]
            return !isDirectory && audioExts.contains(ext)
        case .archives:
            return !isDirectory && ArchiveService.isArchiveURL(url)
        }
    }
}

public enum AdvancedSearchSizeComparison: String, CaseIterable, Identifiable, Sendable {
    case any
    case greaterThan
    case lessThan

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .any: return loc.text(es: "Cualquiera", en: "Any")
        case .greaterThan: return loc.text(es: "Mayor que (>)", en: "Greater than (>)")
        case .lessThan: return loc.text(es: "Menor que (<)", en: "Less than (<)")
        }
    }
}

public enum AdvancedSearchSizeUnit: String, CaseIterable, Identifiable, Sendable {
    case kb = "KB"
    case mb = "MB"
    case gb = "GB"

    public var id: String { rawValue }

    public var multiplierBytes: Int64 {
        switch self {
        case .kb: return 1024
        case .mb: return 1024 * 1024
        case .gb: return 1024 * 1024 * 1024
        }
    }
}

public struct AdvancedSearchOptions: Equatable, Sendable {
    public var fileType: AdvancedSearchFileType = .all
    public var customExtension: String = ""
    public var searchInsideContent: Bool = false
    public var includeSubfolders: Bool = false
    public var sizeComparison: AdvancedSearchSizeComparison = .any
    public var sizeValueText: String = ""
    public var sizeUnit: AdvancedSearchSizeUnit = .mb

    public init() {}

    public var targetByteThreshold: Int64? {
        guard sizeComparison != .any else { return nil }
        let normalized = sizeValueText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let numeric = Double(normalized), numeric >= 0 else { return nil }
        return Int64(numeric * Double(sizeUnit.multiplierBytes))
    }

    public var customExtensionsSet: Set<String> {
        let parts = customExtension
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty }
        return Set(parts)
    }

    public var hasActiveFilters: Bool {
        fileType != .all
            || !customExtensionsSet.isEmpty
            || searchInsideContent
            || includeSubfolders
            || targetByteThreshold != nil
    }

    public var requiresDeepScan: Bool {
        includeSubfolders || searchInsideContent
    }
}

/// Servicio de búsqueda avanzada en segundo plano:
/// filtra por tipo, extensión, tamaño, subcarpetas y contenido interno (texto, PDF e imágenes mediante OCR Vision).
public enum AdvancedSearchService {

    private static let plainTextExtensions: Set<String> = [
        "txt", "md", "markdown", "json", "csv", "log", "xml", "yaml", "yml",
        "html", "htm", "css", "scss", "swift", "py", "js", "ts", "tsx", "jsx",
        "sh", "zsh", "bash", "sql", "go", "rs", "java", "kt", "c", "cpp", "h",
        "hpp", "rb", "php", "toml", "ini", "plist", "env", "conf"
    ]

    private static let skipSubtreeNames: Set<String> = [
        "node_modules", ".git", ".hg", ".svn", ".build", ".swiftpm",
        "DerivedData", "Pods", ".Trash", "CoreSimulator", ".venv", "venv",
        "__pycache__", ".next", ".nuxt", "target", "dist"
    ]

    public static func performSearch(
        query: String,
        options: AdvancedSearchOptions,
        in rootURL: URL,
        includeHidden: Bool
    ) async -> [FileItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let standardizedRoot = rootURL.standardizedFileURL
            let keys: [URLResourceKey] = [
                .isDirectoryKey,
                .isPackageKey,
                .isHiddenKey,
                .isSymbolicLinkKey,
                .contentModificationDateKey,
                .fileSizeKey,
                .contentTypeKey,
                .localizedTypeDescriptionKey
            ]
            let keySet = Set(keys)
            let customExts = options.customExtensionsSet
            let sizeThreshold = options.targetByteThreshold

            let candidateURLs: [URL]
            if options.includeSubfolders {
                let enumOptions: FileManager.DirectoryEnumerationOptions = includeHidden
                    ? [.skipsPackageDescendants]
                    : [.skipsHiddenFiles, .skipsPackageDescendants]
                guard let enumerator = fm.enumerator(
                    at: standardizedRoot,
                    includingPropertiesForKeys: keys,
                    options: enumOptions
                ) else {
                    return []
                }
                var collected: [URL] = []
                while let nextURL = enumerator.nextObject() as? URL {
                    if Task.isCancelled { return [] }
                    if skipSubtreeNames.contains(nextURL.lastPathComponent) {
                        enumerator.skipDescendants()
                        continue
                    }
                    collected.append(nextURL)
                    if collected.count >= 25_000 { break }
                }
                candidateURLs = collected
            } else {
                let dirOptions: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
                candidateURLs = (try? fm.contentsOfDirectory(
                    at: standardizedRoot,
                    includingPropertiesForKeys: keys,
                    options: dirOptions
                )) ?? []
            }

            var results: [FileItem] = []
            for rawURL in candidateURLs {
                if Task.isCancelled { return [] }
                guard let values = try? rawURL.resourceValues(forKeys: keySet) else { continue }
                let isDir = values.isDirectory ?? false
                let isPkg = values.isPackage ?? false
                let ext = rawURL.pathExtension.lowercased()

                // 1. Filtro de tipo de archivo / extensión personalizada
                if !customExts.isEmpty {
                    guard !isDir, customExts.contains(ext) else { continue }
                } else if !options.fileType.matches(url: rawURL, isDirectory: isDir, isPackage: isPkg) {
                    continue
                }

                // 2. Filtro de tamaño
                let fileSize = values.fileSize.map { Int64($0) }
                if let sizeThreshold {
                    guard !isDir, let bytes = fileSize else { continue }
                    switch options.sizeComparison {
                    case .any:
                        break
                    case .greaterThan:
                        guard bytes >= sizeThreshold else { continue }
                    case .lessThan:
                        guard bytes <= sizeThreshold else { continue }
                    }
                }

                // 3. Filtro por nombre y/o contenido (texto, PDF, OCR de imagen)
                if !trimmedQuery.isEmpty {
                    let nameMatches = rawURL.lastPathComponent.localizedCaseInsensitiveContains(trimmedQuery)
                    if !nameMatches {
                        guard options.searchInsideContent, !isDir else { continue }
                        let contentMatches = matchesContent(
                            url: rawURL,
                            ext: ext,
                            query: trimmedQuery,
                            fileSize: fileSize
                        )
                        guard contentMatches else { continue }
                    }
                }

                let item = FileItem(
                    url: rawURL.standardizedFileURL,
                    name: rawURL.lastPathComponent,
                    fileExtension: rawURL.pathExtension,
                    isDirectory: isDir,
                    isPackage: isPkg,
                    isHidden: values.isHidden ?? false,
                    isSymbolicLink: values.isSymbolicLink ?? false,
                    modificationDate: values.contentModificationDate ?? .distantPast,
                    size: fileSize,
                    contentType: values.contentType,
                    kindDescription: values.localizedTypeDescription ?? (isDir ? "Carpeta" : "Archivo")
                )
                results.append(item)
                if results.count >= 1500 {
                    break
                }
            }

            return results
        }.value
    }

    private static func matchesContent(
        url: URL,
        ext: String,
        query: String,
        fileSize: Int64?
    ) -> Bool {
        // Texto plano / código
        if plainTextExtensions.contains(ext) {
            if let fileSize, fileSize > 8_000_000 { return false }
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return false }
            let slice = data.count > 4_000_000 ? data.prefix(4_000_000) : data[...]
            if let text = String(data: slice, encoding: .utf8) ?? String(data: slice, encoding: .isoLatin1) {
                return text.localizedCaseInsensitiveContains(query)
            }
            return false
        }

        // PDF (PDFKit)
        if ext == "pdf" {
            guard let doc = PDFDocument(url: url) else { return false }
            let maxPages = min(doc.pageCount, 120)
            for pageIndex in 0..<maxPages {
                if Task.isCancelled { return false }
                if let pageText = doc.page(at: pageIndex)?.string,
                   pageText.localizedCaseInsensitiveContains(query) {
                    return true
                }
            }
            return false
        }

        // Imágenes (OCR nativo con Vision)
        if QuickActionsService.isImageURL(url) {
            if let fileSize, fileSize > 25_000_000 { return false }
            return imageContainsTextViaOCR(url: url, query: query)
        }

        return false
    }

    private static func imageContainsTextViaOCR(url: URL, query: String) -> Bool {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(url: url, options: [:])
        do {
            try handler.perform([request])
            guard let observations = request.results else { return false }
            for observation in observations {
                if let candidate = observation.topCandidates(1).first,
                   candidate.string.localizedCaseInsensitiveContains(query) {
                    return true
                }
            }
        } catch {
            return false
        }
        return false
    }
}
