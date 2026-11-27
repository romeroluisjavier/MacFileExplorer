import AppKit
import Foundation
import Observation

/// Fuente centralizada de la versión instalada de la aplicación.
public enum AppVersionInfo {
    public static let repositoryOwner = "romeroluisjavier"
    public static let repositoryName = "MacFileExplorer"

    public static let repositoryURL = URL(string: "https://github.com/\(repositoryOwner)/\(repositoryName)")!
    public static let releasesPageURL = URL(string: "https://github.com/\(repositoryOwner)/\(repositoryName)/releases")!

    public static var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            ?? "2.8.0"
    }

    public static var currentBuild: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            ?? "18"
    }
}

/// Versión semántica comparable (ej. `1.5.0`, `v1.6`, `2.0.1`).
public struct SemanticVersion: Comparable, Hashable, Sendable {
    public let components: [Int]
    public let isPrerelease: Bool

    public init?(string: String, allowPrerelease: Bool = true) {
        var cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("v") {
            cleaned.removeFirst()
        }
        guard !cleaned.isEmpty else { return nil }

        if let plusIndex = cleaned.firstIndex(of: "+") {
            cleaned = String(cleaned[..<plusIndex])
        }

        var prerelease = false
        if let dashIndex = cleaned.firstIndex(of: "-") {
            prerelease = true
            cleaned = String(cleaned[..<dashIndex])
        }

        if prerelease && !allowPrerelease {
            return nil
        }

        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }

        var parsed: [Int] = []
        parsed.reserveCapacity(parts.count)
        for part in parts {
            guard !part.isEmpty, let value = Int(part), value >= 0 else {
                return nil
            }
            parsed.append(value)
        }

        self.components = parsed
        self.isPrerelease = prerelease
    }

    public var canonicalString: String {
        var normalized = components
        while normalized.count < 3 {
            normalized.append(0)
        }
        return normalized.map(String.init).joined(separator: ".")
    }

    private func normalizedComponents(length: Int) -> [Int] {
        var result = components
        if result.count < length {
            result.append(contentsOf: repeatElement(0, count: length - result.count))
        }
        return result
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        return lhs.normalizedComponents(length: count) == rhs.normalizedComponents(length: count)
            && lhs.isPrerelease == rhs.isPrerelease
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        let left = lhs.normalizedComponents(length: count)
        let right = rhs.normalizedComponents(length: count)
        for (l, r) in zip(left, right) where l != r {
            return l < r
        }
        return lhs.isPrerelease && !rhs.isPrerelease
    }

    public func hash(into hasher: inout Hasher) {
        var trimmed = components
        while trimmed.count > 1, trimmed.last == 0 {
            trimmed.removeLast()
        }
        hasher.combine(trimmed)
        hasher.combine(isPrerelease)
    }
}

/// Información de una versión remota encontrada en el repositorio de GitHub.
public struct UpdateRemoteInfo: Sendable, Equatable {
    public let version: SemanticVersion
    public let tagName: String
    public let installerDownloadURL: URL?
    public let installerFileName: String?
    public let expectedFileSize: Int64?
    public let pageURL: URL
    public let releaseNotesText: String?

    public var versionString: String {
        version.canonicalString
    }

    public init(
        version: SemanticVersion,
        tagName: String,
        installerDownloadURL: URL?,
        installerFileName: String?,
        expectedFileSize: Int64?,
        pageURL: URL,
        releaseNotesText: String?
    ) {
        self.version = version
        self.tagName = tagName
        self.installerDownloadURL = installerDownloadURL
        self.installerFileName = installerFileName
        self.expectedFileSize = expectedFileSize
        self.pageURL = pageURL
        self.releaseNotesText = releaseNotesText
    }
}

/// Estado observable del flujo de búsqueda y descarga de actualizaciones.
public enum AppUpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate(checkedAt: Date, latestKnown: UpdateRemoteInfo?)
    case updateAvailable(info: UpdateRemoteInfo)
    case downloading(info: UpdateRemoteInfo, downloadedBytes: Int64, totalBytes: Int64?, progress: Double?)
    case downloaded(info: UpdateRemoteInfo, fileURL: URL, reusedExisting: Bool)
    case updateAvailableNoInstaller(info: UpdateRemoteInfo)
    case failed(message: String)
}

