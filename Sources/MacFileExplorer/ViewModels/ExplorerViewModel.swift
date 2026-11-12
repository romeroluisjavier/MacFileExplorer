import Foundation
import AppKit
import SwiftUI
import Observation

/// Representa un segmento individual dentro de la barra de ruta tipo "Breadcrumb" estilo Windows 11.
public struct BreadcrumbSegment: Identifiable, Hashable, Sendable {
    public let id: URL
    public let title: String
    public let url: URL

    public init(title: String, url: URL) {
        let standardized = url.standardizedFileURL
        self.id = standardized
        self.title = title
        self.url = standardized
    }
}

/// ViewModel principal (`@Observable`) que coordina la navegación, listado asíncrono, ordenamiento,
/// selección múltiple, edición en línea (`F2`), portapapeles (`Cmd+X`/`Cmd+C`/`Cmd+V`) y barra de estado.
@MainActor
@Observable
public final class ExplorerViewModel {

    // MARK: - Estado de Navegación e Historial

    /// Directorio activo actualmente mostrado en el área principal.
    public private(set) var currentDirectoryURL: URL

    /// Pila de historial para el botón "Atrás".
    public private(set) var backStack: [URL] = []

    /// Pila de historial para el botón "Adelante".
    public private(set) var forwardStack: [URL] = []

    /// Estado de edición en texto plano de la barra de direcciones (`Cmd+L` o clic en espacio vacío).
    public var isEditingAddressBar: Bool = false

    /// Texto editable cuando la barra de direcciones está en modo texto plano.
    public var addressBarText: String = ""

    // MARK: - Contenidos, Filtrado y Ordenamiento

    /// Todos los elementos leídos del directorio actual (sin filtrar).
    public private(set) var allItems: [FileItem] = []

    /// Lista final visible ya filtrada y ordenada (calculada una sola vez por cambio para evitar reordenar en cada redibujo).
    public private(set) var displayedItems: [FileItem] = []

    /// Indica si hay una operación de lectura de directorio en curso.
    public private(set) var isLoading: Bool = false

    /// Indica si la lectura lleva tiempo suficiente como para mostrar un overlay centrado de "Cargando carpeta...".
    public private(set) var isSlowLoadingOverlayVisible: Bool = false

    /// Mensaje de alerta o error reciente para mostrar al usuario si una operación de I/O falla.
    public var errorMessage: String?

    /// Texto de filtrado rápido en la caja de búsqueda superior derecha.
    public var searchQuery: String = "" {
        didSet {
            guard searchQuery != oldValue else { return }
            rebuildDisplayedItems()
        }
    }

    /// Mostrar u ocultar archivos que comienzan por `.` o tienen flag oculto.
    public var showHiddenFiles: Bool {
        didSet {
            guard showHiddenFiles != oldValue else { return }
            PersistenceService.shared.saveShowHiddenFiles(showHiddenFiles)
            sidebarViewModel.refreshAllCachedDirectories(includeHidden: showHiddenFiles)
            rebuildDisplayedItems()
        }
    }

    /// Modo de vista actual (`.details` tipo tabla Windows o `.largeIcons` tipo cuadrícula).
    public var viewMode: ExplorerViewMode {
        didSet {
            PersistenceService.shared.saveViewMode(viewMode)
            if viewMode == .largeIcons && oldValue != .largeIcons && !allItems.isEmpty {
                scheduleThumbnailPreload(for: currentDirectoryURL, items: allItems)
            }
        }
    }

    /// Columna activa de ordenamiento.
    public var sortField: FileItem.SortField {
        didSet {
            PersistenceService.shared.saveSort(field: sortField, ascending: sortAscending)
            rebuildDisplayedItems()
        }
    }

    /// Dirección del ordenamiento (`true` = ascendente, `false` = descendente).
    public var sortAscending: Bool {
        didSet {
            PersistenceService.shared.saveSort(field: sortField, ascending: sortAscending)
            rebuildDisplayedItems()
        }
    }

    // MARK: - Selección Múltiple y Renombrado en Línea (`F2`)

    /// Conjunto de IDs (`URL`) seleccionados actualmente en el panel derecho.
    public var selectedItemIDs: Set<FileItem.ID> = [] {
        didSet {
            if !selectedItemIDs.isEmpty {
                selectedSidebarNode = nil
            } else {
                selectionAnchorID = nil
                selectionFocusID = nil
            }
        }
    }

    /// Carpeta seleccionada directamente desde el árbol desplegable lateral izquierdo (para permitir borrarla con `Delete` / `Shift+Delete`).
    public var selectedSidebarNode: NavigationNode? = nil

    /// Elemento ancla fijo desde el cual se calculan rangos con `Shift + Clic` o `Shift + Flechas`.
    public var selectionAnchorID: FileItem.ID?

    /// Extremo activo (cursor móvil) al extender o reducir una selección por rango con el teclado.
    public var selectionFocusID: FileItem.ID?

    /// ID y token incremental para desplazar el scroll cuando la selección avanza con las flechas del teclado.
    public private(set) var keyboardScrollTargetID: FileItem.ID?
    public private(set) var keyboardScrollToken: Int = 0

    /// ID del elemento que se está renombrando en línea actualmente (`F2` / `Enter`).
    public var renamingItemID: FileItem.ID?

    /// Texto temporal durante el renombrado en línea.
    public var renamingDraftName: String = ""

    /// Indica si el panel flotante de Vista Rápida (Quick Look con Barra Espaciadora) está abierto.
    public var isQuickLookPresented: Bool = false

    /// Elemento cuyo diálogo modal de "Propiedades" (estilo Windows 11 Explorer) está abierto actualmente.
    public var propertiesTargetItem: FileItem? = nil

    /// Controla la presentación del modal "Compartir con Slack".
    public var isShareToSlackPresented: Bool = false
    public var slackShareURLs: [URL] = []

    // MARK: - Historial de Deshacer / Rehacer (`Cmd+Z` / `Cmd+Shift+Z`)

    public private(set) var undoStack: [ExplorerUndoEntry] = []
    public private(set) var redoStack: [ExplorerUndoEntry] = []
    public private(set) var isPerformingUndoRedo: Bool = false

    public var canUndo: Bool {
        !undoStack.isEmpty && !isPerformingUndoRedo
    }

    public var canRedo: Bool {
        !redoStack.isEmpty && !isPerformingUndoRedo
    }

    public var undoMenuTitle: String {
        let loc = LocalizationManager.shared
        guard let last = undoStack.last else {
            return loc.text(es: "Deshacer", en: "Undo")
        }
        return loc.text(
            es: "Deshacer \(last.actionDisplayName(using: loc))",
            en: "Undo \(last.actionDisplayName(using: loc))"
        )
    }

    public var redoMenuTitle: String {
        let loc = LocalizationManager.shared
        guard let last = redoStack.last else {
            return loc.text(es: "Rehacer", en: "Redo")
        }
        return loc.text(
            es: "Rehacer \(last.actionDisplayName(using: loc))",
            en: "Redo \(last.actionDisplayName(using: loc))"
        )
    }

    // MARK: - Dependencias

    public let fileSystemService: FileSystemService
    public let clipboardManager: ClipboardManager
    public let sidebarViewModel: SidebarViewModel

    /// Tarea de carga de directorio en curso, cancelable si el usuario cambia rápido de carpeta.
    private var directoryLoadTask: Task<Void, Never>?
    private var slowLoadingOverlayTask: Task<Void, Never>?
    private var backgroundVerifyTask: Task<Void, Never>?
    private var thumbnailPreloadTask: Task<Void, Never>?

    /// Carpeta a la que pertenecen los `allItems` actualmente visibles en pantalla.
    private var loadedDirectoryURL: URL?

    /// Monitor en tiempo real del directorio activo para sincronizar cambios hechos desde Finder/Terminal.
    private var currentDirectoryWatcher: DirectoryWatcher?
    private var watcherDebounceTask: Task<Void, Never>?
    private var watcherScanTask: Task<Void, Never>?
    private var hasPendingWatcherRescan: Bool = false
    private var lastDirectoryScanDate: Date = .distantPast
    private var lastObservedFolderMtime: TimeInterval?

    // MARK: - Inicialización

    public init(
        initialDirectoryURL: URL? = nil,
        fileSystemService: FileSystemService = .shared,
        clipboardManager: ClipboardManager? = nil,
        sidebarViewModel: SidebarViewModel? = nil
    ) {
        let resolvedInitial = (initialDirectoryURL ?? PersistenceService.shared.loadLastDirectory())
            .standardizedFileURL
        let savedSort = PersistenceService.shared.loadSort()

        self.currentDirectoryURL = resolvedInitial
        self.addressBarText = resolvedInitial.path(percentEncoded: false)
        self.showHiddenFiles = PersistenceService.shared.loadShowHiddenFiles()
        self.viewMode = PersistenceService.shared.loadViewMode()
        self.sortField = savedSort.field
        self.sortAscending = savedSort.ascending
        self.fileSystemService = fileSystemService
        self.clipboardManager = clipboardManager ?? ClipboardManager()
        self.sidebarViewModel = sidebarViewModel ?? SidebarViewModel(fileSystemService: fileSystemService)
    }

    // MARK: - Propiedades Computadas de Navegación y Breadcrumb

    public var canGoBack: Bool {
        !backStack.isEmpty
    }

    public var canGoForward: Bool {
        !forwardStack.isEmpty
    }

    public var canGoUp: Bool {
        currentDirectoryURL.standardizedFileURL.path != "/"
    }

