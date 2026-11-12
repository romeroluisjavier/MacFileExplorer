import Foundation
import AppKit
import SwiftUI
import Observation

/// Servicio encargado de persistir y restaurar el estado de sesión del explorador en `UserDefaults`:
/// - Última carpeta abierta antes de cerrar
/// - Árbol de carpetas expandidas en el panel lateral izquierdo (`expandedNodeIDs` y secciones)
/// - Modo de vista, ordenamiento y visibilidad de archivos ocultos
/// - Posición y tamaño exactos de la ventana en pantalla
@MainActor
public final class PersistenceService {

    public static let shared = PersistenceService()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let lastDirectoryPath = "com.macfileexplorer.state.lastDirectoryPath"
        static let expandedSidebarNodeIDs = "com.macfileexplorer.state.expandedSidebarNodeIDs"
        static let isQuickAccessExpanded = "com.macfileexplorer.state.isQuickAccessExpanded"
        static let isVolumesExpanded = "com.macfileexplorer.state.isVolumesExpanded"
        static let viewMode = "com.macfileexplorer.state.viewMode"
        static let sortField = "com.macfileexplorer.state.sortField"
        static let sortAscending = "com.macfileexplorer.state.sortAscending"
        static let showHiddenFiles = "com.macfileexplorer.state.showHiddenFiles"
        static let windowFrame = "com.macfileexplorer.state.windowFrame"
        static let visibleQuickAccessFolders = "com.macfileexplorer.state.visibleQuickAccessFolders"
        static let customQuickAccessFolderPaths = "com.macfileexplorer.state.customQuickAccessFolderPaths"
        static let showNewButtonInToolbar = "com.macfileexplorer.state.showNewButtonInToolbar"
        static let detailsDateColumnWidth = "com.macfileexplorer.state.detailsDateColumnWidth"
        static let detailsKindColumnWidth = "com.macfileexplorer.state.detailsKindColumnWidth"
        static let detailsSizeColumnWidth = "com.macfileexplorer.state.detailsSizeColumnWidth"
        static let listIconDisplayMode = "com.macfileexplorer.state.listIconDisplayMode"
        static let gridIconSize = "com.macfileexplorer.state.gridIconSize"
    }

    private init() {}

    // MARK: - Último Directorio Abierto

    public func saveLastDirectory(_ url: URL) {
        defaults.set(url.standardizedFileURL.path(percentEncoded: false), forKey: Keys.lastDirectoryPath)
    }

    public func loadLastDirectory() -> URL {
        let fm = FileManager.default
        if let savedPath = defaults.string(forKey: Keys.lastDirectoryPath), !savedPath.isEmpty {
            var candidate = URL(fileURLWithPath: savedPath).standardizedFileURL
            var isDir: ObjCBool = false
            // Si la carpeta guardada existe, abrir en ella; si fue borrada, subir al padre existente más cercano
            while candidate.path != "/" {
                if fm.fileExists(atPath: candidate.path(percentEncoded: false), isDirectory: &isDir), isDir.boolValue {
                    return candidate
                }
                candidate = candidate.deletingLastPathComponent().standardizedFileURL
            }
        }
        return fm.homeDirectoryForCurrentUser.standardizedFileURL
    }

    // MARK: - Estado del Árbol Lateral Izquierdo (Carpetas Expandidas)

    public func saveExpandedSidebarNodes(_ nodeIDs: Set<String>) {
        defaults.set(Array(nodeIDs), forKey: Keys.expandedSidebarNodeIDs)
    }

    public func loadExpandedSidebarNodes() -> Set<String> {
        guard let array = defaults.stringArray(forKey: Keys.expandedSidebarNodeIDs) else {
            return []
        }
        return Set(array)
    }

    public func saveSidebarSections(quickAccessExpanded: Bool, volumesExpanded: Bool) {
        defaults.set(quickAccessExpanded, forKey: Keys.isQuickAccessExpanded)
        defaults.set(volumesExpanded, forKey: Keys.isVolumesExpanded)
    }

    public func loadSidebarSections() -> (quickAccessExpanded: Bool, volumesExpanded: Bool) {
        let quick = defaults.object(forKey: Keys.isQuickAccessExpanded) as? Bool ?? true
        let volumes = defaults.object(forKey: Keys.isVolumesExpanded) as? Bool ?? true
        return (quick, volumes)
    }

    // MARK: - Preferencias de Vista y Ordenamiento

    public func saveViewMode(_ mode: ExplorerViewMode) {
        defaults.set(mode.rawValue, forKey: Keys.viewMode)
    }

    public func loadViewMode() -> ExplorerViewMode {
        guard let raw = defaults.string(forKey: Keys.viewMode),
              let mode = ExplorerViewMode(rawValue: raw) else {
            return .details
        }
        return mode
    }

    public func saveSort(field: FileItem.SortField, ascending: Bool) {
        defaults.set(field.rawValue, forKey: Keys.sortField)
        defaults.set(ascending, forKey: Keys.sortAscending)
    }

    public func loadSort() -> (field: FileItem.SortField, ascending: Bool) {
        let field: FileItem.SortField = {
            guard let raw = defaults.string(forKey: Keys.sortField),
                  let f = FileItem.SortField(rawValue: raw) else {
                return .name
            }
            return f
        }()
        let ascending = defaults.object(forKey: Keys.sortAscending) as? Bool ?? true
        return (field, ascending)
    }

    public func saveShowHiddenFiles(_ show: Bool) {
        defaults.set(show, forKey: Keys.showHiddenFiles)
    }

    public func loadShowHiddenFiles() -> Bool {
        defaults.bool(forKey: Keys.showHiddenFiles)
    }

    // MARK: - Posición y Tamaño de Ventana en Pantalla

    public func saveWindowFrame(_ frame: NSRect) {
        guard frame.width >= 600, frame.height >= 400 else { return }
        defaults.set(NSStringFromRect(frame), forKey: Keys.windowFrame)
    }

    public func loadWindowFrame() -> NSRect? {
        guard let raw = defaults.string(forKey: Keys.windowFrame) else { return nil }
        let rect = NSRectFromString(raw)
        guard rect.width >= 600, rect.height >= 400 else { return nil }
        return rect
    }

    // MARK: - Carpetas Visibles en Acceso Rápido

    public func saveVisibleQuickAccessFolders(_ folders: Set<QuickAccessFolder>) {
        let rawValues = QuickAccessFolder.allCases
            .filter { folders.contains($0) }
            .map(\.rawValue)
        defaults.set(rawValues, forKey: Keys.visibleQuickAccessFolders)
    }

    private static let trashMigrationKey = "com.macfileexplorer.state.hasMigratedTrashToQuickAccess.v1"

    public func loadVisibleQuickAccessFolders() -> Set<QuickAccessFolder> {
        guard let saved = defaults.stringArray(forKey: Keys.visibleQuickAccessFolders) else {
            return QuickAccessFolder.defaultFolders
        }
        var set = Set(saved.compactMap { QuickAccessFolder(rawValue: $0) })
        if !defaults.bool(forKey: Self.trashMigrationKey) {
            defaults.set(true, forKey: Self.trashMigrationKey)
            set.insert(.trash)
            saveVisibleQuickAccessFolders(set)
        }
        return set
    }

    public func saveCustomQuickAccessFolderPaths(_ paths: [String]) {
        defaults.set(paths, forKey: Keys.customQuickAccessFolderPaths)
    }

    public func loadCustomQuickAccessFolderPaths() -> [String] {
        defaults.stringArray(forKey: Keys.customQuickAccessFolderPaths) ?? []
    }

    public func saveShowNewButton(_ show: Bool) {
        defaults.set(show, forKey: Keys.showNewButtonInToolbar)
    }

    public func loadShowNewButton() -> Bool {
        defaults.object(forKey: Keys.showNewButtonInToolbar) as? Bool ?? true
    }

    public func saveDetailsColumnWidths(_ widths: DetailsColumnWidths) {
        defaults.set(Double(widths.dateWidth), forKey: Keys.detailsDateColumnWidth)
        defaults.set(Double(widths.kindWidth), forKey: Keys.detailsKindColumnWidth)
        defaults.set(Double(widths.sizeWidth), forKey: Keys.detailsSizeColumnWidth)
    }

    public func loadDetailsColumnWidths() -> DetailsColumnWidths {
        let def = DetailsColumnWidths.defaults
        let savedDate = defaults.object(forKey: Keys.detailsDateColumnWidth) as? Double
        let savedKind = defaults.object(forKey: Keys.detailsKindColumnWidth) as? Double
        let savedSize = defaults.object(forKey: Keys.detailsSizeColumnWidth) as? Double
        return DetailsColumnWidths(
            dateWidth: max(CGFloat(savedDate ?? Double(def.dateWidth)), DetailsColumnWidths.minDateWidth),
            kindWidth: max(CGFloat(savedKind ?? Double(def.kindWidth)), DetailsColumnWidths.minKindWidth),
            sizeWidth: max(CGFloat(savedSize ?? Double(def.sizeWidth)), DetailsColumnWidths.minSizeWidth)
        )
    }

    public func saveListIconDisplayMode(_ mode: ListIconDisplayMode) {
        defaults.set(mode.rawValue, forKey: Keys.listIconDisplayMode)
    }

    public func loadListIconDisplayMode() -> ListIconDisplayMode {
        guard let raw = defaults.string(forKey: Keys.listIconDisplayMode),
              let mode = ListIconDisplayMode(rawValue: raw) else {
            return .appIcon
        }
        return mode
    }

    public func saveGridIconSize(_ size: Double) {
        defaults.set(size, forKey: Keys.gridIconSize)
    }

    public func loadGridIconSize() -> Double {
        let saved = defaults.double(forKey: Keys.gridIconSize)
        if saved >= GridIconPreferences.minIconSize && saved <= GridIconPreferences.maxIconSize {
            return saved
        }
        return GridIconPreferences.defaultIconSize
    }

    // MARK: - Destinos y Preferencias de Slack

    private static let slackRecentDestinationsKey = "com.macfileexplorer.state.slackRecentDestinations"
    private static let showSlackOptionKey = "com.macfileexplorer.state.showSlackOption"
    private static let slackDirectoryKey = "com.macfileexplorer.state.slackDirectory"

    public static let defaultSlackDirectory: [String] = [
        "#general",
        "#random",
        "#anuncios",
        "#equipo",
        "#desarrollo",
        "#proyectos",
        "#soporte",
        "@yo (bloc de notas)"
    ]

    public func loadShowSlackOption() -> Bool {
        if defaults.object(forKey: Self.showSlackOptionKey) == nil {
            return true
        }
        return defaults.bool(forKey: Self.showSlackOptionKey)
    }

    public func saveShowSlackOption(_ show: Bool) {
        defaults.set(show, forKey: Self.showSlackOptionKey)
    }

    public func loadSlackDirectory() -> [String] {
        defaults.stringArray(forKey: Self.slackDirectoryKey) ?? Self.defaultSlackDirectory
    }

    public func saveSlackDirectory(_ directory: [String]) {
        defaults.set(directory, forKey: Self.slackDirectoryKey)
    }

    public func loadSlackRecentDestinations() -> [String] {
        defaults.stringArray(forKey: Self.slackRecentDestinationsKey) ?? ["#general", "#random"]
    }

    public func saveSlackRecentDestination(_ destination: String) {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = loadSlackRecentDestinations().filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        list.insert(trimmed, at: 0)
        if list.count > 8 {
            list = Array(list.prefix(8))
        }
        defaults.set(list, forKey: Self.slackRecentDestinationsKey)
    }
}

