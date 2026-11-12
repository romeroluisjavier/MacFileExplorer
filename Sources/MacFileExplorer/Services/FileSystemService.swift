import Foundation

/// Errores de dominio para operaciones del sistema de archivos en `MacFileExplorer`.
public enum FileSystemError: LocalizedError, Sendable {
    case invalidDirectory(URL)
    case invalidFileName(String)
    case itemAlreadyExists(String)
    case cannotMoveIntoSubfolder(source: URL, destination: URL)
    case operationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidDirectory(let url):
            return "La ruta '\(url.path(percentEncoded: false))' no es una carpeta válida o no existe."
        case .invalidFileName(let name):
            return "El nombre '\(name)' no es válido. No puede estar vacío ni contener los caracteres '/' o ':'."
        case .itemAlreadyExists(let name):
            return "Ya existe un elemento llamado '\(name)' en esta ubicación."
        case .cannotMoveIntoSubfolder(let source, _):
            return "No se puede mover '\(source.lastPathComponent)' dentro de una subcarpeta de sí misma."
        case .operationFailed(let reason):
            return reason
        }
    }
}

/// Servicio de I/O asíncrono y `Sendable` que encapsula todas las operaciones de `FileManager`
/// ejecutándolas en una cola dedicada (`DispatchQueue`) fuera del hilo principal.
public final class FileSystemService: Sendable {

    public static let shared = FileSystemService()

    /// Cola concurrente dedicada a operaciones de lectura y escritura de disco.
    private let ioQueue = DispatchQueue(
        label: "com.macfileexplorer.filesystem.io",
        qos: .userInitiated,
        attributes: .concurrent
    )

    public init() {}

    // MARK: - Lectura Asíncrona de Directorios

