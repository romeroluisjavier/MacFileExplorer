import CoreGraphics
import Foundation
import ImageIO
import os
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
/// filtra por tipo, extensión, tamaño, subcarpetas y contenido interno (texto, PDF e imágenes mediante OCR Vision),
/// apoyándose en el índice oculto por carpeta `.macfileexplorer_ocr.cache` (<= 5 MB por carpeta).
public enum AdvancedSearchService {

    private static let prewarmClaimedLock = OSAllocatedUnfairLock(initialState: false)

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

    private struct CandidateMetadata: Sendable {
        let url: URL
        let ext: String
        let isDir: Bool
        let isPkg: Bool
        let isHidden: Bool
        let isSymlink: Bool
        let modificationDate: Date
        let fileSize: Int64?
        let contentType: UTType?
        let kindDescription: String

        func makeFileItem() -> FileItem {
            FileItem(
                url: url.standardizedFileURL,
                name: url.lastPathComponent,
                fileExtension: url.pathExtension,
                isDirectory: isDir,
                isPackage: isPkg,
                isHidden: isHidden,
                isSymbolicLink: isSymlink,
                modificationDate: modificationDate,
                size: fileSize,
                contentType: contentType,
                kindDescription: kindDescription
            )
        }
    }

    /// Precalienta el motor OCR `.fast` de Vision en segundo plano (~50 ms, sin provocar compilaciones
    /// pesadas del Neural Engine al arrancar la app) para búsquedas instantáneas dentro de imágenes.
    public static func prewarmOCRInBackground() {
        let shouldRun = prewarmClaimedLock.withLock { claimed in
            if claimed { return false }
            claimed = true
            return true
        }
        guard shouldRun else { return }

        Task.detached(priority: .background) {
            try? await Task.sleep(for: .seconds(4))
            if Task.isCancelled || ProcessInfo.processInfo.isLowPowerModeEnabled { return }
            autoreleasepool {
                let width = 96
                let height = 32
                guard let ctx = CGContext(
                    data: nil,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ),
                let cgImage = ctx.makeImage() else {
                    return
                }
                let request = makeFastOCRRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([request])
            }
        }
    }

    public static func performSearch(
        query: String,
        options: AdvancedSearchOptions,
        in rootURL: URL,
        includeHidden: Bool,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil,
        onPartialResults: (@Sendable ([FileItem]) -> Void)? = nil
    ) async -> [FileItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        let scanPlan = await Task.detached(priority: .userInitiated) { () -> (directMatches: [FileItem], contentQueue: [CandidateMetadata]) in
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
                    return ([], [])
                }
                var collected: [URL] = []
                while let nextURL = enumerator.nextObject() as? URL {
                    if Task.isCancelled { return ([], []) }
                    let name = nextURL.lastPathComponent
                    if skipSubtreeNames.contains(name) {
                        enumerator.skipDescendants()
                        continue
                    }
                    if name.hasPrefix(".macfileexplorer_") { continue }
                    collected.append(nextURL)
                    if collected.count >= 25_000 { break }
                }
                candidateURLs = collected
            } else {
                let dirOptions: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
                candidateURLs = ((try? fm.contentsOfDirectory(
                    at: standardizedRoot,
                    includingPropertiesForKeys: keys,
                    options: dirOptions
                )) ?? []).filter { !$0.lastPathComponent.hasPrefix(".macfileexplorer_") }
            }

            var directMatches: [FileItem] = []
            var contentQueue: [CandidateMetadata] = []

            for rawURL in candidateURLs {
                if Task.isCancelled { return ([], []) }
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

                let meta = CandidateMetadata(
                    url: rawURL,
                    ext: ext,
                    isDir: isDir,
                    isPkg: isPkg,
                    isHidden: values.isHidden ?? false,
                    isSymlink: values.isSymbolicLink ?? false,
                    modificationDate: values.contentModificationDate ?? .distantPast,
                    fileSize: fileSize,
                    contentType: values.contentType,
                    kindDescription: values.localizedTypeDescription ?? (isDir ? "Carpeta" : "Archivo")
                )

                // 3. Filtro por nombre y/o contenido
                if trimmedQuery.isEmpty {
                    directMatches.append(meta.makeFileItem())
                    if directMatches.count >= 1500 { break }
                } else if containsQuery(rawURL.lastPathComponent, query: trimmedQuery) {
                    directMatches.append(meta.makeFileItem())
                    if directMatches.count >= 1500 { break }
                } else if options.searchInsideContent,
                          !isDir,
                          isSupportedContentCandidate(url: rawURL, ext: ext, contentType: values.contentType) {
                    contentQueue.append(meta)
                }
            }