/// Anchos configurables de las columnas de la vista Detalles junto con la lógica de ajuste por divisores.
public struct DetailsColumnWidths: Equatable, Sendable {
    public var dateWidth: CGFloat
    public var kindWidth: CGFloat
    public var sizeWidth: CGFloat

    public static let defaults = DetailsColumnWidths(
        dateWidth: 165,
        kindWidth: 165,
        sizeWidth: 105
    )

    public static let minNameWidth: CGFloat = 140
    public static let minDateWidth: CGFloat = 95
    public static let minKindWidth: CGFloat = 80
    public static let minSizeWidth: CGFloat = 68

    public init(dateWidth: CGFloat, kindWidth: CGFloat, sizeWidth: CGFloat) {
        self.dateWidth = dateWidth
        self.kindWidth = kindWidth
        self.sizeWidth = sizeWidth
    }

    /// Ajusta el divisor 1 (`Nombre | Fecha de modificación`) manteniendo fijas `Tipo` y `Tamaño`.
    public func resizingNameAndDate(deltaX: CGFloat, availableContentWidth: CGFloat) -> DetailsColumnWidths {
        let safeContentWidth = availableContentWidth > 0 ? availableContentWidth : 800
        let maxDateByAvailable = safeContentWidth - Self.minNameWidth - kindWidth - sizeWidth
        let upperBound = max(Self.minDateWidth, maxDateByAvailable)
        let clampedDate = min(max(dateWidth - deltaX, Self.minDateWidth), upperBound)
        return DetailsColumnWidths(dateWidth: clampedDate, kindWidth: kindWidth, sizeWidth: sizeWidth)
    }