/// Analizador puro (sin E/S) de respuestas de GitHub API / `Info.plist` / `ReleaseNotes.swift`.
public enum GitHubUpdateParser {
    struct GitHubReleaseDTO: Decodable {
        struct AssetDTO: Decodable {
            let name: String
            let size: Int64?
            let browser_download_url: String
        }

        let tag_name: String
        let name: String?
        let draft: Bool?
        let prerelease: Bool?
        let html_url: String?
        let body: String?
        let assets: [AssetDTO]?
    }

    struct GitHubTagDTO: Decodable {
        let name: String
    }

    struct GitHubContentEntryDTO: Decodable {
        let name: String
        let type: String?
        let size: Int64?
        let download_url: String?
        let html_url: String?
    }

    struct AssetMatch: Sendable {
        let version: SemanticVersion
        let fileName: String
        let downloadURL: URL
        let pageURL: URL?
        let size: Int64?
        let priorityRank: Int // .dmg = 2, .zip = 1
    }

    /// Extrae la versión semántica de un nombre de paquete como `MacFileExplorer-1.5.0.dmg`.
    public static func parseVersionFromAssetName(_ name: String) -> (version: SemanticVersion, priorityRank: Int)? {
        let lower = name.lowercased()
        let rank: Int
        if lower.hasSuffix(".dmg") {
            rank = 2
        } else if lower.hasSuffix(".zip") {
            rank = 1
        } else {
            return nil
        }

        guard let regex = try? NSRegularExpression(
            pattern: "(?i)macfileexplorer[-_]?v?(\\d+(?:\\.\\d+)+)\\.(dmg|zip)$"
        ) else {
            return nil
        }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        guard let match = regex.firstMatch(in: name, range: range),
              let versionRange = Range(match.range(at: 1), in: name),
              let parsed = SemanticVersion(string: String(name[versionRange]), allowPrerelease: false) else {
            return nil
        }
        return (parsed, rank)
    }

