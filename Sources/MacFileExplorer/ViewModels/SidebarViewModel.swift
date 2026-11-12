import Foundation
import Observation

/// ViewModel (`@Observable`) encargado del Panel de Navegación Izquierdo (Navigation Pane).
/// Gestiona el despliegue perezoso de subcarpetas mediante chevrons sin forzar la navegación en el panel principal,
/// y persiste las carpetas expandidas entre sesiones.
@MainActor
@Observable
public final class SidebarViewModel {

    // MARK: - Propiedades Observables

    /// Nodos de la sección "Acceso rápido" (Inicio, Escritorio, Descargas, Documentos, Aplicaciones).
    public private(set) var quickAccessNodes: [NavigationNode] = []

    /// Nodos de la sección "Este equipo / Volúmenes" (Macintosh HD y discos en `/Volumes`).
    public private(set) var volumeNodes: [NavigationNode] = []

    /// Estado de expansión de los encabezados principales (persistido en `UserDefaults`).
    public var isQuickAccessExpanded: Bool {
        didSet {
            PersistenceService.shared.saveSidebarSections(
                quickAccessExpanded: isQuickAccessExpanded,
                volumesExpanded: isVolumesExpanded
            )
        }
    }

    public var isVolumesExpanded: Bool {
        didSet {
            PersistenceService.shared.saveSidebarSections(
                quickAccessExpanded: isQuickAccessExpanded,
                volumesExpanded: isVolumesExpanded
            )
        }
    }

    /// Conjunto de identificadores de nodos (`NavigationNode.id`) actualmente desplegados con su chevron.
    public var expandedNodeIDs: Set<String> {
        didSet {
            PersistenceService.shared.saveExpandedSidebarNodes(expandedNodeIDs)
        }
    }

    /// Caché de subcarpetas cargadas de forma asíncrona por URL de carpeta padre.
    public private(set) var subdirectoriesByURL: [URL: [NavigationNode]] = [:]

    /// URLs cuyas subcarpetas se están leyendo actualmente en segundo plano.
    public private(set) var loadingURLs: Set<URL> = []

    /// Recargas forzadas pendientes cuando una carpeta ya estaba en proceso de lectura.
    private var pendingForceReloadIncludeHidden: [URL: Bool] = [:]

    /// Monitores de sistema de archivos para detectar cambios externos o en otras pestañas sobre carpetas cacheadas del árbol lateral.
    private var directoryWatchers: [URL: DirectoryWatcher] = [:]
    private var watchDebounceTasks: [URL: Task<Void, Never>] = [:]

    /// Estado actual del filtro de archivos ocultos usado al reaccionar a eventos del sistema de archivos.
    private var latestIncludeHidden: Bool = false

    // MARK: - Dependencias

    private let fileSystemService: FileSystemService

    // MARK: - Inicialización

    public init(fileSystemService: FileSystemService = .shared) {
        self.fileSystemService = fileSystemService
        let sections = PersistenceService.shared.loadSidebarSections()
        self.isQuickAccessExpanded = sections.quickAccessExpanded
        self.isVolumesExpanded = sections.volumesExpanded
        self.expandedNodeIDs = PersistenceService.shared.loadExpandedSidebarNodes()
        self.quickAccessNodes = fileSystemService.fetchQuickAccessNodes(
            visibleFolders: QuickAccessPreferences.shared.visibleFolders,
            customFolderURLs: QuickAccessPreferences.shared.customFolderURLs
        )
    }

    // MARK: - Carga Inicial, Volúmenes y Restauración del Árbol Expandido

    /// Recarga la lista de carpetas de Acceso Rápido respetando las preferencias seleccionadas en el menú Ver
    /// y las carpetas personalizadas fijadas como favoritas.
    public func reloadQuickAccessNodes() {
        refreshQuickAccessNodes(includeHidden: latestIncludeHidden)
    }

    private func refreshQuickAccessNodes(includeHidden: Bool) {
        quickAccessNodes = fileSystemService.fetchQuickAccessNodes(
            includeHidden: includeHidden,
            visibleFolders: QuickAccessPreferences.shared.visibleFolders,
            customFolderURLs: QuickAccessPreferences.shared.customFolderURLs
        )
    }

    /// Carga la lista de volúmenes montados y restaura las subcarpetas de todos los nodos que quedaron expandidos al cerrar la app.
    public func loadInitialSections(includeHidden: Bool = false) async {
        latestIncludeHidden = includeHidden
        refreshQuickAccessNodes(includeHidden: includeHidden)
        volumeNodes = await fileSystemService.fetchMountedVolumeNodes()
        await restoreExpandedSubdirectories(includeHidden: includeHidden)
    }