    /// Ajusta el divisor 2 (`Fecha de modificación | Tipo`) manteniendo fijas `Nombre` y `Tamaño`.
    public func resizingDateAndKind(deltaX: CGFloat) -> DetailsColumnWidths {
        let minDelta = Self.minDateWidth - dateWidth
        let maxDelta = kindWidth - Self.minKindWidth
        let clampedDelta: CGFloat = minDelta <= maxDelta ? min(max(deltaX, minDelta), maxDelta) : 0
        return DetailsColumnWidths(
            dateWidth: dateWidth + clampedDelta,
            kindWidth: kindWidth - clampedDelta,
            sizeWidth: sizeWidth
        )
    }

    /// Ajusta el divisor 3 (`Tipo | Tamaño`) manteniendo fijas `Nombre` y `Fecha de modificación`.
    public func resizingKindAndSize(deltaX: CGFloat) -> DetailsColumnWidths {
        let minDelta = Self.minKindWidth - kindWidth
        let maxDelta = sizeWidth - Self.minSizeWidth
        let clampedDelta: CGFloat = minDelta <= maxDelta ? min(max(deltaX, minDelta), maxDelta) : 0
        return DetailsColumnWidths(
            dateWidth: dateWidth,
            kindWidth: kindWidth + clampedDelta,
            sizeWidth: sizeWidth - clampedDelta
        )
    }
}