    /// Parsea la versión declarada en `Config/Info.plist`.
    public static func parseVersionFromInfoPlist(_ data: Data) -> SemanticVersion? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = plist as? [String: Any],
              let rawVersion = dict["CFBundleShortVersionString"] as? String else {
            return nil
        }
        return SemanticVersion(string: rawVersion, allowPrerelease: false)
    }

    /// Construye la lista ordenada de versiones candidatas combinando Releases, carpeta `releases/` y Tags.
    public static func collectCandidates(
        releasesData: Data?,
        tagsData: Data?,
        contentsData: Data?,
        fallbackPlistData: Data?,
        owner: String = AppVersionInfo.repositoryOwner,
        repo: String = AppVersionInfo.repositoryName
    ) -> [UpdateRemoteInfo] {
        var repoAssetsByVersion: [SemanticVersion: AssetMatch] = [:]

        if let contentsData,
           let entries = try? JSONDecoder().decode([GitHubContentEntryDTO].self, from: contentsData) {
            for entry in entries where entry.type == "file" {
                guard let parsed = parseVersionFromAssetName(entry.name),
                      let rawDownload = entry.download_url,
                      let downloadURL = URL(string: rawDownload) else {
                    continue
                }
                let pageURL = entry.html_url.flatMap(URL.init(string:))
                let existing = repoAssetsByVersion[parsed.version]
                if existing == nil || parsed.priorityRank > existing!.priorityRank {
                    repoAssetsByVersion[parsed.version] = AssetMatch(
                        version: parsed.version,
                        fileName: entry.name,
                        downloadURL: downloadURL,
                        pageURL: pageURL,
                        size: entry.size,
                        priorityRank: parsed.priorityRank
                    )
                }
            }
        }

        var mergedByVersion: [SemanticVersion: UpdateRemoteInfo] = [:]

        if let releasesData,
           let releases = try? JSONDecoder().decode([GitHubReleaseDTO].self, from: releasesData) {
            for release in releases where release.draft != true && release.prerelease != true {
                guard let version = SemanticVersion(string: release.tag_name, allowPrerelease: false)
                    ?? release.name.flatMap({ extractVersionFromText($0) }) else {
                    continue
                }

                let bestReleaseAsset = bestAsset(in: release.assets ?? [])
                let repoFallbackAsset = repoAssetsByVersion[version]
                let downloadURL = bestReleaseAsset?.downloadURL ?? repoFallbackAsset?.downloadURL
                let fileName = bestReleaseAsset?.fileName ?? repoFallbackAsset?.fileName
                let fileSize = bestReleaseAsset?.size ?? repoFallbackAsset?.size
                let pageURL = release.html_url.flatMap(URL.init(string:))
                    ?? URL(string: "https://github.com/\(owner)/\(repo)/releases/tag/\(release.tag_name)")!
                let body = release.body?.trimmingCharacters(in: .whitespacesAndNewlines)

                let candidate = UpdateRemoteInfo(
                    version: version,
                    tagName: release.tag_name,
                    installerDownloadURL: downloadURL,
                    installerFileName: fileName,
                    expectedFileSize: fileSize,
                    pageURL: pageURL,
                    releaseNotesText: (body?.isEmpty == false) ? body : nil
                )
                mergedByVersion[version] = preferredInfo(existing: mergedByVersion[version], incoming: candidate)
            }
        }

        if let tagsData,
           let tags = try? JSONDecoder().decode([GitHubTagDTO].self, from: tagsData) {
            for tag in tags {
                guard let version = SemanticVersion(string: tag.name, allowPrerelease: false) else {
                    continue
                }
                let matchedAsset = repoAssetsByVersion[version]
                let pageURL = URL(string: "https://github.com/\(owner)/\(repo)/releases/tag/\(tag.name)")!
                let candidate = UpdateRemoteInfo(
                    version: version,
                    tagName: tag.name,
                    installerDownloadURL: matchedAsset?.downloadURL,
                    installerFileName: matchedAsset?.fileName,
                    expectedFileSize: matchedAsset?.size,
                    pageURL: pageURL,
                    releaseNotesText: nil
                )
                mergedByVersion[version] = preferredInfo(existing: mergedByVersion[version], incoming: candidate)
            }
        }

        for (version, asset) in repoAssetsByVersion {
            let tag = "v\(version.canonicalString)"
            let pageURL = URL(string: "https://github.com/\(owner)/\(repo)/tree/main/releases")!
            let candidate = UpdateRemoteInfo(
                version: version,
                tagName: tag,
                installerDownloadURL: asset.downloadURL,
                installerFileName: asset.fileName,
                expectedFileSize: asset.size,
                pageURL: pageURL,
                releaseNotesText: nil
            )
            mergedByVersion[version] = preferredInfo(existing: mergedByVersion[version], incoming: candidate)
        }

        if let fallbackPlistData,
           let plistVersion = parseVersionFromInfoPlist(fallbackPlistData) {
            let tag = "v\(plistVersion.canonicalString)"
            let matchedAsset = repoAssetsByVersion[plistVersion]
            let pageURL = URL(string: "https://github.com/\(owner)/\(repo)")!
            let candidate = UpdateRemoteInfo(
                version: plistVersion,
                tagName: tag,
                installerDownloadURL: matchedAsset?.downloadURL,
                installerFileName: matchedAsset?.fileName,
                expectedFileSize: matchedAsset?.size,
                pageURL: pageURL,
                releaseNotesText: nil
            )
            mergedByVersion[plistVersion] = preferredInfo(existing: mergedByVersion[plistVersion], incoming: candidate)
        }

        return mergedByVersion.values.sorted { lhs, rhs in
            if lhs.version != rhs.version {
                return lhs.version > rhs.version
            }
            return (lhs.installerDownloadURL != nil) && (rhs.installerDownloadURL == nil)
        }
    }

    /// Extrae títulos breves de la sección más reciente en `ReleaseNotes.swift` remoto según el idioma.
    public static func extractLatestSectionTitles(fromReleaseNotesSwift source: String, isSpanish: Bool) -> String? {
        let key = isSpanish ? "titleES" : "titleEN"
        guard let sectionAnchor = source.range(of: "ReleaseNoteSection(") else { return nil }
        let afterFirstSection = source[sectionAnchor.upperBound...]
        let sectionSlice: Substring
        if let secondSection = afterFirstSection.range(of: "ReleaseNoteSection(") {
            sectionSlice = afterFirstSection[..<secondSection.lowerBound]
        } else {
            sectionSlice = afterFirstSection
        }

        let sectionText = String(sectionSlice)
        guard let regex = try? NSRegularExpression(pattern: "\(key):\\s*\"((?:[^\"\\\\]|\\\\.)+)\"") else {
            return nil
        }
        let range = NSRange(sectionText.startIndex..<sectionText.endIndex, in: sectionText)
        let matches = regex.matches(in: sectionText, range: range)
        let titles = matches.prefix(8).compactMap { match -> String? in
            guard let r = Range(match.range(at: 1), in: sectionText) else { return nil }
            let value = String(sectionText[r])
                .replacingOccurrences(of: "\\\"", with: "\"")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : "• \(value)"
        }
        return titles.isEmpty ? nil : titles.joined(separator: "\n")
    }

    /// Limpia sintaxis Markdown cruda (`[texto](url)`, `**negrita**`, encabezados `###`, enlaces boilerplate)
    /// para mostrar notas de actualización claras y amigables para cualquier usuario.
    public static func sanitizeReleaseNotesForDisplay(_ raw: String) -> String {
        let markdownLinkRegex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\((https?://[^)]+)\)"#)
        let rawLines = raw.components(separatedBy: .newlines)
        var cleanedLines: [String] = []

        for line in rawLines {
            var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "---" || trimmed == "***" { continue }

            let lower = trimmed.lowercased()
            // Omitir líneas boilerplate de enlaces o instrucciones repetitivas del README de GitHub
            if lower.contains("sitio web y demos")
                || lower.contains("historial de cambios")
                || lower.contains("releases/readme.md")
                || lower.contains("sha-256")
                || lower.contains("shasum")
                || lower.contains("xattr -dr")
                || lower.hasPrefix("## instalación")
                || lower.hasPrefix("## instalacion")
                || lower.hasPrefix("## how to install")
                || lower.hasPrefix("### instalación")
                || lower.hasPrefix("```") {
                continue
            }

            // Reemplazar enlaces Markdown `[label](url)` por solo `label`
            if let regex = markdownLinkRegex {
                let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
                trimmed = regex.stringByReplacingMatches(in: trimmed, range: range, withTemplate: "$1")
            }

            // Limpiar marcadores de Markdown crudo
            trimmed = trimmed
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "__", with: "")
                .replacingOccurrences(of: "`", with: "")

            while trimmed.hasPrefix("#") {
                trimmed.removeFirst()
            }
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                trimmed = "• " + String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }

            // Evitar líneas que sean únicamente una URL suelta
            if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
                continue
            }

            cleanedLines.append(trimmed)
            if cleanedLines.count >= 12 { break }
        }

        return cleanedLines.joined(separator: "\n")
    }

    private static func bestAsset(in assets: [GitHubReleaseDTO.AssetDTO]) -> AssetMatch? {
        var best: AssetMatch?
        for asset in assets {
            let lower = asset.name.lowercased()
            let rank: Int
            if lower.hasSuffix(".dmg") {
                rank = 2
            } else if lower.hasSuffix(".zip") {
                rank = 1
            } else {
                continue
            }
            guard let url = URL(string: asset.browser_download_url) else { continue }
            let version = parseVersionFromAssetName(asset.name)?.version ?? SemanticVersion(string: "0.0.0")!
            let candidate = AssetMatch(
                version: version,
                fileName: asset.name,
                downloadURL: url,
                pageURL: nil,
                size: asset.size,
                priorityRank: rank
            )
            if best == nil || candidate.priorityRank > best!.priorityRank {
                best = candidate
            }
        }
        return best
    }

    private static func extractVersionFromText(_ text: String) -> SemanticVersion? {
        guard let regex = try? NSRegularExpression(pattern: "(?i)\\bv?(\\d+(?:\\.\\d+)+)\\b") else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let versionRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return SemanticVersion(string: String(text[versionRange]), allowPrerelease: false)
    }

    private static func preferredInfo(existing: UpdateRemoteInfo?, incoming: UpdateRemoteInfo) -> UpdateRemoteInfo {
        guard let existing else { return incoming }
        let downloadURL = existing.installerDownloadURL ?? incoming.installerDownloadURL
        let fileName = existing.installerFileName ?? incoming.installerFileName
        let fileSize = existing.expectedFileSize ?? incoming.expectedFileSize
        let notes = existing.releaseNotesText ?? incoming.releaseNotesText
        let tagName = existing.tagName.isEmpty ? incoming.tagName : existing.tagName
        let pageURL = existing.installerDownloadURL != nil ? existing.pageURL : incoming.pageURL

        return UpdateRemoteInfo(
            version: existing.version,
            tagName: tagName,
            installerDownloadURL: downloadURL,
            installerFileName: fileName,
            expectedFileSize: fileSize,
            pageURL: pageURL,
            releaseNotesText: notes
        )
    }
}