    /// Lee todos los elementos de un directorio en segundo plano precargando metadatos (`URLResourceKey`) en bloque.
    public func fetchDirectoryContents(at directoryURL: URL) async throws -> [FileItem] {
        let standardizedDir = directoryURL.standardizedFileURL

        return try await performAsyncIO {
            let fileManager = FileManager.default
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: standardizedDir.path(percentEncoded: false), isDirectory: &isDir),
                  isDir.boolValue else {
                throw FileSystemError.invalidDirectory(standardizedDir)
            }

            let urls = try fileManager.contentsOfDirectory(
                at: standardizedDir,
                includingPropertiesForKeys: FileItem.prefetchedResourceKeys,
                options: [.skipsPackageDescendants]
            )

            var items: [FileItem] = []
            items.reserveCapacity(urls.count)

            for (index, url) in urls.enumerated() {
                if index & 127 == 0 && Task.isCancelled {
                    throw CancellationError()
                }
                let fileName = url.lastPathComponent
                if fileName.hasPrefix(ThumbnailDiskCoordinator.hiddenCacheFileName) ||
                   fileName.hasPrefix(DirectoryIndexCacheService.hiddenCacheFileName) {
                    continue
                }
                if let values = try? url.resourceValues(forKeys: FileItem.prefetchedResourceKeySet) {
                    items.append(FileItem(url: url, resourceValues: values))
                } else {
                    items.append(
                        FileItem(
                            url: url,
                            name: url.lastPathComponent,
                            isDirectory: url.hasDirectoryPath
                        )
                    )
                }
            }

            return items
        }
    }

    /// Obtiene únicamente las subcarpetas navegables de un directorio para el árbol lateral (Navigation Pane).
    public func fetchSubdirectories(
        at directoryURL: URL,
        includeHidden: Bool = false
    ) async throws -> [NavigationNode] {
        let standardizedDir = directoryURL.standardizedFileURL

        return try await performAsyncIO {
            let fileManager = FileManager.default
            let keys: [URLResourceKey] = [.nameKey, .isDirectoryKey, .isPackageKey, .isHiddenKey]
            let keySet = Set(keys)

            let urls = try fileManager.contentsOfDirectory(
                at: standardizedDir,
                includingPropertiesForKeys: keys,
                options: includeHidden ? [.skipsPackageDescendants] : [.skipsHiddenFiles, .skipsPackageDescendants]
            )

            var nodes: [NavigationNode] = []
            for url in urls {
                guard let values = try? url.resourceValues(forKeys: keySet),
                      values.isDirectory == true,
                      values.isPackage != true else {
                    continue
                }
                if !includeHidden && (values.isHidden == true || url.lastPathComponent.hasPrefix(".")) {
                    continue
                }
                let title = values.name ?? url.lastPathComponent
                let hasChildFolders = self.directoryHasSubdirectories(
                    at: url,
                    includeHidden: includeHidden
                )
                nodes.append(
                    NavigationNode(
                        url: url,
                        title: title,
                        systemImage: "folder.fill",
                        section: .directory,
                        isExpandable: hasChildFolders
                    )
                )
            }

            nodes.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            return nodes
        }
    }

    /// Comprueba de forma ultrarrápida (deteniéndose en la primera coincidencia) si un directorio contiene al menos una subcarpeta navegable.
    public func directoryHasSubdirectories(at directoryURL: URL, includeHidden: Bool = false) -> Bool {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isHiddenKey]
        let keySet = Set(keys)
        let options: FileManager.DirectoryEnumerationOptions = includeHidden
            ? [.skipsSubdirectoryDescendants, .skipsPackageDescendants]
            : [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants]

        guard let enumerator = fm.enumerator(
            at: directoryURL.standardizedFileURL,
            includingPropertiesForKeys: keys,
            options: options
        ) else {
            return false
        }

        for case let childURL as URL in enumerator {
            guard let values = try? childURL.resourceValues(forKeys: keySet),
                  values.isDirectory == true,
                  values.isPackage != true else {
                continue
            }
            if !includeHidden && (values.isHidden == true || childURL.lastPathComponent.hasPrefix(".")) {
                continue
            }
            return true
        }
        return false
    }

    // MARK: - Nodos del Panel Lateral (Acceso Rápido y Volúmenes)

    /// Devuelve los nodos de "Acceso Rápido" / Favoritos filtrados según las carpetas visibles seleccionadas,
    /// seguidos debajo por las carpetas personalizadas fijadas mediante arrastrar y soltar.
    public func fetchQuickAccessNodes(
        includeHidden: Bool = false,
        visibleFolders: Set<QuickAccessFolder> = QuickAccessFolder.defaultFolders,
        customFolderURLs: [URL] = []
    ) -> [NavigationNode] {
        let fm = FileManager.default

        var nodes: [NavigationNode] = QuickAccessFolder.allCases.compactMap { folder in
            guard visibleFolders.contains(folder),
                  let url = folder.directoryURL,
                  fm.fileExists(atPath: url.path(percentEncoded: false)) else {
                return nil
            }
            let hasChildFolders = self.directoryHasSubdirectories(at: url, includeHidden: includeHidden)
            return NavigationNode(
                url: url,
                title: folder.defaultTitle,
                systemImage: folder.systemImage,
                section: .quickAccess,
                isExpandable: hasChildFolders
            )
        }

        var existingPaths = Set(nodes.map { $0.url.standardizedFileURL.path(percentEncoded: false) })
        for customURL in customFolderURLs {
            let standardized = customURL.standardizedFileURL
            let path = standardized.path(percentEncoded: false)
            var isDir: ObjCBool = false
            guard !existingPaths.contains(path),
                  fm.fileExists(atPath: path, isDirectory: &isDir),
                  isDir.boolValue else {
                continue
            }
            existingPaths.insert(path)
            let hasChildFolders = self.directoryHasSubdirectories(at: standardized, includeHidden: includeHidden)
            let displayName = fm.displayName(atPath: path)
            nodes.append(
                NavigationNode(
                    url: standardized,
                    title: displayName.isEmpty ? standardized.lastPathComponent : displayName,
                    systemImage: "folder.fill",
                    section: .quickAccess,
                    isExpandable: hasChildFolders,
                    isCustomQuickAccessFavorite: true
                )
            )
        }

        return nodes
    }

    /// Descubre los volúmenes montados en el sistema ("Este Equipo / Volúmenes").
    public func fetchMountedVolumeNodes() async -> [NavigationNode] {
        (try? await performAsyncIO {
            let fm = FileManager.default
            let keys: [URLResourceKey] = [
                .volumeNameKey,
                .volumeIsRemovableKey,
                .volumeIsEjectableKey,
                .volumeIsInternalKey
            ]
            let keySet = Set(keys)

            var nodes: [NavigationNode] = []
            if let volumeURLs = fm.mountedVolumeURLs(
                includingResourceValuesForKeys: keys,
                options: [.skipHiddenVolumes]
            ) {
                for url in volumeURLs {
                    let values = try? url.resourceValues(forKeys: keySet)
                    let name = values?.volumeName ?? (url.path == "/" ? "Macintosh HD" : url.lastPathComponent)
                    let isRemovable = (values?.volumeIsRemovable == true) || (values?.volumeIsEjectable == true)
                    let icon = isRemovable ? "externaldrive.fill" : "internaldrive.fill"

                    nodes.append(
                        NavigationNode(
                            url: url,
                            title: name,
                            systemImage: icon,
                            section: .volumes,
                            isExpandable: true
                        )
                    )
                }
            }

            if nodes.isEmpty {
                nodes.append(
                    NavigationNode(
                        url: URL(fileURLWithPath: "/"),
                        title: "Macintosh HD",
                        systemImage: "internaldrive.fill",
                        section: .volumes,
                        isExpandable: true
                    )
                )
            }
            return nodes
        }) ?? []
    }

    // MARK: - Operaciones de Creación, Renombrado y Papelera

    /// Crea una nueva carpeta con nombre único estilo Windows ("Nueva carpeta", "Nueva carpeta (2)"...).
    public func createFolder(
        in directoryURL: URL,
        baseName: String = "Nueva carpeta"
    ) async throws -> URL {
        let parent = directoryURL.standardizedFileURL
        return try await performAsyncIO {
            let fm = FileManager.default
            let targetURL = self.makeUniqueDestinationURL(
                in: parent,
                baseName: baseName,
                pathExtension: "",
                copySuffix: false
            )
            try fm.createDirectory(at: targetURL, withIntermediateDirectories: false)
            return targetURL.standardizedFileURL
        }
    }

    /// Crea un archivo vacío con nombre único estilo Windows ("Nuevo documento de texto.txt").
    public func createFile(
        in directoryURL: URL,
        baseName: String = "Nuevo documento de texto",
        fileExtension: String = "txt"
    ) async throws -> URL {
        let parent = directoryURL.standardizedFileURL
        return try await performAsyncIO {
            let fm = FileManager.default
            let targetURL = self.makeUniqueDestinationURL(
                in: parent,
                baseName: baseName,
                pathExtension: fileExtension,
                copySuffix: false
            )
            let created = fm.createFile(atPath: targetURL.path(percentEncoded: false), contents: Data())
            guard created else {
                throw FileSystemError.operationFailed("No se pudo crear el archivo '\(targetURL.lastPathComponent)'.")
            }
            return targetURL.standardizedFileURL
        }
    }

    /// Renombra un archivo o carpeta en su mismo directorio padre (`F2` / `Enter`).
    public func renameItem(at sourceURL: URL, to rawNewName: String) async throws -> URL {
        let trimmed = rawNewName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.contains(":") else {
            throw FileSystemError.invalidFileName(rawNewName)
        }

        let source = sourceURL.standardizedFileURL
        let destination = source.deletingLastPathComponent().appendingPathComponent(trimmed).standardizedFileURL

        if source == destination {
            return source
        }

        return try await performAsyncIO {
            let fm = FileManager.default
            if fm.fileExists(atPath: destination.path(percentEncoded: false)) {
                throw FileSystemError.itemAlreadyExists(trimmed)
            }
            try fm.moveItem(at: source, to: destination)
            return destination
        }
    }

    /// Envía uno o más elementos a la Papelera del sistema (`Delete` / `Backspace`).
    public func moveItemsToTrash(_ urls: [URL]) async throws -> [URL] {
        try await moveItemsToTrashWithPairs(urls).map(\.destination)
    }

    /// Envía elementos a la Papelera devolviendo cada par `(original -> trashed)` para poder deshacer con `Cmd+Z`.
    public func moveItemsToTrashWithPairs(_ urls: [URL]) async throws -> [FileMovePair] {
        let standardizedURLs = urls.map(\.standardizedFileURL)
        return try await performAsyncIO {
            let fm = FileManager.default
            var pairs: [FileMovePair] = []
            for url in standardizedURLs {
                var resultingURL: NSURL?
                try fm.trashItem(at: url, resultingItemURL: &resultingURL)
                if let resulting = resultingURL as URL? {
                    pairs.append(FileMovePair(source: url, destination: resulting))
                }
            }
            return pairs
        }
    }

    /// Mueve elementos desde rutas exactas hacia destinos exactos (usado para deshacer/rehacer movimientos y restaurar de Papelera).
    public func moveItemsToExactDestinations(_ pairs: [FileMovePair]) async throws -> [FileMovePair] {
        try await performAsyncIO {
            let fm = FileManager.default
            var completed: [FileMovePair] = []

            for pair in pairs {
                let source = pair.source.standardizedFileURL
                let desiredDestination = pair.destination.standardizedFileURL

                if source == desiredDestination {
                    completed.append(FileMovePair(source: source, destination: desiredDestination))
                    continue
                }

                guard fm.fileExists(atPath: source.path(percentEncoded: false)) else {
                    throw FileSystemError.operationFailed(
                        "No se encontró '\(source.lastPathComponent)' para completar la acción."
                    )
                }

                let destDir = desiredDestination.deletingLastPathComponent().standardizedFileURL
                var isDestDir: ObjCBool = false
                if !fm.fileExists(atPath: destDir.path(percentEncoded: false), isDirectory: &isDestDir) {
                    try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                }

                let targetURL: URL
                if fm.fileExists(atPath: desiredDestination.path(percentEncoded: false)) {
                    let isDir = source.hasDirectoryPath
                    let ext = isDir ? "" : desiredDestination.pathExtension
                    let stem = isDir ? desiredDestination.lastPathComponent : desiredDestination.deletingPathExtension().lastPathComponent
                    targetURL = self.makeUniqueDestinationURL(
                        in: destDir,
                        baseName: stem,
                        pathExtension: ext,
                        copySuffix: false
                    )
                } else {
                    targetURL = desiredDestination
                }

                try fm.moveItem(at: source, to: targetURL)
                completed.append(FileMovePair(source: source, destination: targetURL))
            }

            return completed
        }
    }

    /// Elimina permanentemente uno o más elementos del disco sin pasar por la Papelera (`Shift+Delete`).
    public func deleteItemsPermanently(_ urls: [URL]) async throws {
        let standardizedURLs = urls.map(\.standardizedFileURL)
        try await performAsyncIO {
            let fm = FileManager.default
            for url in standardizedURLs {
                guard url.path != "/" else { continue }
                try fm.removeItem(at: url)
            }
        }
    }

    /// Desarchiva un archivo `.zip` en una carpeta con el mismo nombre dentro del directorio actual.
    /// Utiliza `/usr/bin/ditto -x -k` para preservar codificación UTF-8, permisos y atributos extendidos de macOS.
    public func unarchiveZipItem(at archiveURL: URL) async throws -> URL {
        let sourceArchive = archiveURL.standardizedFileURL
        let parentDir = sourceArchive.deletingLastPathComponent().standardizedFileURL
        let rawStem = sourceArchive.deletingPathExtension().lastPathComponent
        let baseFolderName = rawStem.isEmpty ? "Archivo descomprimido" : rawStem

        return try await performAsyncIO {
            let fm = FileManager.default
            guard fm.fileExists(atPath: sourceArchive.path(percentEncoded: false)) else {
                throw FileSystemError.operationFailed("El archivo '\(sourceArchive.lastPathComponent)' no existe.")
            }

            let tempStagingDir = fm.temporaryDirectory
                .appendingPathComponent("MacFileExplorer_Unzip_\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: tempStagingDir, withIntermediateDirectories: true)
            defer {
                try? fm.removeItem(at: tempStagingDir)
            }

            // Extraer con /usr/bin/ditto -x -k
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = [
                "-x",
                "-k",
                sourceArchive.path(percentEncoded: false),
                tempStagingDir.path(percentEncoded: false)
            ]

            let stderrPipe = Pipe()
            process.standardError = stderrPipe

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                // Fallback con /usr/bin/unzip si ditto falla por algún formato zip particular
                let unzipProcess = Process()
                unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                unzipProcess.arguments = [
                    "-q",
                    sourceArchive.path(percentEncoded: false),
                    "-d",
                    tempStagingDir.path(percentEncoded: false)
                ]
                let unzipErrPipe = Pipe()
                unzipProcess.standardError = unzipErrPipe
                try unzipProcess.run()
                unzipProcess.waitUntilExit()

                guard unzipProcess.terminationStatus == 0 else {
                    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let errText = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Error al descomprimir el archivo .zip"
                    throw FileSystemError.operationFailed(errText.isEmpty ? "No se pudo desarchivar '\(sourceArchive.lastPathComponent)'." : errText)
                }
            }

            // Eliminar carpeta fantasma __MACOSX si existe en el staging
            let macosxMetaDir = tempStagingDir.appendingPathComponent("__MACOSX", isDirectory: true)
            if fm.fileExists(atPath: macosxMetaDir.path(percentEncoded: false)) {
                try? fm.removeItem(at: macosxMetaDir)
            }

            let targetFolderURL = self.makeUniqueDestinationURL(
                in: parentDir,
                baseName: baseFolderName,
                pathExtension: "",
                copySuffix: false
            )

            let extractedEntries = (try? fm.contentsOfDirectory(
                at: tempStagingDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )) ?? []

            // Si el .zip contiene una única carpeta raíz, moverla directamente al destino para evitar doble anidamiento (ej. ecoway/ecoway)
            if extractedEntries.count == 1,
               let singleEntry = extractedEntries.first,
               (try? singleEntry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                try fm.moveItem(at: singleEntry, to: targetFolderURL)
            } else {
                try fm.createDirectory(at: targetFolderURL, withIntermediateDirectories: false)
                for entry in extractedEntries {
                    let destEntry = targetFolderURL.appendingPathComponent(entry.lastPathComponent)
                    try fm.moveItem(at: entry, to: destEntry)
                }
            }

            return targetFolderURL.standardizedFileURL
        }
    }

    // MARK: - Operaciones de Portapapeles (Copiar y Cortar/Mover)

    /// Copia una lista de elementos al directorio de destino generando sufijos `- copia` si hay colisión.
    public func copyItems(from sourceURLs: [URL], to destinationDirectory: URL) async throws -> [URL] {
        try await copyItemPairs(from: sourceURLs, to: destinationDirectory).map(\.destination)
    }

    /// Copia elementos devolviendo los pares `(source -> destination)` creados.
    public func copyItemPairs(from sourceURLs: [URL], to destinationDirectory: URL) async throws -> [FileMovePair] {
        let destDir = destinationDirectory.standardizedFileURL
        let sources = sourceURLs.map(\.standardizedFileURL)

        return try await performAsyncIO {
            let fm = FileManager.default
            var pairs: [FileMovePair] = []

            for source in sources {
                let isDir = source.hasDirectoryPath
                let ext = isDir ? "" : source.pathExtension
                let stem = isDir ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
                let directCandidate = destDir.appendingPathComponent(source.lastPathComponent).standardizedFileURL

                let targetURL: URL
                if fm.fileExists(atPath: directCandidate.path(percentEncoded: false)) {
                    targetURL = self.makeUniqueDestinationURL(
                        in: destDir,
                        baseName: stem,
                        pathExtension: ext,
                        copySuffix: true
                    )
                } else {
                    targetURL = directCandidate
                }

                try fm.copyItem(at: source, to: targetURL)
                pairs.append(FileMovePair(source: source, destination: targetURL.standardizedFileURL))
            }

            return pairs
        }
    }

    /// Mueve una lista de elementos al directorio de destino (`Cmd+X` seguido de `Cmd+V` -> `FileManager.moveItem`).
    public func moveItems(from sourceURLs: [URL], to destinationDirectory: URL) async throws -> [URL] {
        try await moveItemPairs(from: sourceURLs, to: destinationDirectory).map(\.destination)
    }

    /// Mueve elementos devolviendo los pares `(source -> destination)` efectivos para soportar Deshacer (`Cmd+Z`).
    public func moveItemPairs(from sourceURLs: [URL], to destinationDirectory: URL) async throws -> [FileMovePair] {
        let destDir = destinationDirectory.standardizedFileURL
        let sources = sourceURLs.map(\.standardizedFileURL)

        return try await performAsyncIO {
            let fm = FileManager.default
            var pairs: [FileMovePair] = []

            for source in sources {
                let directDestination = destDir.appendingPathComponent(source.lastPathComponent).standardizedFileURL

                // Si se corta y pega en la misma carpeta, no hacer nada y conservar el elemento
                if source == directDestination {
                    pairs.append(FileMovePair(source: source, destination: source))
                    continue
                }

                // Prevenir mover una carpeta dentro de una subcarpeta de sí misma
                let sourcePathWithSlash = source.path(percentEncoded: false).hasSuffix("/")
                    ? source.path(percentEncoded: false)
                    : source.path(percentEncoded: false) + "/"
                if destDir.path(percentEncoded: false).hasPrefix(sourcePathWithSlash) {
                    throw FileSystemError.cannotMoveIntoSubfolder(source: source, destination: destDir)
                }

                let targetURL: URL
                if fm.fileExists(atPath: directDestination.path(percentEncoded: false)) {
                    let isDir = source.hasDirectoryPath
                    let ext = isDir ? "" : source.pathExtension
                    let stem = isDir ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
                    targetURL = self.makeUniqueDestinationURL(
                        in: destDir,
                        baseName: stem,
                        pathExtension: ext,
                        copySuffix: false
                    )
                } else {
                    targetURL = directDestination
                }

                try fm.moveItem(at: source, to: targetURL)
                pairs.append(FileMovePair(source: source, destination: targetURL.standardizedFileURL))
            }

            return pairs
        }
    }

    // MARK: - Resolución de Rutas (Barra de Direcciones / Cmd+L)

    /// Valida y resuelve una cadena de ruta escrita o pegada manualmente (`/Users/...` o `~/Downloads`).
    public func resolveDirectoryPath(_ rawPath: String) -> URL? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let expanded = NSString(string: trimmed).expandingTildeInPath
        let candidateURL = URL(fileURLWithPath: expanded).standardizedFileURL

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: candidateURL.path(percentEncoded: false),
            isDirectory: &isDir
        ), isDir.boolValue else {
            return nil
        }
        return candidateURL
    }

    // MARK: - Helpers Privados

    /// Ejecuta un bloque síncrono de I/O en `ioQueue` sin bloquear el actor principal.
    private func performAsyncIO<T: Sendable>(
        _ operation: @Sendable @escaping () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                do {
                    let result = try operation()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Genera un nombre único cuando existe colisión en el directorio de destino.
    private func makeUniqueDestinationURL(
        in directory: URL,
        baseName: String,
        pathExtension: String,
        copySuffix: Bool
    ) -> URL {
        let fm = FileManager.default
        let extSuffix = pathExtension.isEmpty ? "" : ".\(pathExtension)"

        if !copySuffix {
            let initial = directory.appendingPathComponent("\(baseName)\(extSuffix)")
            if !fm.fileExists(atPath: initial.path(percentEncoded: false)) {
                return initial
            }
            var index = 2
            while true {
                let candidate = directory.appendingPathComponent("\(baseName) (\(index))\(extSuffix)")
                if !fm.fileExists(atPath: candidate.path(percentEncoded: false)) {
                    return candidate
                }
                index += 1
            }
        } else {
            let firstCopy = directory.appendingPathComponent("\(baseName) - copia\(extSuffix)")
            if !fm.fileExists(atPath: firstCopy.path(percentEncoded: false)) {
                return firstCopy
            }
            var index = 2
            while true {
                let candidate = directory.appendingPathComponent("\(baseName) - copia (\(index))\(extSuffix)")
                if !fm.fileExists(atPath: candidate.path(percentEncoded: false)) {
                    return candidate
                }
                index += 1
            }
        }
    }
}