    /// Recorre todos los `expandedNodeIDs` guardados (`"<section>::<path>"`) y precarga sus subdirectorios.
    public func restoreExpandedSubdirectories(includeHidden: Bool = false) async {
        latestIncludeHidden = includeHidden
        let currentExpanded = expandedNodeIDs
        for nodeID in currentExpanded {
            let parts = nodeID.components(separatedBy: "::")
            guard parts.count >= 2 else { continue }
            let path = parts.dropFirst().joined(separator: "::")
            let url = URL(fileURLWithPath: path).standardizedFileURL
            await loadSubdirectories(for: url, includeHidden: includeHidden, forceReload: true)
        }
    }

    // MARK: - Expansión Independiente de Navegación

    /// Indica si un nodo tiene al menos una subcarpeta navegable y por lo tanto debe mostrar la flecha desplegable (`chevron`).
    public func canExpand(_ node: NavigationNode) -> Bool {
        let standardized = node.url.standardizedFileURL
        if let cached = subdirectoriesByURL[standardized] {
            return !cached.isEmpty
        }
        return node.isExpandable
    }

    /// Indica si un nodo específico tiene su chevron expandido.
    public func isExpanded(_ node: NavigationNode) -> Bool {
        canExpand(node) && expandedNodeIDs.contains(node.id)
    }

    /// Indica si las subcarpetas de un nodo se están cargando.
    public func isLoading(_ node: NavigationNode) -> Bool {
        loadingURLs.contains(node.url.standardizedFileURL)
    }

    /// Devuelve las subcarpetas hijas de un nodo (personalizando su `id` por rama para evitar colisiones en SwiftUI).
    public func children(for parentNode: NavigationNode) -> [NavigationNode] {
        let rawChildren = subdirectoriesByURL[parentNode.url.standardizedFileURL] ?? []
        return rawChildren.map { child in
            NavigationNode(
                url: child.url,
                title: child.title,
                systemImage: child.systemImage,
                section: parentNode.section,
                isExpandable: child.isExpandable
            )
        }
    }

    /// Alterna el despliegue (`chevron`) de una carpeta en el árbol lateral SIN cambiar la carpeta activa del explorador.
    public func toggleExpansion(for node: NavigationNode, includeHidden: Bool = false) {
        latestIncludeHidden = includeHidden
        if expandedNodeIDs.contains(node.id) {
            expandedNodeIDs.remove(node.id)
        } else if canExpand(node) {
            expandedNodeIDs.insert(node.id)
            Task {
                await loadSubdirectories(for: node.url, includeHidden: includeHidden, forceReload: true)
            }
        }
    }

    /// Recarga las subcarpetas de una URL y de su carpeta padre cuando se crean, renombran o eliminan carpetas.
    public func refreshSubdirectoriesIfNeeded(at directoryURL: URL, includeHidden: Bool = false) {
        latestIncludeHidden = includeHidden
        let standardized = directoryURL.standardizedFileURL
        let parentStandardized = standardized.deletingLastPathComponent().standardizedFileURL

        Task {
            if subdirectoriesByURL[standardized] != nil || isDirectoryExpanded(standardized) {
                await loadSubdirectories(for: standardized, includeHidden: includeHidden, forceReload: true)
            }
            if parentStandardized != standardized,
               (subdirectoriesByURL[parentStandardized] != nil || isDirectoryExpanded(parentStandardized)) {
                await loadSubdirectories(for: parentStandardized, includeHidden: includeHidden, forceReload: true)
            }
            refreshQuickAccessNodes(includeHidden: includeHidden)
        }
    }

    /// Recarga todas las carpetas actualmente cacheadas o expandidas en el árbol lateral (p. ej. al pulsar `Cmd+R` o cambiar ocultos).
    public func refreshAllCachedDirectories(includeHidden: Bool = false) {
        latestIncludeHidden = includeHidden
        let cachedURLs = Array(subdirectoriesByURL.keys)
        Task {
            refreshQuickAccessNodes(includeHidden: includeHidden)
            for url in cachedURLs {
                await loadSubdirectories(for: url, includeHidden: includeHidden, forceReload: true)
            }
        }
    }