/// Gestor central (`@MainActor @Observable`) encargado de comprobar actualizaciones en GitHub
/// y descargar el instalador `.dmg` cuando exista una versión superior a la instalada.
@MainActor
@Observable
public final class AppUpdateManager {
    public static let shared = AppUpdateManager()

    public var state: AppUpdateState = .idle

    private var activeCheckTask: Task<Void, Never>?
    private var activeDownloadSession: URLSession?
    private var activeDownloadTask: URLSessionDownloadTask?
    private var isCancellingExplicitly = false

    private init() {}

    public var isBusy: Bool {
        switch state {
        case .checking, .downloading:
            return true
        default:
            return false
        }
    }

    /// Consulta el repositorio de GitHub y descarga automáticamente el instalador si hay una versión nueva.
    public func checkForUpgrades(autoDownload: Bool = true) {
        if case .checking = state { return }
        if case .downloading = state { return }

        activeCheckTask?.cancel()
        isCancellingExplicitly = false
        state = .checking

        activeCheckTask = Task { [weak self] in
            guard let self else { return }
            await self.performCheck(autoDownload: autoDownload)
        }
    }

    /// Inicia la descarga del paquete instalador hacia `~/Downloads`.
    public func downloadUpdate(_ info: UpdateRemoteInfo, forceRedownload: Bool = false) {
        guard let downloadURL = info.installerDownloadURL else {
            state = .updateAvailableNoInstaller(info: info)
            return
        }

        guard let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            state = .failed(message: LocalizationManager.shared.text(
                es: "No se pudo localizar la carpeta Descargas.",
                en: "Could not locate the Downloads folder."
            ))
            return
        }