/// Preferencias reactivas y persistentes de los anchos de columnas de la vista Detalles.
@MainActor
@Observable
public final class DetailsColumnPreferences {
    public static let shared = DetailsColumnPreferences()

    public var widths: DetailsColumnWidths {
        didSet {
            guard widths != oldValue else { return }
            PersistenceService.shared.saveDetailsColumnWidths(widths)
        }
    }

    private init() {
        self.widths = PersistenceService.shared.loadDetailsColumnWidths()
    }

    public func resetToDefaults() {
        widths = .defaults
    }
}

/// Preferencias reactivas y persistentes de las carpetas mostradas en la sección "Acceso rápido" del panel lateral.
@MainActor
@Observable
public final class QuickAccessPreferences {
    public static let shared = QuickAccessPreferences()

    public var visibleFolders: Set<QuickAccessFolder> {
        didSet {
            PersistenceService.shared.saveVisibleQuickAccessFolders(visibleFolders)
        }
    }

    /// Rutas personalizadas fijadas manualmente por el usuario mediante arrastrar y soltar en "Acceso rápido".
    public var customFolderPaths: [String] {
        didSet {
            PersistenceService.shared.saveCustomQuickAccessFolderPaths(customFolderPaths)
        }
    }

    public var customFolderURLs: [URL] {
        customFolderPaths.map { URL(fileURLWithPath: $0).standardizedFileURL }
    }

    private init() {
        self.visibleFolders = PersistenceService.shared.loadVisibleQuickAccessFolders()
        self.customFolderPaths = PersistenceService.shared.loadCustomQuickAccessFolderPaths()
    }

    public func isVisible(_ folder: QuickAccessFolder) -> Bool {
        visibleFolders.contains(folder)
    }

    public func setVisible(_ visible: Bool, for folder: QuickAccessFolder) {
        if visible {
            visibleFolders.insert(folder)
        } else {
            visibleFolders.remove(folder)
        }
    }

