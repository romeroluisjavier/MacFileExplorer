import Foundation

public enum ArchiveFormat: String, CaseIterable, Identifiable, Sendable {
    case zip = "zip"
    case tarGz = "tar.gz"
    case sevenZ = "7z"

    public var id: String { rawValue }
}

public enum ArchiveService {

    public static let extractableExtensions: Set<String> = [
        "zip", "7z", "rar", "tgz", "gz", "tar"
    ]

    public static func isArchiveURL(_ url: URL) -> Bool {
        let lower = url.lastPathComponent.lowercased()
        if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz") {
            return true
        }
        return extractableExtensions.contains(url.pathExtension.lowercased())
    }

    private static func findExecutable(names: [String]) -> String? {
        let searchPaths = [
            "/usr/bin",
            "/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ]
        let fm = FileManager.default
        for name in names {
            for dir in searchPaths {
                let fullPath = "\(dir)/\(name)"
                if fm.isExecutableFile(atPath: fullPath) {
                    return fullPath
                }
            }
        }
        return nil
    }

    private static func localizedText(es: String, en: String) -> String {
        LocalizationManager.currentLanguageIsSpanish() ? es : en
    }

    // MARK: - Compresión

    public static func compress(
        urls: [URL],
        format: ArchiveFormat,
        progressHandler: (@Sendable (Double, String) -> Void)? = nil
    ) async throws -> URL {
        guard let first = urls.first else {
            throw NSError(domain: "ArchiveService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: localizedText(
                    es: "No hay elementos seleccionados para comprimir.",
                    en: "No items selected to compress."
                )
            ])
        }
        let parentDir = first.deletingLastPathComponent()
        let baseName = urls.count == 1
            ? first.deletingPathExtension().lastPathComponent
            : localizedText(
                es: "Archivo_\(urls.count)_elementos",
                en: "Archive_\(urls.count)_items"
            )
        let destURL = uniqueURL(in: parentDir, baseName: baseName, ext: format.rawValue)

        progressHandler?(0.15, localizedText(
            es: "Comprimiendo en .\(format.rawValue)…",
            en: "Compressing into .\(format.rawValue)…"
        ))

        try await Task.detached(priority: .userInitiated) {
            let names = urls.map(\.lastPathComponent)
            switch format {
            case .zip:
                try runProcess(
                    executable: "/usr/bin/zip",
                    arguments: ["-r", "-y", destURL.path(percentEncoded: false)] + names,
                    currentDirectory: parentDir
                )

            case .tarGz:
                try runProcess(
                    executable: "/usr/bin/tar",
                    arguments: ["-czf", destURL.path(percentEncoded: false)] + names,
                    currentDirectory: parentDir
                )

            case .sevenZ:
                guard let sevenZip = findExecutable(names: ["7zz", "7z", "7za"]) else {
                    throw NSError(domain: "ArchiveService", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: localizedText(
                            es: "Para crear archivos .7z instala p7zip/sevenzip (brew install sevenzip).",
                            en: "To create .7z archives, install p7zip/sevenzip (brew install sevenzip)."
                        )
                    ])
                }
                try runProcess(
                    executable: sevenZip,
                    arguments: ["a", destURL.path(percentEncoded: false)] + names,
                    currentDirectory: parentDir
                )
            }
        }.value

        progressHandler?(1.0, localizedText(es: "Completado", en: "Completed"))
        return destURL
    }

    // MARK: - Extracción Limpia (Sin Carpetas Intermedias Basura)

    public static func extract(
        archiveURL: URL,
        progressHandler: (@Sendable (Double, String) -> Void)? = nil
    ) async throws -> [URL] {
        let parentDir = archiveURL.deletingLastPathComponent()
        let lowerName = archiveURL.lastPathComponent.lowercased()
        let archiveBaseName: String = {
            if lowerName.hasSuffix(".tar.gz") {
                return String(archiveURL.lastPathComponent.dropLast(7))
            }
            return archiveURL.deletingPathExtension().lastPathComponent
        }()

        progressHandler?(0.15, localizedText(
            es: "Extrayendo \(archiveURL.lastPathComponent)…",
            en: "Extracting \(archiveURL.lastPathComponent)…"
        ))

        let createdURLs: [URL] = try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let stagingDir = fm.temporaryDirectory.appendingPathComponent("MFE_Extract_\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            defer {
                try? fm.removeItem(at: stagingDir)
            }

            let path = archiveURL.path(percentEncoded: false)
            let stagingPath = stagingDir.path(percentEncoded: false)

            if lowerName.hasSuffix(".tar.gz") || lowerName.hasSuffix(".tgz") || archiveURL.pathExtension.lowercased() == "tar" {
                try runProcess(
                    executable: "/usr/bin/tar",
                    arguments: ["-xzf", path, "-C", stagingPath],
                    currentDirectory: parentDir
                )
            } else if archiveURL.pathExtension.lowercased() == "zip" {
                try runProcess(
                    executable: "/usr/bin/ditto",
                    arguments: ["-xk", path, stagingPath],
                    currentDirectory: parentDir
                )
            } else if archiveURL.pathExtension.lowercased() == "7z" {
                guard let sevenZip = findExecutable(names: ["7zz", "7z", "7za", "unar"]) else {
                    throw NSError(domain: "ArchiveService", code: 3, userInfo: [
                        NSLocalizedDescriptionKey: localizedText(
                            es: "Para extraer .7z instala sevenzip o unar (brew install sevenzip).",
                            en: "To extract .7z archives, install sevenzip or unar (brew install sevenzip)."
                        )
                    ])
                }
                if sevenZip.hasSuffix("unar") {
                    try runProcess(executable: sevenZip, arguments: ["-o", stagingPath, path], currentDirectory: parentDir)
                } else {
                    try runProcess(executable: sevenZip, arguments: ["x", path, "-o\(stagingPath)", "-y"], currentDirectory: parentDir)
                }
            } else if archiveURL.pathExtension.lowercased() == "rar" {
                guard let unrar = findExecutable(names: ["unrar", "unar", "7zz", "7z"]) else {
                    throw NSError(domain: "ArchiveService", code: 4, userInfo: [
                        NSLocalizedDescriptionKey: localizedText(
                            es: "Para extraer .rar instala unar o rar (brew install unar).",
                            en: "To extract .rar archives, install unar or rar (brew install unar)."
                        )
                    ])
                }
                if unrar.hasSuffix("unar") {
                    try runProcess(executable: unrar, arguments: ["-o", stagingPath, path], currentDirectory: parentDir)
                } else {
                    try runProcess(executable: unrar, arguments: ["x", "-y", path, stagingPath + "/"], currentDirectory: parentDir)
                }
            } else {
                throw NSError(domain: "ArchiveService", code: 5, userInfo: [
                    NSLocalizedDescriptionKey: localizedText(
                        es: "Formato de archivo comprimido no soportado.",
                        en: "Unsupported archive format."
                    )
                ])
            }

            // Limpiar basura intermedia (__MACOSX, .DS_Store)
            let rawContents = try fm.contentsOfDirectory(
                at: stagingDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ).filter { item in
                let name = item.lastPathComponent
                return name != "__MACOSX" && name != ".DS_Store"
            }

            if rawContents.isEmpty {
                return []
            }

            // Si hay un único elemento raíz (ej. una carpeta o un archivo), moverlo directamente sin crear carpeta contenedora extra
            if rawContents.count == 1, let singleItem = rawContents.first {
                let targetName = singleItem.lastPathComponent
                let destURL = uniqueItemURL(in: parentDir, preferredName: targetName)
                try fm.moveItem(at: singleItem, to: destURL)
                return [destURL]
            }

            // Si hay múltiples elementos sueltos en la raíz, agruparlos en una carpeta limpia con el nombre del archivo
            let containerURL = uniqueItemURL(in: parentDir, preferredName: archiveBaseName)
            try fm.createDirectory(at: containerURL, withIntermediateDirectories: true)
            for item in rawContents {
                let dest = containerURL.appendingPathComponent(item.lastPathComponent)
                try fm.moveItem(at: item, to: dest)
            }
            return [containerURL]
        }.value

        progressHandler?(1.0, localizedText(es: "Completado", en: "Completed"))
        return createdURLs
    }

    private static func runProcess(
        executable: String,
        arguments: [String],
        currentDirectory: URL
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw NSError(domain: "ArchiveService", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: errMsg.isEmpty
                    ? localizedText(
                        es: "Error al procesar el archivo comprimido.",
                        en: "Error processing the archive."
                    )
                    : errMsg
            ])
        }
    }

    private static func uniqueURL(in directory: URL, baseName: String, ext: String) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent("\(baseName).\(ext)")
        var counter = 1
        while fm.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = directory.appendingPathComponent("\(baseName)_\(counter).\(ext)")
            counter += 1
        }
        return candidate
    }

    private static func uniqueItemURL(in directory: URL, preferredName: String) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(preferredName)
        var counter = 1
        while fm.fileExists(atPath: candidate.path(percentEncoded: false)) {
            let ns = preferredName as NSString
            let ext = ns.pathExtension
            let base = ns.deletingPathExtension
            let nextName = ext.isEmpty ? "\(preferredName)_\(counter)" : "\(base)_\(counter).\(ext)"
            candidate = directory.appendingPathComponent(nextName)
            counter += 1
        }
        return candidate
    }
}