        let fileName = info.installerFileName ?? "MacFileExplorer-\(info.versionString).dmg"
        let destinationURL = downloadsDir.appendingPathComponent(fileName)

        if !forceRedownload,
           let expectedSize = info.expectedFileSize,
           expectedSize > 0,
           FileManager.default.fileExists(atPath: destinationURL.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: destinationURL.path),
           let localSize = (attrs[.size] as? NSNumber)?.int64Value,
           localSize == expectedSize {
            state = .downloaded(info: info, fileURL: destinationURL, reusedExisting: true)
            return
        }

        cancelDownloadSessionOnly()
        isCancellingExplicitly = false
        state = .downloading(
            info: info,
            downloadedBytes: 0,
            totalBytes: info.expectedFileSize,
            progress: nil
        )

        var request = URLRequest(url: downloadURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue("MacFileExplorer/\(AppVersionInfo.currentVersion)", forHTTPHeaderField: "User-Agent")

        let bridge = DownloadDelegateBridge(
            destinationURL: destinationURL,
            expectedFileSize: info.expectedFileSize,
            onProgress: { [weak self] written, totalExpected in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard case .downloading(let currentInfo, _, _, _) = self.state else { return }
                    let resolvedTotal: Int64? = totalExpected > 0
                        ? totalExpected
                        : currentInfo.expectedFileSize
                    let progress: Double?
                    if let resolvedTotal, resolvedTotal > 0 {
                        progress = min(max(Double(written) / Double(resolvedTotal), 0.0), 1.0)
                    } else {
                        progress = nil
                    }
                    self.state = .downloading(
                        info: currentInfo,
                        downloadedBytes: written,
                        totalBytes: resolvedTotal,
                        progress: progress
                    )
                }
            },
            onCompletion: { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.cleanupDownloadReferences()

                    switch result {
                    case .success(let savedURL):
                        self.state = .downloaded(info: info, fileURL: savedURL, reusedExisting: false)
                    case .failure(let error):
                        if self.isCancellingExplicitly || (error as NSError).code == NSURLErrorCancelled {
                            self.isCancellingExplicitly = false
                            self.state = .updateAvailable(info: info)
                        } else {
                            InternalErrorLogger.shared.logNonFatalError(
                                category: "APP_UPDATE_DOWNLOAD",
                                error: error,
                                context: ["targetVersion": info.versionString]
                            )
                            self.state = .failed(message: error.localizedDescription)
                        }
                    }
                }
            }
        )

        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: bridge, delegateQueue: nil)
        let task = session.downloadTask(with: request)
        activeDownloadSession = session
        activeDownloadTask = task
        task.resume()
    }

    /// Cancela la comprobación o descarga en curso.
    public func cancelCurrentOperation() {
        isCancellingExplicitly = true
        activeCheckTask?.cancel()
        activeCheckTask = nil

        switch state {
        case .checking:
            state = .idle
        case .downloading(let info, _, _, _):
            cancelDownloadSessionOnly()
            state = .updateAvailable(info: info)
        default:
            cancelDownloadSessionOnly()
        }
    }

    /// Abre el archivo `.dmg` descargado en macOS para montar el instalador.
    public func openInstaller(_ fileURL: URL) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            state = .failed(message: LocalizationManager.shared.text(
                es: "El archivo descargado ya no está en Descargas.",
                en: "The downloaded file is no longer in Downloads."
            ))
            return
        }
        NSWorkspace.shared.open(fileURL)
    }

    /// Abre la carpeta Descargas directamente dentro de MacFileExplorer.
    public func showInDownloads(_ fileURL: URL) {
        let folderURL = fileURL.deletingLastPathComponent()
        NSApplication.shared.activate(ignoringOtherApps: true)
        GoogleAccountsManager.shared.openOrFocusMainWindow(at: folderURL)
    }

    /// Abre la página del release o repositorio en el navegador predeterminado.
    public func openGitHubPage(_ url: URL? = nil) {
        NSWorkspace.shared.open(url ?? AppVersionInfo.releasesPageURL)
    }

    // MARK: - Implementación interna

    private func performCheck(autoDownload: Bool) async {
        let currentSemantic = SemanticVersion(string: AppVersionInfo.currentVersion, allowPrerelease: true)
            ?? SemanticVersion(string: "1.5.0")!

        do {
            let result = try await fetchRemoteCandidates(currentVersion: currentSemantic)
            if Task.isCancelled || isCancellingExplicitly {
                return
            }

            let candidates = result.candidates
            guard let highestKnown = candidates.first else {
                if let failureError = result.lastError {
                    state = .failed(message: localizedNetworkErrorMessage(failureError))
                } else {
                    state = .upToDate(checkedAt: Date(), latestKnown: nil)
                }
                return
            }

            let upgrades = candidates.filter { $0.version > currentSemantic }
            guard let newestUpgrade = upgrades.first else {
                state = .upToDate(checkedAt: Date(), latestKnown: highestKnown)
                return
            }

            var chosen = upgrades.first(where: { $0.installerDownloadURL != nil }) ?? newestUpgrade
            chosen = await enrichCandidateIfNeeded(chosen)
            if Task.isCancelled || isCancellingExplicitly {
                return
            }

            if chosen.installerDownloadURL != nil {
                if autoDownload {
                    downloadUpdate(chosen)
                } else {
                    state = .updateAvailable(info: chosen)
                }
            } else {
                state = .updateAvailableNoInstaller(info: chosen)
            }
        } catch is CancellationError {
            return
        } catch {
            if !isCancellingExplicitly {
                state = .failed(message: localizedNetworkErrorMessage(error))
            }
        }
    }

    private func fetchRemoteCandidates(
        currentVersion: SemanticVersion
    ) async throws -> (candidates: [UpdateRemoteInfo], lastError: Error?) {
        let owner = AppVersionInfo.repositoryOwner
        let repo = AppVersionInfo.repositoryName

        let releasesURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases?per_page=10")!
        let tagsURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/tags?per_page=30")!
        let contentsURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/contents/releases?ref=main")!
        let plistURL = URL(string: "https://raw.githubusercontent.com/\(owner)/\(repo)/main/Config/Info.plist")!

        async let releasesRes = fetchData(from: releasesURL, isGitHubAPI: true)
        async let tagsRes = fetchData(from: tagsURL, isGitHubAPI: true)
        async let contentsRes = fetchData(from: contentsURL, isGitHubAPI: true)

        let releases = await releasesRes
        let tags = await tagsRes
        let contents = await contentsRes

        var candidates = GitHubUpdateParser.collectCandidates(
            releasesData: releases.data,
            tagsData: tags.data,
            contentsData: contents.data,
            fallbackPlistData: nil
        )
        var lastError: Error? = [releases.error, tags.error, contents.error].compactMap { $0 }.first

        // Si las llamadas a la API fallaron o alcanzaron límite de peticiones, usar Info.plist raw (sin rate-limit).
        if candidates.isEmpty {
            let plistRes = await fetchData(from: plistURL, isGitHubAPI: false)
            if let plistData = plistRes.data {
                candidates = GitHubUpdateParser.collectCandidates(
                    releasesData: releases.data,
                    tagsData: tags.data,
                    contentsData: contents.data,
                    fallbackPlistData: plistData
                )
            } else if let plistError = plistRes.error {
                lastError = lastError ?? plistError
            }
        }
        return (candidates, lastError)
    }

    private func enrichCandidateIfNeeded(_ candidate: UpdateRemoteInfo) async -> UpdateRemoteInfo {
        var resolvedURL = candidate.installerDownloadURL
        var resolvedName = candidate.installerFileName
        var resolvedSize = candidate.expectedFileSize
        var resolvedNotes = candidate.releaseNotesText

        if resolvedURL == nil {
            let fileName = "MacFileExplorer-\(candidate.versionString).dmg"
            let owner = AppVersionInfo.repositoryOwner
            let repo = AppVersionInfo.repositoryName
            let probeURLs = [
                URL(string: "https://raw.githubusercontent.com/\(owner)/\(repo)/main/releases/\(fileName)")!,
                URL(string: "https://raw.githubusercontent.com/\(owner)/\(repo)/\(candidate.tagName)/releases/\(fileName)")!
            ]
            for probeURL in probeURLs {
                if let size = await probeRemoteFileSize(url: probeURL) {
                    resolvedURL = probeURL
                    resolvedName = fileName
                    resolvedSize = size
                    break
                }
            }
        }

        // Preferir siempre viñetas limpias en el idioma elegido por el usuario desde `ReleaseNotes.swift` remoto;
        // si no está disponible, usar el cuerpo del release de GitHub saneado (sin Markdown crudo).
        let owner = AppVersionInfo.repositoryOwner
        let repo = AppVersionInfo.repositoryName
        let rawNotesURLs = [
            URL(string: "https://raw.githubusercontent.com/\(owner)/\(repo)/\(candidate.tagName)/Sources/MacFileExplorer/Models/ReleaseNotes.swift")!,
            URL(string: "https://raw.githubusercontent.com/\(owner)/\(repo)/main/Sources/MacFileExplorer/Models/ReleaseNotes.swift")!
        ]
        let isSpanish = LocalizationManager.shared.effectiveLanguage == .spanish
        var localizedBullets: String?
        for notesURL in rawNotesURLs {
            if let data = await fetchData(from: notesURL, isGitHubAPI: false).data,
               let source = String(data: data, encoding: .utf8),
               let extracted = GitHubUpdateParser.extractLatestSectionTitles(fromReleaseNotesSwift: source, isSpanish: isSpanish) {
                localizedBullets = extracted
                break
            }
        }
        if let localizedBullets, !localizedBullets.isEmpty {
            resolvedNotes = localizedBullets
        } else if let existingBody = resolvedNotes {
            let sanitized = GitHubUpdateParser.sanitizeReleaseNotesForDisplay(existingBody)
            resolvedNotes = sanitized.isEmpty ? nil : sanitized
        }

        return UpdateRemoteInfo(
            version: candidate.version,
            tagName: candidate.tagName,
            installerDownloadURL: resolvedURL,
            installerFileName: resolvedName,
            expectedFileSize: resolvedSize,
            pageURL: candidate.pageURL,
            releaseNotesText: resolvedNotes
        )
    }

    private func fetchData(from url: URL, isGitHubAPI: Bool) async -> (data: Data?, error: Error?) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("MacFileExplorer/\(AppVersionInfo.currentVersion)", forHTTPHeaderField: "User-Agent")
        if isGitHubAPI {
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return (data, nil)
            }
            if (200...299).contains(http.statusCode) {
                return (data, nil)
            }
            let apiError = NSError(
                domain: "AppUpdateManager.HTTP",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                ]
            )
            return (nil, apiError)
        } catch {
            return (nil, error)
        }
    }

    private func probeRemoteFileSize(url: URL) async -> Int64? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "HEAD"
        request.setValue("MacFileExplorer/\(AppVersionInfo.currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                return nil
            }
            let contentLength = http.expectedContentLength
            return contentLength > 0 ? contentLength : nil
        } catch {
            return nil
        }
    }

    private func localizedNetworkErrorMessage(_ error: Error) -> String {
        let loc = LocalizationManager.shared
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorNotConnectedToInternet {
            return loc.text(
                es: "No hay conexión a Internet para consultar GitHub.",
                en: "No Internet connection available to check GitHub."
            )
        }
        if nsError.domain == "AppUpdateManager.HTTP", nsError.code == 403 || nsError.code == 429 {
            return loc.text(
                es: "GitHub limitó temporalmente las consultas. Intenta nuevamente en unos minutos o abre el repositorio directamente.",
                en: "GitHub temporarily rate-limited requests. Please try again shortly or open the repository directly."
            )
        }
        return nsError.localizedDescription
    }

    private func cancelDownloadSessionOnly() {
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        activeDownloadSession?.invalidateAndCancel()
        activeDownloadSession = nil
    }

    private func cleanupDownloadReferences() {
        activeDownloadTask = nil
        activeDownloadSession?.finishTasksAndInvalidate()
        activeDownloadSession = nil
    }
}