            return (directMatches, contentQueue)
        }.value

        if Task.isCancelled { return [] }

        var results = scanPlan.directMatches
        let queue = scanPlan.contentQueue
        if !results.isEmpty {
            onPartialResults?(results)
        }
        guard !trimmedQuery.isEmpty, !queue.isEmpty, results.count < 1500 else {
            return results
        }

        let totalCount = queue.count
        onProgress?(0, totalCount)

        let maxConcurrency = max(2, min(ProcessInfo.processInfo.activeProcessorCount / 2, 4))
        var nextIndex = 0
        var completedCount = 0
        var lastStreamEmitCount = results.count

        await withTaskGroup(of: FileItem?.self) { group in
            let initialBatch = min(maxConcurrency, queue.count)
            for _ in 0..<initialBatch {
                let candidate = queue[nextIndex]
                nextIndex += 1
                group.addTask(priority: .userInitiated) {
                    if Task.isCancelled { return nil }
                    let matched = await matchesContent(
                        candidate: candidate,
                        query: trimmedQuery
                    )
                    return matched ? candidate.makeFileItem() : nil
                }
            }

            while let maybeItem = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }

                completedCount += 1
                if completedCount == totalCount || completedCount % 2 == 0 {
                    onProgress?(completedCount, totalCount)
                }

                if let item = maybeItem {
                    results.append(item)
                    if results.count != lastStreamEmitCount {
                        lastStreamEmitCount = results.count
                        onPartialResults?(results)
                    }
                    if results.count >= 1500 {
                        group.cancelAll()
                        break
                    }
                }

                if nextIndex < queue.count {
                    let candidate = queue[nextIndex]
                    nextIndex += 1
                    group.addTask(priority: .userInitiated) {
                        if Task.isCancelled { return nil }
                        let matched = await matchesContent(
                            candidate: candidate,
                            query: trimmedQuery
                        )
                        return matched ? candidate.makeFileItem() : nil
                    }
                }
            }
        }

        return Task.isCancelled ? [] : results
    }

    private static func isSupportedContentCandidate(url: URL, ext: String, contentType: UTType?) -> Bool {
        if plainTextExtensions.contains(ext) || ext == "pdf" || QuickActionsService.isImageURL(url) {
            return true
        }
        return contentType?.conforms(to: .image) == true || contentType?.conforms(to: .plainText) == true
    }

    private static func containsQuery(_ text: String, query: String) -> Bool {
        guard !query.isEmpty, !text.isEmpty else { return false }
        if text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return true
        }

        let normalizedText = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if normalizedText.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return true
        }

        // Si la consulta tiene múltiples palabras, exigir que cada término aparezca en el texto OCR/documento
        let tokens = query
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= 2 }
        if tokens.count >= 2 {
            return tokens.allSatisfy { token in
                normalizedText.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
        return false
    }

    private static func matchesContent(
        candidate: CandidateMetadata,
        query: String
    ) async -> Bool {
        let url = candidate.url
        let ext = candidate.ext
        let fileSize = candidate.fileSize

        // Texto plano / código
        if plainTextExtensions.contains(ext) || candidate.contentType?.conforms(to: .plainText) == true {
            if let fileSize, fileSize > 8_000_000 { return false }
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return false }
            let slice = data.count > 4_000_000 ? data.prefix(4_000_000) : data[...]
            if let text = String(data: slice, encoding: .utf8) ?? String(data: slice, encoding: .isoLatin1) {
                return containsQuery(text, query: query)
            }
            return false
        }

        // PDF (PDFKit)
        if ext == "pdf" {
            return autoreleasepool {
                guard let doc = PDFDocument(url: url) else { return false }
                let maxPages = min(doc.pageCount, 120)
                for pageIndex in 0..<maxPages {
                    if Task.isCancelled { return false }
                    if let pageText = doc.page(at: pageIndex)?.string,
                       containsQuery(pageText, query: query) {
                        return true
                    }
                }
                return false
            }
        }

        // Imágenes (índice oculto por carpeta `.macfileexplorer_ocr.cache` + OCR Vision preciso)
        if QuickActionsService.isImageURL(url) || candidate.contentType?.conforms(to: .image) == true {
            if let fileSize, fileSize > 50_000_000 { return false }
            return await imageContainsTextViaOCR(
                url: url,
                fileSize: fileSize,
                modificationDate: candidate.modificationDate,
                query: query
            )
        }

        return false
    }

    private static func makeFastOCRRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["es-ES", "en-US"]
        return request
    }

    private static func makeAccurateOCRRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["es-ES", "en-US"]
        request.minimumTextHeight = 0.015
        return request
    }

    private static func imageContainsTextViaOCR(
        url: URL,
        fileSize: Int64?,
        modificationDate: Date,
        query: String
    ) async -> Bool {
        if let cachedTranscript = await OCRIndexCacheService.shared.cachedTranscript(
            for: url,
            fileSize: fileSize,
            modificationDate: modificationDate
        ) {
            return containsQuery(cachedTranscript, query: query)
        }

        let transcript = extractOCRTranscript(at: url)
        await OCRIndexCacheService.shared.storeTranscript(
            transcript,
            for: url,
            fileSize: fileSize,
            modificationDate: modificationDate
        )
        return containsQuery(transcript, query: query)
    }

    /// Extrae todo el texto legible de una imagen usando Vision optimizado para Apple Silicon:
    /// - `isBackgroundIndex == true`: decodificación ImageIO reescalada a máx. 1400 px y pasada `.fast` en E-cores.
    /// - `isBackgroundIndex == false`: estrategia en 2 etapas — pasada `.fast` (~15–50 ms sin compilación ANE en frío)
    ///   con respaldo `.accurate` + reescalado 2× únicamente si `.fast` no detecta texto legible.
    public static func extractOCRTranscript(at url: URL, isBackgroundIndex: Bool = false) -> String {
        autoreleasepool {
            let source = CGImageSourceCreateWithURL(url as CFURL, nil)

            if isBackgroundIndex {
                guard let source else { return "" }
                let thumbOptions: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: false,
                    kCGImageSourceThumbnailMaxPixelSize: 1400
                ]
                guard let downsampled = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
                    return ""
                }
                let request = makeFastOCRRequest()
                let handler = VNImageRequestHandler(cgImage: downsampled, options: [:])
                if (try? handler.perform([request])) != nil,
                   let observations = request.results,
                   !observations.isEmpty {
                    return buildTranscript(from: observations)
                }
                return ""
            }

            let orientation = readImageOrientation(from: source)

            // Etapa 1: pasada `.fast` (~15–50 ms, evita bloqueos de compilación ANE en frío de 60s+ en Apple Silicon)
            var primaryTranscript = ""
            let fastRequest = makeFastOCRRequest()
            let fastHandler = VNImageRequestHandler(url: url, orientation: orientation, options: [:])
            if (try? fastHandler.perform([fastRequest])) != nil,
               let observations = fastRequest.results,
               !observations.isEmpty {
                primaryTranscript = buildTranscript(from: observations)
                if !primaryTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return primaryTranscript
                }
            }

            // Etapa 2: respaldo `.accurate` (solo si `.fast` no logró extraer texto, p. ej. texto inclinado o muy chico)
            if let source,
               let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                let fallbackImage: CGImage
                if cgImage.width < 1400 && cgImage.height < 1400,
                   let upscaled = upscaleCGImage2x(cgImage) {
                    fallbackImage = upscaled
                } else {
                    fallbackImage = cgImage
                }

                let fallbackRequest = makeAccurateOCRRequest()
                let cgHandler = VNImageRequestHandler(cgImage: fallbackImage, orientation: orientation, options: [:])
                if (try? cgHandler.perform([fallbackRequest])) != nil,
                   let observations = fallbackRequest.results,
                   !observations.isEmpty {
                    let secondary = buildTranscript(from: observations)
                    return secondary.count >= primaryTranscript.count ? secondary : primaryTranscript
                }
            }

            return primaryTranscript
        }
    }

    private static func upscaleCGImage2x(_ image: CGImage) -> CGImage? {
        let newW = image.width * 2
        let newH = image.height * 2
        guard newW > 0, newH > 0, newW <= 4096, newH <= 4096 else { return nil }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: newW,
            height: newH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return ctx.makeImage()
    }

    private static func readImageOrientation(from source: CGImageSource?) -> CGImagePropertyOrientation {
        guard let source,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawValue = props[kCGImagePropertyOrientation] as? UInt32,
              let orientation = CGImagePropertyOrientation(rawValue: rawValue) else {
            return .up
        }
        return orientation
    }

    private static func buildTranscript(from observations: [VNRecognizedTextObservation]) -> String {
        var topLines: [String] = []
        var extraCandidates: [String] = []
        topLines.reserveCapacity(observations.count)

        for observation in observations {
            let candidates = observation.topCandidates(3)
            if let first = candidates.first?.string, !first.isEmpty {
                topLines.append(first)
            }
            for alt in candidates.dropFirst() where !alt.string.isEmpty {
                extraCandidates.append(alt.string)
            }
        }

        let joinedTop = topLines.joined(separator: " ")
        if extraCandidates.isEmpty {
            return joinedTop
        }
        return ([joinedTop] + extraCandidates).joined(separator: "\n")
    }
}