    /// Limpia caché y nodos expandidos de carpetas eliminadas al instante y recarga sus directorios padres en el árbol lateral.
    public func handleDeletedURLs(_ deletedURLs: [URL], includeHidden: Bool = false) {
        latestIncludeHidden = includeHidden
        let deletedPaths = deletedURLs.map { $0.standardizedFileURL.path(percentEncoded: false) }
        func isUnderDeleted(_ candidatePath: String) -> Bool {
            deletedPaths.contains { path in
                candidatePath == path || candidatePath.hasPrefix(path.hasSuffix("/") ? path : path + "/")
            }
        }

        for cachedURL in Array(subdirectoriesByURL.keys) {
            let cachedPath = cachedURL.path(percentEncoded: false)
            if isUnderDeleted(cachedPath) {
                subdirectoriesByURL.removeValue(forKey: cachedURL)
                stopWatchingDirectory(cachedURL)
            } else {
                // Eliminación optimista inmediata en la caché del padre para que desaparezca al instante de la UI
                let filtered = (subdirectoriesByURL[cachedURL] ?? []).filter { child in
                    !isUnderDeleted(child.url.standardizedFileURL.path(percentEncoded: false))
                }
                if filtered.count != (subdirectoriesByURL[cachedURL]?.count ?? 0) {
                    subdirectoriesByURL[cachedURL] = filtered
                }
            }
        }

        expandedNodeIDs = expandedNodeIDs.filter { nodeID in
            let parts = nodeID.components(separatedBy: "::")
            guard parts.count >= 2 else { return true }
            let nodePath = parts.dropFirst().joined(separator: "::")
            return !isUnderDeleted(nodePath)
        }

        let parentURLs = Set(deletedURLs.map { $0.standardizedFileURL.deletingLastPathComponent().standardizedFileURL })
        Task {
            let fm = FileManager.default
            for parentURL in parentURLs {
                if fm.fileExists(atPath: parentURL.path(percentEncoded: false)) {
                    await loadSubdirectories(for: parentURL, includeHidden: includeHidden, forceReload: true)
                }
            }
            refreshQuickAccessNodes(includeHidden: includeHidden)
        }
    }

    // MARK: - Helpers Privados

    private func isDirectoryExpanded(_ directoryURL: URL) -> Bool {
        let suffix = "::\(directoryURL.standardizedFileURL.path(percentEncoded: false))"
        return expandedNodeIDs.contains { $0.hasSuffix(suffix) }
    }

    private func loadSubdirectories(
        for directoryURL: URL,
        includeHidden: Bool,
        forceReload: Bool
    ) async {
        let standardized = directoryURL.standardizedFileURL
        if !forceReload, subdirectoriesByURL[standardized] != nil {
            return
        }
        if loadingURLs.contains(standardized) {
            if forceReload {
                pendingForceReloadIncludeHidden[standardized] = includeHidden
            }
            return
        }

        loadingURLs.insert(standardized)

        do {
            let children = try await fileSystemService.fetchSubdirectories(
                at: standardized,
                includeHidden: includeHidden
            )
            if subdirectoriesByURL[standardized] != children {
                subdirectoriesByURL[standardized] = children
            }
            if children.isEmpty {
                let suffix = "::\(standardized.path(percentEncoded: false))"
                expandedNodeIDs = expandedNodeIDs.filter { !$0.hasSuffix(suffix) }
                stopWatchingDirectory(standardized)
            } else {
                ensureWatchingDirectory(standardized)
            }
        } catch {
            subdirectoriesByURL[standardized] = []
            let suffix = "::\(standardized.path(percentEncoded: false))"
            expandedNodeIDs = expandedNodeIDs.filter { !$0.hasSuffix(suffix) }
            stopWatchingDirectory(standardized)
        }

        loadingURLs.remove(standardized)

        if let queuedIncludeHidden = pendingForceReloadIncludeHidden.removeValue(forKey: standardized) {
            await loadSubdirectories(for: standardized, includeHidden: queuedIncludeHidden, forceReload: true)
        }
    }

    // MARK: - Vigilancia en Tiempo Real del Sistema de Archivos

    private func ensureWatchingDirectory(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard directoryWatchers[standardized] == nil, directoryWatchers.count < 48 else { return }
        if let watcher = DirectoryWatcher(url: standardized, onChange: { [weak self] in
            self?.scheduleWatcherRefresh(for: standardized)
        }) {
            directoryWatchers[standardized] = watcher
        }
    }

    private func stopWatchingDirectory(_ url: URL) {
        let standardized = url.standardizedFileURL
        watchDebounceTasks[standardized]?.cancel()
        watchDebounceTasks.removeValue(forKey: standardized)
        directoryWatchers[standardized]?.invalidate()
        directoryWatchers.removeValue(forKey: standardized)
    }

    private func scheduleWatcherRefresh(for url: URL) {
        let standardized = url.standardizedFileURL
        watchDebounceTasks[standardized]?.cancel()
        watchDebounceTasks[standardized] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self else { return }
            let fm = FileManager.default
            if fm.fileExists(atPath: standardized.path(percentEncoded: false)) {
                await self.loadSubdirectories(for: standardized, includeHidden: self.latestIncludeHidden, forceReload: true)
            } else {
                self.handleDeletedURLs([standardized], includeHidden: self.latestIncludeHidden)
            }
            self.reloadQuickAccessNodes()
        }
    }
}