    public func binding(for folder: QuickAccessFolder) -> Binding<Bool> {
        Binding(
            get: { self.visibleFolders.contains(folder) },
            set: { newValue in
                self.setVisible(newValue, for: folder)
            }
        )
    }

    public func resetToDefaults() {
        visibleFolders = QuickAccessFolder.defaultFolders
    }

    /// Agrega una o más carpetas a los favoritos de Acceso rápido evitando duplicados.
    @discardableResult
    public func addCustomFolders(from urls: [URL]) -> Int {
        let fm = FileManager.default
        let visibleSystemPaths: Set<String> = Set(
            QuickAccessFolder.allCases
                .filter { visibleFolders.contains($0) }
                .compactMap { $0.directoryURL?.standardizedFileURL.path(percentEncoded: false) }
        )
        var existingPaths = Set(customFolderPaths)
        var updated = customFolderPaths
        var addedCount = 0

        for url in urls {
            let standardized = url.standardizedFileURL
            guard standardized.isFileURL else { continue }
            var isDir: ObjCBool = false
            let path = standardized.path(percentEncoded: false)
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
            guard !existingPaths.contains(path), !visibleSystemPaths.contains(path) else { continue }

            existingPaths.insert(path)
            updated.append(path)
            addedCount += 1
        }

        if addedCount > 0 {
            customFolderPaths = updated
        }
        return addedCount
    }

    /// Quita una carpeta personalizada de los favoritos de Acceso rápido.
    public func removeCustomFolder(_ url: URL) {
        let targetPath = url.standardizedFileURL.path(percentEncoded: false)
        customFolderPaths.removeAll { $0 == targetPath }
    }
}

/// Preferencias reactivas y persistentes de la barra de comandos superior.
@MainActor
@Observable
public final class ToolbarPreferences {
    public static let shared = ToolbarPreferences()

    public var isNewButtonVisible: Bool {
        didSet {
            PersistenceService.shared.saveShowNewButton(isNewButtonVisible)
        }
    }

    private init() {
        self.isNewButtonVisible = PersistenceService.shared.loadShowNewButton()
    }
}

/// Preferencias reactivas y persistentes del estilo de iconos en la vista Lista (`Basic`, `App Icon`, `Thumbnail`).
@MainActor
@Observable
public final class ListIconPreferences {
    public static let shared = ListIconPreferences()

    public var mode: ListIconDisplayMode {
        didSet {
            guard mode != oldValue else { return }
            PersistenceService.shared.saveListIconDisplayMode(mode)
        }
    }

    private init() {
        self.mode = PersistenceService.shared.loadListIconDisplayMode()
    }
}

/// Preferencias reactivas y persistentes del tamaño de iconos en la vista de Cuadrícula / Iconos grandes estilo Finder.
@MainActor
@Observable
public final class GridIconPreferences {
    public static let shared = GridIconPreferences()

    public static let minIconSize: Double = 40
    public static let maxIconSize: Double = 192
    public static let defaultIconSize: Double = 64

    public var iconSize: Double {
        didSet {
            let clamped = min(max(iconSize, Self.minIconSize), Self.maxIconSize)
            if clamped != iconSize {
                iconSize = clamped
                return
            }
            PersistenceService.shared.saveGridIconSize(clamped)
        }
    }

    private init() {
        self.iconSize = PersistenceService.shared.loadGridIconSize()
    }

    public func resetToDefault() {
        iconSize = Self.defaultIconSize
    }
}

/// Preferencias reactivas y persistentes de la integración con Slack (visibilidad de menú y directorio de autocompletado).
@MainActor
@Observable
public final class SlackPreferences {
    public static let shared = SlackPreferences()

    public var isShareToSlackEnabled: Bool {
        didSet {
            guard isShareToSlackEnabled != oldValue else { return }
            PersistenceService.shared.saveShowSlackOption(isShareToSlackEnabled)
        }
    }

    public var savedDestinations: [String] {
        didSet {
            PersistenceService.shared.saveSlackDirectory(savedDestinations)
        }
    }

    public var recentDestinations: [String]

    private init() {
        self.isShareToSlackEnabled = PersistenceService.shared.loadShowSlackOption()
        self.savedDestinations = PersistenceService.shared.loadSlackDirectory()
        self.recentDestinations = PersistenceService.shared.loadSlackRecentDestinations()
    }