    /// Título de la carpeta activa para la ventana o pestaña.
    public var currentFolderTitle: String {
        if currentDirectoryURL.path == "/" {
            return FileManager.default.displayName(atPath: "/")
        }
        if let trashURL = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first?.standardizedFileURL,
           currentDirectoryURL.standardizedFileURL == trashURL {
            return LocalizationManager.shared.text(es: "Papelera", en: "Trash")
        }
        return currentDirectoryURL.lastPathComponent
    }

    /// Descompone `currentDirectoryURL` en segmentos clicables para la barra Breadcrumb.
    public var breadcrumbSegments: [BreadcrumbSegment] {
        var segments: [BreadcrumbSegment] = []
        let components = currentDirectoryURL.standardizedFileURL.pathComponents
        let trashURL = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first?.standardizedFileURL
        var runningURL = URL(fileURLWithPath: "/")

        for component in components {
            if component == "/" {
                let rootName = FileManager.default.displayName(atPath: "/")
                segments.append(BreadcrumbSegment(title: rootName, url: runningURL))
            } else {
                runningURL.appendPathComponent(component)
                let segmentTitle: String
                if let trashURL, runningURL.standardizedFileURL == trashURL {
                    segmentTitle = LocalizationManager.shared.text(es: "Papelera", en: "Trash")
                } else {
                    segmentTitle = component
                }
                segments.append(BreadcrumbSegment(title: segmentTitle, url: runningURL))
            }
        }
        return segments
    }

    // MARK: - Elementos Filtrados y Ordenados

    private func setAllItems(_ items: [FileItem], precomputedDisplayed: [FileItem]? = nil) {
        self.allItems = items
        self.displayedItems = precomputedDisplayed ?? Self.computeDisplayedItems(
            from: items,
            showHiddenFiles: showHiddenFiles,
            searchQuery: searchQuery,
            sortField: sortField,
            sortAscending: sortAscending
        )
    }

    private func rebuildDisplayedItems() {
        self.displayedItems = Self.computeDisplayedItems(
            from: allItems,
            showHiddenFiles: showHiddenFiles,
            searchQuery: searchQuery,
            sortField: sortField,
            sortAscending: sortAscending
        )
    }

    private func scheduleThumbnailPreload(for directoryURL: URL, items: [FileItem]) {
        thumbnailPreloadTask?.cancel()
        guard viewMode == .largeIcons else { return }
        thumbnailPreloadTask = Task(priority: .utility) {
            await ThumbnailCacheService.shared.preloadFolderThumbnails(for: directoryURL, items: items)
        }
    }

    /// Filtra y ordena en cualquier hilo para evitar bloquear el hilo principal en carpetas masivas.
    private nonisolated static func computeDisplayedItems(
        from items: [FileItem],
        showHiddenFiles: Bool,
        searchQuery: String,
        sortField: FileItem.SortField,
        sortAscending: Bool
    ) -> [FileItem] {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        let filtered: [FileItem]
        if showHiddenFiles && trimmedQuery.isEmpty {
            filtered = items
        } else {
            filtered = items.filter { item in
                if !showHiddenFiles && item.isHidden {
                    return false
                }
                if !trimmedQuery.isEmpty {
                    return item.name.localizedCaseInsensitiveContains(trimmedQuery)
                        || item.kindDescription.localizedCaseInsensitiveContains(trimmedQuery)
                }
                return true
            }
        }

        return FileItem.sort(
            filtered,
            by: sortField,
            ascending: sortAscending,
            foldersFirst: true
        )
    }

    /// Diccionario rápido de elementos visibles indexados por su `id` (`URL`).
    public var displayedItemsByID: [FileItem.ID: FileItem] {
        Dictionary(uniqueKeysWithValues: displayedItems.map { ($0.id, $0) })
    }

    /// Modelos completos de los elementos actualmente seleccionados.
    public var selectedItems: [FileItem] {
        let map = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
        return selectedItemIDs.compactMap { map[$0] }
    }

    // MARK: - Métricas para la Barra de Estado Inferior (Status Bar)

    /// Total de elementos visibles en la carpeta actual.
    public var totalItemCount: Int {
        displayedItems.count
    }

    /// Total de elementos seleccionados.
    public var selectedItemCount: Int {
        selectedItemIDs.count
    }

    /// Suma en bytes de los tamaños de todos los archivos seleccionados (las carpetas aportan 0, igual que en Windows Explorer).
    public var selectedTotalBytes: Int64 {
        selectedItems.reduce(into: Int64(0)) { partial, item in
            if let size = item.size {
                partial += size
            }
        }
    }

    /// Suma formateada de los tamaños de los archivos seleccionados (vacío si solo hay carpetas seleccionadas o nada seleccionado).
    public var formattedSelectedTotalSize: String {
        let bytes = selectedTotalBytes
        guard bytes > 0 else { return "" }
        return bytes.formatted(
            .byteCount(
                style: .file,
                allowedUnits: [.kb, .mb, .gb, .tb],
                spellsOutZero: false,
                includesActualByteCount: false
            )
        )
    }

    // MARK: - Estado de Botones de la Barra de Comandos (Command Bar)

    public var canCutOrCopy: Bool {
        !selectedItemIDs.isEmpty
    }

    public var canPaste: Bool {
        clipboardManager.hasItemsToPaste
    }

    public var canRename: Bool {
        selectedItemIDs.count == 1
    }

    public var canDelete: Bool {
        !selectedItemIDs.isEmpty || canDeleteActiveSidebarNode
    }

    /// Indica si la carpeta actualmente focalizada desde el árbol lateral puede borrarse de forma segura.
    public var canDeleteActiveSidebarNode: Bool {
        guard let node = selectedSidebarNode,
              node.url.standardizedFileURL == currentDirectoryURL.standardizedFileURL else {
            return false
        }
        return isDeletableSidebarFolder(node.url)
    }

    /// Valida que una carpeta del árbol lateral no sea una ruta protegida del sistema, volumen raíz o directorio estándar de macOS.
    public func isDeletableSidebarFolder(_ url: URL) -> Bool {
        let std = url.standardizedFileURL
        let path = std.path(percentEncoded: false)
        if path == "/" { return false }
        if std.deletingLastPathComponent().path(percentEncoded: false) == "/Volumes" {
            return false
        }

        let fm = FileManager.default
        var protectedPaths: Set<String> = [
            "/",
            "/Applications",
            "/System",
            "/Library",
            "/Users",
            "/Volumes",
            "/bin",
            "/sbin",
            "/usr",
            "/etc",
            "/var",
            "/private",
            "/opt",
            "/cores",
            fm.homeDirectoryForCurrentUser.standardizedFileURL.path(percentEncoded: false)
        ]

        let protectedDomains: [FileManager.SearchPathDirectory] = [
            .desktopDirectory,
            .downloadsDirectory,
            .documentDirectory,
            .picturesDirectory,
            .moviesDirectory,
            .musicDirectory,
            .libraryDirectory,
            .applicationDirectory
        ]
        for domain in protectedDomains {
            if let dirURL = fm.urls(for: domain, in: .userDomainMask).first?.standardizedFileURL {
                protectedPaths.insert(dirURL.path(percentEncoded: false))
            }
        }
        return !protectedPaths.contains(path)
    }

    // MARK: - Acciones de Navegación

    /// Navega hacia una carpeta seleccionada desde el árbol lateral izquierdo manteniéndola focalizada.
    public func selectSidebarFolder(_ node: NavigationNode) {
        selectedItemIDs.removeAll()
        selectionAnchorID = nil
        selectedSidebarNode = node
        navigate(to: node.url, recordHistory: true, fromSidebar: true)
    }

    /// Navega a un directorio, registrando opcionalmente el cambio en el historial Atrás/Adelante.
    public func navigate(to destinationURL: URL, recordHistory: Bool = true, fromSidebar: Bool = false) {
        let standardized = destinationURL.standardizedFileURL

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: standardized.path(percentEncoded: false),
            isDirectory: &isDir
        ), isDir.boolValue else {
            let loc = LocalizationManager.shared
            errorMessage = loc.text(
                es: "La carpeta '\(standardized.path(percentEncoded: false))' no existe o no es accesible.",
                en: "The folder '\(standardized.path(percentEncoded: false))' does not exist or is not accessible."
            )
            return
        }

        if recordHistory && standardized != currentDirectoryURL {
            backStack.append(currentDirectoryURL)
            forwardStack.removeAll()
        }

        if !fromSidebar {
            selectedSidebarNode = nil
        }
        cancelRename()
        isQuickLookPresented = false
        selectedItemIDs.removeAll()
        selectionAnchorID = nil
        searchQuery = ""
        isEditingAddressBar = false
        KeyboardShortcuts.resignTextFocus()
        currentDirectoryURL = standardized
        addressBarText = standardized.path(percentEncoded: false)
        PersistenceService.shared.saveLastDirectory(standardized)