/// Puente `@unchecked Sendable` para `URLSessionDownloadDelegate` que mueve el archivo
/// descargado de forma sincrónica antes de que macOS elimine el archivo temporal.
private final class DownloadDelegateBridge: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destinationURL: URL
    private let expectedFileSize: Int64?
    private let onProgress: @Sendable (Int64, Int64) -> Void
    private let onCompletion: @Sendable (Result<URL, Error>) -> Void

    private let lock = NSLock()
    private var didFinish = false

    init(
        destinationURL: URL,
        expectedFileSize: Int64?,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void,
        onCompletion: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        self.destinationURL = destinationURL
        self.expectedFileSize = expectedFileSize
        self.onProgress = onProgress
        self.onCompletion = onCompletion
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            let statusError = NSError(
                domain: "AppUpdateManager.DownloadHTTP",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(HTTPURLResponse.localizedString(forStatusCode: http.statusCode))"
                ]
            )
            finishOnce(.failure(statusError))
            return
        }

        do {
            let fm = FileManager.default
            let parentDir = destinationURL.deletingLastPathComponent()
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)

            let attrs = try fm.attributesOfItem(atPath: location.path)
            let downloadedSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            guard downloadedSize > 1024 else {
                let isES = LocalizationManager.currentLanguageIsSpanish()
                let corruptError = NSError(
                    domain: "AppUpdateManager.Download",
                    code: -2,
                    userInfo: [
                        NSLocalizedDescriptionKey: isES
                            ? "El archivo descargado está vacío o incompleto."
                            : "The downloaded update file is empty or incomplete."
                    ]
                )
                finishOnce(.failure(corruptError))
                return
            }

            let resolvedExpectedSize: Int64
            if let expectedFileSize, expectedFileSize > 0 {
                resolvedExpectedSize = expectedFileSize
            } else if let responseLength = downloadTask.response?.expectedContentLength, responseLength > 0 {
                resolvedExpectedSize = responseLength
            } else {
                resolvedExpectedSize = 0
            }

            if resolvedExpectedSize > 0 && downloadedSize != resolvedExpectedSize {
                let isES = LocalizationManager.currentLanguageIsSpanish()
                let truncatedError = NSError(
                    domain: "AppUpdateManager.Download",
                    code: -3,
                    userInfo: [
                        NSLocalizedDescriptionKey: isES
                            ? "La descarga quedó incompleta (\(downloadedSize) de \(resolvedExpectedSize) bytes). Intentá nuevamente."
                            : "The downloaded update file is incomplete (\(downloadedSize) of \(resolvedExpectedSize) bytes). Please try again."
                    ]
                )
                finishOnce(.failure(truncatedError))
                return
            }

            let tempStagingURL = parentDir.appendingPathComponent(".\(destinationURL.lastPathComponent).download.\(UUID().uuidString)")
            if fm.fileExists(atPath: tempStagingURL.path) {
                try? fm.removeItem(at: tempStagingURL)
            }
            try fm.moveItem(at: location, to: tempStagingURL)

            if fm.fileExists(atPath: destinationURL.path) {
                _ = try fm.replaceItemAt(destinationURL, withItemAt: tempStagingURL)
            } else {
                try fm.moveItem(at: tempStagingURL, to: destinationURL)
            }

            finishOnce(.success(destinationURL))
        } catch {
            finishOnce(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            finishOnce(.failure(error))
        } else {
            let isES = LocalizationManager.currentLanguageIsSpanish()
            let unknownError = NSError(
                domain: "AppUpdateManager.Download",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: isES
                        ? "La descarga finalizó sin entregar el archivo."
                        : "The download finished without delivering the file."
                ]
            )
            finishOnce(.failure(unknownError))
        }
    }

    private func finishOnce(_ result: Result<URL, Error>) {
        lock.lock()
        let shouldReport = !didFinish
        didFinish = true
        lock.unlock()

        if shouldReport {
            onCompletion(result)
        }
    }
}