    public func addDestination(_ destination: String) {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !savedDestinations.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            savedDestinations.append(trimmed)
        }
        recordRecent(trimmed)
    }

    public func removeDestination(_ destination: String) {
        savedDestinations.removeAll { $0.caseInsensitiveCompare(destination) == .orderedSame }
    }

    public func recordRecent(_ destination: String) {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        PersistenceService.shared.saveSlackRecentDestination(trimmed)
        recentDestinations = PersistenceService.shared.loadSlackRecentDestinations()
    }

    public func resetDirectoryToDefaults() {
        savedDestinations = PersistenceService.defaultSlackDirectory
    }
}

/// Representable invisible que vincula el `NSWindow` anfitrión para restaurar su posición/tamaño exactos
/// al abrir la aplicación, guardar cualquier movimiento/redimensionamiento y mantener el icono de carpeta en la pestaña nativa.
public struct WindowFrameAutosaveView: NSViewRepresentable {
    public let folderTitle: String

    public init(folderTitle: String) {
        self.folderTitle = folderTitle
    }

    public func makeNSView(context: Context) -> NSView {
        let view = WindowObserverNSView()
        view.folderTitle = folderTitle
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let observerView = nsView as? WindowObserverNSView else { return }
        observerView.folderTitle = folderTitle
        observerView.syncWindowTabAppearanceIfNeeded()
    }
}

@MainActor
private final class WindowObserverNSView: NSView {
    private var didRestoreFrame = false
    private var lastAppliedTitle: String = ""
    var folderTitle: String = ""

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if let oldWindow = self.window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didMoveNotification, object: oldWindow)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: oldWindow)
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: oldWindow)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window = self.window else { return }

        NSWindow.allowsAutomaticWindowTabbing = true
        window.tabbingMode = .preferred
        window.tabbingIdentifier = GoogleAccountsManager.mainWindowTabbingIdentifier

        if !didRestoreFrame {
            didRestoreFrame = true
            let visibleMainWindows = NSApplication.shared.windows.filter {
                $0 !== window && $0.isVisible && $0.canBecomeMain
            }
            if visibleMainWindows.isEmpty {
                window.setFrameAutosaveName("MacFileExplorerMainWindow")
                if let savedFrame = PersistenceService.shared.loadWindowFrame() {
                    window.setFrame(savedFrame, display: true)
                }
            }
        }

        syncWindowTabAppearanceIfNeeded(force: true)
        DispatchQueue.main.async { [weak self] in
            self?.syncWindowTabAppearanceIfNeeded(force: true)
        }

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleWindowFrameChange(_:)),
            name: NSWindow.didMoveNotification,
            object: window
        )
        center.addObserver(
            self,
            selector: #selector(handleWindowFrameChange(_:)),
            name: NSWindow.didResizeNotification,
            object: window
        )
        center.addObserver(
            self,
            selector: #selector(handleWindowFrameChange(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    func syncWindowTabAppearanceIfNeeded(force: Bool = false) {
        guard let window = self.window, !folderTitle.isEmpty else { return }
        if window.tabbingIdentifier != GoogleAccountsManager.mainWindowTabbingIdentifier {
            window.tabbingMode = .preferred
            window.tabbingIdentifier = GoogleAccountsManager.mainWindowTabbingIdentifier
        }
        guard force || lastAppliedTitle != folderTitle else { return }
        lastAppliedTitle = folderTitle
        let titleSnapshot = folderTitle
        NativeWindowTabIconBuilder.applyFolderTabAppearance(to: window, title: titleSnapshot)
        if !force {
            DispatchQueue.main.async { [weak self] in
                guard let self, let win = self.window, self.lastAppliedTitle == titleSnapshot else { return }
                NativeWindowTabIconBuilder.applyFolderTabAppearance(to: win, title: titleSnapshot)
            }
        }
    }

    @objc private func handleWindowFrameChange(_ notification: Notification) {
        guard let window = self.window ?? (notification.object as? NSWindow) else { return }
        PersistenceService.shared.saveWindowFrame(window.frame)
    }
}