        loadCurrentDirectory()
    }

    /// Retrocede al directorio anterior en el historial.
    public func goBack() {
        guard let previousURL = backStack.popLast() else { return }
        forwardStack.append(currentDirectoryURL)
        navigate(to: previousURL, recordHistory: false)
    }

    /// Avanza al directorio siguiente en el historial.
    public func goForward() {
        guard let nextURL = forwardStack.popLast() else { return }
        backStack.append(currentDirectoryURL)
        navigate(to: nextURL, recordHistory: false)
    }

    /// Sube al directorio padre (`Up` / `Alt + Up`).
    public func goUp() {
        guard canGoUp else { return }
        let parentURL = currentDirectoryURL.deletingLastPathComponent().standardizedFileURL
        navigate(to: parentURL, recordHistory: true)
    }

    /// Recarga el contenido del directorio actual y la barra lateral conservando la selección de los ítems que sigan existiendo.
    public func refresh(preservingSelection: Bool = true) {
        loadCurrentDirectory(preservingSelection: preservingSelection)
        sidebarViewModel.refreshAllCachedDirectories(includeHidden: showHiddenFiles)
    }

    /// Activa el modo de edición de texto plano en la barra de direcciones (`Cmd+L`).
    public func beginAddressBarEditing() {
        addressBarText = currentDirectoryURL.path(percentEncoded: false)
        isEditingAddressBar = true
    }

    /// Confirma la ruta escrita manualmente en la barra de direcciones.
    public func commitAddressBarNavigation() {
        guard let resolvedURL = fileSystemService.resolveDirectoryPath(addressBarText) else {
            let loc = LocalizationManager.shared
            errorMessage = loc.text(
                es: "No se encontró el directorio '\(addressBarText)'.",
                en: "Could not find directory '\(addressBarText)'."
            )
            return
        }
        isEditingAddressBar = false
        navigate(to: resolvedURL, recordHistory: true)
    }

    /// Cancela la edición manual de la barra de direcciones y restaura el Breadcrumb.
    public func cancelAddressBarEditing() {
        addressBarText = currentDirectoryURL.path(percentEncoded: false)
        isEditingAddressBar = false
    }

    // MARK: - Apertura de Elementos y Vista Rápida (Quick Look / Preview.app)

    /// Abre un elemento: si es carpeta navegable, entra en ella; si es archivo o aplicación, lo abre con `NSWorkspace`.
    public func openItem(_ item: FileItem) {
        if item.isNavigableFolder {
            navigate(to: item.url, recordHistory: true)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    /// Elemento activo para previsualizar en Quick Look (Barra espaciadora).
    public var quickLookItem: FileItem? {
        let items = displayedItems
        if let anchorID = selectionAnchorID,
           selectedItemIDs.contains(anchorID),
           let match = items.first(where: { $0.id == anchorID }) {
            return match
        }
        if let firstSelectedID = selectedItemIDs.first,
           let match = items.first(where: { $0.id == firstSelectedID }) {
            return match
        }
        return nil
    }

    public var canSelectPreviousItem: Bool {
        guard let current = quickLookItem,
              let idx = displayedItems.firstIndex(where: { $0.id == current.id }) else {
            return false
        }
        return idx > 0
    }

    public var canSelectNextItem: Bool {
        guard let current = quickLookItem,
              let idx = displayedItems.firstIndex(where: { $0.id == current.id }) else {
            return false
        }
        return idx < displayedItems.count - 1
    }

    /// Alterna la apertura/cierre de la Vista Rápida al presionar la Barra Espaciadora (`Space`).
    public func toggleQuickLook() {
        if isQuickLookPresented {
            isQuickLookPresented = false
        } else if quickLookItem != nil {
            isQuickLookPresented = true
        }
    }

    /// Cierra la Vista Rápida.
    public func closeQuickLook() {
        isQuickLookPresented = false
    }

    private func requestKeyboardScroll(to itemID: FileItem.ID) {
        keyboardScrollTargetID = itemID
        keyboardScrollToken &+= 1
    }

    private func selectInitialItemIfEmpty(in items: [FileItem], offset: Int) -> Bool {
        guard selectedItemIDs.isEmpty, !items.isEmpty else { return false }
        let target = offset >= 0 ? items[0] : items[items.count - 1]
        selectedItemIDs = [target.id]
        selectionAnchorID = target.id
        selectionFocusID = target.id
        requestKeyboardScroll(to: target.id)
        return true
    }

    /// Selecciona el elemento anterior o siguiente en la lista (usado con las flechas ↑/↓ y dentro de Quick Look).
    public func selectAdjacentItem(offset: Int) {
        let items = displayedItems
        guard !items.isEmpty else { return }
        if selectInitialItemIfEmpty(in: items, offset: offset) { return }

        let currentIndex: Int? = {
            if let focusID = selectionFocusID,
               selectedItemIDs.contains(focusID),
               let idx = items.firstIndex(where: { $0.id == focusID }) {
                return idx
            }
            if let current = quickLookItem,
               let idx = items.firstIndex(where: { $0.id == current.id }) {
                return idx
            }
            return nil
        }()

        if let currentIndex {
            let newIndex = max(0, min(items.count - 1, currentIndex + offset))
            let target = items[newIndex]
            selectedItemIDs = [target.id]
            selectionAnchorID = target.id
            selectionFocusID = target.id
            requestKeyboardScroll(to: target.id)
        } else {
            let fallback = offset >= 0 ? items[0] : items[items.count - 1]
            selectedItemIDs = [fallback.id]
            selectionAnchorID = fallback.id
            selectionFocusID = fallback.id
            requestKeyboardScroll(to: fallback.id)
        }
    }

    /// Extiende o ajusta la selección en rango desde el elemento ancla (`Shift + ↓ / ↑ / ← / →`),
    /// replicando exactamente la selección por rango con `Shift + Clic` usando solo el teclado.
    public func extendSelection(offset: Int) {
        let items = displayedItems
        guard !items.isEmpty else { return }
        if selectInitialItemIfEmpty(in: items, offset: offset) { return }

        let anchorIndex: Int = {
            if let anchorID = selectionAnchorID,
               selectedItemIDs.contains(anchorID),
               let idx = items.firstIndex(where: { $0.id == anchorID }) {
                return idx
            }
            if offset >= 0, let firstIdx = items.firstIndex(where: { selectedItemIDs.contains($0.id) }) {
                return firstIdx
            }
            if offset < 0, let lastIdx = items.lastIndex(where: { selectedItemIDs.contains($0.id) }) {
                return lastIdx
            }
            return 0
        }()

        let currentFocusIndex: Int = {
            if let focusID = selectionFocusID,
               selectedItemIDs.contains(focusID),
               let idx = items.firstIndex(where: { $0.id == focusID }) {
                return idx
            }
            if offset >= 0, let lastIdx = items.lastIndex(where: { selectedItemIDs.contains($0.id) }) {
                return lastIdx
            }
            if offset < 0, let firstIdx = items.firstIndex(where: { selectedItemIDs.contains($0.id) }) {
                return firstIdx
            }
            return anchorIndex
        }()

        let newFocusIndex = max(0, min(items.count - 1, currentFocusIndex + offset))
        let lower = min(anchorIndex, newFocusIndex)
        let upper = max(anchorIndex, newFocusIndex)

        selectionAnchorID = items[anchorIndex].id
        selectionFocusID = items[newFocusIndex].id
        selectedItemIDs = Set(items[lower...upper].map(\.id))
        requestKeyboardScroll(to: items[newFocusIndex].id)
    }

    /// Abre explícitamente el archivo en la aplicación nativa `Preview.app` (Vista Previa) de macOS.
    public func openInNativePreviewApp(_ item: FileItem) {
        isQuickLookPresented = false
        let previewAppURL = URL(fileURLWithPath: "/System/Applications/Preview.app")

        if FileManager.default.fileExists(atPath: previewAppURL.path(percentEncoded: false)) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open(
                [item.url],
                withApplicationAt: previewAppURL,
                configuration: config
            ) { _, error in
                if error != nil {
                    Task { @MainActor in
                        NSWorkspace.shared.open(item.url)
                    }
                }
            }
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    /// Resuelve la URL de `Terminal.app` en el sistema macOS.
    public func terminalApplicationURL() -> URL? {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            return appURL
        }
        let fallback = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        return FileManager.default.fileExists(atPath: fallback.path(percentEncoded: false)) ? fallback : nil
    }

    /// Abre una ventana o pestaña de Terminal ubicada directamente en la carpeta indicada.
    public func openTerminal(at directoryURL: URL) {
        let targetURL = directoryURL.standardizedFileURL
        var isDir: ObjCBool = false
        let resolvedDir = (FileManager.default.fileExists(atPath: targetURL.path(percentEncoded: false), isDirectory: &isDir) && isDir.boolValue)
            ? targetURL
            : targetURL.deletingLastPathComponent()

        guard let terminalURL = terminalApplicationURL() else {
            errorMessage = LocalizationManager.shared.text(
                es: "No se encontró la aplicación Terminal en el sistema.",
                en: "Terminal application could not be found."
            )
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(
            [resolvedDir],
            withApplicationAt: terminalURL,
            configuration: config
        ) { [weak self] _, error in
            if let error {
                Task { @MainActor [weak self] in
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    public static let geminiBundleIdentifier = "com.google.GeminiMacOS"
    public static let geminiFinderSyncPasteboardName = NSPasteboard.Name("com.google.GeminiMacOS.FinderSync")
    public static let geminiAddFilesNotificationName = Notification.Name("com.google.GeminiMacOS.addFilesFromFinder")

    /// Resuelve la URL de la aplicación nativa `Gemini.app` si está instalada en macOS.
    public func geminiApplicationURL() -> URL? {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.geminiBundleIdentifier) {
            return appURL.standardizedFileURL
        }
        let candidates = [
            URL(fileURLWithPath: "/Applications/Gemini.app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Gemini.app", isDirectory: true),
        ]
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate.standardizedFileURL
            }
        }
        return nil
    }

    /// Devuelve el ícono de `Gemini.app` redimensionado a 16×16 para el menú contextual.
    public func geminiMenuIcon() -> NSImage? {
        guard let geminiURL = geminiApplicationURL() else { return nil }
        let rawIcon = NSWorkspace.shared.icon(forFile: geminiURL.path(percentEncoded: false))
        let sized = (rawIcon.copy() as? NSImage) ?? rawIcon
        sized.size = NSSize(width: 16, height: 16)
        return sized
    }

    /// Escribe las rutas estandarizadas como `NSString` en el pasteboard de `FinderSync` de Gemini.
    @discardableResult
    public func writePathsToGeminiPasteboard(_ urls: [URL], to pasteboard: NSPasteboard = NSPasteboard(name: ExplorerViewModel.geminiFinderSyncPasteboardName)) -> [String] {
        let targetPaths = urls.map { $0.standardizedFileURL.path(percentEncoded: false) }
        guard !targetPaths.isEmpty else { return [] }
        pasteboard.clearContents()
        pasteboard.writeObjects(targetPaths.map { $0 as NSString })
        return targetPaths
    }

    /// Envía uno o más archivos/carpetas a la aplicación `Gemini.app` usando el mismo flujo que la extensión de Finder.
    public func addToGemini(_ urls: [URL]) {
        let targetURLs = urls.map(\.standardizedFileURL)
        guard !targetURLs.isEmpty else { return }

        guard let geminiURL = geminiApplicationURL() else {
            errorMessage = LocalizationManager.shared.text(
                es: "No se encontró la aplicación Gemini instalada en el sistema.",
                en: "Gemini application could not be found on this Mac."
            )
            return
        }

        let wasAlreadyRunning = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.geminiBundleIdentifier
        ).contains { !$0.isTerminated }

        writePathsToGeminiPasteboard(targetURLs)

        DistributedNotificationCenter.default().postNotificationName(
            Self.geminiAddFilesNotificationName,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: geminiURL, configuration: config) { [weak self] _, error in
            Task { @MainActor [weak self] in
                if let error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                if !wasAlreadyRunning {
                    // Tras el arranque en frío, reforzamos la notificación una vez que Gemini terminó de registrar su observer.
                    try? await Task.sleep(for: .milliseconds(450))
                    DistributedNotificationCenter.default().postNotificationName(
                        Self.geminiAddFilesNotificationName,
                        object: nil,
                        userInfo: nil,
                        deliverImmediately: true
                    )
                }
            }
        }
    }

    // MARK: - Integración con Slack ("Añadir a Slack / Compartir con Slack")

    public static let slackBundleIdentifier = "com.tinyspeck.slackmacgap"

    /// Resuelve la URL de la aplicación nativa `Slack.app` si está instalada en macOS.
    public func slackApplicationURL() -> URL? {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.slackBundleIdentifier) {
            return appURL.standardizedFileURL
        }
        let candidates = [
            URL(fileURLWithPath: "/Applications/Slack.app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Slack.app", isDirectory: true),
        ]
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate.standardizedFileURL
            }
        }
        return nil
    }

    /// Devuelve el ícono de `Slack.app` redimensionado a 16×16 para el menú contextual.
    public func slackMenuIcon() -> NSImage? {
        guard let slackURL = slackApplicationURL() else { return nil }
        let rawIcon = NSWorkspace.shared.icon(forFile: slackURL.path(percentEncoded: false))
        let sized = (rawIcon.copy() as? NSImage) ?? rawIcon
        sized.size = NSSize(width: 16, height: 16)
        return sized
    }

    /// Prepara y presenta el modal "Compartir con Slack" para las URLs indicadas.
    public func presentShareToSlack(for urls: [URL]) {
        let targets = urls.map(\.standardizedFileURL)
        guard !targets.isEmpty else { return }

        guard slackApplicationURL() != nil else {
            errorMessage = LocalizationManager.shared.text(
                es: "No se encontró la aplicación Slack instalada en el sistema.",
                en: "Slack application could not be found on this Mac."
            )
            return
        }

        self.slackShareURLs = targets
        self.isShareToSlackPresented = true
    }

    /// Envía los archivos seleccionados a Slack, copiándolos al portapapeles y navegando al canal/usuario especificado.
    public func sendToSlack(urls: [URL], destination: String, message: String) {
        let targets = urls.map(\.standardizedFileURL)
        guard !targets.isEmpty else { return }

        guard let slackURL = slackApplicationURL() else {
            errorMessage = LocalizationManager.shared.text(
                es: "No se encontró la aplicación Slack instalada en el sistema.",
                en: "Slack application could not be found on this Mac."
            )
            return
        }

        let trimmedDestination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDestination.isEmpty {
            PersistenceService.shared.saveSlackRecentDestination(trimmedDestination)
        }

        // 1. Escribir los archivos en el portapapeles universal del sistema
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(targets.map { $0 as NSURL })

        // 2. Activar la app Slack
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: slackURL, configuration: config) { [weak self] _, error in
            Task { @MainActor [weak self] in
                if let error {
                    self?.errorMessage = error.localizedDescription
                    return
                }

                // 3. Si se especificó canal/persona, automatizar Quick Switcher (Cmd+K)
                if !trimmedDestination.isEmpty {
                    let cleanDest = trimmedDestination
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "\"", with: "\\\"")
                    let cleanMsg = message.trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "\"", with: "\\\"")

                    let scriptSource: String
                    if !cleanMsg.isEmpty {
                        scriptSource = """
                        tell application "Slack" to activate
                        delay 0.25
                        tell application "System Events"
                            tell process "Slack"
                                keystroke "k" using {command down}
                                delay 0.35
                                keystroke "\(cleanDest)"
                                delay 0.45
                                key code 36
                                delay 0.45
                                keystroke "v" using {command down}
                                delay 0.35
                                keystroke "\(cleanMsg)"
                            end tell
                        end tell
                        """
                    } else {
                        scriptSource = """
                        tell application "Slack" to activate
                        delay 0.25
                        tell application "System Events"
                            tell process "Slack"
                                keystroke "k" using {command down}
                                delay 0.35
                                keystroke "\(cleanDest)"
                                delay 0.45
                                key code 36
                                delay 0.45
                                keystroke "v" using {command down}
                            end tell
                        end tell
                        """
                    }

                    Task.detached {
                        let appleScript = NSAppleScript(source: scriptSource)
                        var errorDict: NSDictionary?
                        appleScript?.executeAndReturnError(&errorDict)
                    }
                } else {
                    let scriptSource = """
                    tell application "Slack" to activate
                    delay 0.25
                    tell application "System Events"
                        tell process "Slack"
                            keystroke "v" using {command down}
                        end tell
                    end tell
                    """
                    Task.detached {
                        let appleScript = NSAppleScript(source: scriptSource)
                        var errorDict: NSDictionary?
                        appleScript?.executeAndReturnError(&errorDict)
                    }
                }
            }
        }
    }

    /// Abre el modal de "Propiedades" (estilo Windows 11 Explorer) para el elemento indicado o el seleccionado.
    public func showProperties(for item: FileItem? = nil) {
        if let item {
            propertiesTargetItem = item
        } else if let selected = selectedItems.first {
            propertiesTargetItem = selected
        } else if let currentFolderItem = try? FileItem(url: currentDirectoryURL) {
            propertiesTargetItem = currentFolderItem
        }
    }

    /// Abre el modal de "Propiedades" construyendo un `FileItem` a partir de cualquier `URL` (ej. árbol lateral).
    public func showPropertiesForURL(_ url: URL) {
        if let folderItem = try? FileItem(url: url) {
            propertiesTargetItem = folderItem
        } else {
            propertiesTargetItem = FileItem(
                url: url,
                name: url.lastPathComponent.isEmpty ? "Macintosh HD" : url.lastPathComponent,
                isDirectory: url.hasDirectoryPath
            )
        }
    }

    // MARK: - Ordenamiento por Encabezados de Columna

    /// Alterna el ordenamiento al hacer clic en un encabezado de columna en la vista Detalles.
    public func toggleSort(by field: FileItem.SortField) {
        if sortField == field {
            sortAscending.toggle()
        } else {
            sortField = field
            sortAscending = true
        }
    }

    // MARK: - Selección Múltiple (Clic, Cmd+Clic, Shift+Clic, Cuadro de Arrastre)

    /// Gestiona la selección de un ítem respetando los modificadores nativos (`Shift` para rango, `Cmd` para alternar).
    public func handleSelection(of item: FileItem, modifiers: EventModifiers) {
        if renamingItemID == nil && !isEditingAddressBar {
            KeyboardShortcuts.resignTextFocus()
        }
        let items = displayedItems
        if modifiers.contains(.shift),
           let anchorID = selectionAnchorID,
           let anchorIndex = items.firstIndex(where: { $0.id == anchorID }),
           let targetIndex = items.firstIndex(where: { $0.id == item.id }) {
            let lower = min(anchorIndex, targetIndex)
            let upper = max(anchorIndex, targetIndex)
            let rangeIDs = items[lower...upper].map(\.id)
            if modifiers.contains(.command) {
                selectedItemIDs.formUnion(rangeIDs)
            } else {
                selectedItemIDs = Set(rangeIDs)
            }
            selectionFocusID = item.id
        } else if modifiers.contains(.command) {
            if selectedItemIDs.contains(item.id) {
                selectedItemIDs.remove(item.id)
            } else {
                selectedItemIDs.insert(item.id)
                selectionAnchorID = item.id
                selectionFocusID = item.id
            }
        } else {
            selectedItemIDs = [item.id]
            selectionAnchorID = item.id
            selectionFocusID = item.id
        }
    }

    /// Selecciona todos los elementos visibles (`Cmd+A`).
    public func selectAll() {
        selectedItemIDs = Set(displayedItems.map(\.id))
    }

    /// Deselecciona todos los elementos y cancela cualquier edición en línea activa.
    public func clearSelection() {
        selectedItemIDs.removeAll()
        selectionAnchorID = nil
        cancelRename()
        if !isEditingAddressBar {
            KeyboardShortcuts.resignTextFocus()
        }
    }

    // MARK: - Operaciones de Barra de Comandos y Atajos (`Cmd+X`, `Cmd+C`, `Cmd+V`, `F2`, `Delete`)

    /// Crea una nueva carpeta en el directorio actual, la selecciona y activa el renombrado en línea (`F2`).
    public func createNewFolder() {
        let targetDir = currentDirectoryURL
        let baseName = LocalizationManager.shared.text(es: "Nueva carpeta", en: "New folder")
        Task {
            do {
                let createdURL = try await fileSystemService.createFolder(in: targetDir, baseName: baseName)
                recordUndo(.createdItems(urls: [createdURL], trashedURLs: [], actionType: .newFolder))
                await reloadDirectoryAndSelect([createdURL], startRenameOn: createdURL)
                sidebarViewModel.refreshSubdirectoriesIfNeeded(at: targetDir, includeHidden: showHiddenFiles)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Crea un nuevo archivo de texto vacío en el directorio actual, lo selecciona y activa el renombrado en línea.
    public func createNewTextFile() {
        let targetDir = currentDirectoryURL
        let baseName = LocalizationManager.shared.text(es: "Nuevo documento de texto", en: "New Text Document")
        Task {
            do {
                let createdURL = try await fileSystemService.createFile(in: targetDir, baseName: baseName)
                recordUndo(.createdItems(urls: [createdURL], trashedURLs: [], actionType: .newFile))
                await reloadDirectoryAndSelect([createdURL], startRenameOn: createdURL)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Corta los elementos seleccionados (`Cmd+X`), atenuándolos visualmente hasta que se peguen con `Cmd+V`.
    public func cutSelectedItems() {
        guard !selectedItemIDs.isEmpty else { return }
        clipboardManager.cut(Array(selectedItemIDs))
    }

    /// Copia los elementos seleccionados (`Cmd+C`).
    public func copySelectedItems() {
        guard !selectedItemIDs.isEmpty else { return }
        clipboardManager.copy(Array(selectedItemIDs))
    }

    /// Pega los elementos del portapapeles en la carpeta actual (`Cmd+V`).
    /// Si provienen de `Cmd+X`, ejecuta `moveItem` real y actualiza tanto la carpeta actual como el árbol lateral.
    public func pasteItems() {
        guard clipboardManager.hasItemsToPaste else { return }
        let targetDir = currentDirectoryURL
        let previousCutParents = Set(clipboardManager.payload?.urls.map { $0.deletingLastPathComponent().standardizedFileURL } ?? [])

        Task {
            do {
                let result = try await clipboardManager.pasteWithResult(
                    into: targetDir,
                    using: fileSystemService
                )
                switch result.mode {
                case .cut:
                    let movedPairs = result.pairs.filter { $0.source != $0.destination }
                    if !movedPairs.isEmpty {
                        recordUndo(.move(pairs: movedPairs))
                    }
                case .copy:
                    let copiedURLs = result.resultingURLs
                    if !copiedURLs.isEmpty {
                        recordUndo(.createdItems(urls: copiedURLs, trashedURLs: [], actionType: .pasteCopy))
                    }
                }
                await reloadDirectoryAndSelect(result.resultingURLs, startRenameOn: nil)
                sidebarViewModel.refreshSubdirectoriesIfNeeded(at: targetDir, includeHidden: showHiddenFiles)
                for parent in previousCutParents {
                    sidebarViewModel.refreshSubdirectoriesIfNeeded(at: parent, includeHidden: showHiddenFiles)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Inicia el renombrado en línea (`F2` o `Enter`) sobre el único elemento seleccionado.
    public func beginRenamingSelectedItem() {
        guard selectedItemIDs.count == 1,
              let selectedID = selectedItemIDs.first,
              let item = allItems.first(where: { $0.id == selectedID }) else {
            return
        }
        renamingItemID = item.id
        renamingDraftName = item.name
    }

    /// Confirma el renombrado en línea y actualiza el archivo en disco.
    public func commitRename() {
        guard let itemID = renamingItemID,
              let item = allItems.first(where: { $0.id == itemID }) else {
            cancelRename()
            return
        }

        let newName = renamingDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        cancelRename()

        guard !newName.isEmpty, newName != item.name else { return }
        let targetDir = currentDirectoryURL
        let oldURL = item.url.standardizedFileURL

        Task {
            do {
                let newURL = try await fileSystemService.renameItem(at: oldURL, to: newName)
                if newURL.standardizedFileURL != oldURL {
                    recordUndo(.rename(oldURL: oldURL, newURL: newURL.standardizedFileURL))
                }
                await reloadDirectoryAndSelect([newURL], startRenameOn: nil)
                if item.isNavigableFolder {
                    sidebarViewModel.refreshSubdirectoriesIfNeeded(at: targetDir, includeHidden: showHiddenFiles)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Cancela el renombrado en línea sin modificar el sistema de archivos.
    public func cancelRename() {
        renamingItemID = nil
        renamingDraftName = ""
        if hasPendingWatcherRescan && !isLoading {
            hasPendingWatcherRescan = false
            scheduleCurrentDirectoryWatcherRefresh(for: currentDirectoryURL.standardizedFileURL)
        }
    }

    /// Envía a la Papelera los elementos seleccionados (en la lista o en el árbol lateral izquierdo).
    public func moveSelectedItemsToTrash() {
        if !selectedItemIDs.isEmpty {
            moveURLsToTrash(Array(selectedItemIDs))
        } else if canDeleteActiveSidebarNode, let sidebarNode = selectedSidebarNode {
            moveSidebarNodeToTrash(sidebarNode)
        }
    }

    /// Envía a la Papelera una carpeta específica seleccionada desde el árbol lateral izquierdo.
    public func moveSidebarNodeToTrash(_ node: NavigationNode) {
        let targetURL = node.url.standardizedFileURL
        guard isDeletableSidebarFolder(targetURL) else { return }
        moveURLsToTrash([targetURL])
    }

    private func moveURLsToTrash(_ urlsToDelete: [URL]) {
        guard !urlsToDelete.isEmpty else { return }
        cancelRename()

        Task {
            do {
                let trashedPairs = try await fileSystemService.moveItemsToTrashWithPairs(urlsToDelete)
                if !trashedPairs.isEmpty {
                    recordUndo(.trash(pairs: trashedPairs))
                }
                await finishDeletingItems(urlsToDelete)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Solicita confirmación y borra permanentemente los elementos seleccionados (`Shift+Delete`).
    public func requestPermanentDeleteSelectedItems() {
        if !selectedItems.isEmpty {
            let itemsToDelete = selectedItems
            requestPermanentDelete(
                urls: itemsToDelete.map(\.url),
                displayNames: itemsToDelete.map(\.name)
            )
        } else if canDeleteActiveSidebarNode, let sidebarNode = selectedSidebarNode {
            requestPermanentDeleteSidebarNode(sidebarNode)
        }
    }

    /// Solicita confirmación y borra permanentemente una carpeta específica desde el árbol lateral izquierdo.
    public func requestPermanentDeleteSidebarNode(_ node: NavigationNode) {
        let targetURL = node.url.standardizedFileURL
        guard isDeletableSidebarFolder(targetURL) else { return }
        requestPermanentDelete(
            urls: [targetURL],
            displayNames: [LocalizationManager.shared.sidebarNodeTitle(for: node)]
        )
    }

    private func requestPermanentDelete(urls: [URL], displayNames: [String]) {
        guard !urls.isEmpty else { return }

        cancelRename()

        let loc = LocalizationManager.shared
        let alert = NSAlert()
        alert.alertStyle = .warning
        if let trashSlashIcon = NSImage(systemSymbolName: "trash.slash.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 36, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
            alert.icon = trashSlashIcon.withSymbolConfiguration(config) ?? trashSlashIcon
        }

        if urls.count == 1, let singleName = displayNames.first ?? urls.first?.lastPathComponent {
            alert.messageText = loc.text(
                es: "¿Eliminar \"\(singleName)\" de forma permanente?",
                en: "Permanently delete \"\(singleName)\"?"
            )
        } else {
            alert.messageText = loc.text(
                es: "¿Eliminar \(urls.count) elementos de forma permanente?",
                en: "Permanently delete \(urls.count) items?"
            )
        }

        alert.informativeText = loc.text(
            es: "Se borrará directamente del disco sin pasar por la Papelera. Esta acción no se puede deshacer.",
            en: "Items will be deleted directly from disk without moving to the Trash. This action cannot be undone."
        )

        let confirmButton = alert.addButton(
            withTitle: loc.text(es: "Eliminar permanentemente", en: "Delete Permanently")
        )
        confirmButton.bezelColor = .systemRed
        confirmButton.keyEquivalent = "\r"
        let cancelButton = alert.addButton(
            withTitle: loc.text(es: "Cancelar", en: "Cancel")
        )
        cancelButton.keyEquivalent = "\u{1b}"

        let standardizedURLs = urls.map(\.standardizedFileURL)

        let targetWindow = NSApp.keyWindow?.tabGroup?.selectedWindow
            ?? NSApp.keyWindow
            ?? NSApp.mainWindow?.tabGroup?.selectedWindow
            ?? NSApp.mainWindow

        if let hostWindow = targetWindow {
            alert.beginSheetModal(for: hostWindow) { [weak self] response in
                guard response == .alertFirstButtonReturn else { return }
                Task { @MainActor [weak self] in
                    await self?.permanentlyDeleteItems(standardizedURLs)
                }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            Task { @MainActor [weak self] in
                await self?.permanentlyDeleteItems(standardizedURLs)
            }
        }
    }

    private func permanentlyDeleteItems(_ urlsToDelete: [URL]) async {
        do {
            try await fileSystemService.deleteItemsPermanently(urlsToDelete)
            await finishDeletingItems(urlsToDelete)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finishDeletingItems(_ deletedURLs: [URL]) async {
        let deletedPaths = deletedURLs.map { $0.standardizedFileURL.path(percentEncoded: false) }
        func isDeletedOrDescendant(_ url: URL) -> Bool {
            let candidatePath = url.standardizedFileURL.path(percentEncoded: false)
            return deletedPaths.contains { path in
                candidatePath == path || candidatePath.hasPrefix(path.hasSuffix("/") ? path : path + "/")
            }
        }

        if let payload = clipboardManager.payload,
           !payload.urlSet.isDisjoint(with: Set(deletedURLs.map(\.standardizedFileURL))) {
            clipboardManager.clear()
        }

        backStack.removeAll { isDeletedOrDescendant($0) }
        forwardStack.removeAll { isDeletedOrDescendant($0) }

        if let sidebarSelection = selectedSidebarNode, isDeletedOrDescendant(sidebarSelection.url) {
            selectedSidebarNode = nil
        }

        sidebarViewModel.handleDeletedURLs(deletedURLs, includeHidden: showHiddenFiles)

        let fm = FileManager.default
        var survivingDir = currentDirectoryURL.standardizedFileURL
        var shouldNavigateToParent = isDeletedOrDescendant(survivingDir)

        while survivingDir.path != "/" {
            var isDir: ObjCBool = false
            if !isDeletedOrDescendant(survivingDir),
               fm.fileExists(atPath: survivingDir.path(percentEncoded: false), isDirectory: &isDir),
               isDir.boolValue {
                break
            }
            survivingDir = survivingDir.deletingLastPathComponent().standardizedFileURL
            shouldNavigateToParent = true
        }

        selectedItemIDs.removeAll()
        selectionAnchorID = nil

        if shouldNavigateToParent {
            navigate(to: survivingDir, recordHistory: false)
        } else {
            await reloadDirectoryAndSelect([], startRenameOn: nil)
        }
    }

    /// Desarchiva el archivo `.zip` indicado (o todos los archivos `.zip` seleccionados) dentro de la carpeta actual.
    public func unarchiveItem(_ item: FileItem) {
        let zipCandidates = selectedItems.filter(\.isZipArchive)
        let itemsToUnarchive = zipCandidates.contains(where: { $0.id == item.id })
            ? zipCandidates
            : (item.isZipArchive ? [item] : [])

        guard !itemsToUnarchive.isEmpty else { return }
        let targetDir = currentDirectoryURL

        Task {
            do {
                var extractedFolderURLs: [URL] = []
                for zipItem in itemsToUnarchive {
                    let extractedURL = try await fileSystemService.unarchiveZipItem(at: zipItem.url)
                    extractedFolderURLs.append(extractedURL)
                }
                if !extractedFolderURLs.isEmpty {
                    recordUndo(.createdItems(urls: extractedFolderURLs, trashedURLs: [], actionType: .unarchive))
                }
                await reloadDirectoryAndSelect(extractedFolderURLs, startRenameOn: nil)
                sidebarViewModel.refreshSubdirectoriesIfNeeded(at: targetDir, includeHidden: showHiddenFiles)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Deshacer / Rehacer Operaciones de Archivos (`Cmd+Z` / `Cmd+Shift+Z`)

    private func recordUndo(_ kind: ExplorerUndoOperationKind) {
        redoStack.removeAll()
        undoStack.append(ExplorerUndoEntry(kind: kind))
        if undoStack.count > 50 {
            undoStack.removeFirst(undoStack.count - 50)
        }
    }

    /// Deshace la última acción reversible sobre archivos (eliminar a Papelera, mover, pegar/copiar, renombrar, crear, desarchivar).
    public func undoLastOperation() {
        guard canUndo, let entry = undoStack.popLast() else { return }
        Task { @MainActor [weak self] in
            await self?.performUndoOrRedo(entry: entry, isUndo: true)
        }
    }

    /// Rehace la última acción deshecha con `Cmd+Shift+Z`.
    public func redoLastOperation() {
        guard canRedo, let entry = redoStack.popLast() else { return }
        Task { @MainActor [weak self] in
            await self?.performUndoOrRedo(entry: entry, isUndo: false)
        }
    }

    private func performUndoOrRedo(entry: ExplorerUndoEntry, isUndo: Bool) async {
        isPerformingUndoRedo = true
        defer { isPerformingUndoRedo = false }

        cancelRename()
        errorMessage = nil

        do {
            var revealURLs: [URL] = []
            var affectedParents: Set<URL> = []
            let inverseEntry: ExplorerUndoEntry?

            switch entry.kind {
            case .move(let pairs):
                let moves = isUndo
                    ? pairs.reversed().map { FileMovePair(source: $0.destination, destination: $0.source) }
                    : pairs
                let completed = try await fileSystemService.moveItemsToExactDestinations(moves)
                revealURLs = completed.map(\.destination)
                for pair in completed {
                    affectedParents.insert(pair.source.deletingLastPathComponent().standardizedFileURL)
                    affectedParents.insert(pair.destination.deletingLastPathComponent().standardizedFileURL)
                }
                let nextKind: ExplorerUndoOperationKind = isUndo
                    ? .move(pairs: completed.reversed().map { FileMovePair(source: $0.destination, destination: $0.source) })
                    : .move(pairs: completed)
                inverseEntry = ExplorerUndoEntry(kind: nextKind)

            case .createdItems(let urls, let trashedURLs, let actionType):
                if isUndo {
                    let fm = FileManager.default
                    let existingURLs = urls.filter { fm.fileExists(atPath: $0.path(percentEncoded: false)) }
                    guard !existingURLs.isEmpty else {
                        let loc = LocalizationManager.shared
                        throw FileSystemError.operationFailed(
                            loc.text(
                                es: "Los elementos ya no existen para deshacer esta acción.",
                                en: "Items no longer exist to undo this action."
                            )
                        )
                    }
                    for url in existingURLs {
                        affectedParents.insert(url.deletingLastPathComponent().standardizedFileURL)
                    }
                    let trashedPairs = try await fileSystemService.moveItemsToTrashWithPairs(existingURLs)
                    inverseEntry = ExplorerUndoEntry(
                        kind: .createdItems(
                            urls: trashedPairs.map(\.source),
                            trashedURLs: trashedPairs.map(\.destination),
                            actionType: actionType
                        )
                    )
                } else {
                    guard trashedURLs.count == urls.count && !trashedURLs.isEmpty else {
                        inverseEntry = nil
                        break
                    }
                    let restorePairs = zip(trashedURLs, urls).map { FileMovePair(source: $0.0, destination: $0.1) }
                    let restored = try await fileSystemService.moveItemsToExactDestinations(restorePairs)
                    revealURLs = restored.map(\.destination)
                    for pair in restored {
                        affectedParents.insert(pair.destination.deletingLastPathComponent().standardizedFileURL)
                    }
                    inverseEntry = ExplorerUndoEntry(
                        kind: .createdItems(
                            urls: restored.map(\.destination),
                            trashedURLs: [],
                            actionType: actionType
                        )
                    )
                }

            case .trash(let pairs):
                if isUndo {
                    let restoreMoves = pairs.reversed().map { FileMovePair(source: $0.destination, destination: $0.source) }
                    let restored = try await fileSystemService.moveItemsToExactDestinations(restoreMoves)
                    revealURLs = restored.map(\.destination)
                    for pair in restored {
                        affectedParents.insert(pair.destination.deletingLastPathComponent().standardizedFileURL)
                    }
                    let nextPairs = restored.reversed().map { FileMovePair(source: $0.destination, destination: $0.source) }
                    inverseEntry = ExplorerUndoEntry(kind: .trash(pairs: nextPairs))
                } else {
                    let urlsToTrash = pairs.map(\.source)
                    for url in urlsToTrash {
                        affectedParents.insert(url.deletingLastPathComponent().standardizedFileURL)
                    }
                    let trashedPairs = try await fileSystemService.moveItemsToTrashWithPairs(urlsToTrash)
                    inverseEntry = trashedPairs.isEmpty ? nil : ExplorerUndoEntry(kind: .trash(pairs: trashedPairs))
                }

            case .rename(let oldURL, let newURL):
                if isUndo {
                    let restoredURL = try await fileSystemService.renameItem(at: newURL, to: oldURL.lastPathComponent)
                    revealURLs = [restoredURL]
                    affectedParents.insert(restoredURL.deletingLastPathComponent().standardizedFileURL)
                    inverseEntry = ExplorerUndoEntry(kind: .rename(oldURL: restoredURL, newURL: newURL))
                } else {
                    let renamedURL = try await fileSystemService.renameItem(at: oldURL, to: newURL.lastPathComponent)
                    revealURLs = [renamedURL]
                    affectedParents.insert(renamedURL.deletingLastPathComponent().standardizedFileURL)
                    inverseEntry = ExplorerUndoEntry(kind: .rename(oldURL: oldURL, newURL: renamedURL))
                }
            }

            if let inverseEntry {
                if isUndo {
                    redoStack.append(inverseEntry)
                } else {
                    undoStack.append(inverseEntry)
                }
            }

            let currentDir = currentDirectoryURL.standardizedFileURL
            for parent in affectedParents {
                sidebarViewModel.refreshSubdirectoriesIfNeeded(at: parent, includeHidden: showHiddenFiles)
            }

            let visibleInCurrentDir = revealURLs.filter {
                $0.deletingLastPathComponent().standardizedFileURL == currentDir
            }

            if affectedParents.contains(currentDir) || !visibleInCurrentDir.isEmpty {
                await reloadDirectoryAndSelect(visibleInCurrentDir, startRenameOn: nil)
            } else if let primaryDir = (revealURLs.first?.deletingLastPathComponent().standardizedFileURL ?? affectedParents.first),
                      FileManager.default.fileExists(atPath: primaryDir.path(percentEncoded: false)) {
                navigate(to: primaryDir, recordHistory: true)
            } else {
                await reloadDirectoryAndSelect([], startRenameOn: nil)
            }
        } catch {
            // Reencolar la entrada si falló (por ej. archivo faltante) para no perder la opción o mostrar mensaje claro
            if isUndo {
                undoStack.append(entry)
            } else {
                redoStack.append(entry)
            }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Drag & Drop Estilo Finder (Origen y Destino)

    /// Devuelve los elementos a arrastrar (toda la selección si `anchorItem` ya está seleccionado,
    /// o selecciona únicamente `anchorItem` antes de iniciar la sesión de arrastre).
    public func itemsForDrag(startingWith anchorItem: FileItem) -> [FileItem] {
        if selectedItemIDs.contains(anchorItem.id) {
            let orderedSelection = displayedItems.filter { selectedItemIDs.contains($0.id) }
            return orderedSelection.isEmpty ? [anchorItem] : orderedSelection
        }
        selectedItemIDs = [anchorItem.id]
        selectionAnchorID = anchorItem.id
        selectedSidebarNode = nil
        return [anchorItem]
    }

    /// Procesa archivos/carpetas soltados dentro de una carpeta o vista de `MacFileExplorer`
    /// ejecutando Mover (`moveItems`) o Copiar (`copyItems`) según las reglas nativas de macOS Finder.
    public func handleDrop(
        urls rawURLs: [URL],
        into destinationDirectory: URL,
        explicitCopy: Bool,
        explicitMove: Bool
    ) async {
        let fm = FileManager.default
        let destDir = destinationDirectory.standardizedFileURL
        let validSources = rawURLs
            .map(\.standardizedFileURL)
            .filter { $0.isFileURL && fm.fileExists(atPath: $0.path(percentEncoded: false)) }
        guard !validSources.isEmpty else { return }

        let shouldCopy = DragDropOperationHelper.shouldCopy(
            sources: validSources,
            destinationDir: destDir,
            forceOptionCopy: explicitCopy,
            forceCommandMove: explicitMove
        )
        guard DragDropOperationHelper.canDrop(validSources, into: destDir, copyRequested: shouldCopy) else {
            return
        }

        let sourceParents = Set(validSources.map { $0.deletingLastPathComponent().standardizedFileURL })
        do {
            let resultingURLs: [URL]
            if shouldCopy {
                let copiedPairs = try await fileSystemService.copyItemPairs(from: validSources, to: destDir)
                resultingURLs = copiedPairs.map(\.destination)
                if !resultingURLs.isEmpty {
                    recordUndo(.createdItems(urls: resultingURLs, trashedURLs: [], actionType: .dragCopy))
                }
            } else {
                let movedPairs = try await fileSystemService.moveItemPairs(from: validSources, to: destDir)
                resultingURLs = movedPairs.map(\.destination)
                let effectiveMoves = movedPairs.filter { $0.source != $0.destination }
                if !effectiveMoves.isEmpty {
                    recordUndo(.move(pairs: effectiveMoves))
                }
                if let payload = clipboardManager.payload,
                   !payload.urlSet.isDisjoint(with: Set(validSources)) {
                    clipboardManager.clear()
                }
            }

            if destDir == currentDirectoryURL.standardizedFileURL {
                await reloadDirectoryAndSelect(resultingURLs, startRenameOn: nil)
            } else if !shouldCopy && sourceParents.contains(currentDirectoryURL.standardizedFileURL) {
                await reloadDirectoryAndSelect([], startRenameOn: nil)
            }

            sidebarViewModel.refreshSubdirectoriesIfNeeded(at: destDir, includeHidden: showHiddenFiles)
            if !shouldCopy {
                for parent in sourceParents where parent != destDir {
                    sidebarViewModel.refreshSubdirectoriesIfNeeded(at: parent, includeHidden: showHiddenFiles)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Finaliza una sesión de arrastre hacia fuera de la vista (ej. Finder, otra app o Papelera del Dock).
    /// Cuando Finder acepta con `.move`, elimina el origen restante para completar el traslado del archivo.
    public func handleCompletedOutgoingDrag(urls: [URL], operation: NSDragOperation) {
        let standardized = urls.map(\.standardizedFileURL)
        guard !standardized.isEmpty else { return }

        if DragDropOperationHelper.consumeInternalDropMatch(for: standardized) {
            if operation == .move {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(120))
                    self?.loadCurrentDirectory(preservingSelection: true)
                }
            }
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let fm = FileManager.default

            if operation == .delete {
                let stillOnDisk = standardized.filter { fm.fileExists(atPath: $0.path(percentEncoded: false)) }
                if !stillOnDisk.isEmpty,
                   let trashedPairs = try? await self.fileSystemService.moveItemsToTrashWithPairs(stillOnDisk),
                   !trashedPairs.isEmpty {
                    self.recordUndo(.trash(pairs: trashedPairs))
                }
                await self.finishDeletingItems(standardized)
                return
            }

            if operation == .move {
                try? await Task.sleep(for: .milliseconds(120))
                let stillOnDisk = standardized.filter { fm.fileExists(atPath: $0.path(percentEncoded: false)) }
                if !stillOnDisk.isEmpty {
                    do {
                        try await self.fileSystemService.deleteItemsPermanently(stillOnDisk)
                    } catch {
                        self.errorMessage = error.localizedDescription
                    }
                }
                await self.finishDeletingItems(standardized)
            }
        }
    }

    // MARK: - Carga Asíncrona de Directorio

    private func loadCurrentDirectory(preservingSelection: Bool = false) {
        directoryLoadTask?.cancel()
        slowLoadingOverlayTask?.cancel()
        backgroundVerifyTask?.cancel()
        thumbnailPreloadTask?.cancel()

        let targetURL = currentDirectoryURL.standardizedFileURL
        let previousSelection = preservingSelection ? selectedItemIDs : []
        let isChangingFolder = (loadedDirectoryURL?.standardizedFileURL != targetURL)

        installCurrentDirectoryWatcher(for: targetURL)

        isLoading = true
        isSlowLoadingOverlayVisible = false
        errorMessage = nil

        // Si la lectura tarda más de 160ms (carpeta muy grande o disco lento), mostrar indicador de carga centrado.
        slowLoadingOverlayTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled, let self, self.isLoading else { return }
            if isChangingFolder {
                self.loadedDirectoryURL = nil
                self.setAllItems([], precomputedDisplayed: [])
            }
            self.isSlowLoadingOverlayVisible = true
        }

        directoryLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                // 1. Intentar carga instantánea desde caché en RAM o archivo oculto `.macfileexplorer_dir.cache`
                if let cached = await DirectoryIndexCacheService.shared.loadCachedSnapshot(for: targetURL),
                   cached.isFolderTimestampFresh {
                    let cachedItems = cached.items
                    let sortedCached = await self.computeDisplayedItemsOffMainThread(from: cachedItems)
                    guard !Task.isCancelled else { return }

                    self.applyDirectorySnapshot(
                        cachedItems,
                        sortedItems: sortedCached,
                        for: targetURL,
                        preservingSelection: preservingSelection,
                        previousSelection: previousSelection,
                        saveToDiskCache: false
                    )

                    // Verificación silenciosa en segundo plano por si cambió tamaño/fecha de un archivo sin alterar el mtime de la carpeta
                    self.scheduleBackgroundDirectoryVerification(
                        for: targetURL,
                        baselineItems: cachedItems,
                        preservingSelection: preservingSelection,
                        previousSelection: previousSelection
                    )
                    return
                }

                // 2. Lectura completa desde disco en segundo plano + ordenamiento fuera del hilo principal
                let fetchedItems = try await fileSystemService.fetchDirectoryContents(at: targetURL)
                guard !Task.isCancelled else { return }

                let sortedFetched = await self.computeDisplayedItemsOffMainThread(from: fetchedItems)
                guard !Task.isCancelled else { return }

                self.applyDirectorySnapshot(
                    fetchedItems,
                    sortedItems: sortedFetched,
                    for: targetURL,
                    preservingSelection: preservingSelection,
                    previousSelection: previousSelection,
                    saveToDiskCache: true
                )
            } catch is CancellationError {
                // Cancelación esperada al cambiar rápido de carpeta
            } catch {
                guard !Task.isCancelled else { return }
                self.slowLoadingOverlayTask?.cancel()
                self.isSlowLoadingOverlayVisible = false
                self.isLoading = false
                self.loadedDirectoryURL = targetURL
                self.setAllItems([], precomputedDisplayed: [])
                if let trashURL = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first?.standardizedFileURL,
                   targetURL == trashURL {
                    let loc = LocalizationManager.shared
                    self.errorMessage = loc.text(
                        es: "Para ver la Papelera dentro de MacFileExplorer, concede \"Acceso total al disco\" en Ajustes del Sistema > Privacidad y seguridad.",
                        en: "To view Trash inside MacFileExplorer, grant \"Full Disk Access\" in System Settings > Privacy & Security."
                    )
                } else {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func computeDisplayedItemsOffMainThread(
        from items: [FileItem],
        priority: TaskPriority = .userInitiated
    ) async -> [FileItem] {
        let showHidden = self.showHiddenFiles
        let query = self.searchQuery
        let field = self.sortField
        let ascending = self.sortAscending
        return await Task.detached(priority: priority) {
            Self.computeDisplayedItems(
                from: items,
                showHiddenFiles: showHidden,
                searchQuery: query,
                sortField: field,
                sortAscending: ascending
            )
        }.value
    }

    private func applyDirectorySnapshot(
        _ items: [FileItem],
        sortedItems: [FileItem],
        for targetURL: URL,
        preservingSelection: Bool,
        previousSelection: Set<FileItem.ID>,
        saveToDiskCache: Bool
    ) {
        slowLoadingOverlayTask?.cancel()
        isSlowLoadingOverlayVisible = false
        isLoading = false
        loadedDirectoryURL = targetURL
        lastDirectoryScanDate = Date()
        lastObservedFolderMtime = Self.directoryModificationTimestamp(for: targetURL)
        setAllItems(items, precomputedDisplayed: sortedItems)
        if preservingSelection {
            let validIDs = Set(items.map(\.id))
            selectedItemIDs = previousSelection.intersection(validIDs)
        }
        sidebarViewModel.refreshSubdirectoriesIfNeeded(at: targetURL, includeHidden: showHiddenFiles)
        scheduleThumbnailPreload(for: targetURL, items: items)

        if saveToDiskCache {
            Task.detached(priority: .utility) {
                await DirectoryIndexCacheService.shared.saveSnapshot(items, for: targetURL)
            }
        }

        if hasPendingWatcherRescan && Self.isSameDirectory(currentDirectoryURL, targetURL) {
            hasPendingWatcherRescan = false
            scheduleCurrentDirectoryWatcherRefresh(for: targetURL)
        }
    }

    private func scheduleBackgroundDirectoryVerification(
        for targetURL: URL,
        baselineItems: [FileItem],
        preservingSelection: Bool,
        previousSelection: Set<FileItem.ID>
    ) {
        backgroundVerifyTask?.cancel()
        backgroundVerifyTask = Task(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            guard self.currentDirectoryURL.standardizedFileURL == targetURL else { return }

            guard let freshItems = try? await self.fileSystemService.fetchDirectoryContents(at: targetURL),
                  !Task.isCancelled,
                  self.currentDirectoryURL.standardizedFileURL == targetURL else {
                return
            }

            guard freshItems != baselineItems else { return }

            let sortedFresh = await self.computeDisplayedItemsOffMainThread(from: freshItems, priority: .utility)
            guard !Task.isCancelled, self.currentDirectoryURL.standardizedFileURL == targetURL else { return }

            let activeSelection = preservingSelection ? previousSelection : self.selectedItemIDs
            self.applyDirectorySnapshot(
                freshItems,
                sortedItems: sortedFresh,
                for: targetURL,
                preservingSelection: !activeSelection.isEmpty,
                previousSelection: activeSelection,
                saveToDiskCache: true
            )
        }
    }

    private func installCurrentDirectoryWatcher(for directoryURL: URL) {
        watcherDebounceTask?.cancel()
        watcherDebounceTask = nil
        watcherScanTask?.cancel()
        watcherScanTask = nil
        hasPendingWatcherRescan = false
        currentDirectoryWatcher?.invalidate()
        currentDirectoryWatcher = nil

        let watchedURL = directoryURL.standardizedFileURL
        currentDirectoryWatcher = DirectoryWatcher(url: watchedURL, enableFSEvents: true) { [weak self] in
            self?.scheduleCurrentDirectoryWatcherRefresh(for: watchedURL)
        }
    }

    private func scheduleCurrentDirectoryWatcherRefresh(for watchedURL: URL) {
        guard Self.isSameDirectory(currentDirectoryURL, watchedURL) else { return }

        if isLoading || watcherScanTask != nil || renamingItemID != nil {
            hasPendingWatcherRescan = true
            return
        }

        watcherDebounceTask?.cancel()
        watcherDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, let self else { return }
            self.watcherDebounceTask = nil
            self.runCoalescedWatcherScan(for: watchedURL)
        }
    }

    /// Verifica silenciosamente si la carpeta actual cambió externamente (p. ej. al volver desde Finder o el navegador).
    public func checkCurrentDirectoryForExternalChanges() {
        guard !isLoading, renamingItemID == nil, watcherScanTask == nil, watcherDebounceTask == nil else {
            return
        }
        let targetURL = currentDirectoryURL.standardizedFileURL
        let currentMtime = Self.directoryModificationTimestamp(for: targetURL)
        let mtimeChanged: Bool
        if let currentMtime, let lastObservedFolderMtime {
            mtimeChanged = abs(currentMtime - lastObservedFolderMtime) >= 0.001
        } else {
            mtimeChanged = (currentMtime != lastObservedFolderMtime)
        }
        let staleInterval = Date().timeIntervalSince(lastDirectoryScanDate) >= 1.5
        guard mtimeChanged || staleInterval else { return }
        runCoalescedWatcherScan(for: targetURL)
    }

    private func runCoalescedWatcherScan(for watchedURL: URL) {
        guard Self.isSameDirectory(currentDirectoryURL, watchedURL) else { return }
        guard renamingItemID == nil else {
            hasPendingWatcherRescan = true
            return
        }
        guard watcherScanTask == nil else {
            hasPendingWatcherRescan = true
            return
        }

        watcherScanTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if !Task.isCancelled {
                    self.watcherScanTask = nil
                    if self.hasPendingWatcherRescan && Self.isSameDirectory(self.currentDirectoryURL, watchedURL) {
                        self.hasPendingWatcherRescan = false
                        self.scheduleCurrentDirectoryWatcherRefresh(for: watchedURL)
                    }
                }
            }

            if FileManager.default.fileExists(atPath: watchedURL.path(percentEncoded: false)) {
                if let fetchedItems = try? await self.fileSystemService.fetchDirectoryContents(at: watchedURL) {
                    guard Self.isSameDirectory(self.currentDirectoryURL, watchedURL), !Task.isCancelled else { return }

                    self.lastDirectoryScanDate = Date()
                    self.lastObservedFolderMtime = Self.directoryModificationTimestamp(for: watchedURL)

                    if self.renamingItemID != nil {
                        self.hasPendingWatcherRescan = true
                        return
                    }

                    if fetchedItems != self.allItems {
                        let sorted = await self.computeDisplayedItemsOffMainThread(from: fetchedItems)
                        guard Self.isSameDirectory(self.currentDirectoryURL, watchedURL), !Task.isCancelled else { return }

                        let validIDs = Set(fetchedItems.map(\.id))
                        self.loadedDirectoryURL = watchedURL
                        self.setAllItems(fetchedItems, precomputedDisplayed: sorted)
                        self.selectedItemIDs = self.selectedItemIDs.intersection(validIDs)
                        self.scheduleThumbnailPreload(for: watchedURL, items: fetchedItems)
                        Task.detached(priority: .utility) {
                            await DirectoryIndexCacheService.shared.saveSnapshot(fetchedItems, for: watchedURL)
                        }
                    }
                    self.sidebarViewModel.refreshSubdirectoriesIfNeeded(at: watchedURL, includeHidden: self.showHiddenFiles)
                }
            } else {
                await self.finishDeletingItems([watchedURL])
            }
        }
    }

    private func reloadDirectoryAndSelect(_ urlsToSelect: [URL], startRenameOn renameURL: URL?) async {
        do {
            let targetURL = currentDirectoryURL.standardizedFileURL
            let fetchedItems = try await fileSystemService.fetchDirectoryContents(at: targetURL)
            let sorted = await computeDisplayedItemsOffMainThread(from: fetchedItems)
            self.loadedDirectoryURL = targetURL
            self.lastDirectoryScanDate = Date()
            self.lastObservedFolderMtime = Self.directoryModificationTimestamp(for: targetURL)
            self.setAllItems(fetchedItems, precomputedDisplayed: sorted)
            Task.detached(priority: .utility) {
                await DirectoryIndexCacheService.shared.saveSnapshot(fetchedItems, for: targetURL)
            }

            let standardizedSet = Set(urlsToSelect.map(\.standardizedFileURL))
            self.selectedItemIDs = standardizedSet
            self.selectionAnchorID = standardizedSet.first

            if let renameURL {
                let stdRename = renameURL.standardizedFileURL
                self.renamingItemID = stdRename
                self.renamingDraftName = stdRename.lastPathComponent
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private static func isSameDirectory(_ lhs: URL, _ rhs: URL) -> Bool {
        normalizedDirectoryPath(lhs) == normalizedDirectoryPath(rhs)
    }

    private static func normalizedDirectoryPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        if path.count > 1 && path.hasSuffix("/") {
            return String(path.dropLast())
        }
        return path
    }

    private static func directoryModificationTimestamp(for url: URL) -> TimeInterval? {
        let values = try? url.standardizedFileURL.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate?.timeIntervalSince1970
    }
}
